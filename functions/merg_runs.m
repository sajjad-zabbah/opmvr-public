function [eD]= merg_runs(eD1,eD2,current_folder,save_data_add)
%MERG_RUNS Merge two SPM M/EEG objects (two runs, or the 0-back/2-back pair).
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

    cd(save_data_add);

    S = [];
    S.prefix = 'merged_'; % Prefix for the output file
    S.D = {eD1 , eD2 }; % List of MEG files to merge
    S.recode = 'same'; % Keep conditions as they are (or use 'merge' to combine conditions)
    eD = spm_eeg_merge(S);

    cd(current_folder);

end
