%% BAD_CHANNEL_POS  Plot the positions of the excluded (bad) channels
%
% Called from main.m (analysis = 'bad_channel_pos'). For each task/run, loads
% the data, marks the bad channels listed in badchannels.xlsx and plots all
% sensors on the scalp mesh with the bad channels in red (Supplementary
% Figure 2).
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

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

        % ----- Check required files exist
        must_exist = {meg_data_add, sens_positions_add, mri_file_add, bad_channel_add, bad_trials_add};
        for k = 1:numel(must_exist)
            if ~exist(must_exist{k},'file')
                error('Missing required file: %s', must_exist{k});
            end
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
        S.lead      = 0;

        if load_raw_data
            % Read raw data (project-specific format)
            D = spm_opm_create(S);
        else
            % Load existing SPM MEEG object
            D = spm_eeg_load(meg_data_add);
        end

        %% ------------------------- 6) Mark bad channels -------------------------
        D = badchannels(D, badChanIndices', 1);
        badChannels  = D.badchannels();

        %% ------------------------- 7) Plot Bad Channels -------------------------

        figure('Name', sprintf('Bad Channels: %s Run %s', task{j}, runs{i}), 'Color', 'w');
        hold on;

        % 1. Get sensor information from the SPM object
        sens = D.sensors('MEG');

        % 2. Plot all sensors as small discs
        ft_plot_sens(sens, 'coilshape', 'disc', 'facecolor', [0.1 0.5 0.0]);

        % 3. Extract and plot the scalp mesh (if available in the inv field)
        try
            % Attempt to grab mesh from SPM's inv structure
            scalp = ft_read_headshape(D.inv{1}.mesh.tess_scalp);
            ft_plot_mesh(scalp, 'edgecolor', [0.7 0.7 0.7], 'facealpha', 0.1, 'edgealpha', 0.2);
        catch
            % Mesh not available: plot sensors only
            warning('Scalp mesh not found in D.inv. Plotting sensors only.');
        end

        % 4. Plot the bad sensors specifically as red '+' signs
        if ~isempty(badChannels)
            bad_pos = sens.chanpos(badChannels, :);
            scatter3(bad_pos(:,1), bad_pos(:,2), bad_pos(:,3), 20, 'r', 'filled', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.2, 'DisplayName', 'Bad Channels');
        end

        % 5. Aesthetic formatting
        axis tight;
        axis equal;
        grid on;

        set(gcf, 'Units', 'centimeters', 'Position', [10 10 5 5]);
        set(gcf, 'Color', 'w');
        exportgraphics(gcf, fullfile(save_data_add, 'BadChannel.tif'), 'Resolution', 600);
    end
end
