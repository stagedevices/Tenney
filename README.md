# Tenney (Android OSS Foundation)

Tenney is a just-intonation workflow focused on fast lattice selection, precise interval labeling, and stage-ready tuning tools. This repository now includes an OSS-ready Android foundation intended to stay in parity with the existing Swift implementation through fixtures and shared specs.

## Repo layout

- `apps/android/` — Android multi-module Gradle project (`:core`, `:formats`, `:lattice`, `:app`).
- `shared/fixtures/` — JSON fixtures used by JVM unit tests across modules.
- `shared/spec/` — shared serialization and contract documentation.

## Parity-first philosophy

Fixtures are the contract. New behavior (or bug fixes) should start with a fixture update/addition, followed by Kotlin changes and tests that prove parity with the Swift reference behavior.

## Quick start

```bash
cd apps/android
./gradlew test
```

## Docs

- [Tenney JSON Contract](shared/spec/json.md)
- [Tenney Parity Checklist](shared/spec/parity-checklist.md)

## How to contribute

- **Math & domain logic**: update `:core` and the fixtures in `shared/fixtures/**`.
- **Formats**: update `:formats` and Scala/KBM fixtures.
- **Lattice selection parity**: update `:lattice` and lattice fixtures.
- **UI (later)**: `:app` is intentionally minimal until parity tests stabilize.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, workflow, and fixture guidance.
