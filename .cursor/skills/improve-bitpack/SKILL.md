---
name: improve-bitpack
description: Optimizes Parquet-style bit-packed decoders using baselines, ReleaseFast benchmarks, hypothesis-driven changes, and updates to docs/bitpack_optimization.md. Use when improving bitpack in maya-zig, tuning parquet encodings, or when the user mentions bitpack, bitpackDecode, decodePack, or bitpack performance docs.
---

# Improve bitpack (maya-zig)

## Scope

- **Code:** `src/parquet/encodings/bitpack.zig`, callers (e.g. `src/parquet/encodings/rle.zig`), tests in `src/tests.zig` (`bitpacking`, `bitpack perf`, `bitpackTime`, `bitpack decodeInto`).
- **Doc:** `docs/bitpack_optimization.md` — experiment log + performance table across all `num_bits`.

Assume **Zig 0.15.x** and **`std.array_list.Managed`** where the codebase uses it.

## Current architecture

The decoder has two paths selected by `decodePack`:

1. **`decodePackByteAligned`** — when `num_bits % 8 == 0`. Reads whole bytes per value via `std.mem.readInt`.
2. **`decodePackBitStream`** — non-aligned widths. Uses a **`u128` accumulator** with **bulk `u64` refill** (loads 8 bytes at once via `readInt(u64, …)` when `avail < num_bits`). Byte-at-a-time tail for the final < 8 bytes. This is the key optimization — it reduces refill iterations ~8× vs loading one byte at a time.

Public API: `bitpackDecode` (allocating) and `bitpackDecodeInto` (caller-owned buffer).

## Workflow (each change)

1. **Baseline:** Run `bitpackTime` with **`-O ReleaseFast`** before edits to get timings across **all `num_bits` 0–24**:
   - `zig test src/tests.zig -O ReleaseFast --test-filter bitpackTime`
2. **Hypothesis:** One clear claim (e.g. "bulk loading reduces refill branches").
3. **Minimal diff:** Touch only what the hypothesis requires; keep correctness tests green.
4. **Measure again:** Run `bitpackTime` again; compare **all widths**, not just one. Note variance (Windows ±15–25% is normal — run multiple times or report range).
5. **Document** — see below.

## Correctness

- Packed byte length: **`(num_values * num_bits + 7) / 8`** required in buffer; truncating division is wrong for tails.
- After changes, ensure **`bitpacking`** and **`bitpack decodeInto`** still pass.

## How to update `docs/bitpack_optimization.md`

### Performance table (`## Performance table`)

The main table shows **`bitpackTime`** results across **all `num_bits` 0–24** (10 iters × 1M values, ms). Each significant iteration gets its own column.

- When adding a new iteration with measurable impact, **add a new column** to the table (e.g. `Iter N (label)`).
- Always run `bitpackTime` to populate the full column — do **not** only measure a single `num_bits`.
- Use **—** for columns where data was never recorded.

### Experiment log (`## Experiment log`)

- Add a **new** subsection at the **end** of the log:

```markdown
### Iteration N — Short title

One-paragraph summary: what changed, key numbers, verdict.

**Verdict:** Keep | Revert | Partial …
```

- Increment **`N`** from the last iteration in the file.
- **Never remove** prior `### Iteration …` blocks.
- Keep entries **concise** — a few sentences, not full tables (the performance table has the numbers).

### Findings / Ideas sections

- **Findings:** May append new numbered bullets; avoid deleting established findings without user request.
- **Ideas not tried:** Append new bullets only.

## Commands (copy-paste)

```sh
cd maya-zig
zig test src/tests.zig -O ReleaseFast --test-filter bitpackTime        # perf: all num_bits
zig test src/tests.zig -O ReleaseFast --test-filter bitpacking          # correctness
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack decodeInto" # correctness
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack perf"      # perf: num_bits=3 only
```

## Anti-patterns

- Measuring only a single `num_bits` (e.g. 3) and missing regressions at other widths.
- Declaring victory on **one** noisy timing sample.
- Broad refactors mixed with a single bitpack hypothesis.
- Removing the `u128` bulk-refill without a replacement — byte-at-a-time refill is ~2–3× slower on non-aligned widths.

## Optional deep dive

If `SKILL.md` grows, add `reference.md` in this folder with full Parquet bit-pack layout notes — link one level deep from here only.
