%% PREPROCESS  Preprocessing pipeline for the participant experiments
%
% Called from main.m. For each task and run this script:
%   1) locates the BIDS-formatted OPM-MEG, MRI and behavioural files,
%   2) loads (or creates) the SPM M/EEG object,
%   3) aligns the behavioural (Unity) events to the MEG triggers,
%   4) marks bad channels (listed in badchannels.xlsx in the MEG folder),
%   5) low-pass filters (90 Hz), downsamples participant 1 to 375 Hz,
%      high-pass filters (2 Hz) and removes 50 Hz line noise (Zapline-plus),
%   6) applies adaptive multipole models (AMM) and the analysis-specific
%      band-pass filter,
%   7) epochs the data and marks bad trials (listed in badtrials.xlsx).
%
% Required workspace variables (set in main.m):
%   sub, ses, task, runs, data_add, analysis
%   load_raw_data, delet_spm_file
%   band_pass_freq, time_window
%   conditionlabel1/2, eventtype1/2
%   eoec_epoch_len, eo_window, ec_window (eyes-open/closed source localisation)
%
% Dependencies:
%   - SPM (incl. the OPM functions spm_opm_create / spm_opm_amm)
%   - analyse_OPMEG (bidsFilename)
%   - zapline-plus (clean_data_with_zapline_plus)
%   - chktask_event_modify.m, beh_meg_time_align.m
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

%% ------------------------- 0) Parameters -------------------------
% Downsampling rate for participant 1 (matches the sampling rate of participant 2)
dws = 375;

% AMM correlation threshold
amm_corlim = 0.95;

% Trigger channel index (participant-specific)
if strcmp(sub,'001')
    trgInd = 169;
elseif strcmp(sub,'002')
    trgInd = 191;
else
    error('Unknown subject ID: %s. Please update trigger index mapping.', sub);
end

%% ------------------------- 1) Optional cleanup ---------------------------
% Delete intermediate SPM files in the MEG folder
if delet_spm_file
    bids = struct();
    bids.directory = data_add;
    bids.sub       = sub;
    bids.ses       = ses;

    cfg = struct();
    cfg.derivative  = false;
    cfg.category    = 'meg';
    cfg.detailed    = true;
    cfg.description = 'meg';
    [~, meg_folder, ~] = bidsFilename(cfg,bids);

    if exist(meg_folder,'dir')
        delete(fullfile(meg_folder, '*.dat'));
        delete(fullfile(meg_folder, '*.mat'));
    else
        warning('MEG folder not found (nothing deleted): %s', meg_folder);
    end
end

