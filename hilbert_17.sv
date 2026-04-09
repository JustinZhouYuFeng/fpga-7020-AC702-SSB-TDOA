`timescale 1ns / 1ps
// ============================================================================
// Hilbert 变换器 ( 5级流水线)
// 33阶 Hilbert FIR 滤波器，生成正交分量 Q 和对齐的 I
// ============================================================================
module hilbert_33 #(
    parameter int W = 16,
    parameter int Q_GAIN_1024 = 1024
)(
    input  logic                clk,
    input  logic                rst_n,
    input  logic signed [W-1:0] x_in,
    output logic signed [W-1:0] i_align,
    output logic signed [W-1:0] q_out
);

    // ========================================================================
    // 1. 移位寄存器链
    // ========================================================================
    logic signed [W-1:0] x_d [0:32];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i <= 32; i++) x_d[i] <= 0;
        end else begin
            x_d[0] <= x_in;
            for (int i = 1; i <= 32; i++) x_d[i] <= x_d[i-1];
        end
    end

    // ========================================================================
    // 系数定义 (Q1.15)
    // ========================================================================
    localparam logic signed [15:0] c1  = 16'sd20861;
    localparam logic signed [15:0] c3  = 16'sd6954;
    localparam logic signed [15:0] c5  = 16'sd4172;
    localparam logic signed [15:0] c7  = 16'sd2980;
    localparam logic signed [15:0] c9  = 16'sd2318;
    localparam logic signed [15:0] c11 = 16'sd1896;
    localparam logic signed [15:0] c13 = 16'sd1605;
    localparam logic signed [15:0] c15 = 16'sd1391;

    // ========================================================================
    // 2. 流水线 Stage 1: 成对差分
    // ========================================================================
    logic signed [W:0] d1_s1, d3_s1, d5_s1, d7_s1;
    logic signed [W:0] d9_s1, d11_s1, d13_s1, d15_s1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d1_s1 <= 0; d3_s1 <= 0; d5_s1 <= 0; d7_s1 <= 0;
            d9_s1 <= 0; d11_s1 <= 0; d13_s1 <= 0; d15_s1 <= 0;
        end else begin
            d1_s1  <= $signed(x_d[15]) - $signed(x_d[17]);
            d3_s1  <= $signed(x_d[13]) - $signed(x_d[19]);
            d5_s1  <= $signed(x_d[11]) - $signed(x_d[21]);
            d7_s1  <= $signed(x_d[9])  - $signed(x_d[23]);
            d9_s1  <= $signed(x_d[7])  - $signed(x_d[25]);
            d11_s1 <= $signed(x_d[5])  - $signed(x_d[27]);
            d13_s1 <= $signed(x_d[3])  - $signed(x_d[29]);
            d15_s1 <= $signed(x_d[1])  - $signed(x_d[31]);
        end
    end

    // ========================================================================
    // 3. 流水线 Stage 2: 乘法
    // ========================================================================
    logic signed [33:0] p1_s2, p3_s2, p5_s2, p7_s2;
    logic signed [33:0] p9_s2, p11_s2, p13_s2, p15_s2;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_s2 <= 0; p3_s2 <= 0; p5_s2 <= 0; p7_s2 <= 0;
            p9_s2 <= 0; p11_s2 <= 0; p13_s2 <= 0; p15_s2 <= 0;
        end else begin
            p1_s2  <= $signed(d1_s1)  * $signed(c1);
            p3_s2  <= $signed(d3_s1)  * $signed(c3);
            p5_s2  <= $signed(d5_s1)  * $signed(c5);
            p7_s2  <= $signed(d7_s1)  * $signed(c7);
            p9_s2  <= $signed(d9_s1)  * $signed(c9);
            p11_s2 <= $signed(d11_s1) * $signed(c11);
            p13_s2 <= $signed(d13_s1) * $signed(c13);
            p15_s2 <= $signed(d15_s1) * $signed(c15);
        end
    end

    // ========================================================================
    // 4. 流水线 Stage 3: 求和树第一级 (两两相加)
    // ========================================================================
    logic signed [35:0] sum_01_s3, sum_23_s3, sum_45_s3, sum_67_s3;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_01_s3 <= 0; sum_23_s3 <= 0; 
            sum_45_s3 <= 0; sum_67_s3 <= 0;
        end else begin
            sum_01_s3 <= $signed({p1_s2[33], p1_s2})   + $signed({p3_s2[33], p3_s2});
            sum_23_s3 <= $signed({p5_s2[33], p5_s2})   + $signed({p7_s2[33], p7_s2});
            sum_45_s3 <= $signed({p9_s2[33], p9_s2})   + $signed({p11_s2[33], p11_s2});
            sum_67_s3 <= $signed({p13_s2[33], p13_s2}) + $signed({p15_s2[33], p15_s2});
        end
    end

    // ========================================================================
    // 5. 流水线 Stage 4: 求和树第二级
    // ========================================================================
    logic signed [36:0] sum_0123_s4, sum_4567_s4;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_0123_s4 <= 0;
            sum_4567_s4 <= 0;
        end else begin
            sum_0123_s4 <= $signed({sum_01_s3[35], sum_01_s3}) + $signed({sum_23_s3[35], sum_23_s3});
            sum_4567_s4 <= $signed({sum_45_s3[35], sum_45_s3}) + $signed({sum_67_s3[35], sum_67_s3});
        end
    end

    // ========================================================================
    // 6. 流水线 Stage 5: 最终加法 + 缩放
    // ========================================================================
    logic signed [37:0] sum_total_s5;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_total_s5 <= 0;
        end else begin
            sum_total_s5 <= $signed({sum_0123_s4[36], sum_0123_s4}) + 
                            $signed({sum_4567_s4[36], sum_4567_s4});
        end
    end
    
    // 缩放计算 (组合逻辑，路径短)
    wire signed [20:0] q_tmp = sum_total_s5[35:15];
    wire signed [26:0] q_mul = $signed(q_tmp[15:0]) * $signed(Q_GAIN_1024[10:0]);
    wire signed [15:0] q_fix = q_mul[25:10];

    // ========================================================================
    // 7. I 路径延迟匹配
    // ========================================================================
    // 原延迟: x_d[16] (16拍)
    // Q路径新增: 5级流水线
    // I路径需要额外延迟5拍以匹配
    logic signed [W-1:0] i_delay [0:4];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i <= 4; i++) i_delay[i] <= 0;
        end else begin
            i_delay[0] <= x_d[16];
            for (int i = 1; i <= 4; i++) i_delay[i] <= i_delay[i-1];
        end
    end

    // ========================================================================
    // 8. 输出寄存器
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_align <= 0;
            q_out   <= 0;
        end else begin
            i_align <= i_delay[4];
            q_out   <= q_fix;
        end
    end

endmodule
