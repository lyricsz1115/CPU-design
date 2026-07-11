from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Callable, Optional


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cpu_uart_loader as loader


class FakeSerial:
    def __init__(
        self,
        responder: Optional[Callable[[bytes, int], bytes]] = None,
    ) -> None:
        self.responder = responder
        self.writes: list[bytes] = []
        self.rx = bytearray()

    def write(self, data: bytes) -> int:
        frame = bytes(data)
        self.writes.append(frame)
        if self.responder is not None:
            self.rx.extend(self.responder(frame, len(self.writes)))
        return len(frame)

    def read(self, size: int = 1) -> bytes:
        if not self.rx:
            return b""
        count = min(size, len(self.rx))
        result = bytes(self.rx[:count])
        del self.rx[:count]
        return result


def ack_for_request(frame: bytes, *, detail: int = 0) -> bytes:
    request = loader.parse_request(frame)
    return loader.build_response(
        loader.Status.OK,
        request.sequence,
        request.address,
        detail,
    )


class ProtocolTests(unittest.TestCase):
    def test_crc8_atm_check_value(self) -> None:
        self.assertEqual(loader.crc8(b"123456789"), 0xF4)

    def test_write_request_layout_and_round_trip(self) -> None:
        raw = loader.build_request(
            loader.Command.WRITE,
            sequence=0x5A,
            address=0x0123,
            data=0x89ABCDEF,
        )
        self.assertEqual(len(raw), 12)
        self.assertEqual(raw[:11], bytes.fromhex("AA 49 02 5A 23 01 EF CD AB 89 00"))
        self.assertEqual(raw[-1], 0x5C)
        self.assertEqual(
            loader.parse_request(raw),
            loader.RequestFrame(loader.Command.WRITE, 0x5A, 0x0123, 0x89ABCDEF, 0),
        )

    def test_response_layout_and_round_trip(self) -> None:
        raw = loader.build_response(loader.Status.OK, 0x2C, 0x0100, 0x0D)
        self.assertEqual(raw, bytes.fromhex("AA 41 00 2C 00 01 0D 37"))
        response = loader.parse_response(raw)
        self.assertTrue(response.ok)
        self.assertEqual(response.address, 256)
        self.assertEqual(response.detail, 0x0D)

    def test_status_detail_format_matches_rtl_state_encoding(self) -> None:
        detail = loader.DETAIL_STATE_RUN | loader.DETAIL_SESSION_ACTIVE | loader.DETAIL_COMPLETE
        response = loader.ResponseFrame(loader.Status.OK, 1, 9, detail)
        summary = loader.format_status(response)
        self.assertIn("written_unique=9", summary)
        self.assertIn("state=run", summary)
        self.assertIn("session_active=1", summary)
        self.assertIn("complete=1", summary)

    def test_bad_response_crc_is_rejected(self) -> None:
        raw = bytearray(loader.build_response(loader.Status.OK, 1, 2, 3))
        raw[-1] ^= 0x01
        with self.assertRaises(loader.FrameError):
            loader.parse_response(bytes(raw))

    def test_stream_decoder_resynchronizes_and_accepts_fragments(self) -> None:
        first = loader.build_response(loader.Status.OK, 1, 2, 3)
        corrupt = bytearray(loader.build_response(loader.Status.OK, 9, 9, 9))
        corrupt[-1] ^= 0xFF
        second = loader.build_response(loader.Status.INCOMPLETE, 2, 4, 5)
        decoder = loader.ResponseStreamDecoder()

        self.assertEqual(decoder.feed(b"noise" + first[:3]), [])
        self.assertEqual(decoder.feed(first[3:] + bytes(corrupt) + second[:2])[0].sequence, 1)
        final = decoder.feed(second[2:])
        self.assertEqual(len(final), 1)
        self.assertEqual(final[0].status, loader.Status.INCOMPLETE)


class ProgramParserTests(unittest.TestCase):
    def test_parse_mem_comments_address_markers_and_nop_fill(self) -> None:
        words = loader.parse_mem_text(
            """
            # first instruction
            00000093
            @0003 00100113 // gap at words 1 and 2
            0000006f ; self-loop
            """
        )
        self.assertEqual(
            words,
            [0x00000093, loader.NOP_INSTRUCTION, loader.NOP_INSTRUCTION, 0x00100113, 0x0000006F],
        )

    def test_start_address_is_filled_with_nops(self) -> None:
        self.assertEqual(
            loader.parse_mem_text("0000006f", start_address=2),
            [loader.NOP_INSTRUCTION, loader.NOP_INSTRUCTION, 0x0000006F],
        )

    def test_empty_and_oversized_programs_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "no instruction"):
            loader.parse_mem_text("# only a comment")
        with self.assertRaisesRegex(ValueError, "exceeds IMEM"):
            loader.parse_mem_text("@100 00000013")

    def test_duplicate_addresses_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate"):
            loader.parse_mem_text("@0 00000013 @0 0000006f")

    def test_interactive_hex_parsers(self) -> None:
        self.assertEqual(loader.parse_hex_word("00A00093"), 0x00A00093)
        self.assertEqual(loader.parse_addressed_word("@0f DEADBEEF"), (15, 0xDEADBEEF))
        with self.assertRaises(ValueError):
            loader.parse_hex_word("123")
        with self.assertRaises(ValueError):
            loader.parse_addressed_word("@100 00000013")


