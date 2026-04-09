`timescale 1ns / 1ps
// ============================================================================
// ģ������: top_fifo_ila
// ��    ��: FPGA�״��źŴ���ϵͳ����ģ��
// 
// ϵͳ���ܸ���:
//   ��ϵͳʵ�����״�����źŵ���������֤���������º��Ĺ���:
//   1. �ٶ���ƭ - ͨ��SSB���ߴ�����ʵ�ֶ�����Ƶ��
//   2. λ����ƭ - ͨ��TDOAʱ�������ʵ�����Ŀ�궨λ
//   3. ������ƭ - ֧��5�ֿɱ���˶��켣(����/����/Բ��/õ��/����)
//
// ��Ҫģ��:
//   - UART����: ������λ�����͵Ļ�����������
//   - RAM�洢: ����4096��16λ������
//   - SSB����: Hilbert�任 + DDS���� + ������Ƶ
//   - TDOA����: 4ͨ����ʱ��������
//   - Ƶ�ʲ���: ��֤SSBƵ��Ч��
//   - VIO����: ʵʱ����ϵͳ����
//   - ILA����: �ڲ��źŹ۲�
//
// ����ָ��:
//   - ϵͳʱ��: 100MHz (��MMCM��50MHz��Ƶ)
//   - SSBƵ��: ��2MHz (VIO�ɵ�)
//   - TDOA����: 10ns (��Ӧ3m���뾫��)
//   - UART������: 921600 bps
//
// ����: FPGA�γ����
// ����: 2026-01
// �汾: v2.0
// ============================================================================

module top_fifo_ila #(
    parameter integer USE_ROM      = 1,             // �Ƿ�ʹ��ROM (��������)
    parameter integer CLK_FREQ_HZ  = 100_000_000,   // ϵͳʱ��Ƶ�� (100MHz)
    parameter integer FS_HZ        = 100_000_000,   // ����Ƶ�� (100MHz)
    parameter integer D_SAMPLES    = 800,           // FIFO��ʱ��� (800������ = 8��s)
    parameter integer SHIFT_HZ     = 2_000_000      // Ĭ��SSBƵ�� (2MHz)
)(                            
    input  wire sys_clk,    // �ⲿ����ʱ�� (50MHz)
    input  wire rst_n,      // �ⲿ��λ���� (active low)
    input  wire uart_rx,    // UART�������� (��Ӧ K16)
    input  wire key_mode,   // ģʽ�л����� (��Ӧ H16, 0=����������, 1=��������)
    output wire uart_tx     // UART��������
);

    // ========================================================================
    // 1. ȫ��ʱ���븴λ����
    // ========================================================================
    // ʹ��Xilinx MMCM/PLL IP�˽�50MHz����ʱ�ӱ�Ƶ��100MHz
    // ����ͬ����λ�ź�ȷ��ϵͳ�ȶ�����
    
    wire clk;               // 100MHzϵͳ��ʱ��
    wire locked;            // PLL����ָʾ
    
    // ʱ������IP��ʵ����
    clk_wiz_1 instance_name (
        .clk_out1(clk),     // ���: 100MHz
        .locked(locked),    // PLL����״̬
        .clk_in1(sys_clk)   // ����: 50MHz
    );

    // ͬ����λ���� (3��ͬ����)
    // ��PLLδ����ʱ���ָ�λ�������󾭹�3��ʱ�������ͷŸ�λ
    reg [2:0] rst_sync_reg;
    wire rst_n_sync;
    
    always_ff @(posedge clk or negedge locked) begin
        if (!locked)
            rst_sync_reg <= 3'b000;
        else
            rst_sync_reg <= {rst_sync_reg[1:0], 1'b1};
    end
    assign rst_n_sync = rst_sync_reg[2];
    
    // ========================================================================
    // 2. UART����ģ��
    // ========================================================================
    // ������λ�����͵Ĳ�������
    // Э��: 8N1, ������921600
    // ͬ��ͷ: 0xAA 0x55
    
    logic       rx_dv;      // ����������Ч����
    logic [7:0] rx_byte;    // ���յ����ֽ�
    
    uart_rx_simple #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD(921600)
    ) u_uart_rx (
        .clk    (clk),
        .rst_n  (rst_n_sync),
        .rx     (uart_rx),      
        .rx_byte(rx_byte),
        .rx_dv  (rx_dv)
    );

    // ========================================================================
    // 3. �ֽ�ƴװ��RAMд���߼�
    // ========================================================================
    // ����: ��UART���յ��ֽ���ƴװ��16λ�����㲢д��RAM
    // �ص�:
    //   - ͬ��ͷ��� (0xAA 0x55) ȷ�����ݶ���
    //   - ����ֽ��� (���ֽ��ȷ���)
    //   - �������ƽ���״̬
    
    logic [11:0] ram_wr_addr;   // RAMд��ַ (0-4095)
    logic [15:0] ram_wr_data;   // RAMд���� (16λ������)
    logic        ram_we;        // RAMдʹ��
    logic        byte_toggle;   // �ֽ�ƴװ״̬ (0=�ȴ����ֽ�, 1=�ȴ����ֽ�)
    logic [7:0]  temp_high;     // �ݴ�ĸ��ֽ�
    logic        sync_found;    // ͬ��ͷ���ҵ���־
    logic [7:0]  prev_byte;     // ��һ�����յ��ֽ� (����ͬ��ͷ���)

    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            ram_wr_addr <= 0;
            ram_we      <= 0;
            byte_toggle <= 0;
            temp_high   <= 0;
            ram_wr_data <= 0;
            sync_found  <= 0;
            prev_byte   <= 0;
        end else begin
            ram_we <= 0;  // Ĭ�ϲ�д��
            
            if (key_mode == 0) begin 
                // �����ɿ�: ���ý���״̬��׼������������
                ram_wr_addr <= 0;
                byte_toggle <= 0;
                sync_found  <= 0;
                prev_byte   <= 0;
            end 
            else if (rx_dv) begin
                // ���յ����ֽ�
                if (!sync_found) begin
                    // ��δͬ��: ���ͬ��ͷ 0xAA 0x55
                    if (prev_byte == 8'hAA && rx_byte == 8'h55) begin
                        sync_found  <= 1;
                        byte_toggle <= 0;
                        ram_wr_addr <= 0;
                    end
                    prev_byte <= rx_byte;
                end else begin
                    // ��ͬ��: ������������
                    if (byte_toggle == 0) begin
                        // ���ո��ֽ�
                        temp_high   <= rx_byte;
                        byte_toggle <= 1;
                    end else begin
                        // ���յ��ֽڣ�ƴװ��16λ��д��RAM
                        ram_wr_data <= {temp_high, rx_byte};
                        ram_we      <= 1; 
                        if (ram_wr_addr < 4095) 
                            ram_wr_addr <= ram_wr_addr + 1;
                        else
                            ram_wr_addr <= 0;  // ��ַ����
                        byte_toggle <= 0;
                    end
                end
            end
        end
    end

    // ========================================================================
    // 4. SSB���ߴ�������·
    // ========================================================================
    // �ź���: RAM �� FIFO��ʱ �� Hilbert�任 �� SSB��Ƶ �� ���
    //
    // ԭ��: SSB���ƹ�ʽ
    //   USB (�ϱߴ�): y(t) = I(t)��cos(��t) - Q(t)��sin(��t)
    //   LSB (�±ߴ�): y(t) = I(t)��cos(��t) + Q(t)��sin(��t)
    //   ���� Q(t) = Hilbert{I(t)} ��I��ϣ�����ر任
    
    // ------------------------------------------------------------------------
    // 4.1 ROM������ - ѭ����ȡRAM�еĲ�������
    // ------------------------------------------------------------------------
    wire [11:0] ram_rd_addr;    // RAM����ַ
    wire        ram_rd_en;      // RAM��ʹ��
    
    rom_player #(
        .ADDR_W(12), 
        .LAST_ADDR(12'd4095)
    ) U_RP (
        .clk (clk), 
        .rst_n (rst_n_sync),
        .addr(ram_rd_addr),                        
        .en  (ram_rd_en)
    );

    // ------------------------------------------------------------------------
    // 4.2 ˫��RAM - �洢������������
    // ------------------------------------------------------------------------
    // ����: 4096 �� 16bit = 8KB
    // A��: UARTд��, B��: �źŲ��Ŷ�ȡ
    
    wire [15:0] ram_dout;       // RAM������ (Q15��ʽ)
    
    blk_mem_gen_1 U_RAM (
        .clka  (clk),
        .wea   (ram_we),        // A��дʹ��
        .addra (ram_wr_addr),   // A�ڵ�ַ
        .dina  (ram_wr_data),   // A������
        .clkb  (clk),
        .enb   (ram_rd_en),     // B�ڶ�ʹ��
        .addrb (ram_rd_addr),   // B�ڵ�ַ
        .doutb (ram_dout)       // B������
    );

    // ------------------------------------------------------------------------
    // 4.3 �̶���ʱFIFO - HilbertȺ�ӳٲ���
    // ------------------------------------------------------------------------
    // ����: ΪIͨ������̶���ʱ������Hilbert�˲�����Ⱥ�ӳ�
    // ��ʱ: D_SAMPLES = 800�������� = 8��s @ 100MHz
    
    wire signed [15:0] fifo_out;    // FIFO���
    wire        fifo_dv;            // �����Ч
    wire        wr_en_m, rd_en_m, rd_started_m;
    wire [9:0]  fill_cnt_m;         // FIFO������
    
    fixed_delay_fifo_xpm #(
        .W(16), 
        .D_SAMPLES(D_SAMPLES), 
        .DEPTH_POW2(1024)                      
    ) U_FIXDLY (
        .clk(clk), 
        .rst_n(rst_n_sync),
        .din(ram_dout), 
        .din_valid(1'b1),                     
        .dout(fifo_out), 
        .dout_valid(fifo_dv), 
        .wr_en_o(wr_en_m), 
        .rd_en_o(rd_en_m), 
        .rd_started_o(rd_started_m),            
        .fill_cnt_o(fill_cnt_m)              
    );

    // ------------------------------------------------------------------------
    // 4.4 DDS����������
    // ------------------------------------------------------------------------
    // ����: ����SSB�������������/�����ز�
    // Ƶ�ʿ�����(FCW)����: FCW = f_out �� 2^32 / f_clk �� f_out �� 42.95
    
    wire        dds_vld;            // DDS�����Ч
    wire signed [31:0] dds_bus;     // DDS������� {sin[15:0], cos[15:0]}
    reg         [31:0] fcw_reg;     // Ƶ�ʿ����ּĴ���
    wire [31:0] vio_shift_hz;       // VIO���Ƶ�Ƶ����
    
    // FCW��̬����: ֧��VIOʵʱ����Ƶ��
    always @(posedge clk) begin
        if (vio_shift_hz == 0)
            fcw_reg <= integer'(SHIFT_HZ * 42.94967296);  // ʹ��Ĭ��ֵ2MHz
        else
            fcw_reg <= (vio_shift_hz * 32'd43);           // VIO��̬����
    end

    // DDS������IP��ʵ����
    dds_compiler_0 U_DDS (                  
        .aclk(clk), 
        .s_axis_phase_tvalid(1'b1), 
        .s_axis_phase_tdata(fcw_reg),        
        .m_axis_data_tvalid(dds_vld), 
        .m_axis_data_tdata(dds_bus)        
    );

    // ------------------------------------------------------------------------
    // 4.5 SSB������·��װģ��
    // ------------------------------------------------------------------------
    // ����: Hilbert�任�� + DDS��� + ������Ƶ��
    
    logic signed [15:0] y_ssb_q15;      // SSB������� (Q15��ʽ)
    logic signed [15:0] tap_i, tap_q;   // ����: I/Qͨ���ź�
    logic signed [15:0] tap_ic, tap_qs; // ����: �˻��ź�
    logic signed [13:0] tap_cos, tap_sin; // ����: �����ź�

    ssb_chain #(
        .DDS_W(14)
    ) U_SSB (                  
        .clk(clk),
        .rst_n(rst_n_sync),
        .usb_sel(vio_usb_sel),      // USB/LSBģʽѡ�� (����VIO)
        .x_in_q15(fifo_out), 
        .dds_bus(dds_bus), 
        .y_ssb_q15(y_ssb_q15),
        .tap_i_q15(tap_i), 
        .tap_q_q15(tap_q),                        
        .tap_cos_q13(tap_cos), 
        .tap_sin_q13(tap_sin),     
        .tap_ic_q15(tap_ic), 
        .tap_qs_q15(tap_qs)                     
    );

    // ========================================================================
    // 5. Ƶ�ʲ���ģ��
    // ========================================================================
    // ����: ���������źź�SSB����źŵ�Ƶ�ʣ���֤Ƶ��Ч��
    // ����: ������ + ����� (�޳�������ʡ��Դ)
    // ����: Լ3% @ 500kHz-50MHz
    
    // ------------------------------------------------------------------------
    // 5.1 �����ź�Ƶ�ʲ���
    // ------------------------------------------------------------------------
    wire [31:0] freq_input_hz;      // �����ź�Ƶ�� (Hz)
    wire        input_signal_active; // �ź���Чָʾ
    
    freq_meter_period #(
        .CLK_FREQ(CLK_FREQ_HZ),
        .AMP_THR(2000),             // ������ֵ: Լ8%������
        .MIN_FREQ_HZ(500_000)       // ��С�ɲ�Ƶ��: 500kHz
    ) u_freq_input (
        .clk(clk),
        .rst_n(rst_n_sync),
        .signal_in(fifo_out),
        .freq_hz(freq_input_hz),
        .signal_active(input_signal_active)
    );

    // ------------------------------------------------------------------------
    // 5.2 SSB����ź�Ƶ�ʲ���
    // ------------------------------------------------------------------------
    wire [31:0] freq_ssb_hz;        // SSB���Ƶ�� (Hz)
    wire        ssb_signal_active;  // �ź���Чָʾ
    
    freq_meter_period #(
        .CLK_FREQ(CLK_FREQ_HZ),
        .AMP_THR(2000),
        .MIN_FREQ_HZ(500_000)
    ) u_freq_ssb (
        .clk(clk),
        .rst_n(rst_n_sync),
        .signal_in(y_ssb_q15),
        .freq_hz(freq_ssb_hz),
        .signal_active(ssb_signal_active)
    );

    // ------------------------------------------------------------------------
    // 5.3 Ƶ��������
    // ------------------------------------------------------------------------
    wire [31:0] freq_shift_hz;
    assign freq_shift_hz = (freq_ssb_hz > freq_input_hz) ? 
                           (freq_ssb_hz - freq_input_hz) : 32'd0;

    // ------------------------------------------------------------------------
    // 5.4 ����ʱ����
    // ------------------------------------------------------------------------
    // ��ʱ = FIFO��ʱ + HilbertȺ�ӳ�(16��) + ��ˮ��(5��) + ��Ƶ(1��) + ���(1��)
    localparam int TOTAL_DELAY_SAMPLES = D_SAMPLES + 23;
    wire [31:0] delay_time_ns;
    assign delay_time_ns = TOTAL_DELAY_SAMPLES * 10;  // ÿ��10ns @ 100MHz

    // ========================================================================
    // 6. VIO����IO����ģ��
    // ========================================================================
    // ����: ͨ��Vivado Hardware Managerʵʱ����ϵͳ����
    // �����ź�:
    //   - vio_scale: ��״����ϵ�� (100-5000)
    //   - vio_center_x/y: Ŀ���������� (��)
    //   - vio_shape_sel: ��״ѡ�� (0-4)
    //   - vio_shift_hz: SSBƵ���� (Hz)
    //   - vio_usb_sel: USB/LSBģʽѡ��
    
    wire [31:0] vio_scale;              // ��״����ϵ��
    wire signed [31:0] vio_center_x;    // Ŀ������X���� (��)
    wire signed [31:0] vio_center_y;    // Ŀ������Y���� (��)
    wire [2:0] vio_shape_sel;           // ��״ѡ��
    // vio_shift_hz ����DDSģ��ǰ����
    wire vio_usb_sel;                   // USB/LSBģʽѡ�� (1=USB, 0=LSB)

    vio_0 u_vio_ctrl (
        .clk(clk),                    
        .probe_out0(vio_scale),         // ��״���� (Ĭ�� 1000)
        .probe_out1(vio_center_x),      // Ŀ������X (��)
        .probe_out2(vio_center_y),      // Ŀ������Y (��)
        .probe_out3(vio_shape_sel),     // ��״ѡ��: 0=����, 1=����, 2=Բ��, 3=õ��, 4=����
        .probe_out4(vio_shift_hz),      // SSBƵ���� (Hz, Ĭ�� 2000000)
        .probe_out5(vio_usb_sel)        // USB/LSBѡ�� (1=USB, 0=LSB, Ĭ�� 1)
    );

    // ========================================================================
    // 7. TDOAλ����ƭ�ź�������
    // ========================================================================
    // ����: ����4ͨ��ʱ��������źţ�ģ�����Ŀ��λ��
    // ԭ��: ����Ŀ�굽�����ߵľ�����㴫����ʱ��
    // ��������: 200m �� 200m �����β���
    
    wire signed [15:0] tdoa_ch0, tdoa_ch1, tdoa_ch2, tdoa_ch3;
    wire [31:0] spo_cnt;            // ���ڼ�����
    wire [15:0] delay_ant0;         // ����0��ʱֵ
    wire [5:0]  dbg_v_idx;          // ��ǰ�켣������
    wire signed [15:0] dbg_heart_x, dbg_heart_y;  // ��ǰ�켣����

    tdoa_spoofer #(
        .W(16), 
        .FS_HZ(100.0e6),            // ����Ƶ��: 100MHz
        .C(3.0e8),                  // ����: 3��10^8 m/s
        .ANT1_X(0.0),   .ANT1_Y(0.0),       // ����1: ԭ��
        .ANT2_X(200.0), .ANT2_Y(0.0),       // ����2: (200, 0)
        .ANT3_X(0.0),   .ANT3_Y(200.0),     // ����3: (0, 200)
        .ANT4_X(200.0), .ANT4_Y(200.0),     // ����4: (200, 200)
        .NUM_HEART_POINTS(40),      // ÿ�ֹ켣40��������
        .PULSE_WIDTH_SAMPLES(5)     // �������: 5�������� = 50ns
    ) u_spoofer (
        .clk(clk),
        .rst_n(rst_n_sync),
        .vio_center_x(vio_center_x),
        .vio_center_y(vio_center_y),
        .vio_scale(vio_scale),
        .vio_shape_sel(vio_shape_sel),
        .ch0_out(tdoa_ch0), 
        .ch1_out(tdoa_ch1), 
        .ch2_out(tdoa_ch2), 
        .ch3_out(tdoa_ch3),
        .cnt_out(spo_cnt),
        .delay_ant0_out(delay_ant0),
        .v_idx_out(dbg_v_idx),
        .heart_x_out(dbg_heart_x),
        .heart_y_out(dbg_heart_y)
    );

    // ========================================================================
    // 8. ��������
    // ========================================================================
    // ����: ���4ͨ������������أ����ɵ����ڴ����ź�
    
    logic p0, p1, p2, p3;           // ���������
    
    pulse_detector #(.W(16)) det0 (
        .clk(clk), .rst_n(rst_n_sync), 
        .s(tdoa_ch0), .thr(16'sd2000), 
        .rise_pulse(p0)
    );
    pulse_detector #(.W(16)) det1 (
        .clk(clk), .rst_n(rst_n_sync), 
        .s(tdoa_ch1), .thr(16'sd2000), 
        .rise_pulse(p1)
    );
    pulse_detector #(.W(16)) det2 (
        .clk(clk), .rst_n(rst_n_sync), 
        .s(tdoa_ch2), .thr(16'sd2000), 
        .rise_pulse(p2)
    );
    pulse_detector #(.W(16)) det3 (
        .clk(clk), .rst_n(rst_n_sync), 
        .s(tdoa_ch3), .thr(16'sd2000), 
        .rise_pulse(p3)
    );

    // ========================================================================
    // 9. ʱ����������߼�
    // ========================================================================
    // ����: ����4ͨ�����嵽��ʱ�䣬�������ʱ���
    // �ص�: Wrap-around��ȫ��ƣ�֧��32λ���������
    
    // ------------------------------------------------------------------------
    // 9.1 ȫ�ֲ���������
    // ------------------------------------------------------------------------
    logic [31:0] sample_cnt;
    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) 
            sample_cnt <= 32'd0;
        else 
            sample_cnt <= sample_cnt + 1'b1;
    end

    // ------------------------------------------------------------------------
    // 9.2 ����״̬��
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE,   // ����: �ȴ����崥��
        CAPT,   // ����: ��¼��ͨ������ʱ��
        SEND    // ����: ͨ��UART�ϱ�����
    } capt_state_t;
    
    capt_state_t capt_st;
    logic [31:0] t0, t1, t2, t3;                    // ��ͨ������ʱ���
    logic [31:0] capt_start_time;                   // ����ʼʱ��
    logic got0, got1, got2, got3;                   // ��ͨ��������ɱ�־
    logic send_done, sending;                       // ����״̬
    
    // ���񴰿�: ���ʱ��� �� 200m / 3m/sample �� 67 samples
    localparam int CAPT_WINDOW = 1024;              // Ԥ������
    
    // ֡��� (0-255ѭ��)
    logic [7:0]  frame_seq;
    
    // �������״��Ϣ
    logic [5:0]  captured_v_idx;
    logic signed [15:0] captured_heart_x;
    logic signed [15:0] captured_heart_y;
    logic [2:0]  captured_shape_sel;
    logic [15:0] captured_delay_ant0;
    
    // ����ͨ�����崥��
    wire any_pulse = p0 | p1 | p2 | p3;

    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            capt_st <= IDLE;
            got0 <= 0; got1 <= 0; got2 <= 0; got3 <= 0;
            t0 <= 0; t1 <= 0; t2 <= 0; t3 <= 0;
            capt_start_time <= 0;
            frame_seq <= 0;
            captured_v_idx <= 0;
            captured_heart_x <= 0;
            captured_heart_y <= 0;
            captured_shape_sel <= 0;
            captured_delay_ant0 <= 0;
        end else begin
            case (capt_st)
                IDLE: begin
                    // ��������־���ȴ�����ͨ������
                    got0 <= 0; got1 <= 0; got2 <= 0; got3 <= 0;
                    if (any_pulse) begin
                        capt_start_time <= sample_cnt;
                        // ���浱ǰ��״��Ϣ
                        captured_v_idx <= dbg_v_idx;
                        captured_heart_x <= dbg_heart_x;
                        captured_heart_y <= dbg_heart_y;
                        captured_shape_sel <= vio_shape_sel;
                        captured_delay_ant0 <= delay_ant0;
                        capt_st <= CAPT;
                        // ͬʱ��¼������ͨ��
                        if (p0) begin t0 <= sample_cnt; got0 <= 1; end
                        if (p1) begin t1 <= sample_cnt; got1 <= 1; end
                        if (p2) begin t2 <= sample_cnt; got2 <= 1; end
                        if (p3) begin t3 <= sample_cnt; got3 <= 1; end
                    end
                end
                
                CAPT: begin
                    // ������������ͨ��
                    if (!got0 && p0) begin t0 <= sample_cnt; got0 <= 1; end
                    if (!got1 && p1) begin t1 <= sample_cnt; got1 <= 1; end
                    if (!got2 && p2) begin t2 <= sample_cnt; got2 <= 1; end
                    if (!got3 && p3) begin t3 <= sample_cnt; got3 <= 1; end
                    
                    // ����ͨ��������� �� ��ʱ
                    if ((got0 && got1 && got2 && got3) || 
                        ((sample_cnt - capt_start_time) >= CAPT_WINDOW)) begin
                        capt_st <= SEND;
                        frame_seq <= frame_seq + 1'b1;
                    end
                end
                
                SEND: begin
                    // �ȴ�UART�������
                    if (send_done) capt_st <= IDLE;
                end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 9.3 ʱ�����㺯�� (�����ȫ)
    // ------------------------------------------------------------------------
    function automatic logic signed [15:0] calc_dt(input logic [31:0] ta, tb);
        logic [31:0] diff_unsigned;
        logic signed [31:0] diff_signed;
    begin
        // �޷��ż��� (����2's complement��Ȼ���)
        diff_unsigned = ta - tb;
        // ����Ϊ�з�����
        diff_signed = $signed(diff_unsigned);
        // ���͵�16λ��Χ
        if (diff_signed > 32767)
            return 16'sd32767;
        else if (diff_signed < -32768)
            return -16'sd32768;
        else
            return diff_signed[15:0];
    end
    endfunction
    
    logic signed [15:0] dt10, dt20, dt30;   // �����ͨ��0��ʱ���
    logic [15:0]        t0_mod;             // ͨ��0����ʱ��
    
    always_comb begin
        t0_mod = captured_delay_ant0;
        // ������ͨ��������ɹ�ʱ������Чʱ���
        dt10   = (got0 && got1) ? calc_dt(t1, t0) : 16'sh8000;  // 0x8000��ʾ��Ч
        dt20   = (got0 && got2) ? calc_dt(t2, t0) : 16'sh8000;
        dt30   = (got0 && got3) ? calc_dt(t3, t0) : 16'sh8000;
    end

    // ========================================================================
    // 10. CRC-8У�����
    // ========================================================================
    // ����ʽ: 0x07, ��ʼֵ: 0x00
    // ��MATLAB crc8()�����㷨һ��
    
    function automatic logic [7:0] crc8_byte(input logic [7:0] crc_in, input logic [7:0] data);
        logic [7:0] c;
        begin
            c = crc_in ^ data;
            for (int i = 0; i < 8; i++) begin
                if (c[7])
                    c = (c << 1) ^ 8'h07;
                else
                    c = c << 1;
            end
            return c;
        end
    endfunction
    
    // CRC��������: [SEQ][T0(2)][DT10(2)][DT20(2)][DT30(2)][SHAPE][V_IDX][X(2)][Y(2)]
    logic [7:0] crc8_computed;
    always_comb begin
        logic [7:0] crc_temp;
        crc_temp = 8'h00;
        crc_temp = crc8_byte(crc_temp, frame_seq);
        crc_temp = crc8_byte(crc_temp, t0_mod[15:8]);
        crc_temp = crc8_byte(crc_temp, t0_mod[7:0]);
        crc_temp = crc8_byte(crc_temp, dt10[15:8]);
        crc_temp = crc8_byte(crc_temp, dt10[7:0]);
        crc_temp = crc8_byte(crc_temp, dt20[15:8]);
        crc_temp = crc8_byte(crc_temp, dt20[7:0]);
        crc_temp = crc8_byte(crc_temp, dt30[15:8]);
        crc_temp = crc8_byte(crc_temp, dt30[7:0]);
        crc_temp = crc8_byte(crc_temp, {5'b0, captured_shape_sel});
        crc_temp = crc8_byte(crc_temp, {2'b0, captured_v_idx});
        crc_temp = crc8_byte(crc_temp, captured_heart_x[15:8]);
        crc_temp = crc8_byte(crc_temp, captured_heart_x[7:0]);
        crc_temp = crc8_byte(crc_temp, captured_heart_y[15:8]);
        crc_temp = crc8_byte(crc_temp, captured_heart_y[7:0]);
        crc8_computed = crc_temp;
    end

    // ========================================================================
    // 11. UART����ģ��
    // ========================================================================
    // ֡��ʽ (18�ֽ�):
    //   [0x55][0xAA] - ͬ��ͷ (2�ֽ�)
    //   [SEQ]        - ֡��� (1�ֽ�)
    //   [T0]         - ͨ��0ʱ�� (2�ֽ�, ���)
    //   [DT10]       - ʱ���1-0 (2�ֽ�, �з���)
    //   [DT20]       - ʱ���2-0 (2�ֽ�, �з���)
    //   [DT30]       - ʱ���3-0 (2�ֽ�, �з���)
    //   [SHAPE]      - ��״ID (1�ֽ�)
    //   [V_IDX]      - ������ (1�ֽ�)
    //   [X]          - X���� (2�ֽ�, �з���)
    //   [Y]          - Y���� (2�ֽ�, �з���)
    //   [CRC8]       - У��� (1�ֽ�)
    
    localparam int PACKET_LEN = 18;
    
    logic        uart_start, uart_busy;
    logic [7:0]  uart_byte;
    logic [4:0]  uart_idx;      // 0-17
    
    // �������ݰ���װ
    logic [7:0] tx_data [0:PACKET_LEN-1];
    always_comb begin
        tx_data[0]  = 8'h55;                        // ͬ���ֽ�1
        tx_data[1]  = 8'hAA;                        // ͬ���ֽ�2
        tx_data[2]  = frame_seq;                    // ֡���
        tx_data[3]  = t0_mod[15:8];                 // T0 ���ֽ�
        tx_data[4]  = t0_mod[7:0];                  // T0 ���ֽ�
        tx_data[5]  = dt10[15:8];                   // DT10 ���ֽ�
        tx_data[6]  = dt10[7:0];                    // DT10 ���ֽ�
        tx_data[7]  = dt20[15:8];                   // DT20 ���ֽ�
        tx_data[8]  = dt20[7:0];                    // DT20 ���ֽ�
        tx_data[9]  = dt30[15:8];                   // DT30 ���ֽ�
        tx_data[10] = dt30[7:0];                    // DT30 ���ֽ�
        tx_data[11] = {5'b0, captured_shape_sel};   // ��״ID
        tx_data[12] = {2'b0, captured_v_idx};       // ������
        tx_data[13] = captured_heart_x[15:8];       // X ���ֽ�
        tx_data[14] = captured_heart_x[7:0];        // X ���ֽ�
        tx_data[15] = captured_heart_y[15:8];       // Y ���ֽ�
        tx_data[16] = captured_heart_y[7:0];        // Y ���ֽ�
        tx_data[17] = crc8_computed;                // CRC-8
    end
    
    // UART������ʵ����
    uart_tx_simple #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD(921600) 
    ) u_uart (
        .clk(clk),
        .rst_n(rst_n_sync),
        .tx_start(uart_start),
        .tx_byte(uart_byte),
        .tx(uart_tx),
        .busy(uart_busy)
    );

    // ========================================================================
    // 12. UART����״̬��
    // ========================================================================
    // ���ֽڷ������ݰ�����ȷ����busy�����ź�
    
    typedef enum logic [2:0] {
        U_IDLE,         // ����: �ȴ�SEND״̬
        U_LOAD,         // ����: ׼�������ֽ�
        U_WAIT_BUSY,    // �ȴ�: UARTȷ�Ͽ�ʼ (busy���)
        U_WAIT_DONE,    // �ȴ�: UART������� (busy���)
        U_NEXT,         // ��һ��: �ƶ�����һ�ֽ�
        U_FINISH        // ���: �����ֽڷ������
    } uart_state_t;
    
    uart_state_t uart_st;

    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            uart_st    <= U_IDLE;
            uart_idx   <= 0;
            uart_start <= 0;
            uart_byte  <= 8'h00;
            send_done  <= 0;
            sending    <= 0;
        end else begin
            // Ĭ����������ź�
            uart_start <= 0;
            send_done  <= 0;
            
            case (uart_st)
                U_IDLE: begin
                    sending  <= 0;
                    uart_idx <= 0;
                    if (capt_st == SEND) begin
                        sending <= 1;
                        uart_st <= U_LOAD;
                    end
                end
                
                U_LOAD: begin
                    // ���ص�ǰ�ֽڲ���������
                    uart_byte  <= tx_data[uart_idx];
                    uart_start <= 1;
                    uart_st    <= U_WAIT_BUSY;
                end
                
                U_WAIT_BUSY: begin
                    // �ȴ�UART��ʼ����
                    if (uart_busy) begin
                        uart_st <= U_WAIT_DONE;
                    end
                end
                
                U_WAIT_DONE: begin
                    // �ȴ���ǰ�ֽڴ������
                    if (!uart_busy) begin
                        uart_st <= U_NEXT;
                    end
                end
                
                U_NEXT: begin
                    // ����Ƿ��и����ֽ�
                    if (uart_idx == PACKET_LEN - 1) begin
                        uart_st <= U_FINISH;
                    end else begin
                        uart_idx <= uart_idx + 1;
                        uart_st  <= U_LOAD;
                    end
                end
                
                U_FINISH: begin
                    send_done <= 1;
                    sending   <= 0;
                    uart_st   <= U_IDLE;
                end
                
                default: uart_st <= U_IDLE;
            endcase
            
            // �쳣�ָ�: �������״̬���뿪SEND״̬
            if (capt_st != SEND && uart_st != U_IDLE && uart_st != U_FINISH) begin
                uart_st <= U_IDLE;
            end
        end
    end

    // ========================================================================
    // 13. ILA�߼�������
    // ========================================================================
    // �������ߵ��ԣ��۲�ؼ��ڲ��ź�
    // ̽������:
    //   probe0-1:   RAM�ź�
    //   probe2:     SSB���
    //   probe3-7:   TDOAͨ����������
    //   probe8-9:   ��������UART
    //   probe12-16: Ƶ�ʲ������
    
    ila_0 U_ILA (                             
        .clk   (clk),                             
        .probe0(ram_rd_addr),       // [11:0] RAM����ַ
        .probe1(ram_dout),          // [15:0] RAM��� (ԭʼ����)
        .probe2(y_ssb_q15),         // [15:0] SSB�������
        .probe3(tdoa_ch0),          // [15:0] TDOAͨ��0
        .probe4(tdoa_ch1),          // [15:0] TDOAͨ��1
        .probe5(tdoa_ch2),          // [15:0] TDOAͨ��2
        .probe6(tdoa_ch3),          // [15:0] TDOAͨ��3
        .probe7({p3, p2, p1, p0}),  // [3:0]  �������־
        .probe8(spo_cnt),           // [31:0] TDOA���ڼ���
        .probe9(uart_start),        // [0:0]  UART���ʹ���
        .probe10(1'b0),             // [0:0]  ����
        .probe11(uart_tx),          // [0:0]  UART���
        .probe12(fcw_reg),          // [31:0] DDSƵ�ʿ�����
        .probe13(fill_cnt_m),       // [9:0]  FIFO������
        .probe14(freq_input_hz),    // [31:0] �����ź�Ƶ�� (Hz)
        .probe15(freq_ssb_hz),      // [31:0] SSB���Ƶ�� (Hz)
        .probe16(delay_time_ns)     // [31:0] ����ʱ (ns)
    );                                          

endmodule
