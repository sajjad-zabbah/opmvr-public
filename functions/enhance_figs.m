%% ENHANCE_FIGS  Export source-level statistical maps as vector figures
%
% Overlays a statistical image written by stats_permutation_F.m on an MNI152
% template with SPM's orthviews and exports a clean vector figure (.emf).
%
% Two modes:
%   plot_halfmax_maps = false
%       Displays the FWE-significant signed-t map (perm<N>_..._sig_signedt_...)
%       in two views (Figures 3E and 4). For the eyes-open/eyes-closed
%       contrast only voxels above half of the peak value are displayed.
%   plot_halfmax_maps = true
%       Reads the unthresholded signed-t map (perm<N>_..._t_...), thresholds
%       the display at half of the peak value and exports three views,
%       separately for each contrast direction ('pos' = cond1 > cond2,
%       'neg' = cond2 > cond1; Supplementary Figure 4). The threshold is for
%       illustration only and does not change the statistics.
%
% With manual_coord = true the crosshair position is chosen interactively:
% click on the orthviews, then press Enter in the Command Window to save.
%
% Required workspace variables (set in main.m / stats_permutation_F.m):
%   save_data_add, output_root, nPerm, pref, tag, conditionlabel1/2,
%   mni_cordinates, small_vol_cor, plot_halfmax_maps
% The MNI152 template is read from <output_root>/mni152.nii.
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

close all;

%% -------- Parameters --------
add = save_data_add;

% Half-maximum figures (Supplementary Figure 4); normally set in main.m.
if ~exist('plot_halfmax_maps','var'), plot_halfmax_maps = false; end

half_max_frac = 0.5;        % display threshold = 50% of the peak value

% Direction displayed when a single half-maximum figure is drawn:
%   'pos' -> cond1 > cond2 | 'neg' -> cond2 > cond1 | 'abs' -> |t|
effect_sign = 'pos';

% Centre the view on the peak voxel of the displayed map (otherwise on
% mni_cordinates).
center_on_peak = false;

% Choose the crosshair position interactively: click on the orthviews, then
% press Enter in the Command Window to save the figure at that location.
% Overrides center_on_peak / mni_cordinates.
manual_coord = true;

% Display only voxels above half of the peak value on the FWE map. Used for
% the eyes-open/eyes-closed alpha map (Figure 3E); illustrative only.
half_max_display = false;
if exist('conditionlabel1','var') && exist('conditionlabel2','var') && ...
   any(strcmp({conditionlabel1,conditionlabel2}, 'EyesClosed'))
    half_max_display = true;
end

% Small-volume correction switch (normally set in main.m). When true, the SVC
% output of stats_permutation_F (perm..._svc_<ROI>.nii) is displayed.
if ~exist('small_vol_cor','var'), small_vol_cor = false; end

% Optional ROI image (.nii) within which the peak / half-maximum are computed.
roi_mask = '';

% Map to display:
%   map_type        : 'F' (all positive) | 'signedt' (direction, +/-)
%   correction_mode : 'fwe' (perm..._sig_...) | 'unc' (perm..._uncsig_...) | 'both'
map_type        = 'signedt';
correction_mode = 'fwe';
if ~exist('halfmax_signs','var'), halfmax_signs = {lower(effect_sign)}; end

if plot_halfmax_maps
    % Unthresholded signed-t map, one figure per contrast direction:
    %   'pos' -> conditionlabel1 > conditionlabel2
    %   'neg' -> conditionlabel2 > conditionlabel1
    base_stem = sprintf('perm%.f_%st_%s_vs_%s', nPerm, pref, conditionlabel1, conditionlabel2);
    halfmax_signs = {'pos','neg'};
    stem_list = repmat({base_stem}, 1, numel(halfmax_signs));
else
    switch lower(correction_mode)
        case 'fwe',  sig_prefix = {'sig'};
        case 'unc',  sig_prefix = {'uncsig'};
        case 'both', sig_prefix = {'sig','uncsig'};
        otherwise,   error('correction_mode must be ''fwe'', ''unc'' or ''both''.');
    end

    stem_list = cell(1, numel(sig_prefix));
    for k = 1:numel(sig_prefix)
        stem_list{k} = sprintf('perm%.f_%s%s_%s_%s_vs_%s%s', ...
            nPerm, pref, sig_prefix{k}, map_type, conditionlabel1, conditionlabel2, tag);
    end
