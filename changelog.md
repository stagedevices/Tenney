> This changelog shows what changed since v0.2.

## Highlights

- **Mac Catalyst + macOS support**: new app shell, inspector, and a macOS split-view layout with a custom top bar.
- **Tuner Context Rail**: a configurable “context rail” experience (macOS/Catalyst + iPad landscape), with cards, presets, and shortcuts.
- **Mac-first lattice ergonomics**: trackpad interactions, improved zoom feel, and Mac-specific chip styling.
- **Diagnostics**: opt-in crash reporting + diagnostics export/upload (Sentry-backed).
- **Polish & fixes**: improved tuner ratio readout behavior, audio binding fixes, and stability tweaks.

---

## New / Expanded Platforms

### macOS

- Added a **macOS split view layout** with a **custom top bar**.
- Added supporting macOS root / preferences views.

### Mac Catalyst

- Added a **Mac Catalyst app shell** and an **inspector-style layout**.
- Hardened Mac Catalyst rendering paths (including gradient behavior) to avoid platform-specific issues.

---

## Tuner

- **Context Rail scaffolding** (macOS/Catalyst), including the underlying models + settings wiring.
- **Enabled the tuner context rail on iPad landscape** layouts.
- Added **tuner rail presets and shortcuts** for faster workflow changes.
- Improved tuner rail UX:
  - more legible “listening” overlays
  - more consistent “mini focus” behavior
- Fixed **tuner ratio readout** so it **unfolds octave** correctly (ratio display behavior).

---

## Lattice

- Added **trackpad interactions** and **cursor-anchored zoom** on Mac platforms, with hover-aware zoom anchoring improvements.
- “Feels better on Mac” tuning:
  - platform-specific zoom boost (without altering stored zoom values)
  - overlay chip appearance tuned for Mac glass/material rendering
- Fixed lattice audio UX:
  - corrected “audition sound” binding behavior
- Refined tuner/lattice integration:
  - mini focus now uses the real lattice model for correctness

---

## Settings & Visualizations

- Added / refined **Lissajous / oscilloscope preview** paths and a ribbon renderer refactor.
- Aligned builder preview behavior with Settings preview behavior and improved draw/layout characteristics on macOS/Catalyst.

---

## Diagnostics & Reliability

- Added **diagnostics plumbing** (export + packaging) plus **opt-in crash reporting**.
- Added **opt-in Sentry crash reporting** and **diagnostics upload** integration.

---

## Housekeeping

- Added and updated an in-repo `changelog.md`.
- Various small fixes and cleanup commits along the way.
