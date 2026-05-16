`timescale 1ns / 1ps
// ============================================================================
// Testbench: 双口RAM波形存储模块测试 (修正版)
// ============================================================================

module tb_dual_port_ram();

    // ========================================================================
    // 参数定义
    // ========================================================================
    parameter CLK_PERIOD = 10;          // 100MHz
    parameter ADDR_WIDTH = 12;
    parameter DATA_WIDTH = 16;
    parameter RAM_DEPTH  = 4096;
    parameter PULSE_LEN  = 1000;        // 脉冲长度

    // ========================================================================
    // 信号声明
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // 写端口信号
    reg                     ram_we;
    reg  [ADDR_WIDTH-1:0]   ram_wr_addr;
    reg signed [DATA_WIDTH-1:0]   ram_wr_data;
    
    // 读端口信号
    wire [ADDR_WIDTH-1:0]   ram_rd_addr;
    wire                    ram_rd_en;
    wire signed [DATA_WIDTH-1:0]   ram_dout;
    
    // 测试用存储器
    reg signed [DATA_WIDTH-1:0] test_mem [0:RAM_DEPTH-1];
    
    // 预计算的正弦波表 (20点一个周期，5MHz @ 100MHz采样)
    reg signed [15:0] sine_lut [0:19];
    
    // 统计变量
    integer write_count;
    integer read_count;
    integer error_count;
    integer i;

    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // 正弦波查找表初始化 (5MHz, 20点/周期)
    // ========================================================================
    initial begin
        // sin(0°)=0, sin(18°)=0.309, sin(36°)=0.588, ... 乘以32767得到Q15
        sine_lut[0]  = 16'sd0;
        sine_lut[1]  = 16'sd10126;   // sin(18°) * 32767
        sine_lut[2]  = 16'sd19260;   // sin(36°)
        sine_lut[3]  = 16'sd26509;   // sin(54°)
        sine_lut[4]  = 16'sd31163;   // sin(72°)
        sine_lut[5]  = 16'sd32767;   // sin(90°) = 1.0
        sine_lut[6]  = 16'sd31163;   // sin(108°)
        sine_lut[7]  = 16'sd26509;   // sin(126°)
        sine_lut[8]  = 16'sd19260;   // sin(144°)
        sine_lut[9]  = 16'sd10126;   // sin(162°)
        sine_lut[10] = 16'sd0;       // sin(180°)
        sine_lut[11] = -16'sd10126;  // sin(198°)
        sine_lut[12] = -16'sd19260;  // sin(216°)
        sine_lut[13] = -16'sd26509;  // sin(234°)
        sine_lut[14] = -16'sd31163;  // sin(252°)
        sine_lut[15] = -16'sd32767;  // sin(270°) = -1.0
        sine_lut[16] = -16'sd31163;  // sin(288°)
        sine_lut[17] = -16'sd26509;  // sin(306°)
        sine_lut[18] = -16'sd19260;  // sin(324°)
        sine_lut[19] = -16'sd10126;  // sin(342°)
    end

    // ========================================================================
    // RAM行为模型
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] ram_array [0:RAM_DEPTH-1];
    reg signed [DATA_WIDTH-1:0] ram_dout_reg;
    
    // Port A (写)
    always @(posedge clk) begin
        if (ram_we) begin
            ram_array[ram_wr_addr] <= ram_wr_data;
        end
    end
    
    // Port B (读)
    always @(posedge clk) begin
        if (ram_rd_en) begin
            ram_dout_reg <= ram_array[ram_rd_addr];
        end
    end
    assign ram_dout = ram_dout_reg;
    
    // ROM播放器
    rom_player #(
        .ADDR_W(ADDR_WIDTH),
        .LAST_ADDR(RAM_DEPTH - 1)
    ) u_rom_player (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (ram_rd_addr),
        .en    (ram_rd_en)
    );

    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        // 初始化
        rst_n = 0;
        ram_we = 0;
        ram_wr_addr = 0;
        ram_wr_data = 0;
        write_count = 0;
        read_count = 0;
        error_count = 0;
        
        // 初始化RAM为0
        for (i = 0; i < RAM_DEPTH; i = i + 1) begin
            ram_array[i] = 0;
            test_mem[i] = 0;
        end
        
        $display("============================================");
        $display("  双口RAM波形存储模块测试");
        $display("============================================");
        
        // 复位
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // ====== 写入正弦脉冲波形 ======
        $display("[阶段1] 写入正弦脉冲波形...");
        
        for (i = 0; i < RAM_DEPTH; i = i + 1) begin
            @(posedge clk);
            ram_we = 1;
            ram_wr_addr = i;
            
            // 脉冲区域: 正弦波, 其他区域: 0
            if (i < PULSE_LEN) begin
                ram_wr_data = sine_lut[i % 20];  // 查表获取正弦值
            end else begin
                ram_wr_data = 16'sd0;            // 静音
            end
            
            test_mem[i] = ram_wr_data;
            write_count = write_count + 1;
            
            // 打印部分数据
            if (i < 25) begin
                $display("  写入[%4d]: %7d", i, ram_wr_data);
            end
            if (i == 25) $display("  ...");
            if (i == PULSE_LEN) $display("  写入[%4d]: %7d  <- 脉冲结束", i, ram_wr_data);
        end
        
        @(posedge clk);
        ram_we = 0;
        $display("  写入完成! 共 %0d 点", write_count);
        
        // ====== 读取验证 ======
        $display("\n[阶段2] 循环读取验证...");
        repeat(5) @(posedge clk);
        
        for (i = 0; i < RAM_DEPTH + 50; i = i + 1) begin
            @(posedge clk);
            
            if (i >= 2) begin
                // 检查数据 (RAM有2拍延迟)
                if (ram_dout !== test_mem[(i-2) % RAM_DEPTH]) begin
                    error_count = error_count + 1;
                    if (error_count <= 5) begin
                        $display("  [错误] addr=%4d, 期望=%7d, 实际=%7d", 
                                 (i-2) % RAM_DEPTH, test_mem[(i-2) % RAM_DEPTH], ram_dout);
                    end
                end
                read_count = read_count + 1;
                
                if (i < 27) begin
                    $display("  读取[%4d]: %7d %s", (i-2) % RAM_DEPTH, ram_dout,
                             (ram_dout === test_mem[(i-2) % RAM_DEPTH]) ? "OK" : "ERR");
                end
            end
        end
        
        // ====== 结果汇总 ======
        $display("\n============================================");
        $display("  测试结果");
        $display("============================================");
        $display("  写入: %0d, 读取: %0d, 错误: %0d", write_count, read_count, error_count);
        
        if (error_count == 0)
            $display("  >>> 测试通过! <<<");
        else
            $display("  >>> 测试失败! <<<");
        $display("============================================\n");
        
        repeat(100) @(posedge clk);
        $finish;
    end

endmodule