end

%% ======================= loop over maps to display =======================
for iMap = 1:numel(stem_list)

perm_stem = stem_list{iMap};

if plot_halfmax_maps
    effect_sign = halfmax_signs{iMap};   % 'pos' = c1>c2, 'neg' = c2>c1
    hits = dir(fullfile(add, [perm_stem '*.nii']));
    assert(~isempty(hits), 'No t map "%s*.nii" in %s.', perm_stem, add);
    [~, file_name] = fileparts(hits(1).name);
else
    if small_vol_cor
        % SVC output carries a _svc_<roi_tag> suffix; glob for it so this script
        % runs standalone without needing roi_tag in the workspace.
        hits = dir(fullfile(add, [perm_stem '*.nii']));
        if isempty(hits)
            warning(['No image "%s*.nii" in %s -- skipping. ' ...
                     '(Re-run stats_permutation_F to write the %s map.)'], ...
                    perm_stem, add, sig_prefix{iMap});
            continue
        end
        if numel(hits) > 1
            warning('%d images match "%s*.nii"; using "%s".', numel(hits), perm_stem, hits(1).name);
        end
        [~, file_name] = fileparts(hits(1).name);
        fprintf('\n[%s] displaying: %s\n', upper(sig_prefix{iMap}), hits(1).name);
    else
        file_name = perm_stem;
        if exist(fullfile(add,[file_name '.nii']),'file') ~= 2
            warning('Not found: %s.nii -- skipping.', file_name);
            continue
        end
        fprintf('\n[%s] displaying: %s.nii\n', upper(sig_prefix{iMap}), file_name);
    end
end

% MNI152 template used as anatomical background (place it in output_root)
mni = fullfile(output_root,'mni152.nii');

% Output format
out_ext = '.emf';

% Layout settings (cm)
stp = 1;                    % left/bottom padding
view_h = 4;                 % height of each orthview panel (cm)
gap = 0.1;                  % gap between panels (cm)
cbar_scale = 0.5;           % relative colorbar width scaling
font_size = 8;

%% -------- Build file paths --------
file_name_full = fullfile(add, [file_name '.nii']);

if plot_halfmax_maps
    out_file = fullfile(add, [file_name '_' lower(effect_sign) '_3view_halfmax' out_ext]);
else
    out_file = fullfile(add, [file_name out_ext]);
end

assert(exist(file_name_full,'file')==2, 'NIfTI not found: %s', file_name_full);
assert(exist(mni,'file')==2, 'MNI template not found: %s', mni);

%% -------- Open SPM orthviews and load overlay data --------
spm_check_registration(mni);
fig = gcf;

V = spm_vol(file_name_full);
Y = spm_read_vols(V);

