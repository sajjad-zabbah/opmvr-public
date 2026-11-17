%% TIME_FREQUENCY  Alpha-band time course and topography (Experiment 3)
%
% This script computes time-frequency power (SPM Morlet wavelets) for a set
% of channels, normalises power (optionally) relative to a baseline, and
% plots:
%   1) sensor positions for selected region
%   2) time course from sensor with highest average power
%   3) FieldTrip topographic map
%
% Expected variables in workspace:
%   eD                : SPM MEEG object (epoched or continuous)
%   time_window       : [t1 t2] in ms for spm_eeg_tf
%   intrest_freq_band : Nx2 frequency band(s) in Hz (e.g., [8 12])
%   sensor_location   : cell array like {'mid-left'} or {'back'}
%   goodChannels      : indices of good channels (from preprocess)
%   task              : cell array, e.g. {'eyesOpenEyesClosed'}
%   save_data_add     : output folder
%
% Notes:
%   - dB conversion uses: 10*log10(P / Pbaseline)
%   - For eyesOpenEyesClosed, baseline is mean during first 60 s (eyes open)
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

%% Frequency band naming
freq_bnds.frq  = intrest_freq_band;
freq_bnds.name = cell(size(intrest_freq_band,1),1);

for i = 1:size(intrest_freq_band, 1)
    band = intrest_freq_band(i,:);

    if isequal(band, [8 12])
        freq_bnds.name{i} = 'alpha';
    elseif isequal(band, [13 30])
        freq_bnds.name{i} = 'beta';
    elseif isequal(band, [31 50])
        freq_bnds.name{i} = 'gamma';
    else
        freq_bnds.name{i} = sprintf('%d-%dHz', band(1), band(2));
    end
end

%% Sensor region selection
sen_loc = sensor_location{1};
switch sen_loc
    case 'mid-left'
        thr_y = [-10 0];
        thr_x = [-70 -30];
    case 'mid-right'
        thr_y = [-10 4];
        thr_x = [30 70];
    case 'back-left'
        thr_y = [-97 -92];
        thr_x = [-40 -31];
    case 'back-right'
        thr_y = [-97 -88];
        thr_x = [10 45];
    case 'back'
        thr_y = [-150 -80];
        thr_x = [-150 150];
    case 'temp-left'
        thr_y = [-30 30];
        thr_x = [-90 -60];
    case 'temp-right'
        thr_y = [-30 30];
        thr_x = [40 90];
    case 'all'
        thr_y = [-300 300];
        thr_x = [-400 900];
    case 'not-front'
        thr_y = [-300 25];
        thr_x = [-400 900];
    case 'front'
        thr_y = [60 300];
        thr_x = [-400 900];
    case 'mid'
        thr_y = [-30 60];
        thr_x = [-65 60];
    otherwise
        error('Unknown sensor_location option: %s', sen_loc);
end

% Get sensor positions (SPM format)
sens = eD.sensors('MEG');
sensor_positions = sens.chanpos;
sensor_lab       = sens.label;

sensors_idx = find(sensor_positions(:,2) < thr_y(2) & ...
                   sensor_positions(:,2) > thr_y(1) & ...
                   sensor_positions(:,1) < thr_x(2) & ...
                   sensor_positions(:,1) > thr_x(1));

good_sensors_idx = sensors_idx(ismember(sensors_idx, goodChannels));

% Plot sensor selection
figure('Color','w');
scatter3(sensor_positions(:,1), sensor_positions(:,2), sensor_positions(:,3), 8, 'b', 'filled'); hold on;
scatter3(sensor_positions(good_sensors_idx,1), sensor_positions(good_sensors_idx,2), sensor_positions(good_sensors_idx,3), 8, 'r', 'filled');

K = convhull(sensor_positions(:,1), sensor_positions(:,2), sensor_positions(:,3));
trisurf(K, sensor_positions(:,1), sensor_positions(:,2), sensor_positions(:,3), ...
    'FaceAlpha', 0.7, 'EdgeColor', 'none', 'FaceColor', [0.8 0.8 0.8]);

xlabel('X'); ylabel('Y'); zlabel('Z');
grid on; axis equal;
title(sprintf('Selected sensors (%s)', sen_loc), 'Interpreter','none');

