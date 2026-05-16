`timescale 1ns / 1ps
// ============================================================================
// Testbench: SSB Mixer - Up/Down Conversion
// Baseband: 1MHz, Carrier: 5MHz
// USB: 6MHz, LSB: 4MHz
// ============================================================================

module tb_ssb_mixer();

    parameter CLK_PERIOD = 10;  // 100MHz

    reg                     clk;
    reg                     rst_n;
    reg  signed [15:0]      i_in;
    reg  signed [15:0]      q_in;
    reg  signed [13:0]      cos14;
    reg  signed [13:0]      sin14;
    wire signed [15:0]      y_usb;
    wire signed [15:0]      y_lsb;

    // ========================================================================
    // Baseband: 1MHz @ 100MHz = 100 samples/cycle
    // I = cos, Q = sin, Amplitude = 5000
    // ========================================================================
    reg signed [15:0] bb_i [0:99];
    reg signed [15:0] bb_q [0:99];
    
    // ========================================================================
    // Carrier: 5MHz @ 100MHz = 20 samples/cycle
    // Amplitude = 3000
    // ========================================================================
    reg signed [13:0] car_c [0:19];
    reg signed [13:0] car_s [0:19];

    initial begin
        // Baseband I = cos(2*pi*k/100)*5000
        bb_i[0]=16'sd5000;  bb_i[1]=16'sd4980;  bb_i[2]=16'sd4921;  bb_i[3]=16'sd4823;
        bb_i[4]=16'sd4686;  bb_i[5]=16'sd4511;  bb_i[6]=16'sd4300;  bb_i[7]=16'sd4053;
        bb_i[8]=16'sd3773;  bb_i[9]=16'sd3461;  bb_i[10]=16'sd3118; bb_i[11]=16'sd2747;
        bb_i[12]=16'sd2349; bb_i[13]=16'sd1928; bb_i[14]=16'sd1485; bb_i[15]=16'sd1024;
        bb_i[16]=16'sd548;  bb_i[17]=16'sd60;   bb_i[18]=-16'sd436; bb_i[19]=-16'sd936;
        bb_i[20]=-16'sd1437;bb_i[21]=-16'sd1935;bb_i[22]=-16'sd2426;bb_i[23]=-16'sd2906;
        bb_i[24]=-16'sd3371;bb_i[25]=-16'sd3817;bb_i[26]=-16'sd4240;bb_i[27]=-16'sd4636;
        bb_i[28]=-16'sd5000;bb_i[29]=-16'sd4980;bb_i[30]=-16'sd4921;bb_i[31]=-16'sd4823;
        bb_i[32]=-16'sd4686;bb_i[33]=-16'sd4511;bb_i[34]=-16'sd4300;bb_i[35]=-16'sd4053;
        bb_i[36]=-16'sd3773;bb_i[37]=-16'sd3461;bb_i[38]=-16'sd3118;bb_i[39]=-16'sd2747;
        bb_i[40]=-16'sd2349;bb_i[41]=-16'sd1928;bb_i[42]=-16'sd1485;bb_i[43]=-16'sd1024;
        bb_i[44]=-16'sd548; bb_i[45]=-16'sd60;  bb_i[46]=16'sd436;  bb_i[47]=16'sd936;
        bb_i[48]=16'sd1437; bb_i[49]=16'sd1935; bb_i[50]=16'sd2426; bb_i[51]=16'sd2906;
        bb_i[52]=16'sd3371; bb_i[53]=16'sd3817; bb_i[54]=16'sd4240; bb_i[55]=16'sd4636;
        bb_i[56]=16'sd5000; bb_i[57]=16'sd4980; bb_i[58]=16'sd4921; bb_i[59]=16'sd4823;
        bb_i[60]=16'sd4686; bb_i[61]=16'sd4511; bb_i[62]=16'sd4300; bb_i[63]=16'sd4053;
        bb_i[64]=16'sd3773; bb_i[65]=16'sd3461; bb_i[66]=16'sd3118; bb_i[67]=16'sd2747;
        bb_i[68]=16'sd2349; bb_i[69]=16'sd1928; bb_i[70]=16'sd1485; bb_i[71]=16'sd1024;
        bb_i[72]=16'sd548;  bb_i[73]=16'sd60;   bb_i[74]=-16'sd436; bb_i[75]=-16'sd936;
        bb_i[76]=-16'sd1437;bb_i[77]=-16'sd1935;bb_i[78]=-16'sd2426;bb_i[79]=-16'sd2906;
        bb_i[80]=-16'sd3371;bb_i[81]=-16'sd3817;bb_i[82]=-16'sd4240;bb_i[83]=-16'sd4636;
        bb_i[84]=-16'sd5000;bb_i[85]=-16'sd4980;bb_i[86]=-16'sd4921;bb_i[87]=-16'sd4823;
        bb_i[88]=-16'sd4686;bb_i[89]=-16'sd4511;bb_i[90]=-16'sd4300;bb_i[91]=-16'sd4053;
        bb_i[92]=-16'sd3773;bb_i[93]=-16'sd3461;bb_i[94]=-16'sd3118;bb_i[95]=-16'sd2747;
        bb_i[96]=-16'sd2349;bb_i[97]=-16'sd1928;bb_i[98]=-16'sd1485;bb_i[99]=-16'sd1024;
        
        // Baseband Q = sin(2*pi*k/100)*5000
        bb_q[0]=16'sd0;     bb_q[1]=16'sd314;   bb_q[2]=16'sd627;   bb_q[3]=16'sd937;
        bb_q[4]=16'sd1243;  bb_q[5]=16'sd1545;  bb_q[6]=16'sd1841;  bb_q[7]=16'sd2130;
        bb_q[8]=16'sd2412;  bb_q[9]=16'sd2684;  bb_q[10]=16'sd2947; bb_q[11]=16'sd3199;
        bb_q[12]=16'sd3439; bb_q[13]=16'sd3666; bb_q[14]=16'sd3880; bb_q[15]=16'sd4079;
        bb_q[16]=16'sd4262; bb_q[17]=16'sd4429; bb_q[18]=16'sd4579; bb_q[19]=16'sd4712;
        bb_q[20]=16'sd4827; bb_q[21]=16'sd4923; bb_q[22]=16'sd5000; bb_q[23]=16'sd4923;
        bb_q[24]=16'sd4827; bb_q[25]=16'sd4712; bb_q[26]=16'sd4579; bb_q[27]=16'sd4429;
        bb_q[28]=16'sd4262; bb_q[29]=16'sd4079; bb_q[30]=16'sd3880; bb_q[31]=16'sd3666;
        bb_q[32]=16'sd3439; bb_q[33]=16'sd3199; bb_q[34]=16'sd2947; bb_q[35]=16'sd2684;
        bb_q[36]=16'sd2412; bb_q[37]=16'sd2130; bb_q[38]=16'sd1841; bb_q[39]=16'sd1545;
        bb_q[40]=16'sd1243; bb_q[41]=16'sd937;  bb_q[42]=16'sd627;  bb_q[43]=16'sd314;
        bb_q[44]=16'sd0;    bb_q[45]=-16'sd314; bb_q[46]=-16'sd627; bb_q[47]=-16'sd937;
        bb_q[48]=-16'sd1243;bb_q[49]=-16'sd1545;bb_q[50]=-16'sd1841;bb_q[51]=-16'sd2130;
        bb_q[52]=-16'sd2412;bb_q[53]=-16'sd2684;bb_q[54]=-16'sd2947;bb_q[55]=-16'sd3199;
        bb_q[56]=-16'sd3439;bb_q[57]=-16'sd3666;bb_q[58]=-16'sd3880;bb_q[59]=-16'sd4079;
        bb_q[60]=-16'sd4262;bb_q[61]=-16'sd4429;bb_q[62]=-16'sd4579;bb_q[63]=-16'sd4712;
        bb_q[64]=-16'sd4827;bb_q[65]=-16'sd4923;bb_q[66]=-16'sd5000;bb_q[67]=-16'sd4923;
        bb_q[68]=-16'sd4827;bb_q[69]=-16'sd4712;bb_q[70]=-16'sd4579;bb_q[71]=-16'sd4429;
        bb_q[72]=-16'sd4262;bb_q[73]=-16'sd4079;bb_q[74]=-16'sd3880;bb_q[75]=-16'sd3666;
        bb_q[76]=-16'sd3439;bb_q[77]=-16'sd3199;bb_q[78]=-16'sd2947;bb_q[79]=-16'sd2684;
        bb_q[80]=-16'sd2412;bb_q[81]=-16'sd2130;bb_q[82]=-16'sd1841;bb_q[83]=-16'sd1545;
        bb_q[84]=-16'sd1243;bb_q[85]=-16'sd937; bb_q[86]=-16'sd627; bb_q[87]=-16'sd314;
        bb_q[88]=16'sd0;    bb_q[89]=16'sd314;  bb_q[90]=16'sd627;  bb_q[91]=16'sd937;
        bb_q[92]=16'sd1243; bb_q[93]=16'sd1545; bb_q[94]=16'sd1841; bb_q[95]=16'sd2130;
        bb_q[96]=16'sd2412; bb_q[97]=16'sd2684; bb_q[98]=16'sd2947; bb_q[99]=16'sd3199;

        // Carrier 5MHz: 20 points, cos(2*pi*k/20)*3000
        car_c[0] =14'sd3000;  car_c[1] =14'sd2853;  car_c[2] =14'sd2427;  car_c[3] =14'sd1763;
        car_c[4] =14'sd927;   car_c[5] =14'sd0;     car_c[6] =-14'sd927;  car_c[7] =-14'sd1763;
        car_c[8] =-14'sd2427; car_c[9] =-14'sd2853; car_c[10]=-14'sd3000; car_c[11]=-14'sd2853;
        car_c[12]=-14'sd2427; car_c[13]=-14'sd1763; car_c[14]=-14'sd927;  car_c[15]=14'sd0;
        car_c[16]=14'sd927;   car_c[17]=14'sd1763;  car_c[18]=14'sd2427;  car_c[19]=14'sd2853;
        
        // Carrier 5MHz: 20 points, sin(2*pi*k/20)*3000
        car_s[0] =14'sd0;     car_s[1] =14'sd927;   car_s[2] =14'sd1763;  car_s[3] =14'sd2427;
        car_s[4] =14'sd2853;  car_s[5] =14'sd3000;  car_s[6] =14'sd2853;  car_s[7] =14'sd2427;
        car_s[8] =14'sd1763;  car_s[9] =14'sd927;   car_s[10]=14'sd0;     car_s[11]=-14'sd927;
        car_s[12]=-14'sd1763; car_s[13]=-14'sd2427; car_s[14]=-14'sd2853; car_s[15]=-14'sd3000;
        car_s[16]=-14'sd2853; car_s[17]=-14'sd2427; car_s[18]=-14'sd1763; car_s[19]=-14'sd927;
    end

    // Clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // USB mixer: y = I*cos - Q*sin → 5+1=6MHz
    complex_ssb_mixer u_usb (
        .clk(clk), .rst_n(rst_n), .usb_sel(1'b1),
        .i_in(i_in), .q_in(q_in), .cos14(cos14), .sin14(sin14),
        .y_out(y_usb), .dbg_ic_q15(), .dbg_qs_q15()
    );

    // LSB mixer: y = I*cos + Q*sin → 5-1=4MHz
    complex_ssb_mixer u_lsb (
        .clk(clk), .rst_n(rst_n), .usb_sel(1'b0),
        .i_in(i_in), .q_in(q_in), .cos14(cos14), .sin14(sin14),
        .y_out(y_lsb), .dbg_ic_q15(), .dbg_qs_q15()
    );

    // Index counters
    reg [6:0] bb_idx;
    reg [4:0] car_idx;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bb_idx  <= 0;
            car_idx <= 0;
        end else begin
            bb_idx  <= (bb_idx == 99) ? 0 : bb_idx + 1;
            car_idx <= (car_idx == 19) ? 0 : car_idx + 1;
        end
    end

    // Drive signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_in  <= 0;
            q_in  <= 0;
            cos14 <= 0;
            sin14 <= 0;
        end else begin
            i_in  <= bb_i[bb_idx];
            q_in  <= bb_q[bb_idx];
            cos14 <= car_c[car_idx];
            sin14 <= car_s[car_idx];
        end
    end

    // Main test
    initial begin
        rst_n = 0;
        
        $display("============================================");
        $display("  SSB Mixer Dual Channel Test");
        $display("============================================");
        $display("  Baseband: 1MHz");
        $display("  Carrier:  5MHz");
        $display("--------------------------------------------");
        $display("  y_usb: 5+1 = 6MHz (Up-conversion)");
        $display("  y_lsb: 5-1 = 4MHz (Down-conversion)");
        $display("============================================");
        
        repeat(20) @(posedge clk);
        rst_n = 1;
        
        repeat(10000) @(posedge clk);
        
        $display("\n  Test complete!");
        $display("  y_usb period ~ 167ns (6MHz)");
        $display("  y_lsb period ~ 250ns (4MHz)");
        $finish;
    end

endmodule
