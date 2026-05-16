vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/xil_defaultlib

vmap xpm questa_lib/msim/xpm
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xpm  -sv "+incdir+../../../../deceived.srcs/sources_1/ip/ila_0/hdl/verilog" \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \

vcom -work xpm  -93 \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  "+incdir+../../../../deceived.srcs/sources_1/ip/ila_0/hdl/verilog" \
"../../../../deceived.srcs/sources_1/ip/ila_0/sim/ila_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

