`timescale 1ns / 1ps
// ============================================================================
// 模块名：rom_player
// 作  用：驱动单口 ROM 的地址，从 0 递增到 LAST_ADDR 后回绕，形成循环播放
// ============================================================================
module rom_player #(
    parameter integer ADDR_W    = 12,        // 参数：地址位宽
    parameter integer LAST_ADDR = 12'd2999   // 参数：最后有效地址
)(
    input  wire                   clk,       // 输入：时钟
    input  wire                   rst_n,     // 输入：复位 (低有效)
    output reg  [ADDR_W-1:0]      addr,      // 输出：ROM 地址
    output reg                    en         // 输出：ROM 使能
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr <= {ADDR_W{1'b0}};
            en   <= 1'b0;
        end else begin
            en   <= 1'b1;
            if (addr == LAST_ADDR)
                addr <= {ADDR_W{1'b0}};
            else
                addr <= addr + 1'b1;
        end
    end

endmodule