%% ------------------------- 2) Locate & load data -------------------------
for j = 1:numel(task)
    for i = 1:numel(runs)

        % ----- Build BIDS identifiers
        bids = struct();
        bids.directory = data_add;
        bids.sub       = sub;
        bids.ses       = ses;
        bids.task      = task{j};
        bids.run       = runs{i};

        % ----- Session folder (used to locate MRI/behaviour)
        cfg = struct();
        cfg.derivative  = false;
        cfg.detailed    = true;
        cfg.description = 'folderOnly';
        [~, ~, ses_folder] = bidsFilename(cfg,bids);

        % ----- MEG data file (raw .lvm or saved .mat)
        cfg = struct();
        cfg.derivative  = false;
        cfg.category    = 'meg';
        cfg.detailed    = true;
        cfg.description = 'meg';
        cfg.type        = '.lvm';
        if ~load_raw_data
            cfg.type = '.mat';
        end
        [meg_data_name, meg_folder, meg_data_add] = bidsFilename(cfg,bids);

        % ----- Sensor positions TSV
        cfg.type        = '.tsv';
        cfg.description = 'meg_positions';
        [~, ~, sens_positions_add] = bidsFilename(cfg,bids);

        % ----- Structural MRI path
        mri_file_add = fullfile(ses_folder,'anat',sprintf('sub-%s_mri.nii', sub));

        % ----- Bad channels/trials tables (project-specific convention)
        bad_channel_add = fullfile(meg_folder,'badchannels.xlsx');
        bad_trials_add  = fullfile(meg_folder,'badtrials.xlsx');

        % ----- Behavioural logs (not present for eyesOpenEyesClosed)
        trial_event_add = fullfile(ses_folder,'beh',sprintf('%s_run-%s',bids.task,bids.run), ...
                                   'othertrialdata','presentationTime_T001.csv');
        trial_event_log_add = fullfile(ses_folder,'beh',sprintf('%s_run-%s',bids.task,bids.run), ...
                                       'sessionlog','log.csv');

        % ----- Check required files exist
        must_exist = {meg_data_add, sens_positions_add, mri_file_add, bad_channel_add, bad_trials_add};
        for k = 1:numel(must_exist)
            if ~exist(must_exist{k},'file')
                error('Missing required file: %s', must_exist{k});
            end
        end
        if ~strcmp(bids.task,'eyesOpenEyesClosed')
            if ~exist(trial_event_add,'file');     error('Missing file: %s', trial_event_add); end
            if ~exist(trial_event_log_add,'file'); error('Missing file: %s', trial_event_log_add); end
        end

        %% ------------------------- 3) Read behaviour + QC lists -------------------------
        if ~strcmp(bids.task,'eyesOpenEyesClosed')
            trial_event     = readtable(trial_event_add);
            trial_event_log = readtable(trial_event_log_add);
        end

        % Read bad channels / trials
        % NOTE: readtable cannot use '-' in variable names -> replace with '_'
        dataTable      = readtable(bad_channel_add);
        varName        = strrep(meg_data_name(1:end-4),'-','_');
        badChanIndices = dataTable.(varName);
        badChanIndices(isnan(badChanIndices)) = [];

        dataTable    = readtable(bad_trials_add);
        badTrIndices = dataTable.(varName);
        badTrIndices(isnan(badTrIndices)) = [];

        %% ------------------------- 4) Load MEG into SPM -------------------------
        S = struct();
        S.data      = meg_data_add;
        S.sMRI      = mri_file_add;
        S.positions = sens_positions_add;
        S.lead      = 1;

        if load_raw_data
            % Read raw data (project-specific format)
            D = spm_opm_create(S);
        else
            % Load existing SPM MEEG object
            D = spm_eeg_load(meg_data_add);
        end
        %% ------------------------- 5) Trigger / event alignment -------------------------
        if strcmp(bids.task,'chk')
            trial_event = chktask_event_modify(trial_event, trial_event_log);
        end

        if ~strcmp(bids.task,'eyesOpenEyesClosed')
            [time_shift, shift_std, tr_event] = beh_meg_time_align( ...
                D, trgInd, trial_event, trial_event_log, bids.task, 1);
            D = events(D, 1, tr_event);
            D.save;
        end

        %% ------------------------- 6) Mark bad channels -------------------------
        D = badchannels(D, badChanIndices', 1);
        badChannels  = D.badchannels();
        goodChannels = setdiff(D.indchantype('MEG'), badChannels);

        %% ------------------------- 7) Filtering + downsampling -------------------------
        % Anti-alias low-pass (before downsampling)
        S = struct();
        S.D    = D;
        S.freq = 90;      % must be < newFs/2; also < dws/2 if downsampling
        S.band = 'low';
        fD = spm_eeg_ffilter(S);

        % Downsample participant 1 to match the sampling rate of participant 2
        if strcmp(bids.sub,'001')
            S = struct();
            S.fsample_new = dws;
            S.D           = fD;
            fD = spm_eeg_downsample(S);
        end

        % High-pass (drift removal, before AMM)
        S = struct();
        S.D    = fD;
        S.freq = 2;
        S.band = 'high';
        fD = spm_eeg_ffilter(S);

        % Line-noise removal (50 Hz and harmonics) with Zapline-plus
        zapline_freqs = 50;

        fs = fsample(fD);
        [zapped_data,~,~,~] = clean_data_with_zapline_plus( ...
            squeeze(fD(goodChannels,:)), fs, 'noisefreqs', zapline_freqs, 'plotResults', 0);
        assert(isequal(size(zapped_data), size(squeeze(fD(goodChannels,:)))), ...
            'Zapline changed size/channel order.');
        fD(goodChannels,:,1) = zapped_data;
        fD.save;

        %% ------------------------- 8) AMM denoising (broadband) -------------
        % AMM is adaptive: it estimates the external-interference subspace from
        % the data it is given, so it must see BROADBAND data (before the
        % analysis-specific band-pass).
        S = struct();
        S.D       = fD;
        S.corrLim = amm_corlim;
        mD = spm_opm_amm(S);

        %% ------------------- 8b) Band-pass (analysis-specific) --------------
        % Applied to the AMM output.
        S = struct();
        S.D    = mD;
        S.freq = band_pass_freq;
        S.band = 'bandpass';
        mD = spm_eeg_ffilter(S);

        %% --- Artificial epochs for eyes-open/closed source localisation ---
        % No triggers exist for this task: cut the continuous recording into
        % fixed-length windows, labelling eyes-open vs eyes-closed by TIME.
        % Only when source-localising; the time_frequency path stays continuous.
        eoec_srcloc = strcmp(task{j},'eyesOpenEyesClosed') && ...
                      strcmp(analysis,'source_localization');
        if eoec_srcloc
            eo_on = eo_window(1) : eoec_epoch_len : (eo_window(2) - eoec_epoch_len);
            ec_on = ec_window(1) : eoec_epoch_len : (ec_window(2) - eoec_epoch_len);
            ev = struct('type',{},'time',{},'value',{},'duration',{},'offset',{});
            for on = eo_on
                ev(end+1) = struct('type','eo_epoch','time',on,'value',1,'duration',[],'offset',[]); %#ok<AGROW>
            end
            for on = ec_on
                ev(end+1) = struct('type','ec_epoch','time',on,'value',2,'duration',[],'offset',[]); %#ok<AGROW>
            end
            mD = events(mD, 1, ev);
            mD.save;
            fprintf('EO/EC: inserted %d eyes-open + %d eyes-closed artificial epochs (%.1f s each).\n', ...
                    numel(eo_on), numel(ec_on), eoec_epoch_len);
        end

        %% ------------------------- 9) Epoching -------------------------
        S = struct();
        S.D       = mD;
        S.timewin = time_window;

        % Define trial conditions depending on task. The 0-back and 2-back
        % tasks are recorded in separate runs, each holding one condition.
        if strcmp(task{j},'0back')
            S.trialdef(1).conditionlabel = conditionlabel2;
            S.trialdef(1).eventtype      = eventtype2;
            S.trialdef(1).eventvalue     = [];
            S.trialdef(1).trlshift       = 0;

        elseif strcmp(task{j},'2back')
            S.trialdef(1).conditionlabel = conditionlabel1;
            S.trialdef(1).eventtype      = eventtype1;
            S.trialdef(1).eventvalue     = [];
            S.trialdef(1).trlshift       = 0;

        elseif eoec_srcloc || strcmp(task{j},'chk') || strcmp(task{j},'grasping')
            S.trialdef(1).conditionlabel = conditionlabel1;
            S.trialdef(1).eventtype      = eventtype1;
            S.trialdef(1).eventvalue     = [];
            S.trialdef(1).trlshift       = 0;

            if ~isempty(conditionlabel2)
                S.trialdef(2).conditionlabel = conditionlabel2;
                S.trialdef(2).eventtype      = eventtype2;
                S.trialdef(2).eventvalue     = [];
                S.trialdef(2).trlshift       = 0;
            end
        end

        if ~strcmp(task{j},'eyesOpenEyesClosed') || eoec_srcloc
            S.bc           = 1;
            S.prefix       = 'e';
            S.eventpadding = 0;
            eD = spm_eeg_epochs(S);
        else
            % Keep continuous for eyes-open/closed (time_frequency path)
            eD = mD;
        end

        %% ------------------------- 10) Mark bad trials -------------------------
        eD = badtrials(eD, badTrIndices', 1);
        eD.save;

        %% ------------------------- 11) Store outputs per run/task -------------------------
        % eD1/eD2 are merged in main.m (two runs, or the 0-back/2-back pair).
        if numel(runs) > 1
            eval(sprintf('eD%d = eD;', i));
        elseif numel(task) > 1
            eval(sprintf('eD%d = eD;', j));
        end

    end
end
