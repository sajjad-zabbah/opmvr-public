function badTrials = psd_trial_reviewer(eD, opts)
% PSD_TRIAL_REVIEWER  Step through epoched trials, view the per-trial PSD of all
% MEG channels overlaid, and mark bad trials by keypress. Saves the bad-trial
% list to file (does NOT modify eD).
%
% Usage:
%   badTrials = psd_trial_reviewer(eD);
%   badTrials = psd_trial_reviewer(eD, opts);
%
% Keys (focus must be on the figure):
%   g / space / ->   mark GOOD  and advance
%   b / down         mark BAD   and advance
%   p / <-           go to PREVIOUS trial (re-decide)
%   s                save now
%   q / Esc          save and quit
%
% opts (all optional):
%   .outfile         CSV of bad-trial numbers        (default badtrials_review.csv in pwd)
%   .excludeBadChan  drop channels already in badchannels(eD) (default true)
%   .win_s           Welch segment length (s)        (default min(1, epoch length))
%
% Resume: progress is stored in <outfile>.progress.mat; re-running resumes where
% you left off. Auto-saves every 25 decisions and on quit.
%
% The display is limited to 0-40 Hz. Per-trial PSD uses pwelch (spm_opm_psd
% has no per-trial mode). Optional quality-control tool; not called by main.m.
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

if nargin < 2, opts = struct(); end
if ~isfield(opts,'outfile'),        opts.outfile        = fullfile(pwd,'badtrials_review.csv'); end
if ~isfield(opts,'excludeBadChan'), opts.excludeBadChan = true; end

fs      = fsample(eD);
nT      = ntrials(eD);
ns      = nsamples(eD);
if ~isfield(opts,'fmax') || isempty(opts.fmax), opts.fmax = fs/2; end
if ~isfield(opts,'win_s'),  opts.win_s = min(1, ns/fs); end

% --- MEG channels ---
chans = indchantype(eD, 'MEG');
if opts.excludeBadChan
    chans = setdiff(chans, badchannels(eD), 'stable');
end
assert(~isempty(chans), 'No MEG channels found.');
fprintf('%d trials | %d MEG channels%s | fs = %g Hz | epoch %.3f s\n', ...
    nT, numel(chans), tern(opts.excludeBadChan,' (good only)',''), fs, ns/fs);

% --- Welch settings (fixed across trials -> identical frequency axis) ---
win   = min(ns, max(16, round(opts.win_s*fs)));
nover = floor(win/2);
opts.fmax = 40;
nfft  = max(256, 2^nextpow2(win));

% --- Resume state ---
progfile = [opts.outfile '.progress.mat'];
decided = false(nT,1);
isbad   = false(nT,1);
startAt = 1;
if exist(progfile,'file')
    S = load(progfile);
    if isfield(S,'decided') && numel(S.decided)==nT
        decided = S.decided; isbad = S.isbad;
        startAt = find(~decided, 1); if isempty(startAt), startAt = nT; end
        fprintf('Resuming: %d already reviewed, %d marked bad.\n', nnz(decided), nnz(isbad));
    end
end

% --- Estimate a stable y-limit from a sample of trials (so axes do not jump) ---
rng(0); samp = unique([1 nT randperm(nT, min(30,nT))]);
alldb = [];

for tr = samp
    P = trial_psd(eD, chans, tr, win, nover, nfft, fs);
    alldb = [alldb; 10*log10(P(:))]; %#ok<AGROW>
end
alldb = alldb(isfinite(alldb));
ylims = prctile(alldb, [1 99]) + [-5 5];
ylims = minmax(alldb');
% --- Figure + key capture ---
fig = figure('Name','PSD trial reviewer','Color','w', ...
             'KeyPressFcn', @onkey, 'NumberTitle','off');
setappdata(fig,'key','');

i = startAt;
count = 0;
while ishandle(fig) && i >= 1 && i <= nT
    P = trial_psd(eD, chans, i, win, nover, nfft, fs);
    f = linspace(0, fs/2, size(P,1))';

    clf(fig);
    ax = axes('Parent',fig); hold(ax,'on');
    plot(ax, f, 10*log10(P), 'Color',[0 0.35 0.8 0.25]);      % all channels, faint
    plot(ax, f, 10*log10(median(P,2)), 'k', 'LineWidth',1.6);  % channel median, bold
    xlim(ax,[0 opts.fmax]); ylim(ax, ylims);
    xlabel(ax,'Frequency (Hz)'); ylabel(ax,'PSD (dB)');
    grid(ax,'on'); set(ax,'Layer','top');

    st = 'undecided';
    if decided(i), st = tern(isbad(i),'BAD','good'); end
    title(ax, sprintf('Trial %d / %d   [%s]   |   bad so far: %d', ...
                      i, nT, st, nnz(isbad)), 'Interpreter','none');
    text(0.99,0.02,'g/space=good   b=bad   p=back   s=save   q=quit', ...
         'Units','normalized','HorizontalAlignment','right','Color',[.4 .4 .4],'Parent',ax);
    drawnow;

    uiwait(fig);
    if ~ishandle(fig), break; end
    key = getappdata(fig,'key'); setappdata(fig,'key','');

    switch key
        case {'g','space','rightarrow'}
            decided(i)=true; isbad(i)=false; i=i+1; count=count+1;
        case {'b','downarrow'}
            decided(i)=true; isbad(i)=true;  i=i+1; count=count+1;
        case {'p','leftarrow'}
            i = max(1, i-1);
        case 's'
            save_now(opts.outfile, progfile, decided, isbad);
        case {'q','escape'}
            break;
        otherwise
            % ignore other keys, redraw same trial
    end

    if mod(count,25)==0 && count>0
        save_now(opts.outfile, progfile, decided, isbad);
    end
end

save_now(opts.outfile, progfile, decided, isbad);
if ishandle(fig), close(fig); end

badTrials = find(isbad);
fprintf('\nDone. %d/%d reviewed, %d bad.\nBad-trial list: %s\n', ...
        nnz(decided), nT, numel(badTrials), opts.outfile);
if ~isempty(badTrials)
    fprintf('To apply later:  eD = badtrials(eD, %s, 1); eD.save;\n', mat2str(badTrials(:)'));
end
end

%% ===================== local functions =====================
function P = trial_psd(eD, chans, tr, win, nover, nfft, fs)
    X = squeeze(eD(chans,:,tr))';   % [nsamples x nchan]
    X = double(X);
    P = pwelch(X, win, nover, nfft, fs);   % [nfreq x nchan]
end

function onkey(src,evt)
    setappdata(src,'key',evt.Key);
    uiresume(src);
end

function save_now(outfile, progfile, decided, isbad)
    bad = find(isbad);
    writematrix(bad(:), outfile);                 % CSV of bad trial numbers (1-based)
    save(progfile, 'decided', 'isbad');           % resume state
    fprintf('  saved: %d bad trials -> %s\n', numel(bad), outfile);
end

function out = tern(c,a,b), if c, out=a; else, out=b; end, end
