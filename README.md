# Jai vs Odin vs Rust vs Zig benchmarks

A small head-to-head benchmark suite comparing **Jai**, **Odin**, **Rust** and
**Zig** on runtime speed, peak memory, binary size and compile time. The same
five workloads are implemented in each language; a build script compiles all
four, runs every benchmark under `/usr/bin/time`, and prints a side-by-side
table.

> ⚠️ **This is not the official Jai compiler.** The Jai side is built with
> **OpenJai**, an MIT-licensed clean-room Jai-compatible compiler — *not*
> Jonathan Blow's closed-beta Jai toolchain. Results reflect OpenJai's code
> generation, which is not representative of official Jai. See
> [OpenJai: an MIT-licensed cleanroom Jai compiler](https://github.com/withlang-dev/open-jai)
> and the [compiler notes](#a-note-on-the-jai-compiler-openjai) below.

## Layout

| File         | What it is                                                        |
| ------------ | ----------------------------------------------------------------- |
| `main.jai`   | All five benchmarks; runs one, chosen by a command-line argument. |
| `main.odin`  | The same five benchmarks in Odin.                                 |
| `main.rs`    | The same five benchmarks in Rust.                                 |
| `main.zig`   | The same five benchmarks in Zig.                                  |
| `bench.sh`   | Builds all four, times/measures each benchmark, prints the table. |

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

Every benchmark prints a `checksum` line. All four languages must produce the
**same** checksum — that's how the script proves everyone did identical work
before comparing their timings.

## Running

```sh
./bench.sh
```

Useful overrides:

```sh
RUNS=10 ./bench.sh                 # more repeats (best wall-time is kept)
JAI=/path/to/jai ODIN=/path/to/odin RUSTC=/path/to/rustc ZIG=/path/to/zig ./bench.sh
```

Output reports, per benchmark, the best-of-N wall time and peak resident memory
for each language and who won, plus binary size and compile time.

## Results

Best of 3 runs on the [test system](#test-system) below (lower is better).

### Wall-clock time (seconds)

| benchmark    |  jai | odin | rust |  zig | fastest    |
| ------------ | ---: | ---: | ---: | ---: | ---------- |
| `fib`        | 2.08 | 2.14 | 2.13 | 2.13 | jai 1.02×  |
| `mandelbrot` | 0.47 | 0.46 | 0.46 | 0.46 | ~tie       |
| `matmul`     | 3.83 | 0.06 | 0.04 | 0.04 | rust/zig   |
| `sieve`      | 1.68 | 0.10 | 0.10 | 0.13 | odin/rust  |
| `sort`       | 0.26 | 0.20 | 0.20 | 0.20 | odin/rust/zig |

### Peak memory (MB)

| benchmark    |  jai | odin | rust |  zig | leanest |
| ------------ | ---: | ---: | ---: | ---: | ------- |
| `fib`        |  1.5 |  1.1 |  1.2 |  1.2 | odin    |
| `mandelbrot` |  1.5 |  1.1 |  1.2 |  1.2 | odin    |
| `matmul`     |  7.7 |  7.2 |  7.3 |  7.2 | odin    |
| `sieve`      | 49.3 | 48.8 | 48.9 | 49.0 | odin    |
| `sort`       | 24.5 | 24.0 | 24.1 | 24.1 | odin    |

### Binary size & compile time

| metric       | jai (OpenJai) | odin   | rust   | zig    |
| ------------ | ------------- | ------ | ------ | ------ |
| binary size  | 4.6 MB        | 0.2 MB | 0.4 MB | 0.4 MB |
| compile time | 1.09 s        | 1.21 s | 0.18 s | 5.84 s |

**Takeaways:**

- **Odin, Rust and Zig are effectively tied** on the LLVM-backed workloads.
  They share the same code-generation backend, so `fib`, `mandelbrot`, `matmul`
  and `sort` land within noise of each other.
- Odin, Rust and Zig **auto-vectorize the tight integer loops** (`matmul`,
  `sieve`); OpenJai 0.1.0 does *not*, so it is ~95× slower on `matmul` and
  ~13–17× slower on `sieve`.
- **Odin is consistently the leanest on peak memory** (a fraction of a MB ahead)
  and ships the **smallest binary** (0.2 MB).
- **Rust compiles fastest here** (single-file `rustc -O`, 0.18 s), while Zig's
  full `ReleaseFast` LLVM pipeline is the slowest to build.

Numbers are machine-specific — re-run `./bench.sh` for your own hardware. The
Jai numbers reflect **OpenJai 0.1.0**, not the official Jai compiler (see notes
below).

## Reproducibility notes

- **Jai** is built with `-release`.
- **Odin** is built with `-o:speed`.
- **Rust** is built with `rustc -O` (single file, no Cargo).
- **Zig** is built with `-O ReleaseFast` (LLVM backend, full optimization).
- Time is the **best** of `RUNS` runs (least affected by OS noise); memory is the
  **peak** resident set size reported by `/usr/bin/time -l`.
- All four produce identical checksums, so the comparison reflects code
  generation and runtime, not different algorithms.

## Test system

The numbers in this repo were produced on:

| | |
| --- | --- |
| Machine | Apple MacBook Pro (MacBookPro18,2) |
| CPU | Apple M1 Max (10 cores), arm64 |
| Memory | 64 GB |
| OS | macOS 15.7.7 (build 24G720) |
| Jai | OpenJai 0.1.0 (`-release`) |
| Odin | dev-2024-04-nightly (`-o:speed`) |
| Rust | 1.90.0 (`rustc -O`) |
| Zig | 0.16.0 (LLVM backend, `-O ReleaseFast`) |

Absolute timings are machine-specific; re-run `./bench.sh` to get numbers for
your own hardware.

## A note on the Jai compiler (OpenJai)

The Jai toolchain here is **[OpenJai](https://github.com/withlang-dev/open-jai)**,
an MIT-licensed clean-room Jai-compatible compiler — a separate project from the
official (closed-beta) Jai compiler. While writing the suite I hit three
behaviours in this build that differ from the LLVM-backed languages and had to
be worked around so all four compute identical results. They're documented
inline in `main.jai`:

1. **First call to a recursive, value-returning function miscompiles to `0`.**
   The very first invocation of `fib` used inside an accumulating expression
   returned `0` (and did no work). A throwaway warm-up call before the measured
   loop primes correct code generation. The warm-up is negligible next to the
   real workload, so timings are unaffected.
2. **`u64` comparison is signed.** `a < b` on `u64` operands compiles to a signed
   compare, so values with the high bit set sort incorrectly relative to the
   other languages.
3. **`u64` right shift is arithmetic** (sign-extending) rather than logical.

To keep the `sort` benchmark identical across all four languages, it uses an LCG
(multiply + add only, which is bit-identical everywhere) instead of an xorshift
(which relies on logical `>>`), and masks each sort key's high bit with bitwise
`&` (sign-independent). `u64` *arithmetic* (add/multiply/xor with wraparound) is
correct in this build — only signed-sensitive comparison and shifts differ.

These are properties of this particular compiler build, not of the Jai language.
