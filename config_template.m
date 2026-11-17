% CONFIG_TEMPLATE  Machine-specific paths for the OPMVR analysis code
%
% Copy this file to config_local.m (in the repository folder) and edit the
% paths. config_local.m is listed in .gitignore and is not shared.

% Participant data (BIDS-like structure: sub-XXX/ses-XXX/{meg,anat,beh})
cfg.paths.data_root = '/path/to/data/Exp2-Main';

% Phantom (coil) recordings, used by ac_noise.m
cfg.paths.phantom_root = '/path/to/data/Exp1-Phantom';

% Excel file with the fluxgate (DC) measurements, used by dc_noise.m
cfg.paths.dc_noise_file = '/path/to/data/Exp0-Headset/Dc_test.xlsx';

% Output folder. enhance_figs.m reads the MNI152 template from
% <output_root>/mni152.nii.
cfg.paths.output_root = '/path/to/output';

% SPM installation folder (the folder that contains spm.m)
cfg.paths.spm = '/path/to/spm';

% analyse_OPMEG toolbox root (added with genpath)
cfg.paths.analyse_opmeg = '/path/to/analyse_OPMEG';

% zapline-plus toolbox root
cfg.paths.zapline = '/path/to/zapline-plus';

% Functions of this repository (relative to the repository folder)
cfg.paths.functions = 'functions/';

% Optional: a separate FieldTrip installation (otherwise the FieldTrip
% version shipped with SPM is used)
% cfg.paths.fieldtrip = '/path/to/fieldtrip';
