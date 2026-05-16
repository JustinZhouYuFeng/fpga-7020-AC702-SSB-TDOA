// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.1 (win64) Build 2902540 Wed May 27 19:54:49 MDT 2020
// Date        : Thu Jan  8 18:12:44 2026
// Host        : LAPTOP-SQ1PBBIP running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/Users/19571/Desktop/fpga-silmulation/final/final.srcs/sources_1/ip/vio_0/vio_0_stub.v
// Design      : vio_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z020clg400-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "vio,Vivado 2020.1" *)
module vio_0(clk, probe_out0, probe_out1, probe_out2, 
  probe_out3, probe_out4, probe_out5)
/* synthesis syn_black_box black_box_pad_pin="clk,probe_out0[31:0],probe_out1[31:0],probe_out2[31:0],probe_out3[3:0],probe_out4[31:0],probe_out5[31:0]" */;
  input clk;
  output [31:0]probe_out0;
  output [31:0]probe_out1;
  output [31:0]probe_out2;
  output [3:0]probe_out3;
  output [31:0]probe_out4;
  output [31:0]probe_out5;
endmodule
