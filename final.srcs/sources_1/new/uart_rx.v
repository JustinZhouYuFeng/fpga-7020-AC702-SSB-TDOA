// ============================================================================
// 简单的UART接收器 (SystemVerilog)
// 功能: 接收8N1格式数据，输出 rx_dv 脉冲表示数据有效
// ============================================================================
module uart_rx_simple #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD        = 921600
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,          // UART RX 输入线
    output logic [7:0] rx_byte,     // 接收到的字节
    output logic       rx_dv        // 数据有效标志 (Data Valid), 高电平脉冲
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;
    localparam int CLKS_HALF_BIT = CLKS_PER_BIT / 2;

    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        START   = 3'd1,
        DATA    = 3'd2,
        STOP    = 3'd3,
        CLEANUP = 3'd4
    } state_t;

    state_t state;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] rx_shifter; // 移位寄存器

    // 1. 异步信号同步化 (消除亚稳态)
    logic rx_sync_1, rx_sync;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_1 <= 1'b1;
            rx_sync   <= 1'b1;
        end else begin
            rx_sync_1 <= rx;
            rx_sync   <= rx_sync_1;
        end
    end

    // 2. 状态机逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            clk_cnt <= 0;
            bit_cnt <= 0;
            rx_dv   <= 1'b0;
            rx_byte <= 8'h00;
            rx_shifter <= 8'h00;
        end else begin
            // 默认拉低有效标志
            rx_dv <= 1'b0; 

            case (state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_cnt <= 0;
                    // 检测到下降沿 (Start Bit)
                    if (rx_sync == 1'b0) begin
                        state <= START;
                    end
                end

                // 起始位确认：等待半个周期，确认还是低电平，定位到波形中心
                START: begin
                    if (clk_cnt == CLKS_HALF_BIT) begin
                        if (rx_sync == 1'b0) begin
                            clk_cnt <= 0;
                            state   <= DATA;
                        end else begin
                            state   <= IDLE; // 误触发，或者是毛刺
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // 接收8位数据
                DATA: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        rx_shifter[bit_cnt] <= rx_sync; // LSB First 采样
                        
                        if (bit_cnt < 7) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            bit_cnt <= 0;
                            state   <= STOP;
                        end
                    end
                end

                // 停止位
                STOP: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        rx_dv   <= 1'b1;       // **数据接收完成，输出脉冲**
                        rx_byte <= rx_shifter; // 更新输出数据
                        state   <= CLEANUP;
                    end
                end
                
                // 回到空闲前的清理
                CLEANUP: begin
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule