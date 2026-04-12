---
name: improve-bitpack
description: Optimizes Parquet-style bit-packed decoders using baselines, ReleaseFast benchmarks, hypothesis-driven changes, and append-only updates to docs/bitpack_optimization.md. Use when improving bitpack in maya-zig, tuning parquet encodings, or when the user mentions bitpack, bitpackDecode, decodePack, or bitpack performance docs.
---

# Improve bitpack (maya-zig)

## Scope

- **Code:** `src/parquet/encodings/bitpack.zig`, callers (e.g. `src/parquet/encodings/rle.zig`), tests in `src/tests.zig` (`bitpacking`, `bitpack perf`, `bitpackTime`, `bitpack decodeInto`).
- **Doc:** `docs/bitpack_optimization.md` — experiment log + performance tables.

Assume **Zig 0.15.x** and **`std.array_list.Managed`** where the codebase uses it.

## Workflow (each change)

1. **Baseline:** Run tests with **`-O ReleaseFast`** before edits:
   - `zig test src/tests.zig -O ReleaseFast --test-filter "bitpack"`
2. **Hypothesis:** One clear claim (e.g. “byte-aligned `num_bits % 8` avoids shift loop”).
3. **Minimal diff:** Touch only what the hypothesis requires; keep correctness tests green.
4. **Measure again:** Same filter; note variance (Windows ±15–25% is normal — run multiple times or report range).
5. **Document (append-only — see below).**

## Correctness

- Packed byte length: **`(num_values * num_bits + 7) / 8`** required in buffer; truncating division is wrong for tails.
- After changes, ensure **`bitpacking`** and **`bitpack decodeInto`** (if relevant) still pass.

## How to update `docs/bitpack_optimization.md` (append-only)

**Do not delete, shorten, or reorder** historical experiment sections or old rows in the master performance table. **Append** new material only.

### Experiment log (`## Experiment log`)

- Add a **new** subsection at the **end** of the log:

```markdown
### Iteration N — Short title

**Hypothesis:** …
**Change:** …
**Result:** … (tables / numbers)
**Verdict:** Keep | Revert | Partial …
```

- Increment **`N`** from the last iteration in the file.
- **Never remove** prior `### Iteration …` blocks. Typos: fix only with explicit user OK if it rewrites history.

### Master performance table (`## Master performance table`)

- **Append** one or more new **rows at the bottom** of the table (next `#` index).
- Columns stay consistent with the existing header (e.g. `# | Step | Scalar 15×1M (ms) | u64 20×1M003 (ms) | Notes`).
- If a column does not apply, use **—** (same as prior rows).
- **Do not delete** old rows; **do not reorder** rows to sort by speed.

### Latest timings / `bitpackTime` snapshots

- Prefer **appending** a new dated snapshot rather than overwriting the only snapshot:

```markdown
### Snapshot YYYY-MM-DD (optional label)

[same table shapes as existing Latest section]
```

- If the doc owner keeps a **single** “current” table without history, only update that block when they explicitly ask to refresh the snapshot — still **do not** erase the experiment log or master table rows.

### Findings / Ideas sections

- **Findings:** May append new numbered bullets; avoid deleting established findings without user request.
- **Ideas not tried:** Append new bullets only.

## Commands (copy-paste)

```sh
cd maya-zig
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack"
zig test src/tests.zig -O ReleaseFast --test-filter bitpacking
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack perf"
zig test src/tests.zig -O ReleaseFast --test-filter bitpackTime
```

## Anti-patterns

- Replacing the whole doc to “clean it up” (loses experiment history).
- Sorting the master table by speed (breaks chronological experiment record).
- Declaring victory on **one** noisy timing sample.
- Broad refactors mixed with a single bitpack hypothesis.

## Optional deep dive

If `SKILL.md` grows, add `reference.md` in this folder with full Parquet bit-pack layout notes — link one level deep from here only.
