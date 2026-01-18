# Tenney

Tenney is a **performer-first just-intonation tuner, lattice tool, and scale builder** designed for both **stage use** and **research workflows**. iOS/macOS are primary today, and **Android is actively being built** with a parity-first approach.

## Status

- **`main`**: iOS/macOS source of truth
- **Android**: active work on branch `android/oss-foundation`
- **Parity-first**: fixtures are the contract (see **Parity** below)

## Features

- Just-intonation tuning + fast ratio workflows
- Lattice-based exploration and selection
- Scale building and organization
- Import/export-friendly formats (Scala / KBM) (parity work in progress across platforms)
- Performer-oriented UI patterns for rehearsal and stage

## Quick start

### Android (no Mac needed)

1. Open `apps/android` in **Android Studio**
2. Run tests:
   ```sh
   cd apps/android
   ./gradlew test

3. Fixture-driven tests live under `shared/fixtures/` and are consumed by the Android JVM modules.

### iOS / macOS

1. Open the Xcode project in this repo (source of truth lives on `main`)
2. Build and run, or run tests from Xcode

> Note: if you don’t see an `apps/ios/` directory yet, that’s expected — the iOS project may still live at the repo root while Android work stabilizes.

## Repo layout

* `apps/android/` — Android Studio project (Gradle multi-module)
* `apps/ios/` — iOS/macOS project (if/when migrated; otherwise see repo root)
* `shared/fixtures/` — parity fixtures (JSON) used by tests
* `shared/spec/` — contracts and parity docs

## Parity

Tenney Android is being built **fixture-first**.

* Fixtures live in: `shared/fixtures/`
* JSON contract: `shared/spec/json.md`
* Parity checklist: `shared/spec/parity-checklist.md`

**Golden rules**

* If you’re changing behavior, **add/adjust fixtures first** whenever possible.
* If fixture expectations change, **bump fixture versions** (`v1 → v2`) rather than silently editing existing files.

## Contributing

Start here: `CONTRIBUTING.md`

Contribution paths (good places to jump in):

* **Math/core**: RatioMath, TenneyScale, JSON shape/round-trip
* **Formats**: Scala (`.scl`) + KBM (`.kbm`) parse/serialize parity
* **Lattice parity**: selection rules + deterministic outputs
* **Android UI shells**: Compose scaffolding once fixture suites are green
* **Audio / MIDI**: larger platform integration work (see issues/spec)

Looking for help right now:

* Android library load/save + import/export flows
* Lattice render + gestures (Compose Canvas) driven by existing selection parity
* Tuner + stage mode UI wiring to the tested core
* Audio engine and MIDI parity design + implementation

## Roadmap (short)

* Android library I/O + import/export flows
* Lattice render + gesture parity
* Tuner + stage mode parity
* Audio engine parity
* MIDI parity

## License

Apache-2.0 — see `LICENSE`.

## Community

* Code of Conduct: `CODE_OF_CONDUCT.md`
* Issues: use the templates [Feature Request](https://github.com/stagedevices/Tenney/issues/new?template=feature_request.yml), [Parity mismatch / fixture failure](https://github.com/stagedevices/Tenney/issues/new?template=parity.yml)
