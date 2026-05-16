# =============================================================================
# 1. 系统时钟 (50MHz)
# =============================================================================
set_property PACKAGE_PIN U18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

# =============================================================================
# 2. 系统复位 (使用扩展板 KEY0)
# =============================================================================
# 注意：KEY0 在 ACZ702 上是 H20
set_property PACKAGE_PIN H20 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# =============================================================================
# 3. 串口 UART (扩展板接口)
# =============================================================================
# TX 发送端 (FPGA -> PC) : 扩展板 GPIO26 -> ACZ702 J16
set_property PACKAGE_PIN J16 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# RX 接收端 (PC -> FPGA) : 扩展板 GPIO27 -> ACZ702 K16
# ★★★ 新增：用于接收电脑下发的波形数据 ★★★
set_property PACKAGE_PIN K16 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# =============================================================================
# 4. 功能按键 (使用扩展板 KEY1)
# =============================================================================
# 用于后续切换波形来源 (ROM/RAM) 或其他模式
# KEY1 在 ACZ702 上是 H16
set_property PACKAGE_PIN H16 [get_ports key_mode]
set_property IOSTANDARD LVCMOS33 [get_ports key_mode]

# =============================================================================
# 5. 调试核配置 (ILA/VIO / Debug Hub)
# =============================================================================

set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_OBUF]