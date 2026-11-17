%% STATS_PERMUTATION_F  Voxel-wise permutation F-test on beamformer images
%
% Non-parametric permutation test (Nichols & Holmes, 2002) comparing the
% trial-wise source power images of two conditions within one participant.
% For two conditions the F statistic equals t^2 (df = 1, n1+n2-2), so the test
% is two-tailed. Condition labels are permuted across trials; on each
% permutation the maximum F over the search volume is retained, and the 95th
% percentile of this max-F null distribution is the FWE-corrected (p < 0.05)
% voxel threshold. With small_vol_cor = true the search volume is restricted
% to the Neuromorphometrics labels in roi_labels (small-volume correction).
%
% Required workspace variables (set in main.m):
%   save_data_add, conditionlabel1, conditionlabel2, ifsmoothed, nPerm,
%   small_vol_cor, roi_labels
%
% Outputs (in save_data_add; <tag> = '_svc_<ROI name>' with SVC, '' otherwise):
%   perm<N>_<pref>F_<c1>_vs_<c2><tag>.nii            observed F map
%   perm<N>_<pref>sig_F_<c1>_vs_<c2><tag>.nii        FWE-significant F
%   perm<N>_<pref>sig_signedt_<c1>_vs_<c2><tag>.nii  FWE-significant signed t
%                                                    (+ = c1 > c2, - = c2 > c1)
%   perm<N>_<pref>uncsig_*                           uncorrected p <= alphaUnc
%   perm<N>_<pref>t_<c1>_vs_<c2><tag>.nii            unthresholded signed t
%   perm<N>_<pref>pUnc_<c1>_vs_<c2><tag>.nii         uncorrected p per voxel
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

%% -------------------- Parameters --------------------
alphaF   = 0.05;    % FWE level (corrected, family = search volume)
alphaUnc = 0.001;   % uncorrected voxel threshold (diagnostic only; not used for inference)
use_spm_mask = false;   % true -> also intersect with mask.nii in save_data_add (if present)

% Search volume for small-volume correction: Neuromorphometrics label
% indices (roi_labels, set per task in main.m). [] = whole brain.
if small_vol_cor
    svc_roi_labels = roi_labels;
else
    svc_roi_labels = [];
end

rng(42);            % reproducible permutations

%% -------------------- Locate input NIfTIs --------------------
if ifsmoothed, pref = 'smoothed15'; else, pref = ''; end
if ~exist(save_data_add,'dir'), error('Output dir does not exist: %s', save_data_add); end

% DAiSS trial power images end in '_meg.nii'. Match those for each condition,
% then exclude anything this script writes back into the folder.
c1 = dir(fullfile(save_data_add, [pref '*_' conditionlabel1 '_*_meg.nii']));
c2 = dir(fullfile(save_data_add, [pref '*_' conditionlabel2 '_*_meg.nii']));

% Keep only genuine DAiSS power images; drop this script's own outputs
% (perm*, mask*, *_vs_*) and, when unsmoothed is requested, any smoothed copies.
unsm    = isempty(pref);
isInput = @(nm) ~startsWith(nm,'perm') & ~startsWith(nm,'mask') & ...
                ~contains(nm,'_vs_')  &  endsWith(nm,'_meg.nii') & ...
                (~unsm | ~startsWith(nm,'smoothed'));
c1 = c1(arrayfun(@(s) isInput(s.name), c1));
c2 = c2(arrayfun(@(s) isInput(s.name), c2));

