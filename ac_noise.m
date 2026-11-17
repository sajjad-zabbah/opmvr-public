%% AC_NOISE  Phantom (coil) recordings with the HMD off and on (Experiment 2)
%
% Preprocesses the two phantom recordings (HMD off, HMD on) with the same
% steps as the participant data (low-pass 90 Hz, Zapline-plus 50 Hz,
% high-pass 2 Hz, AMM) and exports their power spectra before and after AMM.
% With dipole_fit = true, the 30 Hz phantom signal is band-pass filtered,
% epoched on the signal-generator reference channel and averaged, a dipole is
% fitted (FieldTrip, grid search, infinite homogeneous medium) and the
% distance between the HMD-off and HMD-on dipole positions is reported
% (Figure 3C).
%
% Paths are read from config_local.m (see config_template.m):
%   cfg.paths.spm, cfg.paths.zapline, cfg.paths.phantom_root,
%   cfg.paths.output_root
%
% Dependencies:
%   - SPM (incl. OPM functions and the FieldTrip version shipped with SPM)
%   - zapline-plus (clean_data_with_zapline_plus)
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

clear; clc; close all;

%% 1) Parameters

% true : read the original *.lvm files with spm_opm_create
% false: load the converted SPM M/EEG objects (*.mat)
load_raw_data  = false;

sub            = 'coil';
ses            = '001';

dipole_fit = false; % true -> epoch, average and fit a dipole to the phantom signal

% Two files to compare (order matters: HMD off, HMD on)
file_names     = { ...
    'closed_loop_off_hmd_off Array 1.lvm', ...
    'closed_loop_off_hmd_on Array 1.lvm' ...
    };

band_pass_freq = [25 35];   % Hz
time_window    = [0 50];    % ms

amm_corlim = 0.95;
% Bad channels (1-indexed channel indices in SPM object)
badChanIndices = [1, 2, 6, 31, 36, 57, 58, 62, 87, 92, 113, 114, 118, 143, ...
                  148, 152, 41, 97, 153, 108, 52, 164];

%% 2) Paths (set in config_local.m)
cfg = struct();
run('config_local.m');

out_dir       = fullfile(cfg.paths.output_root, 'DC-AC');
spm_dir       = cfg.paths.spm;
dataFolder    = fullfile(cfg.paths.phantom_root, ['sub-' sub], ['ses-' ses], 'meg');
zapline       = cfg.paths.zapline;
save_data_add = fullfile(cfg.paths.output_root, 'ProcessedData', ['sub-' sub]);

% Create output folders if they do not exist
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
if ~exist(save_data_add, 'dir'), mkdir(save_data_add); end

addpath(spm_dir);
addpath(zapline);

spm('defaults', 'eeg');

%% 3) Find input files

all_files = dir(fullfile(dataFolder, '*.lvm'));
dataDir   = all_files(ismember({all_files.name}, file_names));

if numel(dataDir) ~= numel(file_names)
    error('Not all requested files were found in dataFolder. Check file_names and dataFolder.');
end

%% 4) Prepare FieldTrip source grid (used for dipole fitting grid search)

cfg = [];
cfg.method = 'basedongrid';
cfg.xgrid  = -100:5:100;
cfg.ygrid  = -100:5:150;
cfg.zgrid  = -100:5:100;
cfg.unit   = 'mm';
src = ft_prepare_sourcemodel(cfg);

%% 5) Read data, filter, PSD, epoch, dipole fitting

figure;
pos = nan(numel(dataDir), 3);

