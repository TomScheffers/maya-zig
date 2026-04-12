# Bitpack decode optimization log

## How to reproduce

```sh
zig test src/tests.zig -O ReleaseFast --test-filter bitpacking        # correctness
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack decodeInto" # correctness
zig test src/tests.zig -O ReleaseFast --test-filter bitpackTime        # perf: all num_bits
zig test src/tests.zig -O ReleaseFast --test-filter "bitpack perf"     # perf: num_bits=3
```

**Environment:** Windows, Zig 0.15.2, `-O ReleaseFast`. Wall times are noisy (±15–25%); prefer medians of several runs.

---

## Performance table — `bitpackTime` (10 iters × 1M values, ms)

| `num_bits` | Baseline (iter 0–1) | Iter 5 | Iter 8 | Iter 9 (current) |
|------------|---------------------|--------|--------|-------------------|
| 0 | — | 8.9 | 5.8 | 5.9 |
| 1 | — | 12.8 | 10.6 | 10.2 |
| 2 | — | 15.1 | 12.1 | 9.9 |
| 3 | — | 15.8 | 12.3 | 10.9 |
| 4 | — | 17.8 | 14.2 | 11.0 |
| 5 | — | 20.8 | 14.6 | 10.5 |
| 6 | — | 22.2 | 12.1 | 10.9 |
| 7 | — | 24.5 | 13.0 | 10.7 |
| **8** | — | **6.9** | **6.0** | **5.6** |
| 9 | — | 26.6 | 12.2 | 10.3 |
| 10 | — | 27.0 | 15.4 | 10.6 |
| 11 | — | 27.9 | 12.4 | 11.5 |
| 12 | — | 30.0 | 12.1 | 11.5 |
| 13 | — | 27.6 | 12.6 | 11.3 |
| 14 | — | 29.0 | 13.2 | 11.0 |
| 15 | — | 28.8 | 13.6 | 11.0 |
| **16** | — | **6.3** | **5.5** | **5.4** |
| 17 | — | 28.9 | 13.6 | 11.2 |
| 18 | — | 28.9 | 14.0 | 11.4 |
| 19 | — | 29.3 | 13.1 | 12.3 |
| 20 | — | 29.8 | 13.1 | 12.3 |
| 21 | — | 29.8 | 14.4 | 11.6 |
| 22 | — | 30.3 | 14.9 | 11.7 |
| 23 | — | 33.5 | 15.6 | 12.3 |
| **24** | — | **10.6** | **8.0** | **6.6** |

**Key observation:** Iter 5 had a sharp gap between byte-aligned (8/16/24) and non-aligned widths (~7 ms vs ~28 ms). Iter 8 (bulk `u64` refill) dropped non-aligned to ~12–16 ms. Iter 9 (split `lo`/`hi` registers) flattened further to ~10–12 ms across all widths.

Baseline (`bitpackTime`) was not recorded; early iterations only measured `num_bits = 3`.

---

## Experiment log

### Iteration 0 — Baseline

Original decoder with `std.math.pow` masks and `helpers.sliceToUInt` reloads. Bench used truncating `buf_len` (one byte short for non-aligned counts).

`bitpack perf` (`num_bits = 3`): scalar 15×1M = **17.8 ms**, u64 20×1M003 = **46.0 ms**.

---

### Iteration 1 — `maskLower` instead of `std.math.pow`

Replaced `std.math.pow(T, 2, n)` with `(@as(T, 1) << n) - 1`. Scalar → **15.3 ms**, u64 → **30.7 ms**.

**Verdict:** Keep.

---

### Iteration 2 — Bit-stream accumulator

Replaced `sliceToUInt` with a classic `u64` refill/emit/shift-down loop. Fixed ceiling `buf_len`. Scalar → **~10.8–15.7 ms**, u64 → **~22–24 ms**.

**Verdict:** Keep.

---

