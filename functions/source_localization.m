%% SOURCE_LOCALIZATION  LCMV beamformer source localisation (DAiSS/SPM)
%
% Computes LCMV beamformer weights on a 5 mm grid constrained by the inner
% skull, writes one log-power image per trial and smooths each image with a
% 15 mm FWHM Gaussian kernel.
%
% Required variables in workspace (set in main.m):
%   eD             - epoched SPM M/EEG object
%   band_pass_freq - [fLow fHigh] frequency band for source analysis (Hz)
%   time_window    - [tStart tEnd] time window for covariance/output (ms)
%   save_data_add  - output folder (will contain BF folder + NIfTIs)
%   current_folder - folder to return to after processing
%
% Output:
%   Writes trial-wise power images (*_meg.nii) in save_data_add and a smoothed
%   copy of each image (smoothed15_*_meg.nii).
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

%% Initialise SPM (non-interactive)
spm('defaults','eeg');
spm_jobman('initcfg');

%% Basic checks
if ~exist('eD','var') || isempty(eD)
    error('eD not found. Make sure preprocessing/epoching ran and eD exists.');
end
if ~exist(save_data_add,'dir')
    mkdir(save_data_add);
end

freq_band = band_pass_freq;

%% --- DAiSS: Data ---
S = [];
S.D          = eD;
S.val        = 1;
S.gradsource = 'inv';
S.dir        = save_data_add;
S.space      = 'MNI-aligned';
BF = bf_wizard_data(S);

%% --- DAiSS: Sources / grid ---
S = [];
S.BF           = BF;
S.batch        = [];
S.reduce_rank  = [2 3];
S.keep3d       = true;
S.normalise_lf = true;
S.visualise    = true;
S.method       = 'grid';
S.grid.resolution = 5;
S.grid.constrain  = 'iskull';
BF = bf_wizard_sources(S);

%% --- DAiSS: Features (covariance) ---
S = [];
S.BF         = BF;
S.conditions = 'all';
S.method     = 'cov';
S.cov.foi    = freq_band;
S.cov.woi    = time_window;
S.reg        = 'clifftrunc';
S.visualise  = 1;
BF = bf_wizard_features(S);

%% --- DAiSS: Inverse (LCMV beamformer) ---
S = [];
S.BF     = BF;
S.method = 'lcmv';
BF = bf_wizard_inverse(S);

%% --- DAiSS: Output (trial-wise log power images) ---
S = [];
S.BF = BF;
S.foi = freq_band;
S.woi = time_window;
S.contrast = 1;              % single condition / per-trial output
S.method   = 'image_power';
S.(S.method).logpower    = true;
S.(S.method).result      = 'bytrial';
S.(S.method).scale       = 0;
S.(S.method).powermethod = 'trace';
BF = bf_wizard_output(S);

%% --- Write NIfTIs ---
cd(save_data_add);
S = [];
S.BF     = BF;
S.method = 'nifti';
BF = bf_wizard_write(S);

%% --- Smoothing ---
fwhm = [15 15 15];  % isotropic FWHM in mm

% Only smooth the DAiSS MEG output NIfTIs (pattern ends with _meg.nii)
niiFiles = dir(fullfile(save_data_add, '*_meg.nii'));
niiFiles = niiFiles(~startsWith({niiFiles.name}, 'smoothed'));

if isempty(niiFiles)
    warning('No *_meg.nii files found in %s. Skipping smoothing.', save_data_add);
else
    for i = 1:numel(niiFiles)
        inFile  = fullfile(save_data_add, niiFiles(i).name);
        outFile = fullfile(save_data_add, sprintf('smoothed%d_%s', fwhm(1), niiFiles(i).name));
        spm_smooth(inFile, outFile, fwhm);

        % After spm_smooth, re-mask to the brain so the Gaussian's edge-spillover
        % (a 15 mm kernel spreads edge power ~1-2 cm past the inner skull) is removed.
        Vsm = spm_vol(outFile);
        Ysm = spm_read_vols(Vsm);

        % Brain mask: reuse the beamformer's own analysis mask if present...
        maskfile = fullfile(save_data_add,'mask.nii');
        if exist(maskfile,'file')
            Vm = spm_vol(maskfile);
        else
            % ...otherwise derive it from the UNSMOOTHED image (in-grid = finite & nonzero)
            Vm = spm_vol(inFile);
        end
        Ym = spm_read_vols(Vm);
        brain = isfinite(Ym) & (Ym ~= 0);

        Ysm(~brain) = 0;
        spm_write_vol(Vsm, Ysm);

    end
end

%% Return to original folder
if exist('current_folder','var') && ~isempty(current_folder)
    cd(current_folder);
end
