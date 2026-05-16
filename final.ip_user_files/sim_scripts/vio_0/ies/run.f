-makelib ies_lib/xpm -sv \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
-endlib
-makelib ies_lib/xpm \
  "D:/fpga/Vivado/2020.1/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../final.srcs/sources_1/ip/vio_0/sim/vio_0.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

