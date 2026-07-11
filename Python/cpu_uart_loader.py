#!/usr/bin/env python3
"""Load RV32 instructions into the FPGA CPU over a reliable UART protocol.

Wire protocol (115200 baud, 8 data bits, no parity, 1 stop bit):

    Request:  AA 49 CMD SEQ ADDR_L ADDR_H D0 D1 D2 D3 FLAGS CRC8
    Response: AA 41 STATUS SEQ ADDR_L ADDR_H DETAIL CRC8

CRC-8/ATM uses polynomial 0x07, initial value 0x00, no reflection, and no
final XOR. The CRC covers every byte before the CRC field. Instruction data
is little-endian on the wire. WRITE addresses are absolute IMEM word indexes.

BEGIN carries the expected program length in ADDR (1..256). The FPGA clears
IMEM to NOP before acknowledging BEGIN. A RUN is accepted only after every
word in [0, expected_words) has been written. Retries resend the exact same
frame and sequence number so that FPGA-side duplicate suppression is safe.

Examples:

    python cpu_uart_loader.py --list-ports
    python cpu_uart_loader.py --port COM5
    python cpu_uart_loader.py --port COM5 --file ../program/sum.mem --run
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Callable, Iterable, Optional, Protocol, Sequence


REQUEST_SOF = 0xAA
REQUEST_TYPE = 0x49
RESPONSE_SOF = 0xAA
RESPONSE_TYPE = 0x41
REQUEST_SIZE = 12
RESPONSE_SIZE = 8

DEFAULT_BAUD = 115200
DEFAULT_TIMEOUT = 0.5
DEFAULT_RETRIES = 3
IMEM_WORDS = 256
NOP_INSTRUCTION = 0x00000013


class Command(IntEnum):
    BEGIN = 0x01
    WRITE = 0x02
    RUN = 0x03
    STOP = 0x04
    STATUS = 0x05


class Status(IntEnum):
    OK = 0x00
    CRC_ERROR = 0x01
    BAD_CMD = 0x02
    BAD_ADDR = 0x03
    BAD_STATE = 0x04
    BUSY = 0x05
    INCOMPLETE = 0x06
    BAD_LENGTH = 0x07
    BAD_FLAGS = 0x08
    SEQ_CONFLICT = 0x09


STATUS_NAMES = {status.value: status.name for status in Status}
RETRYABLE_STATUSES = {Status.CRC_ERROR, Status.BUSY}

DETAIL_STATE_MASK = 0x03
DETAIL_STATE_IDLE = 0x00
DETAIL_STATE_CLEAR = 0x01
DETAIL_STATE_READY = 0x02
DETAIL_STATE_RUN = 0x03
DETAIL_SESSION_ACTIVE = 1 << 2
DETAIL_COMPLETE = 1 << 3

LOADER_STATE_NAMES = {
    DETAIL_STATE_IDLE: "idle",
    DETAIL_STATE_CLEAR: "clear",
    DETAIL_STATE_READY: "ready",
    DETAIL_STATE_RUN: "run",
}


class LoaderError(Exception):
    """Base class for loader failures that can be shown directly to users."""


class FrameError(LoaderError):
    """A request or response frame is malformed."""


class AckTimeout(LoaderError):
    """No matching response arrived after all retransmissions."""


class TransportError(LoaderError):
    """The serial transport failed to read or write a complete frame."""


class DeviceRejected(LoaderError):
    """The FPGA returned a valid response whose status is not OK."""

    def __init__(self, response: "ResponseFrame") -> None:
        self.response = response
        super().__init__(
            f"FPGA rejected request: status={response.status_name} "
            f"seq=0x{response.sequence:02X} addr=0x{response.address:04X} "
            f"detail=0x{response.detail:02X}"
        )


class SerialLike(Protocol):
    """Subset of pyserial used by UartLoaderClient and test doubles."""

    def write(self, data: bytes) -> Optional[int]: ...

    def read(self, size: int = 1) -> bytes: ...


@dataclass(frozen=True)
class RequestFrame:
    command: int
    sequence: int
    address: int = 0
    data: int = 0
    flags: int = 0

    def encode(self) -> bytes:
        return build_request(
            self.command,
            self.sequence,
            self.address,
            self.data,
            self.flags,
        )


@dataclass(frozen=True)
class ResponseFrame:
    status: int
    sequence: int
    address: int
    detail: int

    @property
    def status_name(self) -> str:
        return STATUS_NAMES.get(self.status, f"UNKNOWN_0x{self.status:02X}")

    @property
    def ok(self) -> bool:
        return self.status == Status.OK


@dataclass(frozen=True)
class UploadResult:
    expected_words: int
    begin_response: ResponseFrame
    write_responses: tuple[ResponseFrame, ...]
    run_response: Optional[ResponseFrame]


def _check_uint(name: str, value: int, bits: int) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{name} must be an integer")
    if not 0 <= value < (1 << bits):
        raise ValueError(f"{name} must fit in {bits} bits")


def crc8(data: Iterable[int]) -> int:
    """Return CRC-8/ATM (poly 0x07, init 0, non-reflected, xorout 0)."""

    crc = 0
    for value in data:
        byte = int(value)
        if not 0 <= byte <= 0xFF:
            raise ValueError("CRC input values must be bytes")
        crc ^= byte
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x07) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc


def build_request(
    command: int,
    sequence: int,
    address: int = 0,
    data: int = 0,
    flags: int = 0,
) -> bytes:
    """Encode one 12-byte PC-to-FPGA request."""

    _check_uint("command", int(command), 8)
    _check_uint("sequence", sequence, 8)
    _check_uint("address", address, 16)
    _check_uint("data", data, 32)
    _check_uint("flags", flags, 8)

    body = bytes(
        [
            REQUEST_SOF,
            REQUEST_TYPE,
            int(command),
            sequence,
            address & 0xFF,
            (address >> 8) & 0xFF,
        ]
    ) + data.to_bytes(4, "little") + bytes([flags])
    return body + bytes([crc8(body)])


def parse_request(raw: bytes) -> RequestFrame:
    """Decode and validate a request frame, primarily for diagnostics/tests."""

    if len(raw) != REQUEST_SIZE:
        raise FrameError(f"request must be {REQUEST_SIZE} bytes")
    if raw[0] != REQUEST_SOF or raw[1] != REQUEST_TYPE:
        raise FrameError("request header is invalid")
    if crc8(raw[:-1]) != raw[-1]:
        raise FrameError("request CRC is invalid")
    return RequestFrame(
        command=raw[2],
        sequence=raw[3],
        address=int.from_bytes(raw[4:6], "little"),
        data=int.from_bytes(raw[6:10], "little"),
        flags=raw[10],
    )


def build_response(status: int, sequence: int, address: int = 0, detail: int = 0) -> bytes:
    """Encode a response frame for protocol tests and UART loopback tools."""

    _check_uint("status", int(status), 8)
    _check_uint("sequence", sequence, 8)
    _check_uint("address", address, 16)
    _check_uint("detail", detail, 8)
    body = bytes(
        [
            RESPONSE_SOF,
            RESPONSE_TYPE,
            int(status),
            sequence,
            address & 0xFF,
            (address >> 8) & 0xFF,
            detail,
        ]
    )
    return body + bytes([crc8(body)])


def parse_response(raw: bytes) -> ResponseFrame:
    """Decode and validate one 8-byte FPGA-to-PC response."""

    if len(raw) != RESPONSE_SIZE:
        raise FrameError(f"response must be {RESPONSE_SIZE} bytes")
    if raw[0] != RESPONSE_SOF or raw[1] != RESPONSE_TYPE:
        raise FrameError("response header is invalid")
    if crc8(raw[:-1]) != raw[-1]:
        raise FrameError("response CRC is invalid")
    return ResponseFrame(
        status=raw[2],
        sequence=raw[3],
        address=int.from_bytes(raw[4:6], "little"),
        detail=raw[6],
    )


class ResponseStreamDecoder:
    """Recover valid response frames from arbitrary serial byte chunks."""

    def __init__(self) -> None:
        self.buffer = bytearray()

    def feed(self, data: bytes) -> list[ResponseFrame]:
        self.buffer.extend(data)
        responses: list[ResponseFrame] = []

        while True:
            try:
                sof_index = self.buffer.index(RESPONSE_SOF)
            except ValueError:
                self.buffer.clear()
                break

            if sof_index:
                del self.buffer[:sof_index]
            if len(self.buffer) < 2:
                break
            if self.buffer[1] != RESPONSE_TYPE:
                del self.buffer[0]
                continue
            if len(self.buffer) < RESPONSE_SIZE:
                break

            candidate = bytes(self.buffer[:RESPONSE_SIZE])
            try:
                response = parse_response(candidate)
            except FrameError:
                del self.buffer[0]
                continue

            responses.append(response)
            del self.buffer[:RESPONSE_SIZE]

        return responses


class UartLoaderClient:
    """Stop-and-wait request client with same-sequence retransmission."""

    def __init__(
        self,
        serial_port: SerialLike,
        *,
        timeout: float = DEFAULT_TIMEOUT,
        retries: int = DEFAULT_RETRIES,
        initial_sequence: int = 0,
        log: Optional[Callable[[str], None]] = None,
    ) -> None:
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        if retries < 0:
            raise ValueError("retries cannot be negative")
        _check_uint("initial_sequence", initial_sequence, 8)
        self.serial_port = serial_port
        self.timeout = timeout
        self.retries = retries
        self.sequence = initial_sequence
        self.decoder = ResponseStreamDecoder()
        self.log = log

    def _emit(self, message: str) -> None:
        if self.log is not None:
            self.log(message)

    def _allocate_sequence(self) -> int:
        sequence = self.sequence
        self.sequence = (self.sequence + 1) & 0xFF
        return sequence

    def _write_exact(self, frame: bytes) -> None:
        try:
            written = self.serial_port.write(frame)
        except Exception as exc:
            raise TransportError(f"serial write failed: {exc}") from exc
        if written is not None and written != len(frame):
            raise TransportError(f"serial write was short: {written}/{len(frame)} bytes")

    def _wait_for_sequence(self, sequence: int) -> ResponseFrame:
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            try:
                data = self.serial_port.read(64)
            except Exception as exc:
                raise TransportError(f"serial read failed: {exc}") from exc

            for response in self.decoder.feed(data):
                if response.sequence == sequence:
                    return response
                self._emit(
                    f"[RX] ignored stale response seq=0x{response.sequence:02X}; "
                    f"waiting for 0x{sequence:02X}"
                )
            if not data:
                time.sleep(0.001)
        raise AckTimeout(f"timeout waiting for response seq=0x{sequence:02X}")

    def transact(
        self,
        command: Command,
        *,
        address: int = 0,
        data: int = 0,
        flags: int = 0,
    ) -> ResponseFrame:
        """Send one request and wait for a matching-sequence OK response.

        ``retries`` is the number of retransmissions after the initial send.
        Every retransmission uses the exact same bytes and sequence number.
        """

        sequence = self._allocate_sequence()
        frame = build_request(command, sequence, address, data, flags)
        attempts = self.retries + 1

        for attempt in range(attempts):
            if attempt:
                self._emit(
                    f"[RETRY] {Command(command).name} seq=0x{sequence:02X} "
                    f"attempt={attempt + 1}/{attempts}"
                )
            self._write_exact(frame)
            try:
                response = self._wait_for_sequence(sequence)
            except AckTimeout:
                if attempt + 1 == attempts:
                    raise AckTimeout(
                        f"no response for {Command(command).name} seq=0x{sequence:02X} "
                        f"after {attempts} attempts"
                    )
                continue

            if not response.ok:
                if response.status in RETRYABLE_STATUSES and attempt + 1 < attempts:
                    self._emit(
                        f"[NACK] {response.status_name} seq=0x{sequence:02X}; "
                        "resending the same frame"
                    )
                    continue
                raise DeviceRejected(response)
            return response

        raise AssertionError("unreachable retry loop")

    def begin(self, expected_words: int) -> ResponseFrame:
        if not 1 <= expected_words <= IMEM_WORDS:
            raise ValueError(f"expected_words must be in 1..{IMEM_WORDS}")
        try:
            return self.transact(Command.BEGIN, address=expected_words)
        except DeviceRejected as exc:
            if exc.response.status != Status.SEQ_CONFLICT:
                raise
            self._emit(
                "[RESYNC] BEGIN sequence collided with the FPGA cache; "
                "retrying once with the next sequence"
            )
            return self.transact(Command.BEGIN, address=expected_words)

    def write_word(self, address: int, instruction: int) -> ResponseFrame:
        if not 0 <= address < IMEM_WORDS:
            raise ValueError(f"write address must be in 0..{IMEM_WORDS - 1}")
        _check_uint("instruction", instruction, 32)
        return self.transact(Command.WRITE, address=address, data=instruction)

    def run(self) -> ResponseFrame:
        return self.transact(Command.RUN)

    def stop(self) -> ResponseFrame:
        return self.transact(Command.STOP)

    def status(self) -> ResponseFrame:
        return self.transact(Command.STATUS)

    def upload_program(
        self,
        words: Sequence[int],
        *,
        auto_run: bool = False,
        progress: Optional[Callable[[int, int], None]] = None,
    ) -> UploadResult:
        if not words:
            raise ValueError("program is empty")
        if len(words) > IMEM_WORDS:
            raise ValueError(f"program exceeds {IMEM_WORDS} instruction words")
        for word in words:
            _check_uint("instruction", word, 32)

        begin_response = self.begin(len(words))
        write_responses: list[ResponseFrame] = []
        for address, word in enumerate(words):
            write_responses.append(self.write_word(address, word))
            if progress is not None:
                progress(address + 1, len(words))
        run_response = self.run() if auto_run else None
        return UploadResult(
            expected_words=len(words),
            begin_response=begin_response,
            write_responses=tuple(write_responses),
            run_response=run_response,
        )


_HEX_WORD_RE = re.compile(r"^(?:0[xX])?([0-9a-fA-F]{8})$")
_ADDRESS_WRITE_RE = re.compile(
    r"^@([0-9a-fA-F]{1,4})\s+(?:0[xX])?([0-9a-fA-F]{8})$"
)


def parse_hex_word(text: str) -> int:
    match = _HEX_WORD_RE.fullmatch(text.strip())
    if match is None:
        raise ValueError("instruction must contain exactly 8 hexadecimal digits")
    return int(match.group(1), 16)


def parse_addressed_word(text: str) -> tuple[int, int]:
    match = _ADDRESS_WRITE_RE.fullmatch(text.strip())
    if match is None:
        raise ValueError("addressed write syntax is: @HEX_WORD_ADDRESS 8_HEX_DIGITS")
    address = int(match.group(1), 16)
    if address >= IMEM_WORDS:
        raise ValueError(f"word address must be in 0..0x{IMEM_WORDS - 1:02X}")
    return address, int(match.group(2), 16)


def _strip_mem_comment(line: str) -> str:
    comment_positions = [
        position
        for marker in ("//", "#", ";")
        if (position := line.find(marker)) >= 0
    ]
    if comment_positions:
        return line[: min(comment_positions)]
    return line


def parse_mem_text(text: str, *, start_address: int = 0) -> list[int]:
    """Parse a Vivado-style readmemh file into a dense program image.

    Plain words are placed sequentially. ``@HEX_ADDRESS`` changes the current
    absolute word address. Gaps, including an explicit start-address offset,
    are filled with RISC-V NOP instructions because RUN requires a complete
    [0, expected_words) write bitmap.
    """

    if not 0 <= start_address < IMEM_WORDS:
        raise ValueError(f"start_address must be in 0..{IMEM_WORDS - 1}")

    current_address = start_address
    sparse_words: dict[int, int] = {}

    for line_number, raw_line in enumerate(text.splitlines(), 1):
        line = _strip_mem_comment(raw_line).strip()
        if not line:
            continue

        for token in line.split():
            if token.startswith("@"):
                address_text = token[1:]
                if not re.fullmatch(r"[0-9a-fA-F]{1,8}", address_text):
                    raise ValueError(f"line {line_number}: invalid address token {token!r}")
                current_address = int(address_text, 16)
                if current_address >= IMEM_WORDS:
                    raise ValueError(
                        f"line {line_number}: address 0x{current_address:X} exceeds IMEM"
                    )
                continue

            word_text = token[2:] if token.lower().startswith("0x") else token
            if not re.fullmatch(r"[0-9a-fA-F]{1,8}", word_text):
                raise ValueError(f"line {line_number}: invalid 32-bit word {token!r}")
            if current_address >= IMEM_WORDS:
                raise ValueError(
                    f"line {line_number}: program exceeds {IMEM_WORDS} instruction words"
                )
            if current_address in sparse_words:
                raise ValueError(
                    f"line {line_number}: duplicate word address 0x{current_address:04X}"
                )
            sparse_words[current_address] = int(word_text, 16)
            current_address += 1

    if not sparse_words:
        raise ValueError("program contains no instruction words")

    expected_words = max(sparse_words) + 1
    words = [NOP_INSTRUCTION] * expected_words
    for address, word in sparse_words.items():
        words[address] = word
    return words


def load_mem_file(path: Path, *, start_address: int = 0) -> list[int]:
    try:
        text = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError) as exc:
        raise LoaderError(f"cannot read program file {path}: {exc}") from exc
    try:
        return parse_mem_text(text, start_address=start_address)
    except ValueError as exc:
        raise LoaderError(f"invalid program file {path}: {exc}") from exc


def format_response(label: str, response: ResponseFrame) -> str:
    return (
        f"[{label}] status={response.status_name} seq=0x{response.sequence:02X} "
        f"addr=0x{response.address:04X} detail=0x{response.detail:02X}"
    )


def format_status(response: ResponseFrame) -> str:
    state = LOADER_STATE_NAMES[response.detail & DETAIL_STATE_MASK]
    session = int(bool(response.detail & DETAIL_SESSION_ACTIVE))
    complete = int(bool(response.detail & DETAIL_COMPLETE))
    return (
        f"[STATUS] written_unique={response.address} state={state} "
        f"session_active={session} complete={complete} "
        f"detail=0x{response.detail:02X}"
    )


INTERACTIVE_HELP = """Commands:
  begin [COUNT]       clear IMEM and expect COUNT words (default: 256)
  8_HEX_DIGITS       write at the current word address, then advance
  @ADDR 8_HEX_DIGITS write at an absolute hexadecimal word address
  load FILE.mem      BEGIN, then load a complete .mem program
  status             query loader state and received-word count
  run                release CPU reset (requires a complete program)
  stop               hold CPU in reset without erasing the program
  help                show this help
  quit                close the serial port
