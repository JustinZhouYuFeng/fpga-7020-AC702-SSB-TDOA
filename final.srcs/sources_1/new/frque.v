`timescale 1ns / 1ps
// ============================================================================
// 频率测量模块 (时序优化版 - 无除法)
// 改进：用查表近似替代除法，添加信号有效检测（方案1）
// ============================================================================
module freq_meter_period #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer AMP_THR  = 100,
    parameter integer MIN_FREQ_HZ = 500_000
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic signed [15:0] signal_in, 
    output logic [31:0]        freq_hz,
    output logic               signal_active  // 新增：信号有效标志
);

    // ========================================================================
    // 1. 包络检测 (信号有效性判断) - 方案1核心
    // ========================================================================
    logic [15:0] abs_sig;
    logic [15:0] envelope;
    
    assign abs_sig = (signal_in < 0) ? (-signal_in) : signal_in;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            envelope <= 0;
        end else begin
            if (abs_sig > envelope)
                envelope <= abs_sig;
            else if (envelope > 16'd64)
                envelope <= envelope - (envelope >> 6);  // 慢衰减
        end
    end
    
    assign signal_active = (envelope > 16'd5000);  // 约20%满量程，更稳定

    // ========================================================================
    // 2. 原始信号过零检测 (已流水线化)
    // ========================================================================
    logic signed [15:0] sig_d1;      // 延时1拍
    logic signed [15:0] sig_d2;      // 延时2拍
    logic signed [16:0] delta;       // 过零跳变量
    logic cross_zero_comb;
    logic cross_zero;
    
    // Stage 1: 信号延时链
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sig_d1 <= 0;
            sig_d2 <= 0;
        end else begin
            sig_d1 <= signal_in;
            sig_d2 <= sig_d1;
        end
    end

    // 计算过零时的跳变量（从负到正的变化量）
    assign delta = $signed({sig_d1[15], sig_d1}) - $signed({sig_d2[15], sig_d2});

    // Stage 2: 过零检测 (检测原始信号从负到正的过零点)
    // 条件：前一个采样 < 0，当前采样 >= 0，且信号有效（包络检测确保）
    // 使用跳变量判断：过零时的变化量应该 > 阈值
    assign cross_zero_comb = (sig_d2 < 0) && (sig_d1 >= 0) && signal_active;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cross_zero <= 0;
        end else begin
            cross_zero <= cross_zero_comb;
        end
    end

    // ========================================================================
    // 3. 周期测量 (带4点滑动平均)
    // ========================================================================
    logic [31:0] period_cnt;
    logic [31:0] period_latch;
    logic        measuring;
    
    // 滑动平均缓冲区
    logic [31:0] period_buf [0:3];
    logic [1:0]  buf_idx;
    logic [33:0] period_sum;  // 4个周期的和
    
    localparam int MAX_PERIOD_CNT = CLK_FREQ / MIN_FREQ_HZ;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt   <= 0;
            period_latch <= 200;  // 默认值 (对应 500kHz)
            measuring    <= 0;
            buf_idx      <= 0;
            period_sum   <= 800;  // 4 * 200
            for (int i = 0; i < 4; i++) period_buf[i] <= 200;
        end else begin
            if (cross_zero) begin
                if (measuring) begin
                    if (period_cnt > 4 && period_cnt < MAX_PERIOD_CNT) begin
                        // 更新滑动平均
                        period_sum <= period_sum - period_buf[buf_idx] + period_cnt;
                        period_buf[buf_idx] <= period_cnt;
                        buf_idx <= buf_idx + 1;
                        // 输出平均周期 (除以4 = 右移2位)
                        period_latch <= (period_sum - period_buf[buf_idx] + period_cnt) >> 2;
                    end
                    period_cnt <= 0;
                end else begin
                    measuring  <= 1;
                    period_cnt <= 0;
                end
            end else begin
                if (measuring) begin
                    period_cnt <= period_cnt + 1;
                    if (period_cnt > (MAX_PERIOD_CNT * 10)) begin 
                        measuring  <= 0;
                        period_cnt <= 0;
                    end
                end
            end
        end
    end

    // ========================================================================
    // 4. 频率计算 - 用查表近似替代除法 (时序安全)
    // ========================================================================
    logic [31:0] freq_approx;
    logic [31:0] period_reg;
    
    // Stage 1: 寄存周期值
    always_ff @(posedge clk) begin
        period_reg <= period_latch;
    end
    
    // Stage 2: 精确查表 (预计算的 100M/period 值, 覆盖 500kHz ~ 25MHz)
    // 每个周期值都有独立映射，精度更高
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_approx <= 0;
        end else begin
            case (period_reg)
                // 25MHz ~ 10MHz (周期 4~10)
                32'd4:  freq_approx <= 32'd25000000;
                32'd5:  freq_approx <= 32'd20000000;
                32'd6:  freq_approx <= 32'd16666667;
                32'd7:  freq_approx <= 32'd14285714;
                32'd8:  freq_approx <= 32'd12500000;
                32'd9:  freq_approx <= 32'd11111111;
                32'd10: freq_approx <= 32'd10000000;
                // 10MHz ~ 5MHz (周期 11~20)
                32'd11: freq_approx <= 32'd9090909;
                32'd12: freq_approx <= 32'd8333333;
                32'd13: freq_approx <= 32'd7692308;
                32'd14: freq_approx <= 32'd7142857;
                32'd15: freq_approx <= 32'd6666667;
                32'd16: freq_approx <= 32'd6250000;
                32'd17: freq_approx <= 32'd5882353;
                32'd18: freq_approx <= 32'd5555556;
                32'd19: freq_approx <= 32'd5263158;
                32'd20: freq_approx <= 32'd5000000;
                // 5MHz ~ 3.33MHz (周期 21~30)
                32'd21: freq_approx <= 32'd4761905;
                32'd22: freq_approx <= 32'd4545455;
                32'd23: freq_approx <= 32'd4347826;
                32'd24: freq_approx <= 32'd4166667;
                32'd25: freq_approx <= 32'd4000000;
                32'd26: freq_approx <= 32'd3846154;
                32'd27: freq_approx <= 32'd3703704;
                32'd28: freq_approx <= 32'd3571429;
                32'd29: freq_approx <= 32'd3448276;
                32'd30: freq_approx <= 32'd3333333;
                // 3.33MHz ~ 2.5MHz (周期 31~40)
                32'd31: freq_approx <= 32'd3225806;
                32'd32: freq_approx <= 32'd3125000;
                32'd33: freq_approx <= 32'd3030303;
                32'd34: freq_approx <= 32'd2941176;
                32'd35: freq_approx <= 32'd2857143;
                32'd36: freq_approx <= 32'd2777778;
                32'd37: freq_approx <= 32'd2702703;
                32'd38: freq_approx <= 32'd2631579;
                32'd39: freq_approx <= 32'd2564103;
                32'd40: freq_approx <= 32'd2500000;
                // 2.5MHz ~ 2MHz (周期 41~50)
                32'd41: freq_approx <= 32'd2439024;
                32'd42: freq_approx <= 32'd2380952;
                32'd43: freq_approx <= 32'd2325581;
                32'd44: freq_approx <= 32'd2272727;
                32'd45: freq_approx <= 32'd2222222;
                32'd46: freq_approx <= 32'd2173913;
                32'd47: freq_approx <= 32'd2127660;
                32'd48: freq_approx <= 32'd2083333;
                32'd49: freq_approx <= 32'd2040816;
                32'd50: freq_approx <= 32'd2000000;
                // 2MHz ~ 1.67MHz (周期 51~60)
                32'd51: freq_approx <= 32'd1960784;
                32'd52: freq_approx <= 32'd1923077;
                32'd53: freq_approx <= 32'd1886792;
                32'd54: freq_approx <= 32'd1851852;
                32'd55: freq_approx <= 32'd1818182;
                32'd56: freq_approx <= 32'd1785714;
                32'd57: freq_approx <= 32'd1754386;
                32'd58: freq_approx <= 32'd1724138;
                32'd59: freq_approx <= 32'd1694915;
                32'd60: freq_approx <= 32'd1666667;
                // 1.67MHz ~ 1.43MHz (周期 61~70)
                32'd61: freq_approx <= 32'd1639344;
                32'd62: freq_approx <= 32'd1612903;
                32'd63: freq_approx <= 32'd1587302;
                32'd64: freq_approx <= 32'd1562500;
                32'd65: freq_approx <= 32'd1538462;
                32'd66: freq_approx <= 32'd1515152;
                32'd67: freq_approx <= 32'd1492537;
                32'd68: freq_approx <= 32'd1470588;
                32'd69: freq_approx <= 32'd1449275;
                32'd70: freq_approx <= 32'd1428571;
                // 1.43MHz ~ 1.25MHz (周期 71~80)
                32'd71: freq_approx <= 32'd1408451;
                32'd72: freq_approx <= 32'd1388889;
                32'd73: freq_approx <= 32'd1369863;
                32'd74: freq_approx <= 32'd1351351;
                32'd75: freq_approx <= 32'd1333333;
                32'd76: freq_approx <= 32'd1315789;
                32'd77: freq_approx <= 32'd1298701;
                32'd78: freq_approx <= 32'd1282051;
                32'd79: freq_approx <= 32'd1265823;
                32'd80: freq_approx <= 32'd1250000;
                // 1.25MHz ~ 1.11MHz (周期 81~90)
                32'd81: freq_approx <= 32'd1234568;
                32'd82: freq_approx <= 32'd1219512;
                32'd83: freq_approx <= 32'd1204819;
                32'd84: freq_approx <= 32'd1190476;
                32'd85: freq_approx <= 32'd1176471;
                32'd86: freq_approx <= 32'd1162791;
                32'd87: freq_approx <= 32'd1149425;
                32'd88: freq_approx <= 32'd1136364;
                32'd89: freq_approx <= 32'd1123596;
                32'd90: freq_approx <= 32'd1111111;
                // 1.11MHz ~ 1MHz (周期 91~100)
                32'd91: freq_approx <= 32'd1098901;
                32'd92: freq_approx <= 32'd1086957;
                32'd93: freq_approx <= 32'd1075269;
                32'd94: freq_approx <= 32'd1063830;
                32'd95: freq_approx <= 32'd1052632;
                32'd96: freq_approx <= 32'd1041667;
                32'd97: freq_approx <= 32'd1030928;
                32'd98: freq_approx <= 32'd1020408;
                32'd99: freq_approx <= 32'd1010101;
                32'd100: freq_approx <= 32'd1000000;
                // 1MHz ~ 500kHz (周期 101~200, 每5个一组)
                32'd101, 32'd102, 32'd103, 32'd104, 32'd105: freq_approx <= 32'd970874;
                32'd106, 32'd107, 32'd108, 32'd109, 32'd110: freq_approx <= 32'd925926;
                32'd111, 32'd112, 32'd113, 32'd114, 32'd115: freq_approx <= 32'd884956;
                32'd116, 32'd117, 32'd118, 32'd119, 32'd120: freq_approx <= 32'd847458;
                32'd121, 32'd122, 32'd123, 32'd124, 32'd125: freq_approx <= 32'd813008;
                32'd126, 32'd127, 32'd128, 32'd129, 32'd130: freq_approx <= 32'd781250;
                32'd131, 32'd132, 32'd133, 32'd134, 32'd135: freq_approx <= 32'd751880;
                32'd136, 32'd137, 32'd138, 32'd139, 32'd140: freq_approx <= 32'd724638;
                32'd141, 32'd142, 32'd143, 32'd144, 32'd145: freq_approx <= 32'd699301;
                32'd146, 32'd147, 32'd148, 32'd149, 32'd150: freq_approx <= 32'd675676;
                32'd151, 32'd152, 32'd153, 32'd154, 32'd155: freq_approx <= 32'd653595;
                32'd156, 32'd157, 32'd158, 32'd159, 32'd160: freq_approx <= 32'd632911;
                32'd161, 32'd162, 32'd163, 32'd164, 32'd165: freq_approx <= 32'd613497;
                32'd166, 32'd167, 32'd168, 32'd169, 32'd170: freq_approx <= 32'd595238;
                32'd171, 32'd172, 32'd173, 32'd174, 32'd175: freq_approx <= 32'd578035;
                32'd176, 32'd177, 32'd178, 32'd179, 32'd180: freq_approx <= 32'd561798;
                32'd181, 32'd182, 32'd183, 32'd184, 32'd185: freq_approx <= 32'd546448;
                32'd186, 32'd187, 32'd188, 32'd189, 32'd190: freq_approx <= 32'd531915;
                32'd191, 32'd192, 32'd193, 32'd194, 32'd195: freq_approx <= 32'd518135;
                32'd196, 32'd197, 32'd198, 32'd199, 32'd200: freq_approx <= 32'd505051;
                default: freq_approx <= 32'd0;  // 低于 500kHz 或超出范围
            endcase
        end
    end
    
    // 只在信号有效时输出频率
    assign freq_hz = signal_active ? freq_approx : 32'd0;

endmodule
