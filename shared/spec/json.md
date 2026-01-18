# Tenney JSON Contract

This document defines the **canonical JSON shapes** used for cross-platform parity (iOS ↔ Android) and fixture-driven tests.

## Guiding principles

- **Fixtures are the contract.** Behavior changes require new fixture versions (`v1 → v2`), not silent edits.
- **Be lossless.** Preserve numeric precision and integer-keyed maps exactly as encoded.
- **Deterministic encoding.** When generating JSON, use stable ordering and formatting so diffs are meaningful.

---

## Primitive conventions

### UUID
- Stored as a JSON **string**.
- Example: `"id": "3C0D2E88-9BB5-4E4B-8A18-6BA6E06F9F88"`

### Integer-keyed maps
- Maps keyed by integers are encoded as **JSON objects with string keys**.
- Example (monzo map):
  ```json
  "monzo": { "3": 1, "5": -2 }
  ```

### Dates / timestamps (`lastPlayed`)

* Tenney fixtures use Swift’s default `JSONEncoder/JSONDecoder` date behavior: **numeric timestamp** (Double), **not** ISO-8601 strings.
* Android should model this as `Double?` and preserve it losslessly.

---

## Core data shapes

### RatioRef (v1)

```json
{
  "p": 3,
  "q": 2,
  "octave": 0,
  "monzo": {}
}
```

Rules:

* `p`, `q` are integers (>= 1 after normalization).
* `octave` is integer (can be negative/positive).
* `monzo` is an object map `{ "<prime>": <exponent-int> }` (string keys).
* **Normalization parity:** if `p <= 0` or `q <= 0`, clamp to `1` (mirrors defensive init behavior).

### TenneyScale (v1)

Canonical keys (current format):

* `name` (string)
* `descriptionText` (string, optional or empty)
* `degrees` (array of RatioRef-like objects)
* `referenceHz` (Double)
* `periodRatio` (RatioRef-like object)
* Optional metadata:

  * `tags` (array of strings)
  * `favorite` (bool)
  * `author` (string)
  * `rootLabel` (string)
  * `lastPlayed` (Double timestamp)

Derived fields:

* `detectedLimit` (int)
* `maxTenneyHeight` (int)

Note: derived fields are included in fixtures to assert parity; platforms may compute them but must match fixture expectations.

---

## Legacy decode compatibility

Some historical exports may use legacy keys:

* `rootHz`
* `tones`
* `notes`

Android should support ingesting legacy shapes and converting to the canonical current model during decode/import.

---

## Numeric comparison rules (fixtures)

* Integer fields must match exactly.
* Floating values:

  * Prefer exact matches where values are explicitly specified.
  * Where tolerance is needed (Hz/cents), use a shared epsilon:

    * `EPS_HZ = 1e-9`
    * `EPS_CENTS = 1e-6`
  * Any tolerance should be stated in the corresponding fixture test harness.
