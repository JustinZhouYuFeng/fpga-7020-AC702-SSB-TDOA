`timescale 1ns / 1ps
// ============================================================================
// SSB 混频器 (时序优化版 - 2级流水线)
// 实现 SSB 混频: USB = I*Cos - Q*Sin, LSB = I*Cos + Q*Sin
// 修改：USB_SEL改为输入端口，支持动态切换
// ============================================================================
module complex_ssb_mixer (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               usb_sel,        // 新增：1=USB, 0=LSB
    input  logic signed [15:0] i_in,
    input  logic signed [15:0] q_in,
    input  logic signed [13:0] cos14,
    input  logic signed [13:0] sin14,
    output logic signed [15:0] y_out,
    output logic signed [15:0] dbg_ic_q15,
    output logic signed [15:0] dbg_qs_q15
);

    // ========================================================================
    // Stage 1: 乘法 (寄存器输出)
    // ========================================================================
    logic signed [29:0] p_ic_s1;
    logic signed [29:0] p_qs_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_ic_s1 <= 0;
            p_qs_s1 <= 0;
        end else begin
            p_ic_s1 <= $signed(i_in) * $signed(cos14);
            p_qs_s1 <= $signed(q_in) * $signed(sin14);
        end
    end

    // ========================================================================
    // Stage 2: 加减法 + 缩放 + 饱和 (组合逻辑，路径短)
    // ========================================================================
    logic signed [30:0] acc_usb;
    logic signed [17:0] acc_q15;
    logic signed [15:0] sat;
    
    always_comb begin
        // USB: I*Cos - Q*Sin, LSB: I*Cos + Q*Sin
        if (usb_sel)  // 修改：使用输入信号
            acc_usb = $signed({p_ic_s1[29], p_ic_s1}) - $signed({p_qs_s1[29], p_qs_s1});
        else
            acc_usb = $signed({p_ic_s1[29], p_ic_s1}) + $signed({p_qs_s1[29], p_qs_s1});
        
        // 缩放回 Q15
        acc_q15 = acc_usb[30:13];
        
        // 饱和处理
        if (acc_q15 > 18'sd32767)
            sat = 16'sd32767;
        else if (acc_q15 < -18'sd32768)
            sat = -16'sd32768;
        else
            sat = acc_q15[15:0];
    end

    // ========================================================================
    // 输出寄存器
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out      <= 0;
            dbg_ic_q15 <= 0;
            dbg_qs_q15 <= 0;
        end else begin
            y_out      <= sat;
            dbg_ic_q15 <= p_ic_s1[28:13];
            dbg_qs_q15 <= p_qs_s1[28:13];
        end
    end

endmodule
