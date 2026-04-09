function tdoa_receiver_cn2(port, varargin)
% TDOA欺骗信号接收和成像 (调试版 - 包含心形索引)
%
% 帧格式 (18 bytes):
%   [0x55][0xAA][SEQ][T0(2)][DT10(2)][DT20(2)][DT30(2)][SHAPE][V_IDX][X(2)][Y(2)][CRC8]
%   SHAPE: 0=Heart, 1=Star, 2=Circle
%   V_IDX: 点索引 (0-39)
%   X/Y: 形状点坐标 (Q6格式, 实际值 = X/64, Y/64)
%
% 用法示例: 
%   tdoa_receiver_cn('COM9')                    % 正常模式
%   tdoa_receiver_cn('COM9', 'debug', true)     % 调试模式
%   tdoa_receiver_cn('COM9', 'frames', 200)     % 采集200帧
%   tdoa_receiver_cn('COM9', 'raw', true)       % 只打印原始数据，不绘图
%   tdoa_receiver_cn('COM9', 'print_every', 5)  % 每5帧打印一次（减少刷屏）

    if nargin < 1
        fprintf('用法: tdoa_receiver_cn(''COMx'')\n');
        fprintf('选项:\n');
        fprintf('  ''debug'', true/false  - 启用调试输出\n');
        fprintf('  ''frames'', N          - 采集N帧数据\n');
        fprintf('  ''raw'', true/false    - 只打印原始数据\n');
        fprintf('  ''print_every'', N     - 每N帧打印一次(默认1)\n');
        return;
    end
    
    % 解析可选参数
    p = inputParser;
    addParameter(p, 'debug', false);
    addParameter(p, 'frames', 120);
    addParameter(p, 'raw', false);
    addParameter(p, 'print_every', 1);
    parse(p, varargin{:});
    
    debugMode = p.Results.debug;
    nFramesTarget = p.Results.frames;
    rawMode = p.Results.raw;
    printEvery = max(1, floor(p.Results.print_every));

    %================= 物理和阵列参数 =================
    fs = 100e6;       % 100MHz 采样率 (与FPGA一致)
    c  = 3e8;         % 光速
    
    % 4 天线阵列位置 (与FPGA参数 ANT2_X=200 等一致)
    ant1 = [0,   0  ];
    ant2 = [200, 0  ];
    ant3 = [0,   200];
    ant4 = [200, 200];
    
    d_x = norm(ant2 - ant1);  % 200m
    d_y = norm(ant3 - ant1);  % 200m

    %================= 串口参数 =================
    baudrate      = 921600;
    totalTimeout  = 60;
    frameTimeout  = 1.0;  

    %================= 打开串口 =================
    try
        fprintf('正在打开串口 %s ...\n', port);
        sp = serialport(port, baudrate); 
        flush(sp);                       
        fprintf('已连接! 正在监听数据...\n');
        fprintf('帧格式: [0x55][0xAA][SEQ][T0(2)][DT10(2)][DT20(2)][DT30(2)][SHAPE][V_IDX][X(2)][Y(2)][CRC8] = 18 bytes\n');
    catch ME
        fprintf('串口打开失败: %s\n', ME.message);
        return;
    end

    %================= 初始化统计变量 =================
    stats = struct();
    stats.total_frames = 0;
    stats.valid_frames = 0;
    stats.invalid_frames = 0;
    stats.crc_errors = 0;
    stats.sync_errors = 0;
    stats.dropped_frames = 0;
    stats.last_seq = -1;  % 上一帧序号 (-1表示未知)
    stats.dt10_values = [];
    stats.dt20_values = [];
    stats.v_idx_values = [];   % DEBUG: heart point indices
    stats.heart_x_values = []; % DEBUG: heart X values
    stats.heart_y_values = []; % DEBUG: heart Y values
    stats.shape_values = [];   % DEBUG: shape id values
    stats.t0_values = [];
    
    %================= 收集数据 =================
    detections = struct([]);           
    tStartAll = tic;
    
    fprintf('正在采集数据 (目标: %d 帧)...\n', nFramesTarget);
    if debugMode
        fprintf('========================================\n');
        fprintf('         调试模式已启用\n');
        fprintf('========================================\n');
    end
    
    while numel(detections) < nFramesTarget
        if toc(tStartAll) > totalTimeout
            fprintf('\n[超时] 接收超时!\n');
            break;
        end
        
        [frame, frame_status] = receive_frame_v2(sp, frameTimeout, debugMode);
        
        % 更新错误统计
        if frame_status.crc_error
            stats.crc_errors = stats.crc_errors + 1;
        end
        if frame_status.sync_error
            stats.sync_errors = stats.sync_errors + 1;
        end
        
        if ~isempty(frame)
            stats.total_frames = stats.total_frames + 1;
            
            % 检查序号连续性（检测丢帧）
            if stats.last_seq >= 0
                expected_seq = mod(stats.last_seq + 1, 256);
                if frame.seq ~= expected_seq
                    % 计算丢失的帧数
                    if frame.seq > stats.last_seq
                        dropped = frame.seq - stats.last_seq - 1;
                    else
                        dropped = (256 - stats.last_seq - 1) + frame.seq;
                    end
                    stats.dropped_frames = stats.dropped_frames + dropped;
                    if debugMode
                        fprintf('  [丢帧警告] 期望seq=%d, 收到seq=%d, 丢失%d帧\n', ...
                            expected_seq, frame.seq, dropped);
                    end
                end
            end
            stats.last_seq = frame.seq;
            
            % 记录原始数据用于统计
            stats.t0_values = [stats.t0_values, frame.t0_mod];
            stats.dt10_values = [stats.dt10_values, frame.dt10];
            stats.dt20_values = [stats.dt20_values, frame.dt20];
            stats.v_idx_values = [stats.v_idx_values, frame.v_idx];
            stats.heart_x_values = [stats.heart_x_values, frame.heart_x];
            stats.heart_y_values = [stats.heart_y_values, frame.heart_y];
            stats.shape_values   = [stats.shape_values, frame.shape];
            
            % 打印帧信息
            if mod(stats.total_frames - 1, printEvery) == 0
                if debugMode || rawMode
                    print_debug_frame(stats.total_frames, frame, fs, c);
                else
                    print_frame_compact(stats.total_frames, frame, fs, c);
                end
            end
            
            if ~rawMode
                det = process_detection(frame, fs, c, d_x, d_y, debugMode);
                if ~isempty(det)
                    detections = [detections, det]; %#ok<AGROW>
                    stats.valid_frames = stats.valid_frames + 1;
                else
                    stats.invalid_frames = stats.invalid_frames + 1;
                end
            end
            
            % 进度显示
            if mod(stats.total_frames, 10) == 0 && ~debugMode && ~rawMode
                fprintf('捕获进度 [%d/%d] (有效:%d, CRC错:%d, 丢帧:%d)\n', ...
                    numel(detections), nFramesTarget, stats.valid_frames, ...
                    stats.crc_errors, stats.dropped_frames);
            end
        end
    end
    
    %================= 打印统计信息 =================
    fprintf('\n========================================\n');
    fprintf('           数据采集完成\n');
    fprintf('========================================\n');
    print_statistics(stats, fs, c);
    
    clear sp;

    %================= 绘图 =================
    if ~rawMode && ~isempty(detections)
        fprintf('\n正在生成态势图...\n');
        plot_results_cn(detections, stats, ant1, ant2, ant3, ant4);
    elseif rawMode
        fprintf('\n[原始模式] 已跳过绘图\n');
    else
        fprintf('\n[错误] 未收到有效数据，无法绘图。\n');
    end
