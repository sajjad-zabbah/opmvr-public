%% MAIN  Analysis entry point for the participant experiments
%
% Runs preprocessing and one analysis for one participant and one task:
%   'time_frequency'      - alpha-band time course and topography
%                           (Experiment 3, Figure 3D)
%   'source_localization' - LCMV beamformer, permutation F-test and figures
%                           (Figures 3E and 4, Supplementary Figure 4)
%   'movement_analysis'   - head and hand displacement for all tasks (Figure 6)
%   'bad_channel_pos'     - positions of the excluded channels
%                           (Supplementary Figure 2)
%
% Tasks: {'eyesOpenEyesClosed'} (Experiment 3), {'chk'} (Experiment 4,
% checkerboard), {'grasping'} (Experiment 5), {'0back','2back'} (Experiment 6,
% N-back).
%
% figure_set:
%   'main'          - permutation F-test (10,000 permutations) with
%                     small-volume correction within the a priori ROI of each
%                     task; FWE-significant voxels are shown as signed t
%                     (Figures 3E and 4).
%   'supplementary' - whole-brain (unmasked) signed-t maps thresholded at half
%                     of the peak value, one figure per contrast direction
%                     (Supplementary Figure 4).
%
% To run on a new machine:
%   1) Copy config_template.m to config_local.m and set the paths.
%   2) Set the parameters in section 1 and run this script from the
%      repository folder.
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

close all;
clearvars;

%% 0) Load machine-specific paths (config_local.m)
cfg = struct();
if exist('config_local.m', 'file')
    run('config_local.m');
else
    warning(['config_local.m not found. Copy config_template.m to config_local.m ' ...
        'and set cfg.paths.* before running.']);
end

requiredFields = {'data_root','output_root','spm','analyse_opmeg','functions','zapline'};
if ~isfield(cfg,'paths')
    error('cfg.paths is missing. Please create config_local.m from config_template.m.');
end
for iF = 1:numel(requiredFields)
    if ~isfield(cfg.paths, requiredFields{iF}) || isempty(cfg.paths.(requiredFields{iF}))
        error('Missing cfg.paths.%s. Please set it in config_local.m.', requiredFields{iF});
    end
end

%% 1) Analysis parameters
load_raw_data  = false;  % true: read the raw .lvm files; false: load the converted SPM .mat files
delet_spm_file = false;  % true: delete SPM-generated intermediate files before running
only_plot      = false;  % true: only redraw the figures from statistics already on disk
stats_only     = false;  % true: re-run statistics and figures on the *_meg.nii images on disk

figure_set     = 'main'; % 'main' | 'supplementary' (see header)

analysis       = 'time_frequency';        % 'time_frequency' | 'source_localization' | 'movement_analysis' | 'bad_channel_pos'
sub            = '001';                   % '001' | '002'
task           = {'eyesOpenEyesClosed'};  % {'eyesOpenEyesClosed'} | {'chk'} | {'grasping'} | {'0back','2back'}
runs           = {'001','002'};           % overwritten below for single-run tasks

switch figure_set
    case 'main'
        small_vol_cor     = true;    % FWE correction within the task ROI
        plot_halfmax_maps = false;
        nPerm             = 10000;   % number of permutations
    case 'supplementary'
        small_vol_cor     = false;   % whole brain
        plot_halfmax_maps = true;    % half-maximum signed-t maps, both directions
        nPerm             = 1;       % the unthresholded t map does not depend on nPerm
    otherwise
        error('Unknown figure_set: %s', figure_set);
end

%% Task-specific parameters
conditionlabel1 = [];  eventtype1 = [];
conditionlabel2 = [];  eventtype2 = [];
band_pass_freq  = [];
roi_labels      = [];

switch task{1}
    case 'eyesOpenEyesClosed'                  % Experiment 3
        ses  = '002';
        runs = {'001'};

        if strcmp(analysis,'time_frequency')
            band_pass_freq    = [2 50];
            time_window       = [0 120000];    % ms (whole two-minute recording)
            intrest_freq_band = [8 12];        % alpha
            sensor_location   = {'all'};

        elseif strcmp(analysis,'source_localization')
            % No triggers exist for this task: preprocess.m cuts the continuous
            % recording into fixed-length epochs labelled by time (first
            % minute = eyes open, second minute = eyes closed).
            band_pass_freq    = [8 12];        % alpha
            intrest_freq_band = [8 12];        % used for the output folder name
            ifsmoothed        = 1;
            roi_labels        = [108 109 114 115 134 135 156 157]; % occipital ROI (Neuromorphometrics)
            mni_cordinates    = [5.9 -72.9 6.1];

            conditionlabel1 = 'EyesOpen';
            eventtype1      = 'eo_epoch';
            conditionlabel2 = 'EyesClosed';
            eventtype2      = 'ec_epoch';

            eoec_epoch_len = 2;                % epoch length (s)
            eo_window      = [5  58];          % eyes-open period used (s)
            ec_window      = [62 118];         % eyes-closed period used (s); excludes the transition
            time_window    = [0 eoec_epoch_len*1000];   % ms
        end

    case 'chk'                                 % Experiment 4 (checkerboard)
        if strcmp(sub,'001'), ses = '002'; end
        if strcmp(sub,'002'), ses = '001'; end

        if strcmp(analysis,'source_localization')
            band_pass_freq = [4 12];
            time_window    = [100 5900];       % ms
            ifsmoothed     = 1;
            mni_cordinates = [5.9 -72.9 6.1];  % default crosshair position
            roi_labels     = [108 109];        % right / left calcarine cortex

            conditionlabel1 = 'Left';
            eventtype1      = 'lef appeared';
            conditionlabel2 = 'Right';
            eventtype2      = 'rig appeared';
        end

    case 'grasping'                            % Experiment 5
        if strcmp(sub,'001'), ses = '002'; end
        if strcmp(sub,'002'), ses = '001'; end

        if strcmp(analysis,'source_localization')
            band_pass_freq = [13 30];          % beta
            time_window    = [-500 500];       % ms
            ifsmoothed     = 1;
            mni_cordinates = [-45.2 -27.0 48.2];
            roi_labels     = [183 177];        % left precentral / postcentral gyrus

            conditionlabel1 = 'Image';
            eventtype1      = 'ima appeared';
            conditionlabel2 = 'Move';
            eventtype2      = 'res yes';
        end

    case {'0back','2back'}                     % Experiment 6 (N-back)
        if strcmp(sub,'001'), ses = '004'; end
        if strcmp(sub,'002'), ses = '001'; end
        runs = {'001'};

        band_pass_freq = [4 8];                % theta
        time_window    = [0 1000];             % ms
        ifsmoothed     = 1;
        if strcmp(sub,'001')
            mni_cordinates = [4.9 34 52.56];
        else
            mni_cordinates = [-13.9 50.9 41.8];
        end
        roi_labels = [152 153];                % right / left superior frontal gyrus, medial segment

        conditionlabel1 = '2back';
        eventtype1      = 'str appeared';
        conditionlabel2 = '0back';
        eventtype2      = 'str appeared';

    otherwise
        error('Unknown task: %s', task{1});
