`timescale 1ns / 1ps
// ============================================================================
// ģ������ssb_chain
// ��  �ã�SSB ���ƶ����װ
// 修改：USB_SEL改为输入端口，支持动态切换
// ============================================================================
module ssb_chain #(
    parameter int DDS_W = 14
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      usb_sel,        // 新增：1=USB, 0=LSB
    input  logic signed [15:0]        x_in_q15,
    input  logic [31:0]               dds_bus,
    output logic signed [15:0]        y_ssb_q15,
    // ���Զ˿�
    output logic signed [15:0]        tap_i_q15,
    output logic signed [15:0]        tap_q_q15,
    output logic signed [13:0]        tap_cos_q13,
    output logic signed [13:0]        tap_sin_q13,
    output logic signed [15:0]        tap_ic_q15,
    output logic signed [15:0]        tap_qs_q15
);

    // 1. DDS ���
    logic signed [DDS_W-1:0] cos_q;
    logic signed [DDS_W-1:0] sin_q;
    dds_unpack #(.W(DDS_W), .SWAP_CS(1'b0)) u_unpack (
        .dds_bus(dds_bus),
        .cos_q (cos_q),
        .sin_q (sin_q)
    );

    // 2. Hilbert �任
    logic signed [15:0] i_aln;
    logic signed [15:0] q_hil;
    hilbert_33 u_hil (
        .clk    (clk),
        .rst_n  (rst_n),
        .x_in   (x_in_q15),
        .i_align(i_aln),
        .q_out  (q_hil)
    );

    // 3. SSB ��Ƶ
    logic signed [15:0] y_ssb;
    logic signed [15:0] dbg_ic, dbg_qs;
    complex_ssb_mixer u_mx (  // 修改：移除参数
        .clk   (clk),
        .rst_n (rst_n),
        .usb_sel(usb_sel),  // 新增：连接输入端口
        .i_in  (i_aln), .q_in(q_hil),
        .cos14 (cos_q[13:0]), .sin14(sin_q[13:0]),
        .y_out (y_ssb),
        .dbg_ic_q15(dbg_ic), .dbg_qs_q15(dbg_qs)
    );

    // 4. �������
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_ssb_q15   <= 0;
            tap_i_q15   <= 0;
            tap_q_q15   <= 0;
            tap_cos_q13 <= 0;
            tap_sin_q13 <= 0;
            tap_ic_q15  <= 0;
            tap_qs_q15  <= 0;
        end else begin
            y_ssb_q15   <= y_ssb;
            tap_i_q15   <= i_aln;
            tap_q_q15   <= q_hil;
            tap_cos_q13 <= cos_q[13:0];
            tap_sin_q13 <= sin_q[13:0];
            tap_ic_q15  <= dbg_ic;
            tap_qs_q15  <= dbg_qs;
        end
    end

endmodule