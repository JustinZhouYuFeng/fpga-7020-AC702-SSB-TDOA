`timescale 1ns / 1ps
// ============================================================================
// 模块名：dds_unpack
// 作用：从 DDS Compiler 的 m_axis_data_tdata 中拆分 COS 和 SIN
// ============================================================================
module dds_unpack #(
    parameter int W = 14,
    parameter bit SWAP_CS = 1'b0
)(
    input  logic [31:0] dds_bus,
    output logic signed [W-1:0] cos_q,
    output logic signed [W-1:0] sin_q
);

    // DDS Compiler 输出格式 (Sine_and_Cosine, 14bit, Two's Complement):
    //   [31:16] = COS (高半字，有效位在 [31:18]，低2位是padding)
    //   [15:0]  = SIN (低半字，有效位在 [15:2]，低2位是padding)
    // 这里直接取高 W 位（已含符号位）
    logic signed [W-1:0] lowW;
    logic signed [W-1:0] highW;

    assign lowW  = dds_bus[15 -: W];   // SIN: bit[15:2] 取14位
    assign highW = dds_bus[31 -: W];   // COS: bit[31:18] 取14位

    always_comb begin
        if (!SWAP_CS) begin
            cos_q = highW;
            sin_q = lowW;
        end else begin
            cos_q = lowW;
            sin_q = highW;
        end
    end

endmodule
