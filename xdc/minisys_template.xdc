## Minisys board constraints for src/minisys_top.v
## clk: on-board 100 MHz oscillator
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## rst_btn: S6 push button, active high
set_property PACKAGE_PIN P20 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

## led[7:0] mapped to red LEDs RLD0~RLD7
set_property PACKAGE_PIN N19 [get_ports {led[0]}]
set_property PACKAGE_PIN N20 [get_ports {led[1]}]
set_property PACKAGE_PIN M20 [get_ports {led[2]}]
set_property PACKAGE_PIN K13 [get_ports {led[3]}]
set_property PACKAGE_PIN K14 [get_ports {led[4]}]
set_property PACKAGE_PIN M13 [get_ports {led[5]}]
set_property PACKAGE_PIN L13 [get_ports {led[6]}]
set_property PACKAGE_PIN K17 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
