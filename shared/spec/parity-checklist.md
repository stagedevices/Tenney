# Tenney Parity Checklist (iOS ↔ Android)

This is the living checklist for keeping Tenney behavior consistent across platforms.
**Fixtures are the contract.** If behavior changes, bump fixture versions (`v1 → v2`) rather than silently editing existing expectations.

## Legend
- ✅ Done / parity verified
- 🟡 In progress
- ❌ Missing
- 🔁 Needs review / drift risk

---

## Fixture suites (contract-level parity)

| Area | Fixtures | Status |
|---|---|---|
| JSON contract + round-trip | `shared/fixtures/json/*` | ✅ |
| RatioMath | `shared/fixtures/math/ratio_math.*.json` | ✅ |
| TenneyScale derived metadata | `shared/fixtures/domain/tenney_scale_derived.*.json` | ✅ |
| Scala parse/serialize | `shared/fixtures/formats/scala_*.json` | ✅ |
| KBM parse/serialize | `shared/fixtures/formats/kbm_*.json` | ✅ |
| Lattice selection refs | `shared/fixtures/lattice/selection_refs.*.json` | ✅ |

---

## Android app-level parity (feature-level)

### Core flows
- Library load/save (TenneyScale JSON): ❌
- Import `.scl` (+ optional `.kbm`) into library: ❌
- Export TenneyScale JSON: ❌
- Export `.scl` / `.kbm`: ❌

### Screens (Compose)
- Root picker sheet: ❌
- Onboarding: ❌
- Settings + sheets: ❌
- Library: ❌
- Tuner + Stage mode: ❌
- Builder + Export sheet: ❌
- Lattice view (render + gestures): ❌
- Tuning wizard: ❌

### Platform integrations
- Audio engine parity: ❌
- MIDI parity: ❌
- Files (SAF / storage): ❌
- Sharing intents: ❌

---

## Rules of engagement
- Any parity mismatch should be filed as: **“Parity mismatch / fixture failure”** issue.
- Any bugfix should add or extend a fixture first whenever possible.
- Behavior changes require:
  - a written note in the relevant spec doc
  - new fixture versions (`v2`) if expectations change
