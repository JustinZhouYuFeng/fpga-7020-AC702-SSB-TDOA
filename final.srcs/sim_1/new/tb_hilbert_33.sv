`timescale 1ns / 1ps
// ============================================================================
// Testbench: Hilbert Transform Filter (33-tap, 5-stage pipeline)
// Function: Verify 90° phase shift between I and Q channels
// ============================================================================

module tb_hilbert_33();

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter CLK_PERIOD = 10;          // 100MHz clock = 10ns
    parameter W = 16;                   // Data width
    parameter Q_GAIN_1024 = 1024;       // Q channel gain
    
    // Test signal parameters
    parameter SAMPLES_PER_CYCLE = 20;   // 100MHz/5MHz = 20 samples per sine cycle
    parameter TEST_CYCLES = 50;         // Number of sine cycles to test
    parameter PIPELINE_DELAY = 22;      // Total pipeline delay (16 group + 6 pipeline)

    // ========================================================================
    // Signal Declarations
    // ========================================================================
    reg                     clk;
    reg                     rst_n;
    reg  signed [W-1:0]     x_in;
    wire signed [W-1:0]     i_align;
    wire signed [W-1:0]     q_out;
    
    // Test counters
    integer sample_cnt;
    integer cycle_cnt;
    integer i;
    
    // Previous values for zero-crossing detection
    reg signed [W-1:0] i_prev;
    reg signed [W-1:0] q_prev;

    // ========================================================================
    // Pre-computed Sine Lookup Table (20 points per cycle for 5MHz @ 100MHz)
    // Amplitude: 16384 (half of Q15 max to avoid overflow)
    // ========================================================================
    reg signed [15:0] sine_lut [0:19];
    
    initial begin
        // sin(2*pi*n/20) * 16384, n = 0..19
        sine_lut[0]  = 16'sd0;
        sine_lut[1]  = 16'sd5063;
        sine_lut[2]  = 16'sd9630;
        sine_lut[3]  = 16'sd13255;
        sine_lut[4]  = 16'sd15582;
        sine_lut[5]  = 16'sd16384;
        sine_lut[6]  = 16'sd15582;
        sine_lut[7]  = 16'sd13255;
        sine_lut[8]  = 16'sd9630;
        sine_lut[9]  = 16'sd5063;
        sine_lut[10] = 16'sd0;
        sine_lut[11] = -16'sd5063;
        sine_lut[12] = -16'sd9630;
        sine_lut[13] = -16'sd13255;
        sine_lut[14] = -16'sd15582;
        sine_lut[15] = -16'sd16384;
        sine_lut[16] = -16'sd15582;
        sine_lut[17] = -16'sd13255;
        sine_lut[18] = -16'sd9630;
        sine_lut[19] = -16'sd5063;
    end

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    hilbert_33 #(
        .W          (W),
        .Q_GAIN_1024(Q_GAIN_1024)
    ) u_hilbert_33 (
        .clk    (clk),
        .rst_n  (rst_n),
        .x_in   (x_in),
        .i_align(i_align),
        .q_out  (q_out)
    );

    // ========================================================================
    // Main Test Process
    // ========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        x_in = 0;
        sample_cnt = 0;
        cycle_cnt = 0;
        i_prev = 0;
        q_prev = 0;
        
        $display("============================================");
        $display("  Hilbert Filter 90-Degree Phase Test");
        $display("============================================");
        $display("  Input: 5MHz sine wave @ 100MHz sample rate");
        $display("  Samples per cycle: %0d", SAMPLES_PER_CYCLE);
        $display("  Test cycles: %0d", TEST_CYCLES);
        $display("  Expected phase diff: 90 degrees (5 samples)");
        $display("============================================");
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // ====== Generate sine wave and monitor outputs ======
        $display("\n[Phase 1] Generating sine wave input...");
        
        for (cycle_cnt = 0; cycle_cnt < TEST_CYCLES; cycle_cnt = cycle_cnt + 1) begin
            for (i = 0; i < SAMPLES_PER_CYCLE; i = i + 1) begin
                @(posedge clk);
                x_in = sine_lut[i];
                sample_cnt = sample_cnt + 1;
                
                // Store previous values for zero-crossing detection
                i_prev = i_align;
                q_prev = q_out;
                
                // Print first few samples
                if (sample_cnt <= 30) begin
                    $display("  [%4d] IN=%6d  I=%6d  Q=%6d", 
                             sample_cnt, x_in, i_align, q_out);
                end
                if (sample_cnt == 30) $display("  ...");
                
                // Print samples around specific points
                if (sample_cnt >= PIPELINE_DELAY + 40 && sample_cnt <= PIPELINE_DELAY + 60) begin
                    $display("  [%4d] IN=%6d  I=%6d  Q=%6d", 
                             sample_cnt, x_in, i_align, q_out);
                end
            end
        end
        
        // ====== Summary ======
        $display("\n============================================");
        $display("  Test Summary");
        $display("============================================");
        $display("  Total samples: %0d", sample_cnt);
        $display("  Sine cycles:   %0d", TEST_CYCLES);
        $display("============================================");
        $display("\n  Hilbert Filter Characteristics:");
        $display("  - 33-tap Type III FIR");
        $display("  - 5-stage pipeline (6 clock latency)");
        $display("  - 16-tap group delay");
        $display("  - Total latency: 22 clocks");
        $display("  - I/Q phase difference: 90 degrees");
        $display("============================================");
        $display("\n  *** Observe waveform to verify 90-deg shift ***");
        $display("  *** I leads Q by 5 samples (90 deg @ 5MHz) ***");
        $display("============================================\n");
        
        // Continue for waveform observation
        repeat(100) @(posedge clk);
        
        $finish;
    end

    // ========================================================================
    // Additional monitoring: Print when I or Q crosses zero
    // ========================================================================
    reg [31:0] global_sample;
    
    initial global_sample = 0;
    
    always @(posedge clk) begin
        if (rst_n) begin
            global_sample <= global_sample + 1;
            
            // Detect I channel zero crossing (positive going)
            if (i_prev < 0 && i_align >= 0 && global_sample > PIPELINE_DELAY + 20) begin
                $display("  I zero-cross (rising) at sample %0d", global_sample);
            end
            
            // Detect Q channel zero crossing (positive going)  
            if (q_prev < 0 && q_out >= 0 && global_sample > PIPELINE_DELAY + 20) begin
                $display("  Q zero-cross (rising) at sample %0d", global_sample);
            end
        end
    end

endmodule