for dataIdx = 1:numel(dataDir)

    this_file = dataDir(dataIdx).name;
    fprintf('Processing (%d/%d): %s\n', dataIdx, numel(dataDir), this_file);

    % --- Load data ---
    if load_raw_data
        % Load raw *.lvm
        S = [];
        S.data      = fullfile(dataDir(dataIdx).folder, this_file);
        S.sMRI      = fullfile(dataFolder, 'SM_structural_MRI_defaced.nii');
        S.positions = [S.data(1:end-4) '_positions.tsv'];
        S.lead      = 1;
        D = spm_opm_create(S);
    else
        % Load preprocessed *.mat (SPM MEEG)
        mat_name = [this_file(1:end-3) 'mat'];
        mat_path = fullfile(dataDir(dataIdx).folder, mat_name);
        D = spm_eeg_load(mat_path);
    end

    % --- Mark bad channels ---
    D = badchannels(D, badChanIndices, 1);
    badChannels = D.badchannels();
    megChannels = setdiff(D.indchantype('MEG'), badChannels);

    %% Filtering (same pipeline as the participant data)

    % Low-pass 90 Hz (as for the participant data)
    S = struct();
    S.D    = D;
    S.freq = 90;
    S.band = 'low';
    fD = spm_eeg_ffilter(S);

    zapline_freqs = [ 50 ];

    fs = fsample(fD);
    [zapped_data,~,~,~] = clean_data_with_zapline_plus( ...
        squeeze(fD(megChannels,:)), fs, 'noisefreqs', zapline_freqs, 'plotResults', 0);
    assert(isequal(size(zapped_data), size(squeeze(fD(megChannels,:)))), ...
        'Zapline changed size/channel order.');
    fD(megChannels,:,1) = zapped_data;
    fD.save;

    % High-pass (drift removal, before AMM)
    S = struct();
    S.D    = fD;
    S.freq = 2;
    S.band = 'high';
    fD = spm_eeg_ffilter(S);

    % AMM
    S = struct();
    S.D       = fD;
    S.corrLim = amm_corlim;
    mD = spm_opm_amm(S);

    %% Power spectra

    % before AMM
    S = [];
    S.D          = fD;
    S.plot       = 1;
    S.triallength= 3000;
    S.channels   = chanlabels(D, megChannels);
    spm_opm_psd(S);

    out_psd = fullfile(out_dir, [this_file(1:end-4)  '_beforeAMM' '.emf']);

    ylim([10^0, 10^4])
    set(gcf, 'Units', 'centimeters', 'Position', [10 10 6 4]);
    set(gcf, 'Color', 'w');
    set(gca, 'FontName','Arial');
    set(gca, 'FontSize', 7);
    set(gca, 'FontWeight','bold');
    set(findall(gca, 'Type', 'Line'), 'LineWidth', 1);
    set(gcf, 'Renderer', 'painters');
    exportgraphics(gcf, out_psd, 'ContentType', 'vector');

    % after AMM
    S = [];
    S.D          = mD;
    S.plot       = 1;
    S.triallength= 3000;
    S.channels   = chanlabels(D, megChannels);
    spm_opm_psd(S);

    out_psd = fullfile(out_dir, [this_file(1:end-4) '_afterAMM' '.emf']);

    ylim([10^0, 10^4])
    set(gcf, 'Units', 'centimeters', 'Position', [10 10 6 4]);
    set(gcf, 'Color', 'w');
    set(gca, 'FontName','Arial');
    set(gca, 'FontSize', 7);
    set(gca, 'FontWeight','bold');
    set(findall(gca, 'Type', 'Line'), 'LineWidth', 1);
    set(gcf, 'Renderer', 'painters');
    exportgraphics(gcf, out_psd, 'ContentType', 'vector');

    %% Dipole fit (optional)
if dipole_fit

    % Band-pass around the phantom frequency
    S = [];
    S.D      = mD;
    S.freq   = band_pass_freq;
    S.band   = 'bandpass';
    S.outdir = save_data_add;
    fD = spm_eeg_ffilter(S);

    S = [];
    S.D               = fD;
    S.timewin         = time_window;
    S.triggerChannels = {'AI9'};

    % spm_opm_epoch_trigger assumes zero-mean trigger; enforce it here
    trigInds = indchannel(S.D, S.triggerChannels);
    S.D(trigInds,:,:) = S.D(trigInds,:,:) - mean(squeeze(S.D(trigInds,:,:)));

    S.thresh = 0.0025;
    eD = spm_opm_epoch_trigger(S);

    % Average epochs
    S = [];
    S.D = eD;
    muD = spm_eeg_average(S);
    Davg = muD;

    %% Dipole fit

    % Pick peak time across good magnetometers
    [maxvals, maxtimes] = max(abs(Davg(indchantype(Davg, 'MEGMAG', 'GOOD'), :, 1)), [], 2);
    [~, fitind] = max(maxvals);
    fitind = maxtimes(fitind);

    if fitind + 1 > numel(Davg.time)
        fittime = [Davg.time(fitind-1) Davg.time(fitind)];
    else
        fittime = [Davg.time(fitind) Davg.time(fitind+1)];
    end

    % Convert to FieldTrip format
    data = ftraw(Davg);

    % Head model (infinite homogeneous medium)
    cfg = [];
    cfg.method = 'infinite';
    cfg.grad   = data.grad;
    hdm = ft_prepare_headmodel(cfg, src);

    % Dipole fitting (grid search)
    cfg = [];
    cfg.headmodel   = hdm;
    cfg.sourcemodel = src;
    cfg.grad        = data.grad;
    cfg.latency     = fittime;
    cfg.gridsearch  = 'yes';
    results = ft_dipolefitting(cfg, data);

    %% Plot dipoles + sensors

    figure(5);
    hold on;

    pos(dataIdx,:) = results.dip.pos;

    % Colour coding: red = HMD off, blue = HMD on
    if dataIdx == 1
        cl = [0.7 0.1 0.1];
    else
        cl = [0.1 0.1 0.7];
    end

    ft_plot_dipole(results.dip.pos, mean(results.dip.mom(1:3,:),2), 'unit', 'mm', 'color', cl);

    if dataIdx == 1
        sens = Davg.sensors('MEG');
        ft_plot_sens(sens,'coilshape','disc');

        scalp = ft_read_headshape(Davg.inv{1}.mesh.tess_scalp);
        ft_plot_mesh(scalp, 'edgecolor', [0.7 0.7 0.7], 'facealpha', 0.3, 'edgealpha', 0.3);

        bad_pos = sens.chanpos(badChannels, :);
        plot3(bad_pos(:,1), bad_pos(:,2), bad_pos(:,3), 'r+', 'MarkerSize', 8, 'LineWidth', 2);
    end
end
end

%% 6) Report dipole distance difference

Diff = sqrt(sum((pos(1,:) - pos(2,:)).^2));
fprintf('Dipole position difference (mm): %.4f\n', Diff);

%% 7) Export dipole figure

set(gcf, 'Units', 'centimeters', 'Position', [10 10 10 8.1]);
set(gcf, 'Color', 'w');
exportgraphics(gcf, fullfile(out_dir, 'dipole_fit.tif'), 'Resolution', 600);
