vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/blk_mem_gen_v8_4_4
vlib questa_lib/msim/xil_defaultlib

vmap xpm questa_lib/msim/xpm
vmap blk_mem_gen_v8_4_4 questa_lib/msim/blk_mem_gen_v8_4_4
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xpm  -sv \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \

vcom -work xpm  -93 \
"D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work blk_mem_gen_v8_4_4  \
"../../../ipstatic/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib  \
"../../../../final.srcs/sources_1/ip/blk_mem_gen_1/sim/blk_mem_gen_1.v" \

vlog -work xil_defaultlib \
"glbl.v"

