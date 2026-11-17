function trial_event = chktask_event_modify(trial_event, trial_log)
%CHKTASK_EVENT_MODIFY Add left/right labels to checkerboard events.
%
% The behavioural table (trial_event) does not explicitly store whether each
% checkerboard was presented on the left or right side. In our Unity log
% (trial_log), we store the checkerboard's x-position at the beginning of
% each stimulus presentation via messages that start with:
%   'RawImage local position updated'
%
% Negative x positions are treated as LEFT, positive as RIGHT.
% This function prefixes the corresponding trial_event.image entry with
% 'left_' or 'right_' for checkerboard stimuli (image label starting 'ch').
%
% Inputs
%   trial_event : table with fields at least:
%                 - stimulus_number (0-based indexing in current pipeline)
%                 - image (cell array of char/strings)
%   trial_log   : table with field:
%                 - message (cell array of char/strings)
%
% Output
%   trial_event : modified table with updated trial_event.image labels.
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

% --- Identify log entries containing the stimulus position updates
msg = trial_log.message;
isPosMsg = startsWith(msg, 'RawImage local position updated');

pos_msgs = msg(isPosMsg);

% Extract numeric x-position from each message using regex.
% This grabs the FIRST floating-point number in the message.
stim_x = nan(numel(pos_msgs), 1);
for k = 1:numel(pos_msgs)
    tok = regexp(pos_msgs{k}, '(-?\d+\.?\d*)', 'match', 'once');
    if ~isempty(tok)
        stim_x(k) = str2double(tok);
    end
end

% Remove any messages where parsing failed
valid = ~isnan(stim_x);
stim_x = stim_x(valid);

% Map x-position to left/right labels
stim_side = cell(numel(stim_x), 1);
stim_side(stim_x < 0) = {'left'};
stim_side(stim_x > 0) = {'right'};

% Determine number of trials expected from behavioural file
num_tr = max(trial_event.stimulus_number) + 1;

% --- Update trial_event.image labels
for t = 1:num_tr
    % Find the first row matching this stimulus number AND a checkerboard image
    idx = find( trial_event.stimulus_number == (t-1) & ...
                cellfun(@(x) ischar(x) && numel(x) >= 2 && strcmp(x(1:2),'ch') ...
                             || (isstring(x) && strlength(x) >= 2 && strcmp(extractBetween(x,1,2),'ch')), ...
                        trial_event.image) );

    if isempty(idx)
        continue;
    end
    idx = idx(1);

    old_label = trial_event.image{idx};
    trial_event.image{idx} = sprintf('%s_%s', stim_side{t}, old_label);
end
end
