`timescale 1ns / 1ps
// ============================================================================
// 综合仿真测试文件 - 测试整个信号处理链路
// 包括：SSB调制、频率测量、TDOA欺骗
// ============================================================================

module sss;

    // ========================================================================
    // 参数定义
    // ========================================================================
    parameter real CLK_FREQ     = 100e6;        // 100 MHz
    parameter real CLK_PERIOD   = 1e9/CLK_FREQ; // 10 ns
    parameter real INPUT_FREQ   = 5e6;          // 输入信号频率 5 MHz
    parameter real DDS_FREQ     = 2e6;          // DDS本振频率 2 MHz
    parameter real EXPECTED_SSB = INPUT_FREQ - DDS_FREQ; // LSB: 3 MHz
    
    parameter int  DATA_WIDTH   = 16;
    parameter int  PULSE_WIDTH  = 200;          // 脉冲持续采样数
    parameter int  PULSE_GAP    = 300;          // 脉冲间隔采样数
    
    // ========================================================================
    // 信号声明
    // ========================================================================
    logic clk;
    logic rst_n;
    
    // SSB链路信号
    logic signed [15:0] input_signal;
    logic signed [15:0] ssb_output;
    logic signed [15:0] i_path, q_path;
    logic signed [15:0] dds_cos, dds_sin;
    logic [31:0] dds_bus;
    logic ssb_valid;
    
    // 频率测量信号
    logic [31:0] freq_input_hz;
    logic [31:0] freq_ssb_hz;
    logic input_active, ssb_active;
    
    // TDOA信号
    logic signed [15:0] ch0_out, ch1_out, ch2_out, ch3_out;
    logic [31:0] cnt_out;
    logic [15:0] delay_ant0;
    logic [5:0] v_idx;
    logic signed [15:0] heart_x, heart_y;
    
    // 测试控制
    integer sample_count;
    logic pulse_enable;
    real phase_in, phase_dds;
    
    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ========================================================================
    // 复位序列
    // ========================================================================
    initial begin
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        $display("=== Reset Released ===");
    end
    
    // ========================================================================
    // 输入信号生成 (脉冲正弦波)
    // ========================================================================
    initial begin
        phase_in = 0;
        sample_count = 0;
        pulse_enable = 0;
        input_signal = 0;
    end
    
    always @(posedge clk) begin
        if (!rst_n) begin
            phase_in <= 0;
            sample_count <= 0;
            pulse_enable <= 0;
            input_signal <= 0;
        end else begin
            // 脉冲控制
            sample_count <= sample_count + 1;
            if (sample_count < PULSE_WIDTH)
                pulse_enable <= 1;
            else if (sample_count < PULSE_WIDTH + PULSE_GAP)
                pulse_enable <= 0;
            else
                sample_count <= 0;
            
            // 正弦波生成
            phase_in <= phase_in + (2.0 * 3.14159265 * INPUT_FREQ / CLK_FREQ);
            if (phase_in > 2.0 * 3.14159265)
                phase_in <= phase_in - 2.0 * 3.14159265;
            
            // 脉冲正弦波输出
            if (pulse_enable)
                input_signal <= $rtoi(32000.0 * $sin(phase_in));
            else
                input_signal <= 0;
        end
    end
    
    // ========================================================================
    // DDS信号生成 (模拟DDS输出)
    // ========================================================================
    initial phase_dds = 0;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            phase_dds <= 0;
            dds_cos <= 0;
            dds_sin <= 0;
        end else begin
            phase_dds <= phase_dds + (2.0 * 3.14159265 * DDS_FREQ / CLK_FREQ);
            if (phase_dds > 2.0 * 3.14159265)
                phase_dds <= phase_dds - 2.0 * 3.14159265;
            
            dds_cos <= $rtoi(16383.0 * $cos(phase_dds));
            dds_sin <= $rtoi(16383.0 * $sin(phase_dds));
        end
    end
    
    // DDS总线打包 (模拟Vivado DDS格式)
    assign dds_bus = {dds_sin, dds_cos};
    
    // ========================================================================
    // DUT: DDS解包
    // ========================================================================
    wire signed [13:0] cos_unpacked, sin_unpacked;
    
    dds_unpack #(
        .W(14),
        .SWAP_CS(1'b0)
    ) u_dds_unpack (
        .dds_bus(dds_bus),
        .cos_q(cos_unpacked),
        .sin_q(sin_unpacked)
    );
    
    // ========================================================================
    // DUT: Hilbert滤波器
    // ========================================================================
    hilbert_33 #(
        .W(16),
        .Q_GAIN_1024(1024)
    ) u_hilbert (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(input_signal),
        .i_align(i_path),
        .q_out(q_path)
    );
    
    assign ssb_valid = 1'b1;  // 简化：总是有效
    
    // ========================================================================
    // DUT: 复数混频器 (LSB模式)
    // ========================================================================
    logic signed [15:0] dbg_ic, dbg_qs;  // 调试输出（未使用）
    
    complex_ssb_mixer #(
        .USB_SEL(1'b0)  // LSB模式: I*cos + Q*sin
    ) u_mixer (
        .clk(clk),
        .rst_n(rst_n),
        .i_in(i_path),
        .q_in(q_path),
        .cos14(cos_unpacked),
        .sin14(sin_unpacked),
        .y_out(ssb_output),
        .dbg_ic_q15(dbg_ic),
        .dbg_qs_q15(dbg_qs)
    );
    
    // ========================================================================
    // DUT: 输入频率测量
    // ========================================================================
    freq_meter_period #(
        .CLK_FREQ(100_000_000),
        .AMP_THR(2000),
        .MIN_FREQ_HZ(500_000)
    ) u_freq_input (
        .clk(clk),
        .rst_n(rst_n),
        .signal_in(input_signal),
        .freq_hz(freq_input_hz),
        .signal_active(input_active)
    );
    
    // ========================================================================
    // DUT: SSB输出频率测量
    // ========================================================================
    freq_meter_period #(
        .CLK_FREQ(100_000_000),
        .AMP_THR(2000),
        .MIN_FREQ_HZ(500_000)
    ) u_freq_ssb (
        .clk(clk),
        .rst_n(rst_n),
        .signal_in(ssb_output),
        .freq_hz(freq_ssb_hz),
        .signal_active(ssb_active)
    );
    
    // ========================================================================
    // DUT: TDOA欺骗器
    // ========================================================================
    tdoa_spoofer #(
        .W(16),
        .FS_HZ(100e6),
        .C(3e8)
    ) u_tdoa (
        .clk(clk),
        .rst_n(rst_n),
        .vio_center_x(32'sd500),
        .vio_center_y(32'sd500),
        .vio_scale(32'd500),
        .vio_shape_sel(3'd0),      // Heart形状
        .ch0_out(ch0_out),
        .ch1_out(ch1_out),
        .ch2_out(ch2_out),
        .ch3_out(ch3_out),
        .cnt_out(cnt_out),
        .delay_ant0_out(delay_ant0),
        .v_idx_out(v_idx),
        .heart_x_out(heart_x),
        .heart_y_out(heart_y)
    );
    
    // ========================================================================
    // 脉冲检测器 (用于TDOA)
    // ========================================================================
    logic pulse_det;
    pulse_detector #(.W(16)) u_pulse_det (
        .clk(clk),
        .rst_n(rst_n),
        .s(ssb_output),
        .thr(16'sd5000),
        .rise_pulse(pulse_det)
    );
    
    // ========================================================================
    // 监控和验证
    // ========================================================================
    
    // 频率测量结果监控
    real measured_input_mhz, measured_ssb_mhz;
    assign measured_input_mhz = freq_input_hz / 1e6;
    assign measured_ssb_mhz = freq_ssb_hz / 1e6;
    
    // 周期性打印测量结果
    initial begin
        forever begin
            #10000;  // 每10us打印一次
            if (rst_n && input_active) begin
                $display("[%0t] Input: %0d Hz (%.2f MHz), SSB: %0d Hz (%.2f MHz)", 
                         $time, freq_input_hz, measured_input_mhz,
                         freq_ssb_hz, measured_ssb_mhz);
            end
        end
    end
    
    // TDOA输出监控
    always @(posedge clk) begin
        if (ch0_out != 0 || ch1_out != 0 || ch2_out != 0 || ch3_out != 0) begin
            $display("[%0t] TDOA Output: ch0=%0d ch1=%0d ch2=%0d ch3=%0d | Shape idx=%0d, X=%0d, Y=%0d",
                     $time, ch0_out, ch1_out, ch2_out, ch3_out, v_idx, heart_x, heart_y);
        end
    end
    
    // ========================================================================
    // 波形验证任务
    // ========================================================================
    task automatic check_frequency(input string name, input int measured, input int expected, input int tolerance);
        int error;
        error = (measured > expected) ? (measured - expected) : (expected - measured);
        if (error <= tolerance)
            $display("  [PASS] %s: Measured=%0d Hz, Expected=%0d Hz, Error=%0d Hz", 
                     name, measured, expected, error);
        else
            $display("  [FAIL] %s: Measured=%0d Hz, Expected=%0d Hz, Error=%0d Hz (tolerance=%0d)", 
                     name, measured, expected, error, tolerance);
    endtask
    
    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        $display("============================================================");
        $display("  FPGA Signal Processing System - Comprehensive Testbench");
        $display("============================================================");
        $display("  Input Frequency:    %.1f MHz", INPUT_FREQ/1e6);
        $display("  DDS Frequency:      %.1f MHz", DDS_FREQ/1e6);
        $display("  Expected SSB (LSB): %.1f MHz", EXPECTED_SSB/1e6);
        $display("  Pulse Width:        %0d samples", PULSE_WIDTH);
        $display("  Pulse Gap:          %0d samples", PULSE_GAP);
        $display("============================================================");
        
        // 等待复位完成
        @(posedge rst_n);
        $display("\n[%0t] System Reset Complete", $time);
        
        // ====================================================================
        // 测试1: SSB调制链路
        // ====================================================================
        $display("\n--- Test 1: SSB Modulation Chain ---");
        
        // 等待足够时间让信号稳定
        repeat(5000) @(posedge clk);  // 50us
        
        $display("  Hilbert I-path sample: %0d", i_path);
        $display("  Hilbert Q-path sample: %0d", q_path);
        $display("  SSB output sample: %0d", ssb_output);
        
        // ====================================================================
        // 测试2: 频率测量
        // ====================================================================
        $display("\n--- Test 2: Frequency Measurement ---");
        
        // 等待更多周期让频率测量稳定
        repeat(20000) @(posedge clk);  // 200us
        
        $display("  Input signal active: %b", input_active);
        $display("  SSB signal active: %b", ssb_active);
        
        check_frequency("Input Frequency", freq_input_hz, $rtoi(INPUT_FREQ), 500000);
        check_frequency("SSB Frequency", freq_ssb_hz, $rtoi(EXPECTED_SSB), 500000);
        
        // ====================================================================
        // 测试3: TDOA欺骗
        // ====================================================================
        $display("\n--- Test 3: TDOA Spoofing ---");
        
        repeat(10000) @(posedge clk);  // 100us
        
        $display("  Current shape index: %0d", v_idx);
        $display("  Heart X: %0d, Y: %0d", heart_x, heart_y);
        $display("  Delay Ant0: %0d samples", delay_ant0);
        
        // ====================================================================
        // 测试4: 不同输入频率
        // ====================================================================
        $display("\n--- Test 4: Different Input Frequencies ---");
        
        // 切换到8MHz测试
        $display("  Switching to 8 MHz input...");
        // (在实际仿真中需要修改INPUT_FREQ参数或动态控制)
        
        repeat(30000) @(posedge clk);  // 300us
        
        // ====================================================================
        // 测试完成
        // ====================================================================
        $display("\n============================================================");
        $display("  Simulation Complete!");
        $display("============================================================");
        
        // 汇总结果
        $display("\n--- Final Measurements ---");
        $display("  Input Frequency:  %0d Hz (%.3f MHz)", freq_input_hz, freq_input_hz/1e6);
        $display("  SSB Frequency:    %0d Hz (%.3f MHz)", freq_ssb_hz, freq_ssb_hz/1e6);
        $display("  Frequency Shift:  %0d Hz (%.3f MHz)", 
                 (freq_input_hz > freq_ssb_hz) ? (freq_input_hz - freq_ssb_hz) : (freq_ssb_hz - freq_input_hz),
                 $itor((freq_input_hz > freq_ssb_hz) ? (freq_input_hz - freq_ssb_hz) : (freq_ssb_hz - freq_input_hz))/1e6);
        
        #1000;
        $finish;
    end
    
    // ========================================================================
    // VCD波形导出 (可选)
    // ========================================================================
    initial begin
        $dumpfile("sss_waveform.vcd");
        $dumpvars(0, sss);
    end
    
    // ========================================================================
    // 超时保护
    // ========================================================================
    initial begin
        #1000000;  // 1ms超时
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
