%% MOVEMENT_ANALYSIS  Head and hand displacement during the tasks (Figure 6)
%
% For every trial of the checkerboard (Exp4), grasping (Exp5), 0-back/2-back
% (Exp6) and imagination (Exp7) tasks, the head and right-hand tracker
% positions are taken from fixation onset to the next response, referenced to
% the trial-onset position, and the maximum translational displacement is
% computed. Produces boxplots of the maximum displacement and example 3D
% trajectories (two randomly sampled trials per task).
%
% Required workspace variables (set in main.m): sub, data_add, output_root,
% analysis
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

% Initialise containers
all_max_dist_head = [];
all_max_dist_hand = [];
all_traj_head     = {};
all_traj_hand     = {};
task_id_list      = [];

save_data_add = fullfile(output_root, ['sub-' sub], analysis);
if ~exist(save_data_add, 'dir'), mkdir(save_data_add); end

all_task={'chk','grasping','0back','2back','imagination'};
Legend_Names = {'Exp4', 'Exp5' , 'Exp6(0bk)' , 'Exp6(2bk)' , 'Exp7'};

if strcmp(sub,'001')
    all_ses ={'002','002','004','004','004'};
else
    all_ses ={'001','001','001','001','002'};
end

for j = 1:numel(all_task)
    current_task_name = all_task{j};
    ses = all_ses{j};

    % Define runs based on task
    if ismember(current_task_name, {'0back', '2back'})
        runs = {'001'};
    else
        runs = {'001','002'};
    end

    for i = 1:numel(runs)
        %% 1) Locate & Load Data
        bids = struct('directory', data_add, 'sub', sub, 'ses', ses, 'task', current_task_name, 'run', runs{i});
        cfg  = struct('derivative', false, 'detailed', true, 'description', 'folderOnly');
        [~, ~, ses_folder] = bidsFilename(cfg, bids);

        % Load Tables
        trial_event = readtable(fullfile(ses_folder,'beh',sprintf('%s_run-%s',bids.task,bids.run),'othertrialdata','presentationTime_T001.csv'));
        head_data   = readtable(fullfile(ses_folder,'beh',sprintf('%s_run-%s',bids.task,bids.run),'trackers','head_movement_T001.csv'));
        hand_data   = readtable(fullfile(ses_folder,'beh',sprintf('%s_run-%s',bids.task,bids.run),'trackers','righthand_movement_T001.csv'));

        if ~ismember('image', trial_event.Properties.VariableNames), trial_event.image = trial_event.word; end

        %% 2) Sync Fixation Labels (Task Specific)
        if strcmp(current_task_name,'imagination')
            for k = 1:length(trial_event.word)-1
                if (strcmp(trial_event.appearance{k+1},'disappeared') && strcmp(trial_event.appearance{k}, 'appeared')), trial_event.image{k} = 'fixation apears'; end
            end
        elseif ismember(current_task_name, {'0back','2back'})
            for k = 2:length(trial_event.word)
                if (strcmp(trial_event.word{k-1}, 'response') && strcmp(trial_event.appearance{k}, 'appeared')), trial_event.image{k} = 'fixation apears'; end
            end
        elseif strcmp(current_task_name,'grasping')
            for k = 1:length(trial_event.image)
                if trial_event.trigger(k) == 502, trial_event.image{k} = 'fixation apears'; end
            end
        end

        %% 3) Extract Trial Data for Head and Hand
        fix_idx  = find(strcmpi(strtrim(trial_event.image), 'fixation apears'));
        resp_idx = find(strcmpi(strtrim(trial_event.image), 'response'));

        for f = 1 : numel(fix_idx)
            next_resp = resp_idx(resp_idx > fix_idx(f));
            if isempty(next_resp), continue; end

            t_start = trial_event.time(fix_idx(f));
            t_end   = trial_event.time(next_resp(1));

            % Process Head
            m_hd = head_data.time >= t_start & head_data.time <= t_end;
            if any(m_hd)
                xh = head_data.pos_x(m_hd)*1e3; yh = head_data.pos_y(m_hd)*1e3; zh = head_data.pos_z(m_hd)*1e3;
                p0h = [xh(1), yh(1), zh(1)];
                all_max_dist_head = [all_max_dist_head; max(sqrt((xh-p0h(1)).^2 + (yh-p0h(2)).^2 + (zh-p0h(3)).^2))];
                all_traj_head{end+1} = [xh-p0h(1), yh-p0h(2), zh-p0h(3)];
                task_id_list = [task_id_list; j];
            end

            % Process Hand (Identical logic)
            m_hn = hand_data.time >= t_start & hand_data.time <= t_end;
            if any(m_hn)
                xw = hand_data.pos_x(m_hn)*1e3; yw = hand_data.pos_y(m_hn)*1e3; zw = hand_data.pos_z(m_hn)*1e3;
                p0w = [xw(1), yw(1), zw(1)];
                all_max_dist_hand = [all_max_dist_hand; max(sqrt((xw-p0w(1)).^2 + (yw-p0w(2)).^2 + (zw-p0w(3)).^2))];
                all_traj_hand{end+1} = [xw-p0w(1), yw-p0w(2), zw-p0w(3)];
            end
        end
    end