"""


def _unquote_path(text: str) -> str:
    value = text.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def run_interactive(
    client: UartLoaderClient,
    *,
    input_fn: Callable[[str], str] = input,
    output: Callable[[str], None] = print,
) -> int:
    """Run the keyboard-driven loader shell."""

    current_address = 0
    expected_words: Optional[int] = None
    output(INTERACTIVE_HELP.rstrip())

    while True:
        try:
            line = input_fn("cpu-uart> ").strip()
        except (EOFError, KeyboardInterrupt):
            output("")
            return 0
        if not line:
            continue

        command_text, _, argument = line.partition(" ")
        command = command_text.lower()

        try:
            if command in {"quit", "exit"}:
                return 0
            if command in {"help", "?"}:
                output(INTERACTIVE_HELP.rstrip())
                continue
            if command == "begin":
                if argument.strip():
                    expected = int(argument.strip(), 0)
                else:
                    expected = IMEM_WORDS
                response = client.begin(expected)
                current_address = 0
                expected_words = expected
                output(format_response("BEGIN", response))
                continue
            if command == "load":
                filename = _unquote_path(argument)
                if not filename:
                    raise ValueError("load requires a .mem file path")
                words = load_mem_file(Path(filename))

                def show_progress(done: int, total: int) -> None:
                    if done == total or done == 1 or done % 16 == 0:
                        output(f"[WRITE] {done}/{total}")

                result = client.upload_program(words, progress=show_progress)
                expected_words = result.expected_words
                current_address = result.expected_words
                output(f"[LOAD] complete, {result.expected_words} words accepted")
                continue
            if command == "status" and not argument.strip():
                output(format_status(client.status()))
                continue
            if command == "run" and not argument.strip():
                output(format_response("RUN", client.run()))
                continue
            if command == "stop" and not argument.strip():
                output(format_response("STOP", client.stop()))
                continue

            if line.startswith("@"):
                address, word = parse_addressed_word(line)
                if expected_words is not None and address >= expected_words:
                    raise ValueError(
                        f"address 0x{address:04X} is outside current BEGIN count "
                        f"({expected_words})"
                    )
                response = client.write_word(address, word)
                current_address = address + 1
                output(format_response(f"WRITE @{address:04X}", response))
                continue

            word = parse_hex_word(line)
            if current_address >= IMEM_WORDS:
                raise ValueError("current address is past the end of IMEM")
            if expected_words is not None and current_address >= expected_words:
                raise ValueError(
                    f"current address is outside current BEGIN count ({expected_words})"
                )
            response = client.write_word(current_address, word)
            output(format_response(f"WRITE @{current_address:04X}", response))
            current_address += 1
        except (LoaderError, ValueError) as exc:
            output(f"[ERROR] {exc}")


def list_serial_ports(output: Callable[[str], None] = print) -> int:
    try:
        from serial.tools import list_ports
    except ImportError:
        output("pyserial is not installed. Run: python -m pip install pyserial")
        return 1

    ports = list(list_ports.comports())
    if not ports:
        output("No serial ports found.")
        return 1
    for port in ports:
        output(f"{port.device:>8}  {port.description}")
    return 0


def open_serial_port(port: str, baud: int, timeout: float):
    try:
        import serial
    except ImportError as exc:
        raise LoaderError(
            "pyserial is not installed. Run: python -m pip install pyserial"
        ) from exc

    try:
        return serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=min(timeout, 0.05),
            write_timeout=timeout,
        )
    except Exception as exc:
        raise LoaderError(f"cannot open serial port {port}: {exc}") from exc


def parse_cli_address(text: str) -> int:
    try:
        value = int(text, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("address must be decimal or 0x-prefixed hex") from exc
    if not 0 <= value < IMEM_WORDS:
        raise argparse.ArgumentTypeError(f"address must be in 0..{IMEM_WORDS - 1}")
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Reliably load 32-bit hexadecimal instructions into FPGA IMEM over UART."
    )
    parser.add_argument("--port", help="serial port, for example COM5")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help="UART baud rate")
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help="seconds to wait for each ACK",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=DEFAULT_RETRIES,
        help="retransmissions after the initial request",
    )
    parser.add_argument("--list-ports", action="store_true", help="list serial ports and exit")
    parser.add_argument("--file", type=Path, help="load a readmemh-style .mem file and exit")
    parser.add_argument(
        "--start-address",
        type=parse_cli_address,
        default=0,
        help="word address for the first plain word in --file (default: 0)",
    )
    parser.add_argument(
        "--run",
        action="store_true",
        help="automatically send RUN after a successful --file upload",
    )
    return parser


def _progress_printer(done: int, total: int) -> None:
    if done == total or done == 1 or done % 16 == 0:
        print(f"[WRITE] {done}/{total}")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.list_ports:
        return list_serial_ports()
    if not args.port:
        parser.error("--port is required unless --list-ports is used")
    if args.run and args.file is None:
        parser.error("--run requires --file")
    if args.baud <= 0:
        parser.error("--baud must be positive")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.retries < 0:
        parser.error("--retries cannot be negative")

    try:
        words = (
            load_mem_file(args.file, start_address=args.start_address)
            if args.file is not None
            else None
        )
        serial_port = open_serial_port(args.port, args.baud, args.timeout)
        with serial_port:
            reset_input = getattr(serial_port, "reset_input_buffer", None)
            if callable(reset_input):
                reset_input()
            print(f"[OPEN] port={args.port} baud={args.baud} format=8N1")
            client = UartLoaderClient(
                serial_port,
                timeout=args.timeout,
                retries=args.retries,
                log=print,
            )
            if words is None:
                return run_interactive(client)

            print(f"[LOAD] file={args.file} expected_words={len(words)}")
            result = client.upload_program(
                words,
                auto_run=args.run,
                progress=_progress_printer,
            )
            print(f"[LOAD] complete, {result.expected_words} words accepted")
            if result.run_response is not None:
                print(format_response("RUN", result.run_response))
            print(format_status(client.status()))
            return 0
    except (LoaderError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