### Iteration 3 — Correct buffer size checks

Required `(num_bits * num_values + 7) / 8` bytes everywhere. Correctness fix, no separate timing impact.

**Verdict:** Keep.

---

### Iteration 4 — Remove `bitpackDecodeSIMD`

SIMD path didn't beat tuned scalar; removed to simplify API.

**Verdict:** Keep.

---

### Iteration 5 — Single-pass decode, byte-aligned fast path, `bitpackDecodeInto`

Eliminated chunk loop + residual scratch. Added `decodePackByteAligned` (`num_bits % 8 == 0` → `readInt`). Added allocation-free `bitpackDecodeInto`. First full `bitpackTime` recorded (see table above, "Iter 5" column).

**Verdict:** Keep.

---

### Iteration 6 — Drop dead `u128`, pointer refill, linear offset

Non-aligned widths can never be 64, so the `u128` branch was dead code. Switched to `[*]const u8` pointer walk and `u6` shift. Byte-aligned path uses `off += num_bytes` instead of `i * num_bytes`.

`bitpack perf` (`num_bits = 3`): scalar → **~13.3–15.3 ms**, u64 → **~24.7–25.3 ms**. Non-aligned `bitpackTime` unchanged (~28–42 ms).

**Verdict:** Keep.

---

### Iteration 7 — Hoist byte-aligned switch (reverted)

Moved `switch (num_bytes)` outside the per-value loop to create 8 dedicated inner loops. Marginal benefit on byte-aligned widths, large code duplication.

**Verdict:** Reverted.

---

### Iteration 8 — Bulk `u64` refill with `u128` accumulator

**Key insight:** the byte-at-a-time refill triggered ~375K inner-while iterations per 1M values at `num_bits = 3`. By widening the accumulator to `u128`, we load a full `u64` (8 bytes) in one `readInt` when bits run low, cutting refill iterations ~8×. Byte-at-a-time tail handles the final < 8 bytes.

Non-aligned `bitpackTime` improved **~2–3× across the board** (see table above, "Iter 8" column). `bitpack perf` (`num_bits = 3`): scalar → **~12.6–15.5 ms**, u64 → **~24.0–29.6 ms**.

**Verdict:** Keep.

---

### Iteration 9 — Split `lo`/`hi` u64 registers instead of `u128` accumulator

Replaced the `u128` accumulator with explicit `lo: u64` + `hi: u64`. Extraction (`lo & msk`, `lo >>= sh`) stays in native `u64` ops — no multi-register `u128` shift per value. The `hi` register only participates during the cross-word transition (`avail > 64`). Also tried an unrolled batch emit loop (iteration 9a) but it regressed due to runtime `batch` preventing LLVM optimization; reverted to per-value loop.

Non-aligned `bitpackTime` improved ~15–20% vs iter 8 (e.g. `num_bits = 5`: 14.6 → 10.5 ms; `num_bits = 22`: 14.9 → 11.7 ms). Profile is now very flat: ~10–12 ms for all non-aligned widths.

**Verdict:** Keep.

---

## Findings

1. **Ceiling byte length:** `(num_values * num_bits + 7) / 8`.
2. **Masks:** `(1 << n) - 1` beats `std.math.pow` on hot paths.
3. **Single pass** over the buffer (no chunking + scratch).
4. **`num_bits % 8 == 0` → `readInt`** fast path.
5. **`bitpackDecodeInto`** when output storage already exists.
6. **Bulk `u64` refill** reduces refill iterations ~8× and yields 2–3× speedup on non-aligned widths.
7. **Split `lo`/`hi` u64 registers** beat a `u128` accumulator: extraction stays in native `u64` ops; `hi` only participates during cross-word transitions.

---

## Ideas not tried

- **`memcpy` bulk decode** when packed layout matches a native `[]T` layout.
- **`rleHybridDecode` + `bitpackDecodeInto`** when output capacity is known up front.