end

% =========================================================
% CRC-8 计算 (多项式 0x07, 初始值 0x00)
% =========================================================
function crc = crc8(data)
    crc = uint8(0);
    poly = uint8(hex2dec('07'));
    
    for i = 1:length(data)
        crc = bitxor(crc, uint8(data(i)));
        for bit = 1:8
            if bitand(crc, uint8(128)) > 0
                crc = bitxor(bitshift(crc, 1), poly);
            else
                crc = bitshift(crc, 1);
            end
        end
    end
end

% =========================================================
% 接收一帧数据 (新协议: 0x55AA同步 + CRC8校验)
% =========================================================
function [frame, status] = receive_frame_v2(sp, frameTimeout, debugMode)
    frame = [];
    status.crc_error = false;
    status.sync_error = false;
    tStart = tic;
    
    % ===== 查找同步字 0x55 0xAA =====
    sync_state = 0;  % 0: 等待0x55, 1: 等待0xAA
    
    while true
        if sp.NumBytesAvailable > 0
            byte = read(sp, 1, 'uint8');
            
            switch sync_state
                case 0
                    if byte == hex2dec('55')
                        sync_state = 1;
                    end
                case 1
                    if byte == hex2dec('AA')
                        % 找到完整同步字，退出循环
                        break;
                    elseif byte == hex2dec('55')
                        % 可能是连续的0x55，保持状态1
                        sync_state = 1;
                    else
                        % 错误的同步字，重新开始
                        sync_state = 0;
                        status.sync_error = true;
                    end
            end
        else
            pause(0.001);
        end
        
        if toc(tStart) > frameTimeout
            return;
        end
    end
    
    % ===== 读取剩余16字节: [SEQ][T0(2)][DT10(2)][DT20(2)][DT30(2)][SHAPE][V_IDX][X(2)][Y(2)][CRC8] =====
    data = uint8([]);
    while numel(data) < 16
        if sp.NumBytesAvailable > 0
            nRead = min(16 - numel(data), sp.NumBytesAvailable);
            data = [data, read(sp, nRead, 'uint8')]; %#ok<AGROW>
        else
            pause(0.001);
        end
        if toc(tStart) > frameTimeout
            return;
        end
    end
    
    % ===== CRC校验 =====
    % CRC计算范围: data(1:15) 即 [SEQ, T0(2), DT10(2), DT20(2), DT30(2), SHAPE, V_IDX, X(2), Y(2)]
    received_crc = data(16);
    computed_crc = crc8(data(1:15));
    
    if received_crc ~= computed_crc
        status.crc_error = true;
        if debugMode
            fprintf('  [CRC错误] 接收=0x%02X, 计算=0x%02X\n', received_crc, computed_crc);
        end
        return;  % CRC错误，丢弃此帧
    end
    
    % ===== 解析数据 (大端序) =====
    seq     = double(data(1));
    t0_mod  = double(typecast(uint8([data(3)  data(2)]),  'uint16')); 
    dt10    = double(typecast(uint8([data(5)  data(4)]),  'int16'));
    dt20    = double(typecast(uint8([data(7)  data(6)]),  'int16'));
    dt30    = double(typecast(uint8([data(9)  data(8)]),  'int16'));
    shape   = double(data(10));
    v_idx   = double(data(11));  % point index (0-39)
    heart_x = double(typecast(uint8([data(13) data(12)]), 'int16'));  % X in Q6
    heart_y = double(typecast(uint8([data(15) data(14)]), 'int16'));  % Y in Q6
    
    frame.seq = seq;
    frame.t0_mod = t0_mod;
    frame.dt10 = dt10;
    frame.dt20 = dt20;
    frame.dt30 = dt30;
    frame.shape = shape;
    frame.v_idx = v_idx;
    frame.heart_x = heart_x;
    frame.heart_y = heart_y;
