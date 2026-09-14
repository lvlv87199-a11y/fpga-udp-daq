## Day23 primary clock constraint.
## The simulation/top-level interface uses a single 100 MHz system clock.
create_clock -name sys_clk -period 10.000 [get_ports clk]