end

%% -------------------- Final Plotting --------------------
task_colors = lines(numel(all_task));

% 1. 3D Head
plot_trajectories(all_traj_head, task_id_list, task_colors, Legend_Names, fullfile(save_data_add, 'Head_Trajectories.pdf'));

% 2. 3D Hand
plot_trajectories(all_traj_hand, task_id_list, task_colors, Legend_Names, fullfile(save_data_add, 'Hand_Trajectories.pdf'));

% 3. Boxplots Head
figure('Units', 'centimeters', 'Position', [18 5 8 6], 'Color', 'w');
boxplot(all_max_dist_head, Legend_Names(task_id_list), 'Colors', task_colors, 'Notch', 'on');
box off
ylabel('Max Displacement (mm)'); xtickangle(45);
exportgraphics(gcf, fullfile(save_data_add, 'Boxplot_Head.pdf'));

% 4. Boxplots Hand
figure('Units', 'centimeters', 'Position', [18 16 8 6], 'Color', 'w');
boxplot(all_max_dist_hand, Legend_Names(task_id_list), 'Colors', task_colors, 'Notch', 'on');
box off
ylabel('Max Displacement (mm)'); xtickangle(45);
exportgraphics(gcf, fullfile(save_data_add, 'Boxplot_Hand.pdf'));

%% Local function: 3D trajectory plots
function plot_trajectories(traj_cell, id_list, colors, names, save_path)
    figure('Units', 'centimeters', 'Position', [5 5 8 6], 'Color', 'w'); hold on;
    h_leg = gobjects(numel(names), 1);
    for j = 1:numel(names)
        t_idx = find(id_list == j);
        if isempty(t_idx), continue; end
        rng(42); subset = t_idx(randperm(numel(t_idx), min(2, numel(t_idx))));
        for k = 1:numel(subset)
            tr = traj_cell{subset(k)};
            p = plot3(tr(:,1), tr(:,2), tr(:,3), 'Color', [colors(j,:), 0.4], 'LineWidth', 2, 'HandleVisibility', 'off');
            if k==1, h_leg(j) = p; p.HandleVisibility = 'on'; end
            plot3(tr(end,1), tr(end,2), tr(end,3), 'x', 'Color', colors(j,:), 'HandleVisibility', 'off');
        end
    end
    grid on; view(45,30); xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
    lgd=legend(h_leg, names, 'Box', 'off');
    set(lgd, 'Units', 'normalized'); % Ensure units are normalized
    set(lgd, 'Position', [0.75, 0.80, 0.15, 0.10]);
    exportgraphics(gcf, save_path, 'ContentType', 'vector');
end