end

% =========================================================
% 打印调试帧信息
% =========================================================
function print_debug_frame(frame_num, frame, fs, c)
    fprintf('--- 帧 #%04d (seq=%d) ---\n', frame_num, frame.seq);
    fprintf('  原始值: t0=%5d, dt10=%+5d, dt20=%+5d, dt30=%+5d\n', ...
        frame.t0_mod, frame.dt10, frame.dt20, frame.dt30);
    
    % 转换为物理量
    R0 = (frame.t0_mod / fs) * c;
    r_diff1 = (frame.dt10 / fs) * c;
    r_diff2 = (frame.dt20 / fs) * c;
    r_diff3 = (frame.dt30 / fs) * c;
    
    fprintf('  距离:   R0=%.1fm, dr1=%.1fm, dr2=%.1fm, dr3=%.1fm\n', ...
        R0, r_diff1, r_diff2, r_diff3);
    
    % 检查异常
    anomalies = [];
    if frame.dt10 == -32768 || frame.dt20 == -32768 || frame.dt30 == -32768
        anomalies = [anomalies, "无效标记(-32768)"];
    end
    if abs(frame.dt10) > 200 || abs(frame.dt20) > 200
        anomalies = [anomalies, "dt值过大"];
    end
    expected_dt30 = frame.dt10 + frame.dt20;
    if abs(frame.dt30 - expected_dt30) > 30
        anomalies = [anomalies, sprintf("dt30异常(期望%d)", expected_dt30)];
    end
    
    if ~isempty(anomalies)
        fprintf('  [警告] %s\n', strjoin(anomalies, ', '));
    end
end

% =========================================================
% 正常模式：单行简洁打印
% =========================================================
function print_frame_compact(frame_num, frame, fs, c)
    R0 = (frame.t0_mod / fs) * c;
    r1 = (frame.dt10 / fs) * c;
    r2 = (frame.dt20 / fs) * c;
    shape_name = shape_to_name(frame.shape);
    x_actual = frame.heart_x / 64;
    y_actual = frame.heart_y / 64;
    fprintf('#%04d seq=%3d shape=%-6s t0=%5d dt10=%+5d dt20=%+5d dt30=%+5d | idx=%2d x=%+5d (%.1f) y=%+5d (%.1f) R0=%7.1fm\n', ...
        frame_num, frame.seq, shape_name, frame.t0_mod, frame.dt10, frame.dt20, frame.dt30, ...
        frame.v_idx, frame.heart_x, x_actual, frame.heart_y, y_actual, R0);
