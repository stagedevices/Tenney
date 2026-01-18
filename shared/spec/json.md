# Tenney JSON contracts (shared)

This document defines the JSON conventions used by shared fixtures and Android parity tests.

## Core rules

- **UUID** values are serialized as **strings**.
- **Maps keyed by integers** are encoded as JSON objects with string keys. Example: `{ "3": 1, "5": -1 }`.
- **Date** values follow Swift `JSONEncoder/Decoder` defaults: numeric timestamps as **`Double` seconds since the reference date**. Android models should store these as `Double?` and preserve the value losslessly.

## Floating point tolerance

Tests that validate floating point outputs should compare with a small tolerance (typically `1e-6` or tighter) rather than exact equality. This applies to cents values and frequency calculations.
