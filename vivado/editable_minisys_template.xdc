## Editable instruction loader top constraints.
## Top: editable_minisys_top
##
## clk/rst/led pins are the same as minisys_template.xdc.
## Fill sw[7:0] and btn_* PACKAGE_PIN values from your Minisys board manual
## before running implementation.

set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

set_property PACKAGE_PIN P20 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

set_property PACKAGE_PIN N19 [get_ports {led[0]}]
set_property PACKAGE_PIN N20 [get_ports {led[1]}]
set_property PACKAGE_PIN M20 [get_ports {led[2]}]
set_property PACKAGE_PIN K13 [get_ports {led[3]}]
set_property PACKAGE_PIN K14 [get_ports {led[4]}]
set_property PACKAGE_PIN M13 [get_ports {led[5]}]
set_property PACKAGE_PIN L13 [get_ports {led[6]}]
set_property PACKAGE_PIN K17 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## sw[7:0] uses Minisys SW7~SW0.
set_property PACKAGE_PIN W4 [get_ports {sw[0]}]
set_property PACKAGE_PIN R4 [get_ports {sw[1]}]
set_property PACKAGE_PIN T4 [get_ports {sw[2]}]
set_property PACKAGE_PIN T5 [get_ports {sw[3]}]
set_property PACKAGE_PIN U5 [get_ports {sw[4]}]
set_property PACKAGE_PIN W6 [get_ports {sw[5]}]
set_property PACKAGE_PIN W5 [get_ports {sw[6]}]
set_property PACKAGE_PIN U6 [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

## btn_write/next/clear/run use Minisys S1~S4.
## btn_write: write current sw[7:0] byte.
## btn_next:  skip to next instruction address.
## btn_clear: return to load mode and clear loader address.
## btn_run:   start CPU from PC=0.
set_property PACKAGE_PIN R1 [get_ports btn_write]
set_property PACKAGE_PIN P1 [get_ports btn_next]
set_property PACKAGE_PIN P5 [get_ports btn_clear]
set_property PACKAGE_PIN P4 [get_ports btn_run]
set_property IOSTANDARD LVCMOS15 [get_ports {btn_write btn_next btn_clear btn_run}]
