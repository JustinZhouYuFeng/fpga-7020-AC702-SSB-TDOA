`timescale 1ns / 1ps
// ============================================================================
// Testbench: Dual-Port RAM Sine Pulse Test
// Function: Test sine pulse waveform write and read operations
// ============================================================================

module tb_dual_port_ram();

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter CLK_PERIOD = 10;          // 100MHz clock = 10ns
    parameter ADDR_WIDTH = 12;
    parameter DATA_WIDTH = 16;
    parameter RAM_DEPTH  = 4096;
    parameter PULSE_LEN  = 1000;        // Pulse length (samples)

    // ========================================================================
    // Signal Declarations
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // Write port signals (Port A)
    reg                     ram_we;
    reg  [ADDR_WIDTH-1:0]   ram_wr_addr;
    reg  [DATA_WIDTH-1:0]   ram_wr_data;
    
    // Read port signals (Port B)
    wire [ADDR_WIDTH-1:0]   ram_rd_addr;
    wire                    ram_rd_en;
    reg  [DATA_WIDTH-1:0]   ram_dout;
    
    // Test memory (for verification)
    reg signed [DATA_WIDTH-1:0] test_mem [0:RAM_DEPTH-1];
    
    // Statistics
    integer write_count;
    integer read_count;
    integer error_count;
    integer i;
    integer check_addr;

    // ========================================================================
    // Pre-computed Sine Lookup Table (64 points per cycle, Q15 format)
    // 5MHz sine at 100MHz sample rate = 20 samples per cycle
    // Using 64-point LUT for smooth waveform
    // ========================================================================
    reg signed [15:0] sine_lut [0:63];
    
    initial begin
        // Sine LUT: 64 points, amplitude = 32767 (Q15 max)
        sine_lut[0]  = 16'sd0;
        sine_lut[1]  = 16'sd3212;
        sine_lut[2]  = 16'sd6393;
        sine_lut[3]  = 16'sd9512;
        sine_lut[4]  = 16'sd12539;
        sine_lut[5]  = 16'sd15446;
        sine_lut[6]  = 16'sd18204;
        sine_lut[7]  = 16'sd20787;
        sine_lut[8]  = 16'sd23170;
        sine_lut[9]  = 16'sd25329;
        sine_lut[10] = 16'sd27245;
        sine_lut[11] = 16'sd28898;
        sine_lut[12] = 16'sd30273;
        sine_lut[13] = 16'sd31356;
        sine_lut[14] = 16'sd32137;
        sine_lut[15] = 16'sd32609;
        sine_lut[16] = 16'sd32767;
        sine_lut[17] = 16'sd32609;
        sine_lut[18] = 16'sd32137;
        sine_lut[19] = 16'sd31356;
        sine_lut[20] = 16'sd30273;
        sine_lut[21] = 16'sd28898;
        sine_lut[22] = 16'sd27245;
        sine_lut[23] = 16'sd25329;
        sine_lut[24] = 16'sd23170;
        sine_lut[25] = 16'sd20787;
        sine_lut[26] = 16'sd18204;
        sine_lut[27] = 16'sd15446;
        sine_lut[28] = 16'sd12539;
        sine_lut[29] = 16'sd9512;
        sine_lut[30] = 16'sd6393;
        sine_lut[31] = 16'sd3212;
        sine_lut[32] = 16'sd0;
        sine_lut[33] = -16'sd3212;
        sine_lut[34] = -16'sd6393;
        sine_lut[35] = -16'sd9512;
        sine_lut[36] = -16'sd12539;
        sine_lut[37] = -16'sd15446;
        sine_lut[38] = -16'sd18204;
        sine_lut[39] = -16'sd20787;
        sine_lut[40] = -16'sd23170;
        sine_lut[41] = -16'sd25329;
        sine_lut[42] = -16'sd27245;
        sine_lut[43] = -16'sd28898;
        sine_lut[44] = -16'sd30273;
        sine_lut[45] = -16'sd31356;
        sine_lut[46] = -16'sd32137;
        sine_lut[47] = -16'sd32609;
        sine_lut[48] = -16'sd32767;
        sine_lut[49] = -16'sd32609;
        sine_lut[50] = -16'sd32137;
        sine_lut[51] = -16'sd31356;
        sine_lut[52] = -16'sd30273;
        sine_lut[53] = -16'sd28898;
        sine_lut[54] = -16'sd27245;
        sine_lut[55] = -16'sd25329;
        sine_lut[56] = -16'sd23170;
        sine_lut[57] = -16'sd20787;
        sine_lut[58] = -16'sd18204;
        sine_lut[59] = -16'sd15446;
        sine_lut[60] = -16'sd12539;
        sine_lut[61] = -16'sd9512;
        sine_lut[62] = -16'sd6393;
        sine_lut[63] = -16'sd3212;
    end

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // RAM Behavioral Model
    // ========================================================================
    reg [DATA_WIDTH-1:0] ram_array [0:RAM_DEPTH-1];
    
    // Initialize RAM to zero
    initial begin
        for (i = 0; i < RAM_DEPTH; i = i + 1) begin
            ram_array[i] = 16'd0;
        end
    end
    
    // Port A - Write
    always @(posedge clk) begin
        if (ram_we) begin
            ram_array[ram_wr_addr] <= ram_wr_data;
        end
    end
    
    // Port B - Read (1 cycle latency)
    always @(posedge clk) begin
        if (ram_rd_en) begin
            ram_dout <= ram_array[ram_rd_addr];
        end
    end

    // ========================================================================
    // ROM Player Instance (Address Generator)
    // ========================================================================
    rom_player #(
        .ADDR_W    (ADDR_WIDTH),
        .LAST_ADDR (RAM_DEPTH - 1)
    ) u_rom_player (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (ram_rd_addr),
        .en    (ram_rd_en)
    );

    // ========================================================================
    // Sine Pulse Generation Function
    // ========================================================================
    function signed [15:0] get_sine_pulse;
        input integer idx;
        reg [5:0] phase_idx;
    begin
        if (idx < PULSE_LEN) begin
            // Pulse region: generate sine wave
            // Phase increment for ~5MHz at 100MHz: 64 * 5 / 100 = 3.2 -> use 3
            phase_idx = (idx * 3) % 64;
            get_sine_pulse = sine_lut[phase_idx];
        end else begin
            // Silent region
            get_sine_pulse = 16'sd0;
        end
    end
    endfunction

    // ========================================================================
    // Main Test Process
    // ========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        ram_we = 0;
        ram_wr_addr = 0;
        ram_wr_data = 0;
        write_count = 0;
        read_count = 0;
        error_count = 0;
        
        $display("============================================");
        $display("  Dual-Port RAM Sine Pulse Test");
        $display("============================================");
        $display("  Pulse Length: %0d samples", PULSE_LEN);
        $display("  Total Length: %0d samples", RAM_DEPTH);
        $display("============================================");
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // ====== Phase 1: Write Sine Pulse ======
        $display("\n[Phase 1] Writing sine pulse waveform...");
        
        for (i = 0; i < RAM_DEPTH; i = i + 1) begin
            @(posedge clk);
            ram_we = 1;
            ram_wr_addr = i;
            ram_wr_data = get_sine_pulse(i);
            test_mem[i] = ram_wr_data;
            write_count = write_count + 1;
            
            // Print some data points
            if (i < 10 || (i >= PULSE_LEN-3 && i <= PULSE_LEN+3)) begin
                $display("  Write [%4d]: %6d", i, $signed(ram_wr_data));
            end
            if (i == 10) $display("  ...");
        end
        
        @(posedge clk);
        ram_we = 0;
        
        $display("  Write complete! Total: %0d points", write_count);
        
        // ====== Phase 2: Read and Verify ======
        $display("\n[Phase 2] Reading and verifying...");
        
        // Wait for rom_player to start
        repeat(5) @(posedge clk);
        
        // Read one complete cycle
        for (i = 0; i < RAM_DEPTH + 50; i = i + 1) begin
            @(posedge clk);
            
            // Check data after 2 cycle delay (RAM read latency)
            if (i >= 2) begin
                check_addr = (i - 2) % RAM_DEPTH;
                
                if (ram_dout !== test_mem[check_addr]) begin
                    error_count = error_count + 1;
                    if (error_count <= 5) begin
                        $display("  [ERROR] Addr=%4d, Expected=%6d, Got=%6d", 
                                 check_addr, $signed(test_mem[check_addr]), $signed(ram_dout));
                    end
                end
                read_count = read_count + 1;
                
                // Print some read data
                if (i < 12 || (i >= PULSE_LEN && i <= PULSE_LEN+5)) begin
                    $display("  Read [%4d]: %6d (Expected: %6d) %s", 
                             check_addr, $signed(ram_dout), $signed(test_mem[check_addr]),
                             (ram_dout === test_mem[check_addr]) ? "OK" : "FAIL");
                end
                if (i == 12) $display("  ...");
            end
        end
        
        // ====== Test Summary ======
        $display("\n============================================");
        $display("  Test Summary");
        $display("============================================");
        $display("  Write Count: %0d", write_count);
        $display("  Read Count:  %0d", read_count);
        $display("  Error Count: %0d", error_count);
        $display("============================================");
        
        if (error_count == 0) begin
            $display("  *** TEST PASSED! ***");
        end else begin
            $display("  *** TEST FAILED! ***");
        end
        
        $display("============================================\n");
        
        // Run a bit more for waveform observation
        repeat(100) @(posedge clk);
        
        $finish;
    end

endmodule
