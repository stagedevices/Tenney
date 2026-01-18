# Contributing to Tenney (Android)

Thanks for helping improve Tenney’s Android foundation! This repo is structured so parity with the existing Swift implementation comes first.

## Setup (no macOS required)

1. Install **Android Studio** (stable channel).
2. Ensure **JDK 21** is available (Android Studio ships one).
3. From the repo root:

```bash
cd apps/android
./gradlew test
```

## Fixtures-first workflow

- **Fixtures are the contract.** Every bugfix or behavioral change should add or update a fixture in `shared/fixtures/**` first.
- Tests in `:core`, `:formats`, and `:lattice` load these fixtures via the test resources path.
- Keep fixtures deterministic and JSON-only.

## Modules

- `:core` — pure Kotlin domain logic (no Android framework dependencies).
- `:formats` — Scala/KBM parsing and serialization.
- `:lattice` — lattice selection logic (pure Kotlin).
- `:app` — minimal Android Compose shell.

## Coding style

- Kotlin code style: **official** (`kotlin.code.style=official`).
- Keep modules pure and dependency-light.
- Prefer explicit, readable code over cleverness.

## Pull requests

- Ensure `./gradlew test` passes.
- Note any fixture changes clearly in the PR description.
