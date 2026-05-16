`timescale 1ns / 1ps
// ============================================================================
// UART发送模块测试平台
// ============================================================================

module tb_uart_tx();

    // ========================================================================
    // 参数定义
    // ========================================================================
    parameter CLK_FREQ_HZ = 100_000_000;
    parameter BAUD = 921600;
    parameter CLK_PERIOD = 10;
    parameter PACKET_LEN = 18;
    
    // ========================================================================
    // 信号定义
    // ========================================================================
    reg clk;
    reg rst_n;
    reg tx_start;
    reg [7:0] tx_byte;
    wire tx;
    wire busy;
    
    // 测试数据包
    reg [7:0] tx_packet [0:17];
    reg [4:0] pkt_idx;
    reg busy_prev;  // 用于检测busy下降沿
    
    // 状态机
    reg [2:0] test_state;
    localparam S_IDLE = 0, S_LOAD = 1, S_START = 2, S_WAIT_BUSY_HIGH = 3, S_WAIT_BUSY_LOW = 4, S_NEXT = 5, S_DONE = 6;
    
    // 统计
    integer bytes_sent;
    
    // ========================================================================
    // DUT实例化
    // ========================================================================
    uart_tx_simple #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD(BAUD)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        .tx(tx),
        .busy(busy)
    );
    
    // ========================================================================
    // 时钟生成 (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ========================================================================
    // CRC-8计算函数
    // ========================================================================
    function [7:0] crc8_calc;
        input [7:0] crc_in;
        input [7:0] data_in;
        reg [7:0] c;
        integer i;
        begin
            c = crc_in ^ data_in;
            for (i = 0; i < 8; i = i + 1) begin
                if (c[7])
                    c = (c << 1) ^ 8'h07;
                else
                    c = c << 1;
            end
            crc8_calc = c;
        end
    endfunction
    
    // ========================================================================
    // 数据包初始化
    // ========================================================================
    task init_packet;
        reg [7:0] crc;
        begin
            // 同步头
            tx_packet[0] = 8'h55;
            tx_packet[1] = 8'hAA;
            // 帧序号
            tx_packet[2] = 8'h01;
            // T0 = 100
            tx_packet[3] = 8'h00;
            tx_packet[4] = 8'h64;
            // DT10 = 10
            tx_packet[5] = 8'h00;
            tx_packet[6] = 8'h0A;
            // DT20 = 20
            tx_packet[7] = 8'h00;
            tx_packet[8] = 8'h14;
            // DT30 = 30
            tx_packet[9] = 8'h00;
            tx_packet[10] = 8'h1E;
            // SHAPE = 0
            tx_packet[11] = 8'h00;
            // V_IDX = 5
            tx_packet[12] = 8'h05;
            // X = 100
            tx_packet[13] = 8'h00;
            tx_packet[14] = 8'h64;
            // Y = 150
            tx_packet[15] = 8'h00;
            tx_packet[16] = 8'h96;
            
            // 计算CRC
            crc = 8'h00;
            crc = crc8_calc(crc, tx_packet[2]);
            crc = crc8_calc(crc, tx_packet[3]);
            crc = crc8_calc(crc, tx_packet[4]);
            crc = crc8_calc(crc, tx_packet[5]);
            crc = crc8_calc(crc, tx_packet[6]);
            crc = crc8_calc(crc, tx_packet[7]);
            crc = crc8_calc(crc, tx_packet[8]);
            crc = crc8_calc(crc, tx_packet[9]);
            crc = crc8_calc(crc, tx_packet[10]);
            crc = crc8_calc(crc, tx_packet[11]);
            crc = crc8_calc(crc, tx_packet[12]);
            crc = crc8_calc(crc, tx_packet[13]);
            crc = crc8_calc(crc, tx_packet[14]);
            crc = crc8_calc(crc, tx_packet[15]);
            crc = crc8_calc(crc, tx_packet[16]);
            tx_packet[17] = crc;
        end
    endtask
    
    // ========================================================================
    // 主测试状态机
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_state <= S_IDLE;
            tx_start <= 0;
            tx_byte <= 0;
            pkt_idx <= 0;
            bytes_sent <= 0;
            busy_prev <= 0;
        end else begin
            busy_prev <= busy;  // 记录上一拍busy状态
            
            case (test_state)
                S_IDLE: begin
                    pkt_idx <= 0;
                    test_state <= S_LOAD;
                end
                
                S_LOAD: begin
                    // 加载当前字节
                    tx_byte <= tx_packet[pkt_idx];
                    tx_start <= 0;
                    test_state <= S_START;
                end
                
                S_START: begin
                    // 等待不忙，然后发送启动脉冲
                    if (!busy) begin
                        tx_start <= 1;
                        test_state <= S_WAIT_BUSY_HIGH;
                    end
                end
                
                S_WAIT_BUSY_HIGH: begin
                    // 等待busy变高（UART开始发送）
                    tx_start <= 0;
                    if (busy) begin
                        test_state <= S_WAIT_BUSY_LOW;
                    end
                end
                
                S_WAIT_BUSY_LOW: begin
                    // 等待busy变低（发送完成）
                    if (!busy) begin
                        bytes_sent <= bytes_sent + 1;
                        test_state <= S_NEXT;
                    end
                end
                
                S_NEXT: begin
                    // 下一字节
                    if (pkt_idx < PACKET_LEN - 1) begin
                        pkt_idx <= pkt_idx + 1;
                        test_state <= S_LOAD;
                    end else begin
                        test_state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    // 完成，保持
                end
                
                default: test_state <= S_IDLE;
            endcase
        end
    end
    
    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        // 初始化
        rst_n = 0;
        tx_start = 0;
        tx_byte = 0;
        
        // 初始化数据包
        init_packet();
        
        // 打印信息
        $display("========================================");
        $display("UART发送测试");
        $display("波特率: %0d bps", BAUD);
        $display("========================================");
        $display("数据包: 0x%02X 0x%02X 0x%02X ...", tx_packet[0], tx_packet[1], tx_packet[2]);
        
        // 复位
        repeat(20) @(posedge clk);
        rst_n = 1;
        $display("[%0t] 复位释放", $time);
        
        // 等待发送完成
        wait(test_state == S_DONE);
        $display("[%0t] 发送完成! 共%0d字节", $time, bytes_sent);
        
        // 额外等待
        repeat(2000) @(posedge clk);
        $display("========================================");
        $finish;
    end
    
    // ========================================================================
    // 监控
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n && test_state == S_WAIT_BUSY_HIGH && busy) begin
            $display("[%0t] 发送[%0d]: 0x%02X", $time, pkt_idx, tx_byte);
        end
    end
    
    // ========================================================================
    // 波形输出
    // ========================================================================
    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end
    
    // ========================================================================
    // 超时保护
    // ========================================================================
    initial begin
        #5000000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