end

%% 2) Toolboxes and input/output paths
spm_dir_add       = cfg.paths.spm;
data_add          = cfg.paths.data_root;
output_root       = cfg.paths.output_root;
analyse_OPMEG     = cfg.paths.analyse_opmeg;
functions         = cfg.paths.functions;
zapline           = cfg.paths.zapline;

save_data_add  = fullfile(output_root, ['sub-' sub], cell2mat(task), analysis, ...
    [conditionlabel2 '-' conditionlabel1], num2str(band_pass_freq));

if strcmp(task{1}, 'eyesOpenEyesClosed') && exist('intrest_freq_band','var')
    save_data_add = fullfile(output_root, ['sub-' sub], cell2mat(task), analysis, ...
        [conditionlabel2 '-' conditionlabel1], num2str(intrest_freq_band));
end

current_folder = pwd;
if ~exist(save_data_add, 'dir')
    mkdir(save_data_add);
end

addpath(genpath(analyse_OPMEG));
addpath(spm_dir_add);
addpath(functions);
addpath(zapline);
spm('defaults', 'eeg');

% Optional FieldTrip
if isfield(cfg.paths,'fieldtrip') && ~isempty(cfg.paths.fieldtrip)
    addpath(cfg.paths.fieldtrip);
    ft_defaults;
end

%% 3) Run
if strcmp(analysis,'movement_analysis')
    movement_analysis;

elseif strcmp(analysis,'bad_channel_pos')
    bad_channel_pos;

elseif stats_only
    % Re-run the permutation statistics and figures on the beamformer images
    % already in save_data_add (no preprocessing or source localisation).
    stats_permutation_F;
    enhance_figs

elseif only_plot
    % Redraw the figures from statistics already on disk. Rebuilds the two
    % variables enhance_figs needs (pref, tag) as stats_permutation_F does;
    % the smoothing prefix and nPerm must match the files on disk.
    % pref: smoothing prefix used by source_localization / stats_permutation_F
    if exist('ifsmoothed','var') && ifsmoothed
        pref = 'smoothed15';
    else
        pref = '';
    end

    % tag: '_svc_<roi_tag>' for an SVC run, '' for whole brain. Rebuilt exactly
    % as stats_permutation_F does, so the enhance_figs filename glob resolves.
    if exist('small_vol_cor','var') && small_vol_cor && ~isempty(roi_labels)
        hits = dir(fullfile(spm('Dir'), '**', 'labels_Neuromorphometrics.xml'));
        if ~isempty(hits)
            txt = fileread(fullfile(hits(1).folder, hits(1).name));
            tok = regexp(txt, '<index>\s*(\d+)\s*</index>\s*<name>(.*?)</name>', 'tokens');
            idxAll  = cellfun(@(c) str2double(c{1}), tok);
            nameAll = cellfun(@(c) strtrim(c{2}), tok, 'UniformOutput', false);
            parts = cell(1,numel(roi_labels));
            for k = 1:numel(roi_labels)
                jj = find(idxAll==roi_labels(k),1);
                if isempty(jj), parts{k} = sprintf('UNKNOWN(%d)',roi_labels(k));
                else,           parts{k} = nameAll{jj}; end
            end
            roi_name = strjoin(parts,' + ');
            roi_tag  = matlab.lang.makeValidName(strrep(roi_name,' + ','_'));
            tag = ['_svc_' roi_tag(1:min(100,length(roi_tag)))];
        else
            warning('Atlas XML not found; cannot rebuild SVC tag. Using tag="".');
            tag = '';
        end
    else
        tag = '';
    end

    enhance_figs

else
    preprocess;

    % Merge the two runs (or the 0-back/2-back pair)
    if (numel(runs) > 1 || numel(task) > 1)
        eD = merg_runs(eD1, eD2, current_folder, save_data_add);
    end

    if strcmp(analysis,'source_localization')
        source_localization;
        stats_permutation_F;
        enhance_figs
    elseif strcmp(analysis,'time_frequency')
        time_frequency;
    else
        error('Unknown analysis: %s', analysis);
    end
end
