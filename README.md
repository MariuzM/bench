# Zig vs Jai benchmarks

A small head-to-head benchmark suite comparing **Zig** and **Jai** on runtime
speed, peak memory, binary size and compile time. The same five workloads are
implemented in each language; a build script compiles both, runs every
benchmark under `/usr/bin/time`, and prints a side-by-side table.

> ⚠️ **This is not the official Jai compiler.** The Jai side is built with
> **OpenJai**, an MIT-licensed clean-room Jai-compatible compiler — *not*
> Jonathan Blow's closed-beta Jai toolchain. Results reflect OpenJai's code
> generation, which is not representative of official Jai. See
> [OpenJai: an MIT-licensed cleanroom Jai compiler](https://github.com/withlang-dev/open-jai)
> and the [compiler notes](#a-note-on-the-jai-compiler-openjai) below.

## Layout

| File         | What it is                                                        |
| ------------ | ----------------------------------------------------------------- |
| `main.zig`   | All five benchmarks; runs one, chosen by a command-line argument. |
| `main.jai`   | The same five benchmarks in Jai.                                  |
| `bench.sh`   | Builds both, times/measures each benchmark, prints the table.     |

Each program runs exactly one benchmark per process (`./prog fib`,
`./prog sieve`, …) so peak memory is measured in isolation.

## The benchmarks

| Name         | What it stresses                                            |
| ------------ | ---------------------------------------------------------- |
| `fib`        | Recursion / function-call overhead (`fib(30..42)`).        |
| `mandelbrot` | Floating-point math, tight scalar loop (1200×1200, 1000 iters). |
| `matmul`     | Integer compute + cache behaviour (512×512 multiply).      |
| `sieve`      | Memory-bound streaming over a 50M-byte array.              |
| `sort`       | Quicksort of 3,000,000 integers (compute + memory).        |

Every benchmark prints a `checksum` line. The two languages must produce the
**same** checksum — that's how the script proves both did identical work before
comparing their timings.

## Running

```sh
./bench.sh
```

Useful overrides:

```sh
RUNS=10 ./bench.sh                 # more repeats (best wall-time is kept)
ZIG=/path/to/zig JAI=/path/to/jai ./bench.sh
```

Output reports, per benchmark, the best-of-N wall time and peak resident memory
for each language and who won, plus binary size and compile time.

## Results

Best of 3 runs on the [test system](#test-system) below (lower time is better,
lower memory is better):

| benchmark    | zig time | jai time | faster    | zig peak | jai peak | leaner |
| ------------ | -------: | -------: | --------- | -------: | -------: | ------ |
| `fib`        |   2.10 s |   2.06 s | jai 1.02× |   1.2 MB |   1.5 MB | zig    |
| `mandelbrot` |   0.45 s |   0.46 s | zig 1.02× |   1.2 MB |   1.5 MB | zig    |
| `matmul`     |   0.04 s |   3.79 s | zig 94.8× |   7.2 MB |   7.7 MB | zig    |
| `sieve`      |   0.12 s |   1.61 s | zig 13.4× |  48.9 MB |  49.3 MB | zig    |
| `sort`       |   0.20 s |   0.26 s | zig 1.30× |  24.1 MB |  24.5 MB | zig    |

| metric      | zig    | jai (OpenJai) |
| ----------- | ------ | ------------- |
| binary size | 0.4 MB | 4.6 MB        |
| compile time | 5.45 s | 1.06 s       |

**Takeaways:**

- Roughly **tied on recursion** (`fib`) and **floating-point** (`mandelbrot`) —
  the two backends generate comparable scalar code there.
- Zig wins **massively on tight integer loops**: `matmul` (~95×) and `sieve`
  (~13×). Zig's LLVM `ReleaseFast` auto-vectorizes these; OpenJai 0.1.0 does not.
- Zig is consistently a little **leaner on peak memory** (~0.3–0.5 MB) and
  produces a **~10× smaller binary**.
- OpenJai **compiles ~5× faster** than Zig here.

Numbers are machine-specific — re-run `./bench.sh` for your own hardware. These
reflect **OpenJai 0.1.0**, not the official Jai compiler (see notes below).

## Reproducibility notes

- **Zig** is built with `-O ReleaseFast` (LLVM backend, full optimization).
- **Jai** is built with `-release`.
- Time is the **best** of `RUNS` runs (least affected by OS noise); memory is the
  **peak** resident set size reported by `/usr/bin/time -l`.
- Both produce identical results, so the comparison reflects code generation and
  runtime, not different algorithms.

## Test system

The numbers in this repo were produced on:

| | |
| --- | --- |
| Machine | Apple MacBook Pro (MacBookPro18,2) |
| CPU | Apple M1 Max (10 cores), arm64 |
| Memory | 64 GB |
| OS | macOS 15.7.7 (build 24G720) |
| Zig | 0.16.0 (LLVM backend, `-O ReleaseFast`) |
| Jai | OpenJai 0.1.0 (`-release`) |

Absolute timings are machine-specific; re-run `./bench.sh` to get numbers for
your own hardware.

## A note on the Jai compiler (OpenJai)

The Jai toolchain here is **[OpenJai](https://github.com/withlang-dev/open-jai)**,
an MIT-licensed clean-room Jai-compatible compiler — a separate project from the
official (closed-beta) Jai compiler. While writing the suite I hit three
behaviours in this build that differ from Zig and had to be worked around so
both languages compute identical results. They're documented inline in
`main.jai`:

1. **First call to a recursive, value-returning function miscompiles to `0`.**
   The very first invocation of `fib` used inside an accumulating expression
   returned `0` (and did no work). A throwaway warm-up call before the measured
   loop primes correct code generation. The warm-up is negligible next to the
   real workload, so timings are unaffected.
2. **`u64` comparison is signed.** `a < b` on `u64` operands compiles to a signed
   compare, so values with the high bit set sort incorrectly relative to Zig.
3. **`u64` right shift is arithmetic** (sign-extending) rather than logical.

To keep the `sort` benchmark identical across both languages, it uses an LCG
(multiply + add only, which is bit-identical in both) instead of an xorshift
(which relies on logical `>>`), and masks each sort key's high bit with bitwise
`&` (sign-independent). `u64` *arithmetic* (add/multiply/xor with wraparound) is
correct in this build — only signed-sensitive comparison and shifts differ.

These are properties of this particular compiler build, not of the Jai language.
