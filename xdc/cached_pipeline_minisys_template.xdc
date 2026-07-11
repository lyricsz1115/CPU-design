## Cached pipeline CPU board test top: cached_pipeline_minisys_top

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

set_property PACKAGE_PIN W4 [get_ports {sw[0]}]
set_property PACKAGE_PIN R4 [get_ports {sw[1]}]
set_property PACKAGE_PIN T4 [get_ports {sw[2]}]
set_property PACKAGE_PIN T5 [get_ports {sw[3]}]
set_property PACKAGE_PIN U5 [get_ports {sw[4]}]
set_property PACKAGE_PIN W6 [get_ports {sw[5]}]
set_property PACKAGE_PIN W5 [get_ports {sw[6]}]
set_property PACKAGE_PIN U6 [get_ports {sw[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]
