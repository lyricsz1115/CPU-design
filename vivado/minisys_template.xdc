## Replace PACKAGE_PIN values with the official Minisys board constraints.
## Keep signal names aligned with src/minisys_top.v.

# set_property PACKAGE_PIN <PIN> [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]

# set_property PACKAGE_PIN <PIN> [get_ports rst_btn]
# set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

# set_property PACKAGE_PIN <PIN> [get_ports {led[0]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[1]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[2]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[3]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[4]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[5]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[6]}]
# set_property PACKAGE_PIN <PIN> [get_ports {led[7]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