end

% =========================================================
% 形状ID -> 名称
% =========================================================
function name = shape_to_name(shape_id)
    switch shape_id
        case 0
            name = 'Heart';
        case 1
            name = 'Star';
        case 2
            name = 'Circle';
        case 3
            name = 'Rose';
        case 4
            name = 'Infty';
        otherwise
            name = sprintf('U%d', shape_id);
    end
end

% =========================================================
% 形状ID -> 中文名称 (用于绘图)
% =========================================================
function name = shape_to_name_cn(shape_id)
    switch shape_id
        case 0
            name = '爱心';
        case 1
            name = '五角星';
        case 2
            name = '圆形';
        case 3
            name = '玫瑰曲线';
        case 4
            name = '八字无穷';
        otherwise
            name = sprintf('未知(%d)', shape_id);
    end
end

% =========================================================
% 打印统计信息
% =========================================================
function print_statistics(stats, fs, c)
    fprintf('--- 通信统计 ---\n');
    fprintf('总帧数:    %d\n', stats.total_frames);
    fprintf('有效帧数:  %d (%.1f%%)\n', stats.valid_frames, ...
        100 * stats.valid_frames / max(1, stats.total_frames));
    fprintf('无效帧数:  %d\n', stats.invalid_frames);
    fprintf('CRC错误:   %d\n', stats.crc_errors);
    fprintf('同步错误:  %d\n', stats.sync_errors);
    fprintf('丢失帧数:  %d\n', stats.dropped_frames);
    
    if ~isempty(stats.dt10_values)
        fprintf('\n--- dt10 统计 ---\n');
        fprintf('  范围:  [%d, %d]\n', min(stats.dt10_values), max(stats.dt10_values));
        fprintf('  均值:  %.2f\n', mean(stats.dt10_values));
        fprintf('  标准差: %.2f\n', std(stats.dt10_values));
        
        fprintf('\n--- dt20 统计 ---\n');
        fprintf('  范围:  [%d, %d]\n', min(stats.dt20_values), max(stats.dt20_values));
        fprintf('  均值:  %.2f\n', mean(stats.dt20_values));
        fprintf('  标准差: %.2f\n', std(stats.dt20_values));
        
        fprintf('\n--- 心形索引 (v_idx) 统计 ---\n');
        fprintf('  范围:  [%d, %d]\n', min(stats.v_idx_values), max(stats.v_idx_values));
        fprintf('  唯一值数量: %d (应为40)\n', numel(unique(stats.v_idx_values)));
        
        fprintf('\n--- 心形X坐标 (heart_x) 统计 ---\n');
        fprintf('  范围:  [%d, %d] (Q6格式)\n', min(stats.heart_x_values), max(stats.heart_x_values));
        fprintf('  实际范围: [%.1f, %.1f]\n', min(stats.heart_x_values)/64, max(stats.heart_x_values)/64);
        
        fprintf('\n--- t0 (距离) 统计 ---\n');
        R_values = (stats.t0_values / fs) * c;
        fprintf('  范围:  [%.1f, %.1f] 米\n', min(R_values), max(R_values));
        fprintf('  均值:  %.1f 米\n', mean(R_values));
        fprintf('  变化幅度: %.1f 米\n', max(R_values) - min(R_values));
        
        % 检查心形是否正确
        dt10_range = max(stats.dt10_values) - min(stats.dt10_values);
        dt20_range = max(stats.dt20_values) - min(stats.dt20_values);
        
        fprintf('\n--- 心形诊断 ---\n');
        if dt10_range < 5 && dt20_range < 5
            fprintf('  [问题] dt10和dt20几乎不变化 (范围<5)\n');
            fprintf('         可能原因: 心形坐标计算错误，所有点坐标相同\n');
        elseif dt10_range < 20 || dt20_range < 20
            fprintf('  [警告] dt变化范围较小 (dt10范围=%d, dt20范围=%d)\n', dt10_range, dt20_range);
        else
            fprintf('  [正常] dt变化范围正常 (dt10范围=%d, dt20范围=%d)\n', dt10_range, dt20_range);
        end
        
        % 检查丢帧率
        if stats.dropped_frames > 0
            drop_rate = 100.0 * stats.dropped_frames / (stats.total_frames + stats.dropped_frames);
            fprintf('\n--- 通信质量 ---\n');
            fprintf('  丢帧率: %.1f%%\n', drop_rate);
            if drop_rate > 10
                fprintf('  [警告] 丢帧率较高，可能影响心形完整性\n');
            end
        end
    end
