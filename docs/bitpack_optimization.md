# Bitpack decode optimization log

## How to reproduce

Use **ReleaseFast** so LLVM can optimize the hot loops:

```sh
zig test src/tests.zig -O ReleaseFast --test-filter bitpacking
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack perf"
zig test src/tests.zig -O ReleaseFast --test-filter bitpackTime
```

- **`bitpacking`**: correctness for the 3-bit × 16 value fixture (`bitpackDecode`, `u64`).
- **`bitpack perf`**: wall-clock totals for fixed iteration counts (see `tests.zig`).
- **`bitpackTime`**: `bitpackDecode` over `num_bits = 0..24`, 1M values, 10 iters each (noisy on laptops).

Windows wall times vary ±20% between runs; treat numbers as directional, not exact microbenchmarks.

---

## Baseline (start of this pass)

`bitpack perf` before any `bitpack.zig` edits in this session:

| Case | Metric | Value |
|------|--------|--------|
| Scalar `u32` | 15 × 1M values `bitpackDecode`, `num_bits = 3` | **17.780 ms** total (historical) |
| `u64` residual | 20 × 1,000,003 values `bitpackDecode` (was `bitpackDecodeSIMD` in early runs) | **45.969 ms** total (historical; bench buffer was initially too short) |

**Note:** `bitpackDecodeSIMD` was removed; **`bitpackDecode`** is the only entry point (faster / simpler in practice than the old SIMD path for typical Parquet widths).

**Bug found:** the SIMD benchmark used `buf_len = num_values * num_bits / 8` (truncating). For `1_000_003 × 3` bits that is **one byte short** of the true packed length. The old `decodePack` tail often did not fail outright (it used `sliceToUInt` on short slices), so the benchmark was misleading. The bench now uses **`(num_values * num_bits + 7) / 8`**.

---

## Iteration 1 — `maskLower` instead of `std.math.pow`

**Hypothesis:** `std.math.pow(T, 2, n)` is unnecessary for an integer bitmask; `((@as(T, 1) << n) - 1)` (with full-width handling) is cheaper and easier for the backend to fold.

**Change:** Added `maskLower` (later folded into inline masks in `decodePack` / SIMD); SIMD path since removed in favor of **`bitpackDecode` only**.

**Result (same flawed SIMD buffer as baseline):** scalar **15.306 ms** / 15 iters; SIMD **30.665 ms** / 20 iters — clear win on SIMD vs 45.969 ms; scalar improved vs 17.780 ms.

**Verdict:** **Keep.**

---

## Iteration 2 — Bit-stream `decodePack`

**Hypothesis:** Reloading with `helpers.sliceToUInt` on complicated boundaries is slower than a classic **64-bit (or 128-bit) accumulator**: pull bytes until `avail >= num_bits`, emit one value, shift down.

**Change:**

- Rewrote `decodePack` to a little-endian bit reader.
- **`num_bits <= 63`:** `u64` accumulator (hot path for Parquet widths).
- **`num_bits == 64`:** `u128` accumulator branch (rare; avoids shift/mask overflow on `u64`).

**Result (with corrected SIMD benchmark buffer):** scalar **~10.8–15.7 ms** / 15 iters across runs; SIMD **~22–24 ms** / 20 iters. Scalar is substantially better than the pre–bit-stream baseline on `num_bits = 3`.

**Verdict:** **Keep** (correctness preserved; `bitpacking` and `bitpackTime` pass under ReleaseFast).

---

## Iteration 3 — Buffer size checks and residual padding

**Hypothesis:** Truncating integer division for “bytes required” can declare a buffer valid when the last partial byte is missing.

**Change:**

- `bitpackDecode`: require **`(num_bits * num_values + 7) / 8`** bytes.
- Residual scratch in `bitpackDecode`: allocate **`(chunk_size * num_bits + 7) / 8`** bytes.

**Verdict:** **Keep** (API correctness; aligns with the Parquet packed layout).

---

## Summary table (ReleaseFast, same machine session)

| Step | Scalar 15×1M (ms) | u64 20×1M003 (ms) | Notes |
|------|-------------------|-------------------|--------|
| Baseline | 17.780 | 45.969 | Second column bench buffer too short |
| + `maskLower` | 15.306 | 30.665 | Still short buffer on u64 bench |
| + bit-stream + ceil buffer | ~10.8–15.7 | ~22–24 | Comparable conditions |

**Takeaways**

1. Always size packed buffers with **ceiling** bit length: `(values * width + 7) / 8`.
2. Prefer **bit shifts** over `pow` for decode masks.
3. A **streaming bit reader** (`u64` fast path) beats repeated `sliceToUInt` for the scalar decoder on large inputs.
4. For serious tuning: use `perf`/VTune, pin CPU frequency, and average many runs; add a `std.testing` checksum over decoded output so the bench cannot “optimize away” work incorrectly.

---

## Ideas not tried (future work)

- **Unaligned `readInt`** on the SIMD inner loop when `byte_offset + 8 <= buf.len` to skip `sliceToUInt` branches.
- **`@Vector` unroll** for multiple 512-bit chunks per iteration when `num_bits` is tiny.
- **Dedicated `num_bits % 8 == 0`** fast path (plain byte or `T`-sized loads) without the generic bit reader.
- **Avoid `Managed` + per-decode alloc** in benchmarks by a `decodeInto([]T)` API (measure decode only).
