%% DC_NOISE  Static magnetic field of the HMD versus distance (Experiment 1)
%
% Plots the change in magnetic flux density caused by the headset, measured
% with a single-axis fluxgate magnetometer in three orthogonal orientations at
% decreasing distances (Figure 3A). At each distance the magnitude is the
% Euclidean norm of the vector difference from the 1 m reference measurement
% (first row of each sheet), |B(d) - B(1 m)|.
%
% Three headsets are compared:
%   1) Proposed MEG-compatible HMD (Sheet1)
%   2) De-metalled Pimax headset    (Sheet2)
%   3) Original Pimax headset       (Sheet3)
%
% Paths are read from config_local.m (cfg.paths.dc_noise_file,
% cfg.paths.output_root).
%
% Authors: Sajjad Zabbah and Claude (Anthropic).
% Part of the analysis code for Zabbah et al., "An integrated virtual
% reality platform for naturalistic neuroimaging with magnetoencephalography".

close all
clearvars

%% Paths (set in config_local.m)
cfg = struct();
run('config_local.m');
out_dir = fullfile(cfg.paths.output_root, 'DC-AC', 'DC');
add     = cfg.paths.dc_noise_file;

% Check that input file exists
if ~isfile(add)
    error('Input Excel file not found: %s', add);
end

% Ensure output directory exists
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% Load data
proposed_hmd  = readtable(add, 'Sheet', 'Sheet1'); % Proposed HMD
pimax_demetal = readtable(add, 'Sheet', 'Sheet2'); % De-metalled Pimax
pimax_orig    = readtable(add, 'Sheet', 'Sheet3'); % Original Pimax

%% Convert distance from cm to meters
distance_proposed_hmd  = proposed_hmd.Distance_cm_  * 0.01;
distance_pimax_demetal = pimax_demetal.Distance_cm_ * 0.01;
distance_pimax_orig    = pimax_orig.Distance_cm_    * 0.01;

%% Compute magnetic field magnitude
% Euclidean norm of the vector difference from the 1 m reference
% measurement (first distance point)

prop_hmd_mag = sqrt( ...
    (proposed_hmd.x - proposed_hmd.x(1)).^2 + ...
    (proposed_hmd.y - proposed_hmd.y(1)).^2 + ...
    (proposed_hmd.z - proposed_hmd.z(1)).^2 );

pimax_demetal_mag = sqrt( ...
    (pimax_demetal.x - pimax_demetal.x(1)).^2 + ...
    (pimax_demetal.y - pimax_demetal.y(1)).^2 + ...
    (pimax_demetal.z - pimax_demetal.z(1)).^2 );

pimax_orig_mag = sqrt( ...
    (pimax_orig.x - pimax_orig.x(1)).^2 + ...
    (pimax_orig.y - pimax_orig.y(1)).^2 + ...
    (pimax_orig.z - pimax_orig.z(1)).^2 );

%% Plot
figure(1); hold on

plot(distance_proposed_hmd(2:end),  prop_hmd_mag(2:end)  * 1e3, '-o', ...
    'MarkerFaceColor','auto','LineWidth',3)

plot(distance_pimax_orig(2:end),     pimax_orig_mag(2:end) * 1e3, '-o', ...
    'MarkerFaceColor','auto','LineWidth',3)

plot(distance_pimax_demetal(2:end),  pimax_demetal_mag(2:end) * 1e3, '-o', ...
    'MarkerFaceColor','auto','LineWidth',3)

set(gca, "TickDir", "out", "box", "off")
ylabel("Magnetic Field Magnitude (nT)")
xlabel("Distance (m)")
legend({'Proposed HMD','Original Pimax','De-metalled Pimax'}, 'box', 'off')

set(gca, 'YScale', 'log')
ylim([2e-4, 15] * 1e3)
xlim([0, 0.6])

%% Figure styling
set(gca, 'TickLength', [0.02 0.02], 'LineWidth', 0.1)
set(gcf, 'Units', 'centimeters', 'Position', [10 10 7.62 7.62])
set(gcf, 'Color', 'w')
set(gca, 'FontName', 'Arial')
set(gca, 'FontWeight', 'bold')
set(gca, 'FontSize', 10)
set(gcf, 'Renderer', 'painters')

%% Export
exportgraphics(gcf, fullfile(out_dir, 'MagneticfieldVsdistance.emf'), ...
    'ContentType', 'vector');
