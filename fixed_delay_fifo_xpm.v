`timescale 1ns / 1ps
// ============================================================================
// 模块名：fixed_delay_fifo_xpm
// 作  用：利用 XPM_FIFO 实现固定样点延迟 D_SAMPLES
// ============================================================================
module fixed_delay_fifo_xpm #(
    parameter integer W            = 16,      // 数据位宽
    parameter integer D_SAMPLES    = 800,     // 固定时延样点数
    parameter integer DEPTH_POW2   = 1024     // FIFO 深度 (2^N >= D)
)(
    input  wire                 clk,
    input  wire                 rst_n,        // 复位 (低有效)
    input  wire [W-1:0]         din,
    input  wire                 din_valid,
    output wire [W-1:0]         dout,
    output wire                 dout_valid,

    // ILA 观测端口
    output wire                 wr_en_o,
    output wire                 rd_en_o,
    output reg                  rd_started_o,
    output reg  [$clog2(D_SAMPLES+1)-1:0] fill_cnt_o,
    output wire [15:0]          wr_count_o,
    output wire [15:0]          rd_count_o
);

    // 1. 写控制
    wire wr_en = din_valid;
    assign wr_en_o = wr_en;

    // 2. 起灌计数逻辑
    localparam FILL_W = $clog2(D_SAMPLES+1);
    reg [FILL_W-1:0] fill_cnt;
    reg              rd_started;

    // 3. 读控制
    wire rd_en = rd_started;
    assign rd_en_o = rd_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_cnt   <= {FILL_W{1'b0}};
            rd_started <= 1'b0;
        end else begin
            if (wr_en) begin
                if (!rd_started) begin
                    // 计数直到存满 D_SAMPLES-1 个数据，下一拍启动读
                    if (fill_cnt == D_SAMPLES-1)
                        rd_started <= 1'b1;
                    else
                        fill_cnt <= fill_cnt + 1'b1;
                end
            end
        end
    end

    // ILA 状态输出
    always @(posedge clk) begin
        rd_started_o <= rd_started;
        fill_cnt_o   <= fill_cnt;
    end

    // 4. XPM FIFO 实例化
    wire [W-1:0] fifo_dout;
    wire         fifo_dv;
    wire [31:0]  wr_data_count;
    wire [31:0]  rd_data_count;
    wire         xpm_rst = ~rst_n; // XPM 复位为高有效

    xpm_fifo_sync #(
        .DOUT_RESET_VALUE   ("0"),
        .ECC_MODE           ("no_ecc"),
        .FIFO_MEMORY_TYPE   ("block"),
        .FIFO_READ_LATENCY  (1),
        .FIFO_WRITE_DEPTH   (DEPTH_POW2),
        .READ_DATA_WIDTH    (W),
        .READ_MODE          ("std"),
        .WAKEUP_TIME        (0),
        .WRITE_DATA_WIDTH   (W)
    ) u_fifo (
        .wr_clk        (clk),
        .rst           (xpm_rst),
        .din           (din),
        .wr_en         (wr_en),
        .rd_en         (rd_en),
        .dout          (fifo_dout),
        .data_valid    (fifo_dv),
        .wr_data_count (wr_data_count),
        .rd_data_count (rd_data_count),
        .full(), .empty(), .prog_full(), .prog_empty(),
        .sleep(1'b0), .injectdbiterr(1'b0), .injectsbiterr(1'b0),
        .sbiterr(), .dbiterr(), .wr_rst_busy(), .rd_rst_busy()
    );

    assign dout       = fifo_dout;
    assign dout_valid = fifo_dv;
    assign wr_count_o = wr_data_count[15:0];
    assign rd_count_o = rd_data_count[15:0];

endmodule