% Optional: restrict to an ROI so the peak / half-max are computed within it
if ~isempty(roi_mask)
    assert(exist(roi_mask,'file')==2, 'ROI mask not found: %s', roi_mask);
    Vroi = spm_vol(roi_mask);
    [gx,gy,gz] = ndgrid(1:size(Y,1), 1:size(Y,2), 1:size(Y,3));
    XYZw  = V.mat * [gx(:)'; gy(:)'; gz(:)'; ones(1,numel(gx))];   % image vox -> world
    vroi  = Vroi.mat \ XYZw;                                       % world -> ROI vox
    inroi = spm_sample_vol(Vroi, vroi(1,:), vroi(2,:), vroi(3,:), 0) > 0.5; % NN
    Y(~reshape(inroi, size(Y))) = 0;
end

has_nonzero = any(isfinite(Y(:)) & Y(:) ~= 0);

%% -------- Mode-specific overlay, threshold, crosshair, view count --------
if plot_halfmax_maps
    n_views = 3;

    % Build the DISPLAY image according to effect_sign
    switch lower(effect_sign)
        case 'pos', Yd = Y;        % cond1 > cond2
        case 'neg', Yd = -Y;       % cond2 > cond1
        case 'abs', Yd = abs(Y);   % magnitude, non-directional (F-like)
        otherwise,  error('effect_sign must be ''pos'', ''neg'' or ''abs''.');
    end

    [peakval, idx] = max(Yd(:));

    if has_nonzero && peakval > 0
        % Peak (maximum) voxel -> MNI mm for the crosshair
        [pi,pj,pk]    = ind2sub(size(Yd), idx);
        xyz           = V.mat * [pi; pj; pk; 1];
        crosshair_mni = xyz(1:3)';

        % Half-maximum DISPLAY threshold (illustrative only)
        thr  = half_max_frac * peakval;
        Ythr = Yd;
        Ythr(~(Ythr >= thr)) = NaN;

        Vthr        = V;
        Vthr.fname  = fullfile(add, [file_name '_' lower(effect_sign) '_halfmax.nii']);
        Vthr.dt     = [spm_type('float32') 0];
        Vthr.n      = [1 1];
        spm_write_vol(Vthr, Ythr);

        % Hot colourmap, scaled from the half-max threshold to the peak
        spm_orthviews('addimage', 1, Vthr.fname, hot(256), 1, peakval, thr);
        spm_orthviews('addcolourbar', 1, 1);

        fprintf(['effect_sign=%s | peak MNI [%.1f %.1f %.1f], value %.3f; ', ...
            'display threshold (%.0f%% of peak) = %.3f\n'], ...
            effect_sign, crosshair_mni, peakval, 100*half_max_frac, thr);
    else
        warning('No values to display for effect_sign=''%s''; centring on mni_cordinates.', effect_sign);
        crosshair_mni = mni_cordinates;
    end
else
    n_views = 2;
    if has_nonzero
        if half_max_display
            Yd = abs(Y); Yd(~isfinite(Yd)) = 0;
            pk  = max(Yd(:));
            thr = half_max_frac * pk;
            Yhm = Y;
            Yhm(~(abs(Y) >= thr)) = NaN;      % below half-max -> transparent
            Vhm = V; Vhm.fname = fullfile(add,[file_name '_halfmaxdisp.nii']);
            Vhm.dt = [spm_type('float32') 0]; Vhm.n = [1 1];
            spm_write_vol(Vhm, Yhm);
            spm_orthviews('addimage', 1, Vhm.fname, hot(256), 1, pk, thr);
            spm_orthviews('addcolourbar', 1, 1);
            fprintf('Half-max display: |value| >= %.3f (50%% of peak %.3f)\n', thr, pk);
        else
            spm_orthviews('addimage', 1, file_name_full, [1 0 0]);
        end

        % Centre the view on the MAXIMUM-activity voxel so the saved figure
        % actually shows the (possibly small/off-centre) significant cluster.
        % |value| is used so this works for BOTH the F map (all positive) and
        % the signed-t map (peak magnitude may be negative, i.e. c2 > c1).
        if center_on_peak
            Yabs = abs(Y);
            Yabs(~isfinite(Yabs)) = -Inf;
            [peakval, idx] = max(Yabs(:));
            if isfinite(peakval) && peakval > 0
                [pi,pj,pk]    = ind2sub(size(Y), idx);
                xyz           = V.mat * [pi; pj; pk; 1];
                crosshair_mni = xyz(1:3)';
                fprintf('Centred on peak activity: value %.3f at MNI [%.1f %.1f %.1f]\n', ...
                        Y(idx), crosshair_mni(1), crosshair_mni(2), crosshair_mni(3));
            else
                crosshair_mni = mni_cordinates;
                warning('Could not find a finite peak; centring on mni_cordinates.');
            end
        else
            crosshair_mni = mni_cordinates;   % fixed coordinate
        end
    else
        crosshair_mni = mni_cordinates;
        warning('No significant voxels in map; centring on mni_cordinates.');
    end
end

if manual_coord
    % Show crosshair, let the user click to position, then read it back.
    spm_orthviews('reposition', crosshair_mni);   % initial guess
    spm_orthviews('Xhairs', 'on');
    spm_orthviews('redraw'); drawnow;
    fprintf('\n>> [%s] Click on the brain to move the crosshair, then press Enter to save...\n', file_name);
    input('', 's');                               % GUI stays live during input()
    crosshair_mni = spm_orthviews('pos')';        % clicked location (world mm)
    fprintf('   saving at MNI [%.1f %.1f %.1f]\n', crosshair_mni);
end

spm_orthviews('reposition', crosshair_mni);
spm_orthviews('Xhairs', 'off');   % clean image; set 'on' to keep the crosshair in the saved figure
spm_orthviews('redraw');
drawnow;

%% -------- Robustly find the orthviews axes and (optional) colorbar --------
all_ax = findobj(fig, 'Type','axes', '-and', 'Visible','on');
if isempty(all_ax)
    error('No axes found in SPM figure. Is spm_check_registration rendering correctly?');
end

ax_pos = arrayfun(@(a) get(a,'Position'), all_ax, 'UniformOutput', false);
ax_pos = vertcat(ax_pos{:});
[~, idx_sorted_w] = sort(ax_pos(:,3), 'ascend');

cbar_ax = [];
if ~isempty(idx_sorted_w)
    candidate = all_ax(idx_sorted_w(1));
    cand_pos  = get(candidate,'Position');
    if cand_pos(3) < 0.15 * max(ax_pos(:,3))
        cbar_ax = candidate;
    end
end

view_ax = all_ax;
if ~isempty(cbar_ax)
    view_ax(view_ax == cbar_ax) = [];
end

view_pos = arrayfun(@(a) get(a,'Position'), view_ax, 'UniformOutput', false);
view_pos = vertcat(view_pos{:});
areas = view_pos(:,3) .* view_pos(:,4);
[~, idx_big] = sort(areas, 'descend');

if numel(idx_big) < n_views
    error('Could not identify %d orthviews axes to export (found %d).', ...
        n_views, numel(idx_big));
end

ax_to_copy = view_ax(idx_big(1:n_views));

pos2 = arrayfun(@(a) get(a,'Position'), ax_to_copy, 'UniformOutput', false);
pos2 = vertcat(pos2{:});
[~, ord] = sortrows(pos2, [1 -2]);     % left-to-right, top row first on ties
ax_to_copy = ax_to_copy(ord);

%% -------- Build a clean "export" figure by copying axes --------
new_fig = figure('Units','centimeters', 'Color','w');
new_fig.Position = [10 10 12 7];

if has_nonzero && ~isempty(cbar_ax)
    new_objs = copyobj([ax_to_copy; cbar_ax], new_fig);
    new_view = new_objs(1:n_views);
    new_cbar = new_objs(n_views + 1);
else
    new_objs = copyobj(ax_to_copy, new_fig);
    new_view = new_objs(1:n_views);
    new_cbar = [];
end

colormap(new_fig, colormap(fig));

%% -------- Layout in centimeters (aspect from DATA extent) --------
set(new_view, 'Units','centimeters');
set(new_view, 'DataAspectRatio',[1 1 1], 'DataAspectRatioMode','manual');

asp = zeros(1, n_views);
for v = 1:n_views
    xl = get(new_view(v),'XLim'); yl = get(new_view(v),'YLim');
    asp(v) = diff(xl)/diff(yl);
end

cbar_w = 0;
if ~isempty(new_cbar)
    set(new_cbar,'Units','centimeters');
    pc = get(new_cbar,'Position');
    asp_c = pc(3)/pc(4);
    set(new_cbar, 'Position', [stp stp (asp_c*view_h*cbar_scale) view_h]);
    cbar_w = (asp_c*view_h*cbar_scale) + gap;
end

x0   = stp + cbar_w;
xcur = x0;
for v = 1:n_views
    w = asp(v) * view_h;
    set(new_view(v), 'Position', [xcur stp w view_h]);
    xcur = xcur + w + gap;
end

total_w = (xcur - gap) + stp;
total_h = stp + view_h + stp;
new_fig.Position = [new_fig.Position(1) new_fig.Position(2) total_w total_h];

%% -------- Styling --------
set(new_fig, 'Renderer','painters');
ax_all = findobj(new_fig, 'Type','axes');
set(ax_all, 'FontName','Arial', 'FontWeight','bold', 'FontSize', font_size, ...
    'TickDir','out', 'Box','off');

%% -------- Export --------
exportgraphics(new_fig, out_file, 'ContentType', 'vector');
fprintf('Saved: %s\n', out_file);

close(new_fig);   % avoid accumulating export figures across iterations

end
%% ===================== end loop over maps to display =====================
