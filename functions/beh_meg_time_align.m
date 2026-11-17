function [time_shift, shift_std, events] = beh_meg_time_align(D, trgInd, trial_event, trial_event_log, task, wantfig)
%BEH_MEG_TIME_ALIGN Align Unity behavioral timestamps with MEG triggers.
%
% This function compares trigger times in:
%   - Unity log (trial_event_log)
%   - MEG trigger channel (D(trgInd,:))
%
% We expect a constant delay between the two clocks. Large variability
% suggests missing/delayed triggers or logging issues.
%
% Outputs:
%   time_shift : mean(Unity_time - MEG_time) across triggers
%   shift_std  : std of that difference
%   events     : SPM-style events struct (type/time/value/image)
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

%% -------------------- Restrict log to current run time window --------------------
% trial_event is run-specific, but trial_event_log may include multiple runs.
valid_time = find(trial_event.time(end) >= trial_event_log.timestamp & ...
               (trial_event.time(1)-10 ) <= trial_event_log.timestamp);
trial_event_log = trial_event_log(valid_time, :);

%% -------------------- Detect triggers --------------------
s = D(trgInd,:);

% MEG triggers: rising edges (0 -> 1)
meg_time_ind = find(s(1:end-1) < 1 & s(2:end) > 0);

% Unity triggers
beh_time_ind = find(strcmp(trial_event_log.message,'@TRIGGEREVENT StartTrial : 1'));

if wantfig
    figure;
    plot(D.time(meg_time_ind)); hold on;
    plot(trial_event_log.timestamp(beh_time_ind));
    title("Trigger registered time before shifting");
    legend({'OPM time','Unity time'}, 'Box','off');
    xlabel('Trigger number');
    ylabel('Trigger time (s)');
end

%% -------------------- Handle potential off-by-one in trigger counts --------------------
meg_t   = D.time(meg_time_ind)';                   % MEG trigger times (s)
beh_t   = trial_event_log.timestamp(beh_time_ind); % Unity trigger times (s)

d = length(meg_time_ind) - length(beh_time_ind);
f = 0; g = 0;
if d > 0
    g = d;     % extra MEG triggers
    warning('Something might be wrong, MEG has more triggeres than Behavioural')
else
    f = abs(d);% extra behavioral triggers
end

% Compute delay (Unity - MEG)
diffs = trial_event_log.timestamp(beh_time_ind(f+1:end))' - D.time(meg_time_ind(g+1:end));
time_shift = mean(diffs);
shift_std  = std(diffs);

% Plotting
if wantfig
    figure;
    plot(diffs);
    title("Trigger time differences (Unity - OPM)");
    xlabel("Trigger number");
    ylabel("Time difference (s)");
end

if wantfig
    figure;
    plot(D.time(meg_time_ind(g+1:end))); hold on;
    plot(trial_event_log.timestamp(beh_time_ind(f+1:end)));
    title("Trigger registered time after shifting");
    legend({'OPM time','Unity time'}, 'Box','off');
    xlabel('Trigger number');
    ylabel('Trigger time (s)');
end

if shift_std > 0.010
    warning('Trigger alignment variability is high (std > 10 ms). Check trigger alignment plots/logs');

    % Re-estimate the lag: shift one trigger train by 0-4 triggers and keep
    % the shift that minimises the variability of the time differences.
    fprintf('Re-estimating the lag from the trigger-time differences\n');

    i=1;
    ml = fix(min(length(meg_t),length(beh_t))); % compare the same number of triggers
    meg_t = meg_t(1:ml);
    beh_t = beh_t(1:ml);
    for shift=1:5
        meg_delay_std(i) = std(meg_t(shift:ml)-beh_t(1:ml-(shift-1)));
        beh_delay_std(i) = std(beh_t(shift:ml)-meg_t(1:ml-(shift-1)));
        i=i+1;
    end
    if  min(beh_delay_std)<min(meg_delay_std)
        [~,sh_beh] = min(beh_delay_std);
        beh_t = beh_t(sh_beh:end);
        meg_t = meg_t(1:end-(sh_beh-1));
    else
        [~,sh_meg] = min(meg_delay_std);
        meg_t = meg_t(sh_meg:end);
        beh_t = beh_t(1:end-(sh_meg-1));
        warning('The MEG trigger train was shifted relative to the Unity log; check the alignment plots.')
    end

    % recalculate time shift
    diffs =  beh_t - meg_t;
    time_shift = mean(diffs);
    shift_std  = std(diffs);

    if shift_std > 0.010
    warning('Lag re-estimation failed (std > 10 ms). Check trigger alignment plots/logs');
    end

    figure;
    plot(diffs);
    title("Trigger time differences (Unity - OPM)");
    xlabel("Trigger number");
    ylabel("Time difference (s)");

    % Sanity check plot after correction
    figure
    plot(meg_t)
    hold on
    plot (beh_t)
    title("Trigger registered time after re-estimating the lag");
    legend({'OPM time','Unity time'}, 'Box','off');
    xlabel('Trigger number');
    ylabel('Trigger time (s)');
end

%% -------------------- Ensure trial_event.image exists --------------------
vn = trial_event.Properties.VariableNames;
if ~ismember('image', vn)
    trial_event.image = trial_event.word;
end

%% -------------------- Task-specific event labeling --------------------
if strcmp(task,'0back') || strcmp(task,'2back')
    for j = 1:length(trial_event.word)
        if (length(trial_event.word{j}) == 1 && trial_event.stimulus_number(j) >= 2 && strcmp(trial_event.appearance(j),'appeared'))
            trial_event.image{j} = 'str';
        end
    end

    trial_event = sortrows(trial_event,'time');
end

if strcmp(task,'grasping')
    for j = 1:length(trial_event.image)
        if ismember(trial_event.image{j}(1:3), {'car','fac'})
            t = trial_event(j,:);
            t.image = {'image'};
            trial_event = [trial_event; t]; %#ok<AGROW>
        end

        % Mark repeated/unsignaled responses (avoid j-1 crash)
        if strcmp(trial_event.image{j}, 'response') && j > 1 ...
                && ~strcmp(trial_event.image{j-1}, 'question')
            trial_event.image{j} = 'uninstructed response';
        end
    end
    trial_event = sortrows(trial_event,'time');
end

%% -------------------- Build SPM events struct --------------------
events = struct('type',{},'time',{},'value',{},'image',{});
for i = 1:length(trial_event.time)
    % Find closest MEG time sample after shifting
    [min_val(i), ind] = min(abs(trial_event.time(i) - (D.time + time_shift)));

    len = min(length(trial_event.image{i}), 3);
    events(i).type  = [trial_event.image{i}(1:len) ' ' trial_event.appearance{i}];
    events(i).time  = D.time(ind);
    events(i).value = trial_event.trigger(i);
    events(i).image = trial_event.image(i);
end

fprintf('Mean event-to-sample time difference after alignment: %.4f s\n', mean(min_val(2:end)));
end
