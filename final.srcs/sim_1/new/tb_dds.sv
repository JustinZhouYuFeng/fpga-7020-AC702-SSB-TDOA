`timescale 1ns / 1ps
// ============================================================================
// Testbench: DDS Compiler + Unpack Module Test
// Function: Verify DDS sine/cosine output with different FCW values
// ============================================================================

module tb_dds();

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter CLK_PERIOD = 10;          // 100MHz clock = 10ns
    parameter DDS_WIDTH  = 14;          // DDS output width
    
    // Frequency Control Word for different frequencies
    // FCW = (f_out * 2^32) / f_clk
    // f_clk = 100MHz
    parameter [31:0] FCW_1MHZ  = 32'h028F_5C29;  // 1MHz
    parameter [31:0] FCW_5MHZ  = 32'h0CCC_CCCD;  // 5MHz  
    parameter [31:0] FCW_10MHZ = 32'h1999_999A;  // 10MHz

    // ========================================================================
    // Signal Declarations
    // ========================================================================
    reg         clk;
    reg         rst_n;
    
    // DDS IP interface
    reg         s_axis_phase_tvalid;
    reg  [31:0] s_axis_phase_tdata;     // FCW input
    wire        m_axis_data_tvalid;
    wire [31:0] m_axis_data_tdata;      // Raw DDS output
    
    // Unpacked outputs
    wire signed [DDS_WIDTH-1:0] cos_out;
    wire signed [DDS_WIDTH-1:0] sin_out;
    
    // Test control
    integer test_phase;
    integer sample_count;
    integer i;

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // DDS Compiler IP Instance
    // ========================================================================
    dds_compiler_0 u_dds (
        .aclk                (clk),
        .s_axis_phase_tvalid (s_axis_phase_tvalid),
        .s_axis_phase_tdata  (s_axis_phase_tdata),
        .m_axis_data_tvalid  (m_axis_data_tvalid),
        .m_axis_data_tdata   (m_axis_data_tdata),
        .m_axis_phase_tvalid (),  // Not used
        .m_axis_phase_tdata  ()   // Not used
    );

    // ========================================================================
    // DDS Unpack Module Instance
    // ========================================================================
    dds_unpack #(
        .W       (DDS_WIDTH),
        .SWAP_CS (1'b0)
    ) u_dds_unpack (
        .dds_bus (m_axis_data_tdata),
        .cos_q   (cos_out),
        .sin_q   (sin_out)
    );

    // ========================================================================
    // Main Test Process
    // ========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        s_axis_phase_tvalid = 0;
        s_axis_phase_tdata = 0;
        test_phase = 0;
        sample_count = 0;
        
        $display("============================================");
        $display("  DDS Compiler IP Core Test");
        $display("============================================");
        $display("  Clock: 100MHz");
        $display("  Output Width: %0d bits", DDS_WIDTH);
        $display("============================================");
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // ====== Test 1: 1MHz Output ======
        test_phase = 1;
        $display("\n[Test 1] FCW = 0x%08X (1MHz)", FCW_1MHZ);
        s_axis_phase_tvalid = 1;
        s_axis_phase_tdata = FCW_1MHZ;
        
        // Run for 200 samples (2 cycles at 1MHz)
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (m_axis_data_tvalid && i < 20) begin
                $display("  [%3d] COS=%6d, SIN=%6d", i, cos_out, sin_out);
            end
            if (i == 20) $display("  ...");
        end
        
        // ====== Test 2: 5MHz Output ======
        test_phase = 2;
        $display("\n[Test 2] FCW = 0x%08X (5MHz)", FCW_5MHZ);
        s_axis_phase_tdata = FCW_5MHZ;
        
        // Run for 100 samples (5 cycles at 5MHz)
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (m_axis_data_tvalid && i < 25) begin
                $display("  [%3d] COS=%6d, SIN=%6d", i, cos_out, sin_out);
            end
            if (i == 25) $display("  ...");
        end
        
        // ====== Test 3: 10MHz Output ======
        test_phase = 3;
        $display("\n[Test 3] FCW = 0x%08X (10MHz)", FCW_10MHZ);
        s_axis_phase_tdata = FCW_10MHZ;
        
        // Run for 50 samples (5 cycles at 10MHz)
        for (i = 0; i < 50; i = i + 1) begin
            @(posedge clk);
            if (m_axis_data_tvalid && i < 15) begin
                $display("  [%3d] COS=%6d, SIN=%6d", i, cos_out, sin_out);
            end
            if (i == 15) $display("  ...");
        end
        
        // ====== Test Summary ======
        $display("\n============================================");
        $display("  Test Summary");
        $display("============================================");
        $display("  Test 1 (1MHz):  100 samples/cycle");
        $display("  Test 2 (5MHz):  20 samples/cycle");
        $display("  Test 3 (10MHz): 10 samples/cycle");
        $display("============================================");
        $display("  Observe waveform for:");
        $display("  - Sine/Cosine 90-degree phase difference");
        $display("  - Correct frequency at each FCW setting");
        $display("  - Clean waveform without distortion");
        $display("============================================\n");
        
        // Continue running for waveform observation
        repeat(200) @(posedge clk);
        
        $finish;
    end

    // ========================================================================
    // Frequency Marker (for waveform annotation)
    // ========================================================================
    reg [31:0] current_fcw;
    reg [7:0]  freq_mhz;
    
    always @(posedge clk) begin
        current_fcw <= s_axis_phase_tdata;
        case (s_axis_phase_tdata)
            FCW_1MHZ:  freq_mhz <= 8'd1;
            FCW_5MHZ:  freq_mhz <= 8'd5;
            FCW_10MHZ: freq_mhz <= 8'd10;
            default:   freq_mhz <= 8'd0;
        endcase
    end

endmodule