cond1_files = fullfile(save_data_add, {c1.name}');
cond2_files = fullfile(save_data_add, {c2.name}');
if isempty(cond1_files) || isempty(cond2_files)
    error('No trial power NIfTIs found for "%s"/"%s" (pref="%s"). Check labels/prefix.', ...
          conditionlabel1, conditionlabel2, pref);
end
n1 = numel(cond1_files); n2 = numel(cond2_files);
fprintf('"%s": %d images | "%s": %d images\n', conditionlabel1, n1, conditionlabel2, n2);

%% -------------------- Read images into voxels x images matrix --------------------
allFiles = [cond1_files; cond2_files];
V   = spm_vol(char(allFiles));
dim = V(1).dim;
N   = numel(V);
Y2  = reshape(spm_read_vols(V), [], N);
g   = [ones(1,n1), 2*ones(1,n2)];

%% -------------------- Analysis mask (finite, non-zero, optional SPM mask) --------------------
% Always drop non-finite and all-zero voxels (outside the beamformer grid).
maskvec = all(isfinite(Y2),2) & any(Y2~=0,2);

% Optionally intersect with the DAiSS brain mask (off by default).
if use_spm_mask
    maskfile = fullfile(save_data_add,'mask.nii');
    if exist(maskfile,'file')
        Vm = spm_vol(maskfile); Ym = spm_read_vols(Vm);
        maskvec = maskvec & (Ym(:) > 0);
        fprintf('Analysis mask: intersected with %s\n', maskfile);
    else
        warning('use_spm_mask = true but no mask.nii in %s; skipping.', save_data_add);
    end
end
%% -------------------- ROI restriction (small-volume correction) --------------------
% The ROI is built from the Neuromorphometrics atlas shipped with SPM and
% resampled (nearest neighbour) onto the grid of the beamformer images.
roi_name = ''; roi_tag = '';
use_labels = ~isempty(svc_roi_labels);

if use_labels
    % --- Locate atlas + label table ---
    hits = dir(fullfile(spm('Dir'), '**', 'labels_Neuromorphometrics.nii'));
    assert(~isempty(hits), ...
        'labels_Neuromorphometrics.nii not found under %s. Set the atlas path manually.', spm('Dir'));
    atlas     = fullfile(hits(1).folder, hits(1).name);
    atlas_xml = fullfile(hits(1).folder, 'labels_Neuromorphometrics.xml');
    fprintf('Using atlas: %s\n', atlas);

    % --- Look up the ROI name(s) from the XML (sanity check) ---
    [roi_name, missing] = lookup_labels(atlas_xml, svc_roi_labels);
    if ~isempty(missing)
        warning('These label indices were NOT found in the atlas XML: %s', mat2str(missing));
    end
    roi_tag = matlab.lang.makeValidName(strrep(roi_name, ' + ', '_'));
    fprintf('ROI (labels %s): %s\n', mat2str(svc_roi_labels), roi_name);

    % --- Build the ROI mask on the SAME grid as the beamformer images ---
    Va = spm_vol(atlas); Ya = spm_read_vols(Va);
    roi_atlas = ismember(round(Ya), svc_roi_labels);
    [gx,gy,gz] = ndgrid(1:dim(1), 1:dim(2), 1:dim(3));
    XYZw  = V(1).mat * [gx(:)'; gy(:)'; gz(:)'; ones(1,numel(gx))];
    va    = Va.mat \ XYZw;
    inroi = spm_sample_vol(double(roi_atlas), va(1,:), va(2,:), va(3,:), 0) > 0.5;  % NN
    if nnz(inroi) == 0
        warning('ROI has 0 voxels on this grid -- check atlas labels / geometry.');
    end
    maskvec = maskvec & inroi(:);
    fprintf('ROI restriction ON (labels) -> small-volume permutation (%d voxels).\n', nnz(maskvec));

end

Y = Y2(maskvec,:); clear Y2
fprintf('Analysis mask: %d voxels.\n', size(Y,1));

%% -------------------- Observed statistic --------------------
t_obs = two_sample_t(Y, g);      % signed t (direction of the effect)
F_obs = t_obs.^2;                % F = t^2, df = (1, n1+n2-2)

%% -------------------- Permutation loop (record max F only) --------------------
maxF    = zeros(nPerm,1);
maxF(1) = max(F_obs);              % observed labelling = permutation #1 (FWE null)
cntUnc  = ones(size(F_obs));       % same Phipson-Winkler +1 convention, PER VOXEL
                                   % -> smallest possible uncorrected p = 1/nPerm

fprintf('Running %d permutations ', nPerm);
for p = 2:nPerm
    gp = g(randperm(N));
    t  = two_sample_t(Y, gp);
    Fp = t.^2;                     % this permutation's F map
    maxF(p) = max(Fp);             % FWE: single maximum over the whole mask
    cntUnc  = cntUnc + (Fp >= F_obs);   % UNCORRECTED: per-voxel exceedance count
    if mod(p, max(1,round(nPerm/20)))==0, fprintf('%d',p); end
end
fprintf(' done.\n');

%% -------------------- FWE threshold and corrected map --------------------
thrF   = prctile(maxF, 100*(1-alphaF));          % FWE F threshold
sig    = F_obs >= thrF;                           % non-directional significant voxels
pCorr  = arrayfun(@(v) mean(maxF >= v), F_obs);   % FWE-corrected p per voxel

% Uncorrected (diagnostic): per-voxel permutation p, no multiplicity control.
pUnc   = cntUnc / nPerm;
sigUnc = pUnc <= alphaUnc;

%% -------------------- Report --------------------
df1 = 1; df2 = n1+n2-2;
fprintf('\n============ PERMUTATION F-TEST (voxel FWE) ============\n');
if ~isempty(roi_name)
    fprintf('ROI (SVC): %s (labels %s)\n', roi_name, mat2str(svc_roi_labels));
else
    fprintf('ROI: whole brain\n');
end
fprintf('F df = (%d, %d) | nPerm = %d | FWE alpha = %.2f\n', df1, df2, nPerm, alphaF);
fprintf('FWE F threshold (p<.05): %.3f | significant voxels: %d\n', thrF, nnz(sig));
fprintf('UNCORRECTED p<=%.4f: %d voxels (expected by chance ~%.0f)\n', ...
        alphaUnc, nnz(sigUnc), alphaUnc*size(Y,1));
if any(sig)
    Fv = F_obs; Fv(~sig) = -Inf;
    [pk, idx] = max(Fv);
    midx = find(maskvec);
    [px,py,pz] = ind2sub(dim, midx(idx));
    xyz = V(1).mat * [px;py;pz;1];
    % direction at the peak (sign of t) and split of significant voxels by direction
    tsig = t_obs(sig);
    dirStr = ternary(t_obs(idx) > 0, ...
        sprintf('%s > %s', conditionlabel1, conditionlabel2), ...
        sprintf('%s > %s', conditionlabel2, conditionlabel1));
    fprintf('Peak F = %.2f (t = %.2f, %s) at MNI [%.1f %.1f %.1f], min FWE p = %.4f\n', ...
            pk, t_obs(idx), dirStr, xyz(1), xyz(2), xyz(3), min(pCorr(sig)));
    fprintf('Significant voxels: %d with %s, %d with %s\n', ...
            nnz(tsig>0), sprintf('%s>%s',conditionlabel1,conditionlabel2), ...
            nnz(tsig<0), sprintf('%s>%s',conditionlabel2,conditionlabel1));
else
    fprintf('No voxels survive FWE.\n');
end
fprintf('=======================================================\n');

%% -------------------- Write outputs --------------------
% Whole brain -> no tag. SVC -> '_svc_<roi_tag>' so different ROIs don't overwrite.
if isempty(roi_tag)
    tag = '';
else
    tag = ['_svc_' roi_tag(1:min(100,length(roi_tag)))];
end

% Observed F map
perm_stem = sprintf('perm%.f_%sF_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_vol(fullfile(save_data_add, perm_stem), ...
          vec2vol(F_obs, maskvec, dim), V(1), 'F = t^2 (two-sample, df 1,n-2)');

% FWE-significant F map (positive; hot colourmap; NaN elsewhere -> transparent)
perm_stem = sprintf('perm%.f_%ssig_F_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_sig(fullfile(save_data_add, perm_stem), ...
          F_obs, sig, maskvec, dim, V(1), 'FWE-significant F');

% FWE-significant signed t map (same voxels; + = c1>c2, - = c2>c1)
perm_stem = sprintf('perm%.f_%ssig_signedt_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_sig(fullfile(save_data_add, perm_stem), ...
          t_obs, sig, maskvec, dim, V(1), 'signed t within FWE-sig voxels');

% ---- UNCORRECTED maps (same naming, 'uncsig' instead of 'sig') ----
perm_stem = sprintf('perm%.f_%suncsig_F_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_sig(fullfile(save_data_add, perm_stem), ...
          F_obs, sigUnc, maskvec, dim, V(1), sprintf('UNCORRECTED p<=%g F', alphaUnc));

perm_stem = sprintf('perm%.f_%suncsig_signedt_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_sig(fullfile(save_data_add, perm_stem), ...
          t_obs, sigUnc, maskvec, dim, V(1), sprintf('signed t within UNCORRECTED p<=%g voxels', alphaUnc));

% Unthresholded signed t over the whole analysis mask (used for the
% half-maximum figures in enhance_figs.m)
perm_stem = sprintf('perm%.f_%st_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_vol(fullfile(save_data_add, perm_stem), ...
          vec2vol(t_obs, maskvec, dim), V(1), 'signed t over whole analysis mask (unthresholded)');

% Full uncorrected p map (unthresholded), useful for choosing a display threshold
perm_stem = sprintf('perm%.f_%spUnc_%s_vs_%s%s.nii', nPerm, pref, conditionlabel1, conditionlabel2,tag);
write_vol(fullfile(save_data_add, perm_stem), ...
          vec2vol(pUnc, maskvec, dim), V(1), 'uncorrected permutation p per voxel');

fprintf('Outputs written to:\n  %s\n', save_data_add);

%% ==================== local functions ====================
function t = two_sample_t(Y, g)
    i1 = (g==1); i2 = (g==2);
    n1 = nnz(i1); n2 = nnz(i2);
    m1 = mean(Y(:,i1),2);  m2 = mean(Y(:,i2),2);
    v1 = var(Y(:,i1),0,2); v2 = var(Y(:,i2),0,2);
    sp = sqrt(((n1-1).*v1 + (n2-1).*v2) ./ (n1+n2-2));
    t  = (m1 - m2) ./ (sp .* sqrt(1/n1 + 1/n2));
    t(~isfinite(t)) = 0;
end

function vol = vec2vol(vec, maskvec, dim)
    vol = zeros(dim); vol(maskvec) = vec;
end

function write_vol(fname, vol, Vt, descrip)
    Vo = Vt; Vo.fname = fname; Vo.descrip = descrip;
    Vo.dt = [spm_type('float32') 0]; Vo.n = [1 1];
    spm_write_vol(Vo, vol);
end

function write_sig(fname, vals, sig, maskvec, dim, Vt, descrip)
    vol = nan(dim);
    idx = find(maskvec);
    vol(idx(sig)) = vals(sig);
    write_vol(fname, vol, Vt, descrip);
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function [name, missing] = lookup_labels(xml_file, labels)
% Return a combined name for the requested Neuromorphometrics label indices,
% by parsing <label><index>N</index><name>TEXT</name></label> entries.
    name = ''; missing = [];
    if exist(xml_file,'file') ~= 2
        warning('Label XML not found (%s); names unavailable.', xml_file);
        name = sprintf('labels %s', mat2str(labels));
        missing = labels;
        return
    end
    txt = fileread(xml_file);
    % Grab all index/name pairs
    tok = regexp(txt, '<index>\s*(\d+)\s*</index>\s*<name>(.*?)</name>', 'tokens');
    idxAll  = cellfun(@(c) str2double(c{1}), tok);
    nameAll = cellfun(@(c) strtrim(c{2}), tok, 'UniformOutput', false);

    parts = cell(1, numel(labels));
    for k = 1:numel(labels)
        j = find(idxAll == labels(k), 1);
        if isempty(j)
            missing(end+1) = labels(k); %#ok<AGROW>
            parts{k} = sprintf('UNKNOWN(%d)', labels(k));
        else
            parts{k} = nameAll{j};
        end
    end
    name = strjoin(parts, ' + ');
end