%% Time-frequency analysis (SPM)
% Select *-Z channels only (e.g., radial/one axis) + restrict to good sensors in region
meg_idx   = indchantype(eD, 'all');
zchan_idx = find(contains(eD.chanlabels(), '-Z'));
good_zchan_ind = intersect(intersect(good_sensors_idx', meg_idx), zchan_idx);
good_zchan_ind_lab = eD.chanlabels(good_zchan_ind);

% Loop through frequency bands
for i = 1:numel(freq_bnds.name)

    S = [];
    S.D          = eD;
    S.frequencies = freq_bnds.frq(i,1):freq_bnds.frq(i,2);
    S.timewin    = time_window;
    S.phase      = 0;
    S.prefix     = [];        % SPM will prefix with 'tf_'
    S.method     = 'morlet';
    S.settings.subsample = 8;
    S.settings.ncycles   = 7;
    S.channels   = good_zchan_ind_lab;

    tfD = spm_eeg_tf(S);
    time = tfD.time;

    % Baseline
    if strcmp(task{1}, 'eyesOpenEyesClosed')
        ind_eye_open = time < 60;
        ind_base = find(ind_eye_open);

        base_line = squeeze(mean(tfD(:,:,ind_base),2));
        base_line = squeeze(mean(base_line,2));   % mean over time -> (Nchan x 1)
    else
        base_line = 1; % no baseline normalisation
    end

    % dB normalisation (power ratio)
    tfD_norm = 10 * log10(tfD(:,:,:) ./ base_line);

    % pick sensor with maximum average power
    mean_sens_time = squeeze(mean(tfD_norm(:,:,:),2)); % (chan x time)
    [~, highest_power_sensor_ind] = max(mean(mean_sens_time,2));
    high_power_sensor = mean_sens_time(highest_power_sensor_ind,:);

    % Plot time course (subsampled for clarity)
    figure('Color','w');
    plot(time(1:20:end), high_power_sensor(1:20:end), 'LineWidth', 1);
    xlabel('Time (s)');
    ylabel('Normalised power (dB)');
    title(sprintf('%s power (max sensor)', freq_bnds.name{i}), 'Interpreter','none');
    grid off;
    set(gca,"TickDir","out","box","off");

    if strcmp(task{1}, 'eyesOpenEyesClosed')
        x_start = 58; x_end = 62;
        yl = ylim; hold on
        patch([x_start x_end x_end x_start], [yl(1) yl(1) yl(2) yl(2)], ...
            [0.8 0.8 0.8], 'FaceAlpha', 0.4, 'EdgeColor', 'none');
    end

    % Save
    if ~exist(save_data_add,'dir'); mkdir(save_data_add); end
    outFile = fullfile(save_data_add, sprintf('%s_timecourse.emf', freq_bnds.name{i}));
    set(gcf, 'Units', 'centimeters', 'Position', [10 10 7.62 7.62], 'Renderer', 'painters');
    set(gca, 'FontName','Arial', 'FontWeight','bold', 'FontSize', 10);
    exportgraphics(gcf, outFile, 'ContentType', 'vector');
end

%% Topographic map (FieldTrip)
% NOTE: uses tfD from the last computed band above
if ~exist('tfD','var')
    warning('No tfD object found (time-frequency may have failed). Skipping topography.');
    return;
end

% Try to use layout from tfD if present
if isfield(tfD, 'lay') && ~isempty(tfD.lay)
    layout = tfD.lay;
else
    warning('tfD.lay not found. You may need to create a FieldTrip layout separately.');
    layout = [];
end

% Restrict layout to good Z channels
if ~isempty(layout)
    layout.label  = layout.label(good_zchan_ind);
    layout.pos    = layout.pos(good_zchan_ind, :);
    layout.width  = layout.width(good_zchan_ind);
    layout.height = layout.height(good_zchan_ind);
    layout.mask{1} = layout.outline{1};

    cfg = [];
    cfg.layout = layout;
    layout = ft_prepare_layout(cfg);
end

% Compute mean over time (for topography)
mean_chan = mean(mean_sens_time(:,:), 2); % (chan x 1)

avg = [];
avg.label  = tfD.chanlabels;
avg.avg    = mean_chan';   % 1 x Nchan
avg.time   = 0;
avg.dimord = 'chan_time';

cfg = [];
cfg.mask      = 'no';
cfg.headshape = [];
cfg.layout    = layout;
cfg.zlim      = 'maxabs';
cfg.marker    = 'on';
cfg.comment   = 'no';
cfg.colorbar  = 'yes';
cfg.style     = 'both';
cfg.channel   = {'*-Z'};

figure('Color','w');
ft_topoplotER(cfg, avg);

cb = findobj(gcf,'Type','Colorbar');
if isempty(cb), cb = colorbar; end
cb.Label.String      = 'dB';
cb.Label.FontWeight  = 'bold';
cb.Label.FontName    = 'Arial';

set(gcf, 'Units', 'centimeters', 'Position', [10 10 5 5], 'Renderer', 'painters');
set(gca, 'FontName','Arial', 'FontWeight','bold', 'FontSize', 10);
set(gca,"TickDir","out","box","off");

outFile = fullfile(save_data_add, 'TopoPlot.emf');
exportgraphics(gcf, outFile, 'ContentType', 'vector');
