%% PSD_HMDON_HMDOFF  Sensor noise spectra with the HMD on and off (Experiment 2)
%
% Preprocesses two recordings without the phantom, one with the HMD switched
% on (displaying the checkerboard task) and one with the HMD switched off,
% with the same steps as the participant data (low-pass 90 Hz, downsampling
% to 375 Hz, Zapline-plus 50 Hz, high-pass 2 Hz, AMM). Exports the PSD before
% and after AMM (Figure 3B, Supplementary Figure 3) and quantifies the effect
% of the HMD:
%   - broadband level: median of the channel-median amplitude spectral
%     density across 5-90 Hz, HMD on vs off in dB (20*log10 of the ratio)
%   - narrowband peaks introduced by the HMD and their prominence (dB)
%
% Paths are read from config_local.m (see config_template.m):
%   cfg.paths.spm, cfg.paths.zapline, cfg.paths.data_root, cfg.paths.output_root
%
% Dependencies:
%   - SPM (incl. OPM functions spm_opm_create, spm_opm_psd, spm_opm_amm)
%   - zapline-plus (clean_data_with_zapline_plus)
%   - Signal Processing Toolbox (findpeaks)
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

clear; clc; close all;

%% -------------------- Paths (set in config_local.m) --------------------
cfg = struct();
run('config_local.m');

spm_dir    = cfg.paths.spm;
zapline    = cfg.paths.zapline;
dataFolder = fullfile(cfg.paths.data_root, 'sub-000', 'ses-001', 'meg');
out_dir    = fullfile(cfg.paths.output_root, 'DC-AC');

addpath(spm_dir); addpath(zapline);
spm('defaults','eeg');
if ~exist(out_dir,'dir'), mkdir(out_dir); end

%% -------------------- Files to process (base names, NO extension) --------------------
file_names = { ...
    'sub-000_ses-001_task-hmdInRoomChk_run-001_meg', ...
    'sub-000_ses-001_task-hmdInRoomButOff_run-001_meg' };

%% -------------------- Bad channels (1-indexed in the SPM object) --------------------
% One entry per file (same order as file_names).
badChanIndices = { ...
    [32,116,68,125,73,57,88,77,75,29,123,9,103,25,27,108,105,40,7,116,20,55,60,12,121,136,1,42,82,79,39,138,14,46,119,97,34,72,114,18,90,49,52,100,4,54,62,100], ...   % hmdInRoomChk
    [32,116,68,125,73,57,88,77,75,29,123,9,103,25,27,108,105,40,7,116,20,55,60,12,121,136,1,42,82,79,39,138,14,46,119,97,34,72,114,18,90,49,52,100,4,54,62,100] };     % hmdInRoomButOff

%% -------------------- Parameters (match ac_noise) --------------------
load_raw_data = false;     % true: read raw .lvm via spm_opm_create; false: load *.mat
amm_corlim    = 0.95;     % AMM correlation limit
zapline_freqs = 50;       % Hz, line-noise frequency for Zapline
dws = 375;                % downsampling rate (Hz)

%% -------------------- Storage for the on-vs-off comparison --------------------
Mmed  = cell(1, numel(file_names));   % channel-median spectrum (after AMM), per file
Ffreq = cell(1, numel(file_names));   % matching frequency axis, per file

