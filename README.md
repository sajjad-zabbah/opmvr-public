# OPMVR analysis code

MATLAB code for the analyses in:

> Zabbah, S., Alexander, N. A., Mohammadi, Y., Mariola, A., Seymour, R. A., Puvvada, S., Barnes, G. R., & Bach, D. R. *An integrated virtual reality platform for naturalistic neuroimaging with magnetoencephalography.*

The code processes optically pumped magnetometer MEG (OPM-MEG) data recorded with a custom MEG-compatible virtual reality head-mounted display (HMD), and reproduces the noise measurements, sensor-level and source-level results and figures reported in the paper.

The code was written by Sajjad Zabbah together with Claude (Anthropic), an AI assistant.

## Repository structure

| File | Purpose | Paper |
|---|---|---|
| `dc_noise.m` | Static magnetic field of the HMD versus distance (Experiment 1) | Figure 3A |
| `psd_hmdon_hmdoff.m` | Sensor spectra with the HMD on and off; broadband level and narrowband peaks (Experiment 2) | Figure 3B, Supplementary Figure 3 |
| `ac_noise.m` | Phantom (coil) spectra and dipole localisation with the HMD on and off (Experiment 2) | Figure 3C |
| `main.m` | Entry point for the participant experiments (Experiments 3 to 6) | Figures 3D, 3E, 4, 6; Supplementary Figures 2 and 4 |
| `config_template.m` | Template for the machine-specific paths (copy to `config_local.m`) | |
| `functions/preprocess.m` | Import, event alignment, filtering, Zapline-plus, AMM, epoching | |
| `functions/beh_meg_time_align.m` | Aligns Unity behavioural logs with the MEG triggers | |
| `functions/chktask_event_modify.m` | Labels left and right checkerboard stimuli | |
| `functions/merg_runs.m` | Merges two runs | |
| `functions/time_frequency.m` | Alpha time course and topography (Experiment 3) | Figure 3D |
| `functions/source_localization.m` | LCMV beamformer (DAiSS), trial-wise power images, 15 mm smoothing | |
| `functions/stats_permutation_F.m` | Within-participant permutation F-test with small-volume correction | |
| `functions/enhance_figs.m` | Exports source maps on the MNI152 template | Figures 3E, 4; Supplementary Figure 4 |
| `functions/movement_analysis.m` | Head and hand displacement per trial | Figure 6 |
| `functions/bad_channel_pos.m` | Positions of the excluded channels | Supplementary Figure 2 |
| `functions/psd_trial_reviewer.m` | Optional interactive tool to review per-trial spectra | |

## Requirements

- MATLAB (developed with R2021b or later), with the Signal Processing Toolbox and the Statistics and Machine Learning Toolbox
- [SPM25 or SPM12](https://www.fil.ion.ucl.ac.uk/spm/), including the OPM functions, the DAiSS beamforming toolbox and the bundled FieldTrip
- [analyse_OPMEG](https://github.com/neurofractal/analyse_OPMEG) (provides `bidsFilename`)
- [zapline-plus](https://github.com/MariusKlug/zapline-plus)
- An MNI152 template saved as `mni152.nii` in the output folder (used as background for the source figures)

`functions/psd_trial_reviewer.m` additionally uses `minmax` (Deep Learning Toolbox).

## Setup

1. Copy `config_template.m` to `config_local.m` and set the paths to the data, the output folder and the toolboxes.
2. Run all scripts from the repository folder.

The participant data are expected in a BIDS-like structure (`sub-XXX/ses-XXX/{meg,anat,beh}`). Bad channels and bad trials are read from `badchannels.xlsx` and `badtrials.xlsx` in each MEG folder.

## Running the analyses

**Experiments 1 and 2 (noise).** Run `dc_noise.m`, `psd_hmdon_hmdoff.m` and `ac_noise.m`. In `ac_noise.m`, set `dipole_fit = true` to localise the phantom.

**Experiments 3 to 6 (participants).** In section 1 of `main.m`, set:

- `sub`: `'001'` or `'002'`
- `task`: `{'eyesOpenEyesClosed'}`, `{'chk'}`, `{'grasping'}` or `{'0back','2back'}`
- `analysis`:
  - `'time_frequency'` for the eyes-open/eyes-closed alpha time course and topography
  - `'source_localization'` for beamforming, statistics and source figures
  - `'movement_analysis'` for the head and hand displacement figure
  - `'bad_channel_pos'` for the bad-channel figure
- `figure_set`:
  - `'main'`: 10,000 permutations, FWE correction within the a priori region of interest of each task, FWE-significant voxels shown as signed t
  - `'supplementary'`: whole-brain signed-t maps thresholded at half of the peak value, one figure per contrast direction

Task-specific settings (frequency band, time window, contrast and region of interest) are defined in `main.m`:

| Task | Contrast | Band | ROI (Neuromorphometrics labels) |
|---|---|---|---|
| Eyes open / closed | EyesClosed vs EyesOpen | 8–12 Hz | Occipital (108 109 114 115 134 135 156 157) |
| Checkerboard | Left vs Right | 4–12 Hz | Bilateral calcarine cortex (108 109) |
| Grasping | Move vs Image | 13–30 Hz | Left precentral and postcentral gyrus (183 177) |
| N-back | 2-back vs 0-back | 4–8 Hz | Bilateral superior frontal gyrus, medial segment (152 153) |

With `enhance_figs.m`, the crosshair position of each figure is set interactively by default (`manual_coord = true`): click on the brain, then press Enter in the Command Window to save.

Set `stats_only = true` to re-run the statistics on beamformer images already on disk, or `only_plot = true` to redraw figures from existing statistical maps.

## Data

The data accompanying the paper are shared on OSF: https://osf.io/qpx37

## Citation

If you use or adapt this code, please cite the paper above.
