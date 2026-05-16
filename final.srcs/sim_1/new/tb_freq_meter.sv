`timescale 1ns / 1ps
// ============================================================================
// Testbench: Frequency Meter (Period Measurement Method)
// Function: Verify frequency measurement accuracy with different input frequencies
// ============================================================================

module tb_freq_meter();

    parameter CLK_PERIOD = 10;  // 100MHz system clock

    // ========================================================================
    // Signals
    // ========================================================================
    reg                     clk;
    reg                     rst_n;
    reg  signed [15:0]      signal_in;
    wire [31:0]             freq_hz;
    wire                    signal_active;

    // Test control
    integer test_freq_hz;
    integer samples_per_cycle;
    integer sample_idx;
    integer i;
    
    // Sine LUT (64 points, amplitude = 10000)
    reg signed [15:0] sine_lut [0:63];

    // ========================================================================
    // Initialize Sine LUT
    // ========================================================================
    initial begin
        // sin(2*pi*k/64) * 10000
        sine_lut[0]  = 16'sd0;      sine_lut[1]  = 16'sd980;
        sine_lut[2]  = 16'sd1951;   sine_lut[3]  = 16'sd2903;
        sine_lut[4]  = 16'sd3827;   sine_lut[5]  = 16'sd4714;
        sine_lut[6]  = 16'sd5556;   sine_lut[7]  = 16'sd6344;
        sine_lut[8]  = 16'sd7071;   sine_lut[9]  = 16'sd7730;
        sine_lut[10] = 16'sd8315;   sine_lut[11] = 16'sd8819;
        sine_lut[12] = 16'sd9239;   sine_lut[13] = 16'sd9569;
        sine_lut[14] = 16'sd9808;   sine_lut[15] = 16'sd9952;
        sine_lut[16] = 16'sd10000;  sine_lut[17] = 16'sd9952;
        sine_lut[18] = 16'sd9808;   sine_lut[19] = 16'sd9569;
        sine_lut[20] = 16'sd9239;   sine_lut[21] = 16'sd8819;
        sine_lut[22] = 16'sd8315;   sine_lut[23] = 16'sd7730;
        sine_lut[24] = 16'sd7071;   sine_lut[25] = 16'sd6344;
        sine_lut[26] = 16'sd5556;   sine_lut[27] = 16'sd4714;
        sine_lut[28] = 16'sd3827;   sine_lut[29] = 16'sd2903;
        sine_lut[30] = 16'sd1951;   sine_lut[31] = 16'sd980;
        sine_lut[32] = 16'sd0;      sine_lut[33] = -16'sd980;
        sine_lut[34] = -16'sd1951;  sine_lut[35] = -16'sd2903;
        sine_lut[36] = -16'sd3827;  sine_lut[37] = -16'sd4714;
        sine_lut[38] = -16'sd5556;  sine_lut[39] = -16'sd6344;
        sine_lut[40] = -16'sd7071;  sine_lut[41] = -16'sd7730;
        sine_lut[42] = -16'sd8315;  sine_lut[43] = -16'sd8819;
        sine_lut[44] = -16'sd9239;  sine_lut[45] = -16'sd9569;
        sine_lut[46] = -16'sd9808;  sine_lut[47] = -16'sd9952;
        sine_lut[48] = -16'sd10000; sine_lut[49] = -16'sd9952;
        sine_lut[50] = -16'sd9808;  sine_lut[51] = -16'sd9569;
        sine_lut[52] = -16'sd9239;  sine_lut[53] = -16'sd8819;
        sine_lut[54] = -16'sd8315;  sine_lut[55] = -16'sd7730;
        sine_lut[56] = -16'sd7071;  sine_lut[57] = -16'sd6344;
        sine_lut[58] = -16'sd5556;  sine_lut[59] = -16'sd4714;
        sine_lut[60] = -16'sd3827;  sine_lut[61] = -16'sd2903;
        sine_lut[62] = -16'sd1951;  sine_lut[63] = -16'sd980;
    end

    // ========================================================================
    // Clock
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // DUT
    // ========================================================================
    freq_meter_period #(
        .CLK_FREQ   (100_000_000),
        .AMP_THR    (100),
        .MIN_FREQ_HZ(500_000)
    ) u_freq_meter (
        .clk          (clk),
        .rst_n        (rst_n),
        .signal_in    (signal_in),
        .freq_hz      (freq_hz),
        .signal_active(signal_active)
    );

    // ========================================================================
    // Signal Generation Task
    // ========================================================================
    task generate_sine;
        input integer freq;
        input integer num_cycles;
        integer period_clks;
        integer phase_step;
        integer phase;
        integer cycle_count;
    begin
        test_freq_hz = freq;
        period_clks = 100_000_000 / freq;  // clocks per cycle
        phase_step = 64 * 1000 / period_clks;  // phase increment * 1000
        phase = 0;
        
        $display("\n  Generating %0d Hz sine wave (%0d clks/cycle)...", freq, period_clks);
        
        for (cycle_count = 0; cycle_count < num_cycles; cycle_count = cycle_count + 1) begin
            for (i = 0; i < period_clks; i = i + 1) begin
                @(posedge clk);
                // Calculate phase index (0-63)
                sample_idx = (phase / 1000) % 64;
                signal_in = sine_lut[sample_idx];
                phase = phase + phase_step;
                if (phase >= 64000) phase = phase - 64000;
            end
        end
    end
    endtask

    // ========================================================================
    // Main Test
    // ========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        signal_in = 0;
        test_freq_hz = 0;
        
        $display("============================================");
        $display("  Frequency Meter Test");
        $display("============================================");
        $display("  Clock: 100MHz");
        $display("  Method: Period measurement + LUT");
        $display("  Range: 500kHz ~ 25MHz");
        $display("============================================");
        
        // Reset
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);
        
        // ====== Test 1: 1MHz ======
        $display("\n[Test 1] Input: 1MHz");
        generate_sine(1_000_000, 50);
        $display("  Measured: %0d Hz, Active: %0d", freq_hz, signal_active);
        $display("  Error: %0d Hz", (freq_hz > 1000000) ? (freq_hz - 1000000) : (1000000 - freq_hz));
        
        // ====== Test 2: 2MHz ======
        $display("\n[Test 2] Input: 2MHz");
        generate_sine(2_000_000, 100);
        $display("  Measured: %0d Hz, Active: %0d", freq_hz, signal_active);
        $display("  Error: %0d Hz", (freq_hz > 2000000) ? (freq_hz - 2000000) : (2000000 - freq_hz));
        
        // ====== Test 3: 5MHz ======
        $display("\n[Test 3] Input: 5MHz");
        generate_sine(5_000_000, 200);
        $display("  Measured: %0d Hz, Active: %0d", freq_hz, signal_active);
        $display("  Error: %0d Hz", (freq_hz > 5000000) ? (freq_hz - 5000000) : (5000000 - freq_hz));
        
        // ====== Test 4: 10MHz ======
        $display("\n[Test 4] Input: 10MHz");
        generate_sine(10_000_000, 400);
        $display("  Measured: %0d Hz, Active: %0d", freq_hz, signal_active);
        $display("  Error: %0d Hz", (freq_hz > 10000000) ? (freq_hz - 10000000) : (10000000 - freq_hz));
        
        // ====== Test 5: Signal off (no input) ======
        $display("\n[Test 5] Signal OFF");
        signal_in = 0;
        repeat(5000) @(posedge clk);
        $display("  Measured: %0d Hz, Active: %0d", freq_hz, signal_active);
        
        // ====== Test 6: 500kHz (minimum) ======
        $display("\n[Test 6] Input: 500kHz (minimum)");
        generate_sine(500_000, 25);
        $display("  Measured: %0d Hz, Active: %0d", freq_hz, signal_active);
        
        // ====== Summary ======
        $display("\n============================================");
        $display("  Test Summary");
        $display("============================================");
        $display("  Frequency measurement method:");
        $display("  1. Zero-crossing detection");
        $display("  2. Period counting");
        $display("  3. 4-point moving average");
        $display("  4. LUT-based frequency lookup");
        $display("============================================\n");
        
        repeat(100) @(posedge clk);
        $finish;
    end

    // ========================================================================
    // Monitor: Print when frequency changes
    // ========================================================================
    reg [31:0] prev_freq;
    
    always @(posedge clk) begin
        if (rst_n && freq_hz != prev_freq && freq_hz != 0) begin
            $display("  [%0t] freq_hz = %0d Hz", $time, freq_hz);
        end
        prev_freq <= freq_hz;
    end

endmodule
