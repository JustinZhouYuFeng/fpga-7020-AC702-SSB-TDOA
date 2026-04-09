`timescale 1ns / 1ps
// ============================================================================
// UART 发送模块 (简化版)
// 波特率: 可配置 (默认 921600)
// 帧格式: 8N1 (8位数据, 无校验, 1位停止)
// ============================================================================

module uart_tx_simple #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD = 921600
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,    // 发送启动脉冲
    input  logic [7:0] tx_byte,     // 待发送字节
    output logic       tx,          // UART TX 引脚
    output logic       busy         // 忙标志
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;
    
    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        START   = 3'd1,
        DATA    = 3'd2,
        STOP    = 3'd3
    } state_t;
    
    state_t state;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] tx_data;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            tx      <= 1'b1;
            busy    <= 1'b0;
            clk_cnt <= 0;
            bit_cnt <= 0;
            tx_data <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 0;
                    bit_cnt <= 0;
                    if (tx_start) begin
                        tx_data <= tx_byte;
                        state   <= START;
                        busy    <= 1'b1;
                    end
                end
                
                START: begin
                    tx <= 1'b0;  // 起始位
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        state   <= DATA;
                    end
                end
                
                DATA: begin
                    tx <= tx_data[bit_cnt];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_cnt < 7) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            bit_cnt <= 0;
                            state   <= STOP;
                        end
                    end
                end
                
                STOP: begin
                    tx <= 1'b1;  // 停止位
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule

