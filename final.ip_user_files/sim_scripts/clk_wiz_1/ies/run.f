-makelib ies_lib/xpm -sv \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
-endlib
-makelib ies_lib/xpm \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../deceived.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1_clk_wiz.v" \
  "../../../../deceived.srcs/sources_1/ip/clk_wiz_1/clk_wiz_1.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

