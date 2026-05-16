`timescale 1ns / 1ps
// ============================================================================
// Testbench: TDOA Spoofer Pipeline Test
// Function: Verify 28-stage pipeline and delay calculation
// ============================================================================

module tb_tdoa_spoofer();

    parameter CLK_PERIOD = 10;  // 100MHz

    // ========================================================================
    // Signals
    // ========================================================================
    reg                     clk;
    reg                     rst_n;
    
    // VIO inputs
    reg signed [31:0]       vio_center_x;
    reg signed [31:0]       vio_center_y;
    reg [31:0]              vio_scale;
    reg [2:0]               vio_shape_sel;
    
    // Outputs
    wire signed [15:0]      ch0_out;
    wire signed [15:0]      ch1_out;
    wire signed [15:0]      ch2_out;
    wire signed [15:0]      ch3_out;
    wire [31:0]             cnt_out;
    wire [15:0]             delay_ant0_out;
    wire [5:0]              v_idx_out;
    wire signed [15:0]      heart_x_out;
    wire signed [15:0]      heart_y_out;

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
    tdoa_spoofer #(
        .W(16),
        .FS_HZ(100e6),
        .C(3e8),
        .ANT1_X(0.0),   .ANT1_Y(0.0),
        .ANT2_X(200.0), .ANT2_Y(0.0),
        .ANT3_X(0.0),   .ANT3_Y(200.0),
        .ANT4_X(200.0), .ANT4_Y(200.0),
        .NUM_HEART_POINTS(40),
        .PULSE_WIDTH_SAMPLES(5)
    ) u_tdoa (
        .clk            (clk),
        .rst_n          (rst_n),
        .vio_center_x   (vio_center_x),
        .vio_center_y   (vio_center_y),
        .vio_scale      (vio_scale),
        .vio_shape_sel  (vio_shape_sel),
        .ch0_out        (ch0_out),
        .ch1_out        (ch1_out),
        .ch2_out        (ch2_out),
        .ch3_out        (ch3_out),
        .cnt_out        (cnt_out),
        .delay_ant0_out (delay_ant0_out),
        .v_idx_out      (v_idx_out),
        .heart_x_out    (heart_x_out),
        .heart_y_out    (heart_y_out)
    );

    // ========================================================================
    // Main Test
    // ========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        vio_center_x = 32'sd100;    // Center at (100, 100)
        vio_center_y = 32'sd100;
        vio_scale = 32'd1000;        // Scale = 1000
        vio_shape_sel = 3'd0;        // Heart shape
        
        $display("============================================");
        $display("  TDOA Spoofer Pipeline Test");
        $display("============================================");
        $display("  Antenna Array: 200m x 200m");
        $display("  Center: (100m, 100m)");
        $display("  Shape: Heart (0)");
        $display("  Scale: 1000");
        $display("============================================");
        
        // Reset
        repeat(20) @(posedge clk);
        rst_n = 1;
        
        $display("\n[Phase 1] Pipeline startup (28 cycles)...");
        repeat(50) @(posedge clk);
        
        // ====== Test 1: Heart shape ======
        $display("\n[Test 1] Heart Shape - Running 3 cycles...");
        vio_shape_sel = 3'd0;
        
        // Run for 3 complete cycles (3 x 50000 = 150000 clocks)
        repeat(150000) @(posedge clk);
        
        // ====== Test 2: Star shape ======
        $display("\n[Test 2] Star Shape - Running 2 cycles...");
        vio_shape_sel = 3'd1;
        repeat(100000) @(posedge clk);
        
        // ====== Test 3: Circle shape ======
        $display("\n[Test 3] Circle Shape - Running 2 cycles...");
        vio_shape_sel = 3'd2;
        repeat(100000) @(posedge clk);
        
        // ====== Test 4: Change center position ======
        $display("\n[Test 4] Move center to (50, 150)...");
        vio_center_x = 32'sd50;
        vio_center_y = 32'sd150;
        vio_shape_sel = 3'd0;  // Back to heart
        repeat(100000) @(posedge clk);
        
        // ====== Summary ======
        $display("\n============================================");
        $display("  Test Complete");
        $display("============================================");
        $display("  Observe in waveform:");
        $display("  - v_idx: cycles 0->39 every 50000 clks");
        $display("  - delay_ant0: changes each cycle");
        $display("  - ch0-ch3: pulses at different delays");
        $display("============================================\n");
        
        $finish;
    end

    // ========================================================================
    // Monitor: Print key events
    // ========================================================================
    reg [31:0] prev_cnt;
    reg [5:0]  prev_v_idx;
    
    always @(posedge clk) begin
        prev_cnt <= cnt_out;
        prev_v_idx <= v_idx_out;
        
        // Print when trajectory index changes
        if (v_idx_out != prev_v_idx && rst_n) begin
            $display("  [%0t] v_idx=%2d, delay0=%5d, heart=(%6d,%6d)",
                     $time, v_idx_out, delay_ant0_out, heart_x_out, heart_y_out);
        end
        
        // Print when pulse occurs on ch0
        if (ch0_out != 0) begin
            $display("  [%0t] PULSE! cnt=%5d, ch0=%d", $time, cnt_out, ch0_out);
        end
    end
    
    // Print periodic status
    initial begin
        @(posedge rst_n);
        forever begin
            repeat(10000) @(posedge clk);
            $display("  Status: cnt=%5d, v_idx=%2d, delay0=%4d, heart=(%5d,%5d)",
                     cnt_out, v_idx_out, delay_ant0_out, heart_x_out, heart_y_out);
        end
    end

endmodule
