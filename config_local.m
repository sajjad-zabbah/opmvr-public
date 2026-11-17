% config_template.m
% Copy this file to config_local.m and edit the paths for your machine.
%
% This file is intentionally NOT called by default in GitHub workflows.
% (You should add config_local.m to .gitignore.)

% Root folder that contains the raw data (BIDS-like structure used in this project)
cfg.paths.data_root = 'D:\Sajjad\Experiment_5_HMDOPM\ExperimentsAndData\Data\Exp2-Main';
%cfg.paths.data_root = '/Volumes/ritd-ag-project-rd0182-dbach45/MEG/OPMHMD/Exp2-Main/';
%cfg.paths.data_root = '/Users/sajjadzabbah/Documents/Work/UCL/Experiemnt_5/data/Exp2-main';
cfg.paths.data_root = '/Volumes/SajjadUCL/Experiment_5_HMDOPM/Experiment_5_HMDOPM/3-Data/Exp2-main';
%cfg.paths.data_root = '/Volumes/SajjadUCL/Experiment_5_HMDOPM/Experiment_5_HMDOPM/others/Back/BackupData/Data/Exp2-main';
cfg.paths.data_root = 'E:\Experiment_5_HMDOPM\Experiment_5_HMDOPM\3-Data\Exp2-main';



% Where outputs will be written
cfg.paths.output_root = 'D:\Sajjad\Experiment_5_HMDOPM\ExperimentsAndData\Analysis\Out\ProcessedData';
cfg.paths.output_root = '/Users/sajjadzabbah/Documents/Work/UCL/Experiemnt_5/4-Analysis/Out';
cfg.paths.output_root = 'D:\Sajjad\Others\BachLab\EXP_5\2-Analysis\out';


% SPM installation folder (the folder that contains spm.m)
cfg.paths.spm = 'D:\Sajjad\Softs\Packages\spm25\spm';
cfg.paths.spm = '/Users/sajjadzabbah/Documents/Work/UCL/Packages/spm';
cfg.paths.spm = 'D:\Sajjad\Softs\SPM';

% analyse_OPMEG toolbox root (will be added with genpath)
cfg.paths.analyse_opmeg = 'D:\Sajjad\Softs\Packages\analyse_OPMEG';
cfg.paths.analyse_opmeg = '/Users/sajjadzabbah/Documents/Work/UCL/Packages/analyse_OPMEG';
cfg.paths.analyse_opmeg = 'D:\Sajjad\Softs\analyse_OPMEG';

% required functions
cfg.paths.functions = 'functions/';
% Optional: FieldTrip root (if you use dipole fitting / FieldTrip functions)
%cfg.paths.fieldtrip = 'D:\Sajjad\Softs\fieldtrip';


cfg.paths.zapline = 'D:\Sajjad\Softs\zapline-plus' ;

% Paths for the standalone noise scripts (ac_noise.m, psd_hmdon_hmdoff.m, dc_noise.m)
cfg.paths.phantom_root  = 'E:\Experiment_5_HMDOPM\Experiment_5_HMDOPM\3-Data\Exp1-Phantom';
cfg.paths.dc_noise_file = 'E:\Experiment_5_HMDOPM\Experiment_5_HMDOPM\3-Data\Exp0-Headset\Dc_test.xlsx'; % check file name