%% ==================== Main loop ====================
for k = 1:numel(file_names)

    base = fullfile(dataFolder, file_names{k});
    fprintf('\n==== Processing (%d/%d): %s ====\n', k, numel(file_names), file_names{k});

    %% --- Load ---
    if load_raw_data
        S = [];
        S.data      = [base '.lvm'];
        S.positions = [base '_positions.tsv'];
        S.lead      = 0;                             % no forward model needed for PSD/AMM
        D = spm_opm_create(S);
    else
        D = spm_eeg_load([base '.mat']);
    end

    %% --- Mark bad channels ---
    if ~isempty(badChanIndices{k})
        D = badchannels(D, badChanIndices{k}, 1);
    end
    megChannels = setdiff(D.indchantype('MEG'), D.badchannels());
    fprintf('%d good MEG channels (%d marked bad)\n', ...
        numel(megChannels), numel(D.badchannels()));

    %% --- Low-pass 90 Hz ---
    S = struct(); S.D = D; S.freq = 90; S.band = 'low';
    fD = spm_eeg_ffilter(S);

    %% --- Downsample ---
    S = struct();
    S.fsample_new = dws;
    S.D           = fD;
    fD = spm_eeg_downsample(S);

    %% --- Zapline line-noise removal (50 Hz) on good MEG channels ---
    fs = fsample(fD);
    [zapped_data,~,~,~] = clean_data_with_zapline_plus( ...
        squeeze(fD(megChannels,:)), fs, 'noisefreqs', zapline_freqs, 'plotResults', 0);
    assert(isequal(size(zapped_data), size(squeeze(fD(megChannels,:)))), ...
        'Zapline changed size/channel order.');
    fD(megChannels,:,1) = zapped_data;
    fD.save;

    %% --- High-pass 2 Hz (drift removal, before AMM) ---
    S = struct(); S.D = fD; S.freq = 2; S.band = 'high';
    fD = spm_eeg_ffilter(S);

    %% --- AMM ---
    S = struct(); S.D = fD; S.corrLim = amm_corlim; S.li = 8;
    mD = spm_opm_amm(S);

    %% --- PSD BEFORE AMM ---
    S = []; S.D = fD; S.plot = 1; S.triallength = 3000;
    S.channels = chanlabels(D, megChannels);
    spm_opm_psd(S);
    style_and_save(gcf, fullfile(out_dir, [file_names{k} '_beforeAMM.emf']));

    %% --- PSD AFTER AMM ---
    S = []; S.D = mD; S.plot = 1; S.triallength = 3000;
    S.channels = chanlabels(D, megChannels);
    [psd, freq] = spm_opm_psd(S);        % psd: [nfreq x nchan], freq in Hz
    style_and_save(gcf, fullfile(out_dir, [file_names{k} '_afterAMM.emf']));

    m = median(psd,2);                    % channel-median spectrum (fT/sqrt(Hz))
    Mmed{k}  = m;                          % store for the on-vs-off comparison
    Ffreq{k} = freq(:);

    % per-file peak list (ranked)
    sel = freq>=10 & freq<=95;            % skip the 1/f shoulder
    [pk,loc] = findpeaks(m(sel), freq(sel), ...
        'MinPeakProminence', 3*median(m(sel)), 'MinPeakDistance', 4);
    [~,o] = sort(pk,'descend');
    fprintf('Peaks (%s):\n', file_names{k});
    fprintf('  %.1f Hz  (amp %.0f)\n', [loc(o)' pk(o)]');

end

%% ==================== HMD on vs off: quantify the difference ====================
% Identify which file is HMD-off (name contains 'Off'); the other is HMD-on.
off_idx = find(contains(file_names,'Off','IgnoreCase',true), 1);
on_idx  = find(~contains(file_names,'Off','IgnoreCase',true), 1);

if ~isempty(off_idx) && ~isempty(on_idx) ...
        && ~isempty(Mmed{on_idx}) && ~isempty(Mmed{off_idx})

    fon  = Ffreq{on_idx};   Mon  = Mmed{on_idx};
    foff = Ffreq{off_idx};  Moff = Mmed{off_idx};

    % put HMD-on onto the HMD-off frequency axis if they differ
    if ~isequal(fon,foff)
        Mon = interp1(fon, Mon, foff, 'linear', 'extrap');
        fon = foff;
    end

    band = fon>=5 & fon<=90;             % comparison band (Hz)

    % --- Broadband level: MEDIAN of the channel-median spectrum within the band ---
    floor_on  = median(Mon(band));
    floor_off = median(Moff(band));
    dB_floor  = 20*log10(floor_on  / floor_off);     % fT/sqrt(Hz) -> dB

    fprintf('\n===== HMD on vs off (after AMM), %g-%g Hz =====\n', ...
            min(fon(band)), max(fon(band)));
    fprintf('Broadband level (median) : off %.1f | on %.1f fT/sqrt(Hz)  -> %+.1f dB\n', ...
            floor_off, floor_on, dB_floor);

    % --- Narrowband: HMD peaks and their prominence above the local floor ---
    [~,lc,~,prom] = findpeaks(20*log10(Mon(band)), fon(band), ...
                    'MinPeakProminence',3, 'MinPeakDistance',4);
    [prom,o] = sort(prom,'descend'); lc = lc(o);
    fprintf('HMD narrowband peaks (freq Hz | prominence above floor, dB):\n');
    for ii = 1:numel(lc)
        fprintf('   %5.1f Hz | %4.1f dB\n', lc(ii), prom(ii));
    end
else
    warning('Could not identify on/off files (need one name containing ''Off'').');
end

%% ==================== helper ====================
function style_and_save(fig, outpath)
    figure(fig);
    ylim([10^0 10^4]);
    set(fig, 'Units','centimeters', 'Position',[10 10 6 4], ...
             'Color','w', 'Renderer','painters');
    set(gca, 'FontName','Arial', 'FontSize',7, 'FontWeight','bold');
    set(findall(gca,'Type','Line'), 'LineWidth', 1);
    exportgraphics(fig, outpath, 'ContentType','vector');
    fprintf('Saved: %s\n', outpath);
end