end

% =========================================================
% 处理检测数据
% =========================================================
function det = process_detection(frame, fs, c, d_x, d_y, debugMode)
    det = [];
    
    % ===== 异常值过滤 =====
    
    % 1. 跳过无效标记帧
    if frame.dt10 == -32768 || frame.dt20 == -32768
        if debugMode
            fprintf('  [过滤] 无效标记 -32768\n');
        end
        return;
    end
    
    % 2. 跳过dt值过大的帧
    %    对于200m天线间距，最大dt ~ 200/3 ~ 67 samples
    if abs(frame.dt10) > 200 || abs(frame.dt20) > 200
        if debugMode
            fprintf('  [过滤] dt值异常过大: dt10=%d, dt20=%d\n', ...
                frame.dt10, frame.dt20);
        end
        return;
    end
    
    % 3. 跳过t0_mod异常的帧
    if frame.t0_mod > 20000 || frame.t0_mod < 10
        if debugMode
            fprintf('  [过滤] t0_mod异常: %d\n', frame.t0_mod);
        end
        return;
    end
    
    % 4. 检查心形索引有效性 (DEBUG)
    if frame.v_idx > 39
        if debugMode
            fprintf('  [过滤] 心形索引无效: v_idx=%d\n', frame.v_idx);
        end
        return;
    end
    
    % ===== 精确 TDOA 定位 (球面展开公式) =====
    % 
    % 原理: 已知到三个天线的距离 r0, r1, r2，利用距离方程:
    %   r0² = x² + y²
    %   r1² = (x - d_x)² + y²
    %   r2² = x² + (y - d_y)²
    % 
    % 展开并求解得到精确的闭合形式解:
    %   x = (d_x² + r0² - r1²) / (2·d_x)
    %   y = (d_y² + r0² - r2²) / (2·d_y)
    %
    % 这比远场近似更准确，适用于任意距离!
    
    % 计算到各天线的距离 (米)
    r0 = (double(frame.t0_mod) / fs) * c;                    % 到 A0(0,0) 的距离
    r1 = r0 + (double(frame.dt10) / fs) * c;                 % 到 A1(d_x,0) 的距离
    r2 = r0 + (double(frame.dt20) / fs) * c;                 % 到 A2(0,d_y) 的距离
    
    % 精确解 (闭合形式，无需迭代)
    x_est = (d_x^2 + r0^2 - r1^2) / (2 * d_x);
    y_est = (d_y^2 + r0^2 - r2^2) / (2 * d_y);
    
    % 计算距离和方位角 (用于显示和统计)
    R_est = sqrt(x_est^2 + y_est^2);
    az_est = atan2(y_est, x_est) * 180 / pi;
    
    % 调试输出
    if debugMode
        fprintf('  精确定位: x=%.1f, y=%.1f, R=%.1f, az=%.1f deg\n', ...
            x_est, y_est, R_est, az_est);
    end
    
    % 输出结果
    det.x  = x_est;
    det.y  = y_est;
    det.R  = R_est;
    det.az = az_est;
end

% =========================================================
% 圆形平均值 (用于角度平均)
% =========================================================
function mean_angle = circular_mean(angles_deg)
    angles_rad = angles_deg * pi / 180;
    mean_sin = mean(sin(angles_rad));
    mean_cos = mean(cos(angles_rad));
    mean_angle = atan2(mean_sin, mean_cos) * 180 / pi;
end

