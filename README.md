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
