`timescale 1ns / 1ps
// ============================================================================
// UART接收模块测试平台 (简化版)
// ============================================================================

module tb_uart_rx();

    // 参数
    parameter CLK_FREQ_HZ = 100_000_000;
    parameter BAUD = 921600;
    parameter CLK_PERIOD = 10;
    parameter BIT_PERIOD = 1080;  // 100M / 921600 ≈ 108 clk = 1080ns
    
    // 信号
    reg clk;
    reg rst_n;
    reg rx;
    wire [7:0] rx_byte;
    wire rx_dv;
    
    // DUT
    uart_rx_simple #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD(BAUD)
    ) u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .rx_byte(rx_byte),
        .rx_dv(rx_dv)
    );
    
    // 时钟
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 发送一个字节
    task send_byte(input [7:0] data);
        integer i;
        begin
            // 起始位
            rx = 0;
            #BIT_PERIOD;
            
            // 8位数据 LSB先发
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                #BIT_PERIOD;
            end
            
            // 停止位
            rx = 1;
            #BIT_PERIOD;
            
            // 间隙
            #(BIT_PERIOD/2);
        end
    endtask
    
    // 主测试
    initial begin
        $display("=== UART RX Test Start ===");
        
        // 初始化
        rst_n = 0;
        rx = 1;
        
        // 复位
        #200;
        rst_n = 1;
        #100;
        
        $display("Sending 0x55...");
        send_byte(8'h55);
        
        $display("Sending 0xAA...");
        send_byte(8'hAA);
        
        $display("Sending 0x12...");
        send_byte(8'h12);
        
        $display("Sending 0x34...");
        send_byte(8'h34);
        
        // 等待
        #5000;
        
        $display("=== UART RX Test End ===");
        $finish;
    end
    
    // 监控接收
    always @(posedge clk) begin
        if (rx_dv) begin
            $display("[%0t] Received: 0x%02X", $time, rx_byte);
        end
    end
    
    // 波形
    initial begin
        $dumpfile("tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
    end

endmodule