% =========================================================
% 绘图函数 (增强版 - 带序号和方向箭头)
% =========================================================
function plot_results_cn(detections, stats, ~, ~, ~, ~)
    x_vals  = [detections.x];
    y_vals  = [detections.y];
    r_vals  = [detections.R];
    az_vals = [detections.az];
    n_points = numel(x_vals);
    
    % 获取形状名称 (根据接收到的形状ID众数)
    if ~isempty(stats.shape_values)
        shape_mode = mode(stats.shape_values);
        shape_str = shape_to_name_cn(shape_mode);
    else
        shape_str = '未知';
    end

    % 创建暗色背景窗口
    fig = figure('Position', [100 100 1600 800], 'Color', [0.1 0.1 0.15], ...
        'Name', 'TDOA 电子战欺骗效果评估终端', 'NumberTitle', 'off', 'InvertHardcopy', 'off', ...
        'DefaultAxesFontName', 'Microsoft YaHei', 'DefaultTextFontName', 'Microsoft YaHei');

    % =====================================================================
    % 左侧: 二维态势图 (带序号和箭头)
    % =====================================================================
    ax1 = axes('Parent', fig, 'Position', [0.04 0.10 0.44 0.84], ...
        'Color', [0 0.05 0.1], 'XColor', [0.6 0.7 0.8], 'YColor', [0.6 0.7 0.8], ...
        'GridColor', [0 0.3 0.4], 'GridAlpha', 0.4, 'LineWidth', 1.2, ...
        'FontName', 'Microsoft YaHei');
    hold(ax1, 'on');
    grid(ax1, 'on');
    axis(ax1, 'equal');
    
    % 绘制距离同心圆
    max_r = max(r_vals) * 1.2;
    if max_r == 0, max_r = 15000; end
    theta = linspace(0, 2*pi, 200);
    
    magnitude = 10^floor(log10(max_r));
    if magnitude == 0, magnitude = 1000; end
    step = magnitude;
    if max_r / step < 2, step = step / 2; end
    
    for r = step:step:(max_r*1.5)
        if r < max_r * 1.5
            plot(ax1, r*cos(theta), r*sin(theta), '--', 'Color', [0 0.3 0.3], 'LineWidth', 0.5);
            text(ax1, 0, r, sprintf('%.0f m', r), 'Color', [0 0.6 0.6], ...
                'FontSize', 9, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
        end
    end

    % 绘制天线阵列 (原点)
    plot(ax1, 0, 0, 'p', 'MarkerSize', 16, 'MarkerEdgeColor', 'w', ...
        'MarkerFaceColor', 'y', 'DisplayName', '雷达/侦察站');

    % ===== 绘制轨迹连线 (渐变色) =====
    % 使用颜色渐变表示时间顺序: 青色(起点) -> 品红色(终点)
    x_closed = [x_vals, x_vals(1)];
    y_closed = [y_vals, y_vals(1)];
    
    % 渐变色轨迹线
    cmap = jet(n_points);  % 彩虹渐变
    for i = 1:n_points
        next_i = mod(i, n_points) + 1;
        plot(ax1, [x_vals(i), x_vals(next_i)], [y_vals(i), y_vals(next_i)], ...
            '-', 'Color', [cmap(i,:), 0.8], 'LineWidth', 2.5, 'HandleVisibility', 'off');
    end
    
    % ===== 绘制方向箭头 =====
    % 每隔几个点画一个箭头，显示运动方向
    arrow_interval = max(1, floor(n_points / 10));  % 大约10个箭头
    arrow_scale = max([max(x_vals)-min(x_vals), max(y_vals)-min(y_vals)]) * 0.06;
    
    for i = 1:arrow_interval:n_points
        next_i = mod(i, n_points) + 1;
        dx = x_vals(next_i) - x_vals(i);
        dy = y_vals(next_i) - y_vals(i);
        len = sqrt(dx^2 + dy^2);
        if len > 0
            % 归一化并缩放箭头
            dx_norm = dx / len * arrow_scale;
            dy_norm = dy / len * arrow_scale;
            % 箭头中点
            mid_x = (x_vals(i) + x_vals(next_i)) / 2;
            mid_y = (y_vals(i) + y_vals(next_i)) / 2;
            % 绘制箭头
            quiver(ax1, mid_x - dx_norm/2, mid_y - dy_norm/2, dx_norm, dy_norm, 0, ...
                'Color', [1 1 0], 'LineWidth', 2, 'MaxHeadSize', 2, ...
                'HandleVisibility', 'off');
        end
    end
    
    % ===== 绘制采样点 (渐变色圆点) =====
    scatter(ax1, x_vals, y_vals, 80, cmap, 'filled', 'MarkerEdgeColor', 'w', ...
        'LineWidth', 1, 'HandleVisibility', 'off');
    % 添加一个单独的点作为图例条目
    plot(ax1, NaN, NaN, 'o', 'MarkerSize', 8, 'MarkerEdgeColor', 'w', ...
        'MarkerFaceColor', [0.5 0.8 1], 'DisplayName', '轨迹采样点');
    
    % ===== 标注点序号 =====
    % 计算序号标注偏移量 (避免遮挡点)
    offset_scale = max([max(x_vals)-min(x_vals), max(y_vals)-min(y_vals)]) * 0.025;
    
    for i = 1:n_points
        % 计算标注位置 (稍微偏离点位)
        if i == 1 || i == n_points
            % 首尾点特殊处理
            offset_x = offset_scale;
            offset_y = offset_scale;
        else
            % 根据前后点计算法向偏移
            prev_i = mod(i-2, n_points) + 1;
            next_i = mod(i, n_points) + 1;
            dx = x_vals(next_i) - x_vals(prev_i);
            dy = y_vals(next_i) - y_vals(prev_i);
            len = sqrt(dx^2 + dy^2);
            if len > 0
                % 法向量 (垂直于切向)
                offset_x = -dy / len * offset_scale;
                offset_y = dx / len * offset_scale;
            else
                offset_x = offset_scale;
                offset_y = offset_scale;
            end
        end
        
        % 绘制序号 (带背景框)
        text(ax1, x_vals(i) + offset_x, y_vals(i) + offset_y, ...
            sprintf('%d', i), ...
            'Color', 'w', 'FontSize', 9, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'BackgroundColor', [0.2 0.2 0.3 0.7], 'Margin', 1);
    end
    
    % ===== 标注起点和终点 =====
    % 起点标记 (绿色三角)
    plot(ax1, x_vals(1), y_vals(1), '^', 'MarkerSize', 14, ...
        'MarkerEdgeColor', 'w', 'MarkerFaceColor', [0 1 0.5], 'LineWidth', 1.5, ...
        'DisplayName', sprintf('起点 #1'));
    
    % 终点标记 (红色方块) - 如果点数>1
    if n_points > 1
        plot(ax1, x_vals(end), y_vals(end), 's', 'MarkerSize', 12, ...
            'MarkerEdgeColor', 'w', 'MarkerFaceColor', [1 0.3 0.3], 'LineWidth', 1.5, ...
            'DisplayName', sprintf('终点 #%d', n_points));
    end
    
    % 绘制中心连线
    mean_x = mean(x_vals);
    mean_y = mean(y_vals);
    line([0, mean_x], [0, mean_y], 'Color', [1 1 0 0.4], 'LineStyle', '-.', 'LineWidth', 1.5, ...
        'HandleVisibility', 'off');
    
    % 绘制轨迹中心点
    plot(ax1, mean_x, mean_y, 'o', 'MarkerSize', 10, ...
        'MarkerEdgeColor', 'w', 'MarkerFaceColor', [1 0.8 0], ...
        'DisplayName', '轨迹中心');

    xlabel(ax1, '东西向距离 / X轴 (米)', 'FontSize', 12, 'Color', [0.8 0.9 1]);
    ylabel(ax1, '南北向距离 / Y轴 (米)', 'FontSize', 12, 'Color', [0.8 0.9 1]);
    title(ax1, sprintf('二维矢量态势图 - %s轨迹 (%d点)', shape_str, n_points), ...
        'Color', 'w', 'FontSize', 15, 'FontWeight', 'bold');
    
    % 动态调整视野
    range_span_x = max(x_vals) - min(x_vals);
    range_span_y = max(y_vals) - min(y_vals);
    margin = max([range_span_x, range_span_y]) * 0.35; 
    if margin == 0, margin = 1000; end
    
    xlim(ax1, [min(x_vals)-margin, max(x_vals)+margin]); 
    ylim(ax1, [min(y_vals)-margin, max(y_vals)+margin]);
    
    % 图例
    leg = legend(ax1, 'TextColor', 'w', 'Color', [0.1 0.1 0.2 0.8], ...
        'EdgeColor', [0.4 0.4 0.6], 'Location', 'northwest', 'FontSize', 10, ...
        'FontName', 'Microsoft YaHei');
    
    % 添加颜色条说明时间顺序
    colormap(ax1, jet);
    cb = colorbar(ax1, 'Position', [0.46 0.10 0.012 0.35], 'Color', [0.8 0.9 1]);
    cb.Label.String = '时间顺序';
    cb.Label.Color = [0.8 0.9 1];
    cb.Label.FontSize = 10;
    caxis(ax1, [1 n_points]);
    cb.Ticks = [1, round(n_points/2), n_points];
    cb.TickLabels = {'起点', '中间', '终点'};

    % =====================================================================
    % 右侧上部: 极坐标 PPI (带箭头)
    % =====================================================================
    ax2 = polaraxes('Parent', fig, 'Position', [0.54 0.45 0.42 0.48], ...
        'Color', [0 0.05 0.1], 'ThetaColor', [0.7 0.8 0.9], 'RColor', [0.7 0.8 0.9], ...
        'GridColor', [0 0.4 0.5], 'GridAlpha', 0.5, 'FontName', 'Microsoft YaHei');
    hold(ax2, 'on');
    
    az_rad = az_vals * pi/180;
    
    % 渐变色轨迹
    for i = 1:n_points
        next_i = mod(i, n_points) + 1;
        polarplot(ax2, [az_rad(i), az_rad(next_i)], [r_vals(i), r_vals(next_i)], ...
            '-', 'Color', [cmap(i,:), 0.8], 'LineWidth', 2, 'HandleVisibility', 'off');
    end
    
    % 绘制点
    polarscatter(ax2, az_rad, r_vals, 50, cmap, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 0.5, ...
        'HandleVisibility', 'off');
    
    % 标记起点终点
    polarplot(ax2, az_rad(1), r_vals(1), '^', 'MarkerSize', 12, ...
        'MarkerEdgeColor', 'w', 'MarkerFaceColor', [0 1 0.5], 'LineWidth', 1.5, ...
        'HandleVisibility', 'off');
    if n_points > 1
        polarplot(ax2, az_rad(end), r_vals(end), 's', 'MarkerSize', 10, ...
            'MarkerEdgeColor', 'w', 'MarkerFaceColor', [1 0.3 0.3], 'LineWidth', 1.5, ...
            'HandleVisibility', 'off');
    end
    
    r_min = min(r_vals) * 0.9;
    r_max = max(r_vals) * 1.1;
    if r_min == r_max, r_min = r_max * 0.8; end
    rlim(ax2, [r_min, r_max]); 
    
    title(ax2, 'PPI 雷达扫描视图', 'Color', 'w', 'FontSize', 14, 'FontWeight', 'bold');

    % =====================================================================
    % 右侧下部: 数据统计面板
    % =====================================================================
    width_est  = max(x_vals) - min(x_vals);
    height_est = max(y_vals) - min(y_vals);
    center_r   = mean(r_vals);
    
    % 使用圆形平均计算中心方位
    center_az  = circular_mean(az_vals);
    
    % 计算轨迹周长
    perimeter = 0;
    for i = 1:n_points
        next_i = mod(i, n_points) + 1;
        perimeter = perimeter + sqrt((x_vals(next_i)-x_vals(i))^2 + (y_vals(next_i)-y_vals(i))^2);
    end
    
    str_info = {
        '══════ 目标情报分析报告 ══════',
        '',
        sprintf('  系统状态:    ● 在线'),
        sprintf('  捕获点数:    %d 点', n_points),
        sprintf('  形状特征:    【 %s 】', shape_str),
        '',
        sprintf('  ────── 位置参数 ──────'),
        sprintf('  中心距离:    %.1f 米', center_r),
        sprintf('  中心方位:    %.1f°', center_az),
        sprintf('  中心坐标:    (%.1f, %.1f) 米', mean_x, mean_y),
        '',
        sprintf('  ────── 尺寸参数 ──────'),
        sprintf('  宽度×高度:   %.0f × %.0f 米', width_est, height_est),
        sprintf('  轨迹周长:    %.1f 米', perimeter),
        '',
        sprintf('  ────── 运动参数 ──────'),
        sprintf('  起点 #1:     (%.1f, %.1f)', x_vals(1), y_vals(1)),
        sprintf('  终点 #%d:    (%.1f, %.1f)', n_points, x_vals(end), y_vals(end)),
        '',
        ['  时间戳: ' datestr(now, 'yyyy-mm-dd HH:MM:SS')]
    };
    
    annotation(fig, 'textbox', [0.54 0.02 0.44 0.38], ...
        'String', str_info, ...
        'Color', [0.9 0.95 1], ...          
        'BackgroundColor', [0.08 0.08 0.15], ... 
        'EdgeColor', [0.3 0.5 0.7], ...      
        'LineWidth', 2, ...
        'FontSize', 11, 'FontName', 'Microsoft YaHei', 'FontWeight', 'bold', 'Margin', 12);
    
    % ===== 添加图例说明 =====
    annotation(fig, 'textbox', [0.54 0.41 0.20 0.04], ...
        'String', '▲ 起点    ■ 终点    → 运动方向', ...
        'Color', [0.8 0.9 1], ...
        'BackgroundColor', 'none', ...
        'EdgeColor', 'none', ...
        'FontSize', 10, 'FontName', 'Microsoft YaHei', 'FontWeight', 'bold', 'Margin', 2);
end
