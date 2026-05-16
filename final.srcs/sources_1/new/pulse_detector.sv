`timescale 1ns / 1ps
// ============================================================================
// Âö³å¼ì²âÆ÷ - ¼ì²âĞÅºÅÉÏÉıÑØ¹ıãĞÖµ
// ============================================================================

module pulse_detector #(
    parameter W = 16
)(
    input  logic               clk, 
    input  logic               rst_n,
    input  logic signed [W-1:0] s,
    input  logic signed [W-1:0] thr,
    output logic               rise_pulse
);
    logic signed [W-1:0] s_d;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            s_d <= '0; 
        else 
            s_d <= s;
    end
    
    assign rise_pulse = (s > thr) && (s_d <= thr);
    
endmodule