class ClientTests(unittest.TestCase):
    def test_transaction_accepts_matching_sequence_ack(self) -> None:
        serial_port = FakeSerial(lambda frame, _: ack_for_request(frame))
        client = loader.UartLoaderClient(serial_port, timeout=0.01, initial_sequence=0x20)

        response = client.write_word(7, 0x00A00093)

        self.assertEqual(response.sequence, 0x20)
        request = loader.parse_request(serial_port.writes[0])
        self.assertEqual(request.command, loader.Command.WRITE)
        self.assertEqual(request.address, 7)
        self.assertEqual(request.data, 0x00A00093)

    def test_timeout_retries_exact_same_frame_and_sequence(self) -> None:
        def respond_on_third_write(frame: bytes, write_count: int) -> bytes:
            return ack_for_request(frame) if write_count == 3 else b""

        serial_port = FakeSerial(respond_on_third_write)
        client = loader.UartLoaderClient(
            serial_port,
            timeout=0.002,
            retries=3,
            initial_sequence=0xFE,
        )

        response = client.stop()

        self.assertEqual(response.sequence, 0xFE)
        self.assertEqual(len(serial_port.writes), 3)
        self.assertTrue(all(frame == serial_port.writes[0] for frame in serial_port.writes))
        self.assertEqual(client.sequence, 0xFF)

    def test_all_retries_exhausted(self) -> None:
        serial_port = FakeSerial()
        client = loader.UartLoaderClient(serial_port, timeout=0.001, retries=3)
        with self.assertRaises(loader.AckTimeout):
            client.status()
        self.assertEqual(len(serial_port.writes), 4)
        self.assertTrue(all(frame == serial_port.writes[0] for frame in serial_port.writes))

    def test_non_ok_response_raises_device_rejected_without_retry(self) -> None:
        def reject(frame: bytes, _: int) -> bytes:
            request = loader.parse_request(frame)
            return loader.build_response(
                loader.Status.BAD_STATE,
                request.sequence,
                request.address,
                detail=2,
            )

        serial_port = FakeSerial(reject)
        client = loader.UartLoaderClient(serial_port, timeout=0.01, retries=3)
        with self.assertRaises(loader.DeviceRejected) as context:
            client.run()
        self.assertEqual(context.exception.response.status, loader.Status.BAD_STATE)
        self.assertEqual(len(serial_port.writes), 1)

    def test_crc_nack_retries_the_exact_same_frame(self) -> None:
        def crc_nack_then_ack(frame: bytes, write_count: int) -> bytes:
            request = loader.parse_request(frame)
            if write_count == 1:
                return loader.build_response(
                    loader.Status.CRC_ERROR,
                    request.sequence,
                    request.address,
                    detail=0xA5,
                )
            return ack_for_request(frame)

        serial_port = FakeSerial(crc_nack_then_ack)
        client = loader.UartLoaderClient(serial_port, timeout=0.01, retries=3)

        self.assertTrue(client.status().ok)
        self.assertEqual(len(serial_port.writes), 2)
        self.assertEqual(serial_port.writes[0], serial_port.writes[1])

    def test_stale_sequence_response_is_ignored(self) -> None:
        def stale_then_ack(frame: bytes, _: int) -> bytes:
            request = loader.parse_request(frame)
            return loader.build_response(loader.Status.OK, request.sequence ^ 0x80) + ack_for_request(frame)

        serial_port = FakeSerial(stale_then_ack)
        client = loader.UartLoaderClient(serial_port, timeout=0.01, initial_sequence=4)
        self.assertEqual(client.status().sequence, 4)

    def test_upload_uses_expected_length_absolute_addresses_and_auto_run(self) -> None:
        serial_port = FakeSerial(lambda frame, _: ack_for_request(frame))
        client = loader.UartLoaderClient(serial_port, timeout=0.01)
        words = [0x00000093, 0x00100113, 0x0000006F]

        result = client.upload_program(words, auto_run=True)

        requests = [loader.parse_request(frame) for frame in serial_port.writes]
        self.assertEqual(
            [request.command for request in requests],
            [loader.Command.BEGIN, loader.Command.WRITE, loader.Command.WRITE, loader.Command.WRITE, loader.Command.RUN],
        )
        self.assertEqual(requests[0].address, 3)
        self.assertEqual([request.address for request in requests[1:4]], [0, 1, 2])
        self.assertEqual([request.data for request in requests[1:4]], words)
        self.assertEqual(result.expected_words, 3)
        self.assertIsNotNone(result.run_response)

    def test_begin_and_reserved_commands_have_required_zero_fields(self) -> None:
        serial_port = FakeSerial(lambda frame, _: ack_for_request(frame))
        client = loader.UartLoaderClient(serial_port, timeout=0.01)
        client.begin(256)
        client.run()
        client.stop()
        client.status()
        requests = [loader.parse_request(frame) for frame in serial_port.writes]

        self.assertEqual(requests[0].address, 256)
        self.assertEqual(requests[0].data, 0)
        self.assertEqual(requests[0].flags, 0)
        for request in requests[1:]:
            self.assertEqual((request.address, request.data, request.flags), (0, 0, 0))


if __name__ == "__main__":
    unittest.main()
