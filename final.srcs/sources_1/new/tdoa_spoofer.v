`timescale 1ns / 1ps
// ============================================================================
// ģ������: tdoa_spoofer
// ��    ��: TDOAλ����ƭ�źŷ����� - ����״Ŀ��켣������ (��ǿ��)
// 
// ���ļܹ��ص�:
// 1. ������Ԥ����: �ڵ�ǰ�����ڼ�����һ�������ʱ
// 2. ˫����Ĵ���: delay_active(������������), delay_next(��ˮ�����)
// 3. �޾�������: delay_active�����ڱ߽����棬���������ڱ����ȶ�
// 4. ��Դ�Ż�: �Ƴ�40������飬��ʹ��8���Ĵ���
// 5. ����״֧��: ���Ρ����Ρ�Բ�Ρ�õ���ߡ��������
//
// ����ԭ��:
//   ����VIO�趨����״����������Ŀ����2Dƽ���ϵ��˶��켣���꣬
//   ����Ŀ�굽4�����ߵľ��룬ת��Ϊ������ʱ��������������
//   ����Ӧ��ʱλ�����������źţ�ģ��TDOA��λϵͳ���յ����źš�
//
// ============================================================================

module tdoa_spoofer #(
    parameter int  W        = 16,           // ����ź�λ��
    parameter real FS_HZ    = 100e6,        // ����Ƶ�� (100MHz)
    parameter real C        = 3e8,          // ���� (m/s)
    
    // 4������λ������ (��λ: ��)
    // ���߲��ó�200m��200m������������
    parameter real ANT1_X = 0.0,    parameter real ANT1_Y = 0.0,      // ����1: ���½�
    parameter real ANT2_X = 200.0,  parameter real ANT2_Y = 0.0,      // ����2: ���½�
    parameter real ANT3_X = 0.0,    parameter real ANT3_Y = 200.0,    // ����3: ���Ͻ�
    parameter real ANT4_X = 200.0,  parameter real ANT4_Y = 200.0,    // ����4: ���Ͻ�
    
    parameter int  NUM_HEART_POINTS = 40,   // �켣���� (ÿ����״40��������)
    parameter int  PULSE_WIDTH_SAMPLES = 5  // ������� (��������)
)(
    input  logic               clk,          // ϵͳʱ�� (100MHz)
    input  logic               rst_n,        // �첽��λ (����Ч)
    
    // VIO ʵʱ��������
    input  wire signed [31:0]  vio_center_x,  // Ŀ������X���� (��λ: ��)
    input  wire signed [31:0]  vio_center_y,  // Ŀ������Y���� (��λ: ��)
    input  wire [31:0]         vio_scale,     // ��״����ϵ�� (1000 = 1000��)
    input  wire [2:0]          vio_shape_sel, // ��״ѡ��: 0=����, 1=����, 2=Բ��, 3=õ��, 4=����
    
    // 4ͨ���������
    output logic signed [W-1:0] ch0_out,      // ͨ��0������� (��Ӧ����1)
    output logic signed [W-1:0] ch1_out,      // ͨ��1������� (��Ӧ����2)
    output logic signed [W-1:0] ch2_out,      // ͨ��2������� (��Ӧ����3)
    output logic signed [W-1:0] ch3_out,      // ͨ��3������� (��Ӧ����4)
    
    // �������
    output logic [31:0]         cnt_out,      // ���ڼ�����
    output logic [15:0]         delay_ant0_out, // ����0��ʱֵ (������)
    output logic [5:0]          v_idx_out,    // ��ǰ�켣������
    output logic signed [15:0]  heart_x_out,  // ��ǰ�켣X���� (������)
    output logic signed [15:0]  heart_y_out   // ��ǰ�켣Y���� (������)
);

    // ========================================================================
    // 1. ��״�������궨�� (Ӳ���� - �ۺϼ���)
    // ========================================================================
    // ��������ֵ����Q6�����ʽ (ʵ��ֵ����64)
    // X/Y���귶Χ: Լ -1024 �� +1024
    
    // ------------------------------------------------------------------------
    // �������� X���� (Q6��ʽ, 40����)
    // ���β�������: x = 16*sin?(t), y = 13*cos(t) - 5*cos(2t) - 2*cos(3t) - cos(4t)
    // ------------------------------------------------------------------------
    localparam int signed HEART_X [0:39] = '{
           0,     4,    30,    96,   208,   362,   543,   724,
         881,   986,  1024,   986,   881,   724,   543,   362,
         208,    96,    30,     4,     0,    -4,   -30,   -96,
        -208,  -362,  -543,  -724,  -881,  -986, -1024,  -986,
        -881,  -724,  -543,  -362,  -208,   -96,   -30,    -4
    };
    
    // �������� Y���� (Q6��ʽ)
    localparam int signed HEART_Y [0:39] = '{
         320,   352,   437,   549,   655,   725,   737,   685,
         480,   280,    80,  -100,  -240,  -350,  -420,  -460,
        -490,  -540,  -620,  -720,  -780,  -720,  -620,  -540,
        -490,  -460,  -420,  -350,  -240,  -100,    80,   280,
         480,   685,   737,   725,   655,   549,   437,   352
    };

    // ------------------------------------------------------------------------
    // �������״ (Q6��ʽ, 40����)
    // ��5���ⶥ���5���ڰ��㽻�������γ�
    // ------------------------------------------------------------------------
    localparam int signed STAR_X [0:39] = '{
           0,    58,   115,   173,
         230,   416,   602,   788,
         974,   823,   673,   522,
         372,   430,   487,   545,
         602,   451,   301,   150,
           0,  -150,  -301,  -451,
        -602,  -545,  -487,  -430,
        -372,  -522,  -673,  -823,
        -974,  -788,  -602,  -416,
        -230,  -173,  -115,   -58
    };
    
    localparam int signed STAR_Y [0:39] = '{
        1024,   847,   670,   493,
         316,   316,   316,   316,
         316,   207,    98,   -12,
        -121,  -298,  -475,  -651,
        -828,  -719,  -609,  -500,
        -391,  -500,  -609,  -719,
        -828,  -651,  -475,  -298,
        -121,   -12,    98,   207,
         316,   316,   316,   316,
         316,   493,   670,   847
    };

    // ------------------------------------------------------------------------
    // Բ�ι켣 (Q6��ʽ, 40����, �뾶 = 1024)
    // ��������: x = r*cos(t), y = r*sin(t)
    // ------------------------------------------------------------------------
    localparam int signed CIRCLE_X [0:39] = '{
        1024, 1011,  973,  911,  828,  724,  602,  464,
         316,  160,    0, -160, -316, -464, -602, -724,
        -828, -911, -973,-1011,-1024,-1011, -973, -911,
        -828, -724, -602, -464, -316, -160,    0,  160,
         316,  464,  602,  724,  828,  911,  973, 1011
    };
    
    localparam int signed CIRCLE_Y [0:39] = '{
           0,  160,  316,  464,  602,  724,  828,  911,
         973, 1011, 1024, 1011,  973,  911,  828,  724,
         602,  464,  316,  160,    0, -160, -316, -464,
        -602, -724, -828, -911, -973,-1011,-1024,-1011,
        -973, -911, -828, -724, -602, -464, -316, -160
    };

    // ------------------------------------------------------------------------
    // õ���� (5�껨��, Q6��ʽ, 40����)
    // �����귽��: r = cos(5��)
    // ------------------------------------------------------------------------
    localparam int signed ROSE_X [0:39] = '{
        1024,  864,  487,  134,    0,  106,  301,  397,
         316,  137,    0,  -23,    0,  -68, -301, -619,
        -828, -780, -487, -148,    0, -148, -487, -780,
        -828, -619, -301,  -68,    0,  -23,    0,  137,
         316,  397,  301,  106,    0,  134,  487,  864
    };
    
    localparam int signed ROSE_Y [0:39] = '{
           0,  137,  158,   68,    0,  106,  414,  780,
         974,  864,  512,  148,    0,  134,  414,  619,
         602,  397,  158,   23,    0,  -23, -158, -397,
        -602, -619, -414, -134,    0, -148, -512, -864,
        -974, -780, -414, -106,    0,  -68, -158, -137
    };

    // ------------------------------------------------------------------------
    // ������� (������8����, Q6��ʽ, 40����)
    // ��������: x = sin(t), y = sin(2t)/2
    // ------------------------------------------------------------------------
    localparam int signed INF_X [0:39] = '{
           0,  160,  316,  465,  602,  724,  828,  913,
         974, 1012, 1024, 1012,  974,  913,  828,  724,
         602,  465,  316,  160,    0, -160, -316, -465,
        -602, -724, -828, -913, -974,-1012,-1024,-1012,
        -974, -913, -828, -724, -602, -465, -316, -160
    };
    
    localparam int signed INF_Y [0:39] = '{
           0,  158,  301,  414,  487,  512,  487,  414,
         301,  158,    0, -158, -301, -414, -487, -512,
        -487, -414, -301, -158,    0,  158,  301,  414,
         487,  512,  487,  414,  301,  158,    0, -158,
        -301, -414, -487, -512, -487, -414, -301, -158
    };

    // ------------------------------------------------------------------------
    // ����λ�ó������� (ת��Ϊ����)
    // ------------------------------------------------------------------------
    localparam signed [31:0] ANT_X [0:3] = '{
        int'(ANT1_X), int'(ANT2_X), int'(ANT3_X), int'(ANT4_X)
    };
    localparam signed [31:0] ANT_Y [0:3] = '{
        int'(ANT1_Y), int'(ANT2_Y), int'(ANT3_Y), int'(ANT4_Y)
    };

    // ========================================================================
    // 2. ������������������
    // ========================================================================
    
    // ���ڳ���: 50000��ʱ������ = 500��s @ 100MHz
    // ÿ���켣�����500��s��40���� = 20ms���һȦ
    localparam int CYCLE_LENGTH = 50000;
    
    // ��ˮ�����: �������(4��) + �������(5��) + ����(17��) + ��ʱת��(2��) = 28��
    localparam int PIPELINE_DEPTH = 28;
    
    // �����ʱֵ (��ֹ����Խ��)
    localparam int MAX_DELAY = CYCLE_LENGTH - PULSE_WIDTH_SAMPLES - 1;
    
    // ���ڼ����� (0 ~ CYCLE_LENGTH-1)
    logic [$clog2(CYCLE_LENGTH)-1:0] cnt;
    
    // ��ǰ����Ĺ켣������ (0 ~ 39)
    logic [$clog2(NUM_HEART_POINTS)-1:0] v_idx;
    
    // ��ˮ�������ڼ���Ĺ켣������ (��ǰv_idxһ������)
    logic [$clog2(NUM_HEART_POINTS)-1:0] calc_idx;
    
    // ========================================================================
    // 3. ˫����ܹ� - ������������Ĺؼ�
    // ========================================================================
    // delay_active: ��ǰ����ʹ�õ���ʱֵ (�ȶ���������������)
    // delay_next:   ��ˮ���������һ��������ʱֵ (�����ڱ仯)
    
    logic [31:0] delay_active [0:3];  // ��Ծ��ʱ�Ĵ��� (4������)
    logic [31:0] delay_next [0:3];    // ��һ������ʱ�Ĵ���
    
    // ��ʼ�� (������)
    initial begin
        for (int i = 0; i < 4; i++) begin
            delay_active[i] = 4000;   // Ĭ����ʱ4000��������
        end
    end
    
    // ========================================================================
    // 4. ��������޷� (����߼�)
    // ========================================================================
    // ��ֹVIO���õĲ�������������Χ
    
    logic [31:0] scale_limited;                // �޷��������ϵ��
    logic signed [32:0] scale_signed;          // �з�����չ������ϵ��
    logic signed [31:0] center_x_limited;      // �޷��������X����
    logic signed [31:0] center_y_limited;      // �޷��������Y����
    
    always_comb begin
        // ����ϵ������: 100 ~ 5000
        if (vio_scale < 100)
            scale_limited = 100;
        else if (vio_scale > 5000)
            scale_limited = 5000;
        else
            scale_limited = vio_scale;
        
        // ת��Ϊ�з�������֧�ֺ����˷�
        scale_signed = $signed({1'b0, scale_limited});
        
        // ������������: -50000m ~ +50000m
        if (vio_center_x > 50000)
            center_x_limited = 50000;
        else if (vio_center_x < -50000)
            center_x_limited = -50000;
        else
            center_x_limited = vio_center_x;
            
        if (vio_center_y > 50000)
            center_y_limited = 50000;
        else if (vio_center_y < -50000)
            center_y_limited = -50000;
        else
            center_y_limited = vio_center_y;
    end

    // ========================================================================
    // 5. ��״���������ˮ�� (4��)
    // ========================================================================
    
    // ��״ѡ���·������ (����߼�)
    logic signed [15:0] selected_shape_x, selected_shape_y;
    
    always_comb begin
        case (vio_shape_sel)
            3'd0: begin  // ����
                selected_shape_x = HEART_X[calc_idx];
                selected_shape_y = HEART_Y[calc_idx];
            end
            3'd1: begin  // ����
                selected_shape_x = STAR_X[calc_idx];
                selected_shape_y = STAR_Y[calc_idx];
            end
            3'd2: begin  // Բ��
                selected_shape_x = CIRCLE_X[calc_idx];
                selected_shape_y = CIRCLE_Y[calc_idx];
            end
            3'd3: begin  // õ����
                selected_shape_x = ROSE_X[calc_idx];
                selected_shape_y = ROSE_Y[calc_idx];
            end
            3'd4: begin  // �������
                selected_shape_x = INF_X[calc_idx];
                selected_shape_y = INF_Y[calc_idx];
            end
            default: begin  // Ĭ������
                selected_shape_x = HEART_X[calc_idx];
                selected_shape_y = HEART_Y[calc_idx];
            end
        endcase
    end
    
    // H1��: ��ȡ��״ROM
    logic signed [15:0] raw_heart_x, raw_heart_y;
    
    always_ff @(posedge clk) begin
        raw_heart_x <= selected_shape_x;
        raw_heart_y <= selected_shape_y;
    end
    
    // H2��: ��������ϵ��
    logic signed [47:0] scaled_x_temp, scaled_y_temp;
    
    always_ff @(posedge clk) begin
        scaled_x_temp <= raw_heart_x * scale_signed;
        scaled_y_temp <= raw_heart_y * scale_signed;
    end
    
    // H3��: ����10λ (����1024����Q6��ʽת��Ϊʵ������)
    logic signed [31:0] heart_x_scaled, heart_y_scaled;
    
    always_ff @(posedge clk) begin
        heart_x_scaled <= scaled_x_temp >>> 10;
        heart_y_scaled <= scaled_y_temp >>> 10;
    end
    
    // H4��: ��������ƫ�ƣ��õ�����Ŀ������
    logic signed [31:0] point_x, point_y;
    
    always_ff @(posedge clk) begin
        point_x <= center_x_limited + heart_x_scaled;
        point_y <= center_y_limited + heart_y_scaled;
    end
    
    // ========================================================================
    // 6. ���������ˮ�� (5��)
    // ========================================================================
    // ����Ŀ��㵽4�����ߵ�ŷ�Ͼ���: d = sqrt(dx? + dy?)
    
    // D1��: ��ʱ�Ĵ��� (����ʱ��)
    logic signed [31:0] point_x_d, point_y_d;
    
    always_ff @(posedge clk) begin
        point_x_d <= point_x;
        point_y_d <= point_y;
    end
    
    // D2��: ���㵽�����ߵĲ�ֵ
    logic signed [31:0] dx [0:3];
    logic signed [31:0] dy [0:3];
    
    always_ff @(posedge clk) begin
        dx[0] <= point_x_d - ANT_X[0];  dy[0] <= point_y_d - ANT_Y[0];
        dx[1] <= point_x_d - ANT_X[1];  dy[1] <= point_y_d - ANT_Y[1];
        dx[2] <= point_x_d - ANT_X[2];  dy[2] <= point_y_d - ANT_Y[2];
        dx[3] <= point_x_d - ANT_X[3];  dy[3] <= point_y_d - ANT_Y[3];
    end
    
    // D3��: ȡ����ֵ (Ϊƽ������׼���޷�����)
    logic [31:0] abs_dx [0:3];
    logic [31:0] abs_dy [0:3];
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            abs_dx[i] <= (dx[i] < 0) ? (-dx[i]) : dx[i];
            abs_dy[i] <= (dy[i] < 0) ? (-dy[i]) : dy[i];
        end
    end

    // D4��: ����ƽ��
    logic [63:0] dx_sq [0:3];
    logic [63:0] dy_sq [0:3];
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            dx_sq[i] <= abs_dx[i] * abs_dx[i];
            dy_sq[i] <= abs_dy[i] * abs_dy[i];
        end
    end
    
    // D5��: ��ƽ����
    logic [63:0] sum_sq [0:3];
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sum_sq[i] <= dx_sq[i] + dy_sq[i];
        end
    end

    // ========================================================================
    // 16����ˮ������������ (��λ�ȽϷ�)
    // ========================================================================
    // �㷨: �����λ��ʼ����λ��̽ȷ�������ÿһλ
    // ÿ������2λ���룬��16������32λ���룬����16λ���
    
    // ��ˮ�߼Ĵ������� (����r, ��q, ��������s)
    logic [33:0] sqrt_r_0 [0:3], sqrt_r_1 [0:3], sqrt_r_2 [0:3], sqrt_r_3 [0:3];
    logic [33:0] sqrt_r_4 [0:3], sqrt_r_5 [0:3], sqrt_r_6 [0:3], sqrt_r_7 [0:3];
    logic [33:0] sqrt_r_8 [0:3], sqrt_r_9 [0:3], sqrt_r_10[0:3], sqrt_r_11[0:3];
    logic [33:0] sqrt_r_12[0:3], sqrt_r_13[0:3], sqrt_r_14[0:3], sqrt_r_15[0:3];
    logic [33:0] sqrt_r_16[0:3];
    
    logic [15:0] sqrt_q_0 [0:3], sqrt_q_1 [0:3], sqrt_q_2 [0:3], sqrt_q_3 [0:3];
    logic [15:0] sqrt_q_4 [0:3], sqrt_q_5 [0:3], sqrt_q_6 [0:3], sqrt_q_7 [0:3];
    logic [15:0] sqrt_q_8 [0:3], sqrt_q_9 [0:3], sqrt_q_10[0:3], sqrt_q_11[0:3];
    logic [15:0] sqrt_q_12[0:3], sqrt_q_13[0:3], sqrt_q_14[0:3], sqrt_q_15[0:3];
    logic [15:0] sqrt_q_16[0:3];
    
    logic [31:0] sqrt_s_0 [0:3], sqrt_s_1 [0:3], sqrt_s_2 [0:3], sqrt_s_3 [0:3];
    logic [31:0] sqrt_s_4 [0:3], sqrt_s_5 [0:3], sqrt_s_6 [0:3], sqrt_s_7 [0:3];
    logic [31:0] sqrt_s_8 [0:3], sqrt_s_9 [0:3], sqrt_s_10[0:3], sqrt_s_11[0:3];
    logic [31:0] sqrt_s_12[0:3], sqrt_s_13[0:3], sqrt_s_14[0:3], sqrt_s_15[0:3];
    logic [31:0] sqrt_s_16[0:3];
    
    // ����������������
    function automatic void sqrt_stage(
        input  logic [33:0] r_in,      // ��������
        input  logic [15:0] q_in,      // ������
        input  logic [31:0] s_in,      // ��������
        input  int          bit_pos,   // ��ǰ������λλ��
        output logic [33:0] r_out,     // �������
        output logic [15:0] q_out,     // �����
        output logic [31:0] s_out      // ����������� (����)
    );
        logic [1:0]  next_bits;        // ��һ��2λ
        logic [33:0] r_shifted;        // ���ƺ������
        logic [33:0] trial;            // ��ֵ̽
        
        // �ӱ���������ȡ����һ��2λ
        if (bit_pos >= 0)
            next_bits = s_in[bit_pos+1 -: 2];
        else
            next_bits = 2'b00;
        
        // ��������2λ�������µ�2λ
        r_shifted = (r_in << 2) | {32'd0, next_bits};
        
        // ������ֵ̽: trial = q * 4 + 1 = {q, 01}
        trial = {q_in, 2'b01};
        
        // �Ƚϲ�������ǰλ
        if (r_shifted >= trial) begin
            r_out = r_shifted - trial;
            q_out = {q_in[14:0], 1'b1};  // ��ǰλΪ1
        end else begin
            r_out = r_shifted;
            q_out = {q_in[14:0], 1'b0};  // ��ǰλΪ0
        end
        s_out = s_in;
    endfunction
    
    // S0��: ��ʼ��
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_r_0[i] <= 34'd0;
            sqrt_q_0[i] <= 16'd0;
            // �������뷶Χ��ֹ���
            sqrt_s_0[i] <= (sum_sq[i] > 64'hFFFFFFFF) ? 32'hFFFFFFFF : sum_sq[i][31:0];
        end
    end
    
    // S1-S16��: ��λ����
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_0[i], sqrt_q_0[i], sqrt_s_0[i], 30, sqrt_r_1[i], sqrt_q_1[i], sqrt_s_1[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_1[i], sqrt_q_1[i], sqrt_s_1[i], 28, sqrt_r_2[i], sqrt_q_2[i], sqrt_s_2[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_2[i], sqrt_q_2[i], sqrt_s_2[i], 26, sqrt_r_3[i], sqrt_q_3[i], sqrt_s_3[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_3[i], sqrt_q_3[i], sqrt_s_3[i], 24, sqrt_r_4[i], sqrt_q_4[i], sqrt_s_4[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_4[i], sqrt_q_4[i], sqrt_s_4[i], 22, sqrt_r_5[i], sqrt_q_5[i], sqrt_s_5[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_5[i], sqrt_q_5[i], sqrt_s_5[i], 20, sqrt_r_6[i], sqrt_q_6[i], sqrt_s_6[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_6[i], sqrt_q_6[i], sqrt_s_6[i], 18, sqrt_r_7[i], sqrt_q_7[i], sqrt_s_7[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_7[i], sqrt_q_7[i], sqrt_s_7[i], 16, sqrt_r_8[i], sqrt_q_8[i], sqrt_s_8[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_8[i], sqrt_q_8[i], sqrt_s_8[i], 14, sqrt_r_9[i], sqrt_q_9[i], sqrt_s_9[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_9[i], sqrt_q_9[i], sqrt_s_9[i], 12, sqrt_r_10[i], sqrt_q_10[i], sqrt_s_10[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_10[i], sqrt_q_10[i], sqrt_s_10[i], 10, sqrt_r_11[i], sqrt_q_11[i], sqrt_s_11[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_11[i], sqrt_q_11[i], sqrt_s_11[i], 8, sqrt_r_12[i], sqrt_q_12[i], sqrt_s_12[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_12[i], sqrt_q_12[i], sqrt_s_12[i], 6, sqrt_r_13[i], sqrt_q_13[i], sqrt_s_13[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_13[i], sqrt_q_13[i], sqrt_s_13[i], 4, sqrt_r_14[i], sqrt_q_14[i], sqrt_s_14[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_14[i], sqrt_q_14[i], sqrt_s_14[i], 2, sqrt_r_15[i], sqrt_q_15[i], sqrt_s_15[i]);
        end
    end
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            sqrt_stage(sqrt_r_15[i], sqrt_q_15[i], sqrt_s_15[i], 0, sqrt_r_16[i], sqrt_q_16[i], sqrt_s_16[i]);
        end
    end
    
    // ������� (�������)
    logic [31:0] distance [0:3];
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            distance[i] <= {16'b0, sqrt_q_16[i]};  // 16λ�����չ��32λ
        end
    end
    
    // ========================================================================
    // ����ת��ʱ����
    // ========================================================================
    // ��ʱ(������) = ����(m) / ����(m/s) �� ������(Hz)
    // = ���� / (3e8) �� 100e6 = ���� / 3 �� ���� �� 85 / 256
    // ʹ�� ��85 >> 8 ����ʵ�ֳ���3
    
    always_ff @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            delay_next[i] <= (distance[i] * 85) >> 8;
        end
    end

    // ========================================================================
    // 7. ���������ͻ��彻���߼�
    // ========================================================================
    
    logic pipeline_valid;          // ��ˮ�������Ч��־
    logic [5:0] startup_cnt;       // ���������� (�ȴ���ˮ������)
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= '0;
            v_idx <= '0;
            calc_idx <= 1;         // ����������ǰ�������1��λ��
            startup_cnt <= '0;
            pipeline_valid <= 1'b0;
            
            // ��λʱ����Ĭ����ʱ
            for (int i = 0; i < 4; i++) begin
                delay_active[i] <= 32'd4000;
            end
        end else begin
            // �����׶�: �ȴ���ˮ������
            if (startup_cnt < PIPELINE_DEPTH + 2) begin
                startup_cnt <= startup_cnt + 1'b1;
            end else begin
                pipeline_valid <= 1'b1;
            end
            
            // ���ڼ���������
            if (cnt >= CYCLE_LENGTH - 1) begin
                cnt <= '0;
                
                // ���ڽ���ʱ��������: ��Ԥ�������ʱ���ص���Ծ�Ĵ���
                if (pipeline_valid) begin
                    for (int i = 0; i < 4; i++) begin
                        // ��ʱֵ�޷�����
                        if (delay_next[i] > MAX_DELAY)
                            delay_active[i] <= MAX_DELAY;
                        else if (delay_next[i] < 1)
                            delay_active[i] <= 1;
                        else
                            delay_active[i] <= delay_next[i];
                    end
                end
                
                // ���¹켣������
                if (v_idx == NUM_HEART_POINTS - 1) begin
                    v_idx <= '0;
                    calc_idx <= 1;
                end else begin
                    v_idx <= v_idx + 1'b1;
                    if (calc_idx == NUM_HEART_POINTS - 1)
                        calc_idx <= '0;
                    else
                        calc_idx <= calc_idx + 1'b1;
                end
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
    
    // ========================================================================
    // 8. ���������ֵ
    // ========================================================================
    
    assign cnt_out = 32'(cnt);
    assign delay_ant0_out = delay_active[0][15:0];
    assign v_idx_out = v_idx;
    assign heart_x_out = raw_heart_x;
    assign heart_y_out = raw_heart_y;

    // ========================================================================
    // 9. ���������߼�
    // ========================================================================
    // �������������Ӧ���ߵ���ʱֵʱ�����ɹ̶����ȵ�����

    localparam signed [W-1:0] PULSE_AMP = 16'sd8000;  // �������

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch0_out <= '0; ch1_out <= '0; ch2_out <= '0; ch3_out <= '0;
        end else begin
            // ͨ��0: �� [delay_active[0], delay_active[0]+PULSE_WIDTH) ��Χ���������
            ch0_out <= (cnt >= delay_active[0] && cnt < delay_active[0] + PULSE_WIDTH_SAMPLES) ? PULSE_AMP : '0;
            ch1_out <= (cnt >= delay_active[1] && cnt < delay_active[1] + PULSE_WIDTH_SAMPLES) ? PULSE_AMP : '0;
            ch2_out <= (cnt >= delay_active[2] && cnt < delay_active[2] + PULSE_WIDTH_SAMPLES) ? PULSE_AMP : '0;
            ch3_out <= (cnt >= delay_active[3] && cnt < delay_active[3] + PULSE_WIDTH_SAMPLES) ? PULSE_AMP : '0;
        end
    end

endmodule
