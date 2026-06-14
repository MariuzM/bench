# C vs C++ vs Jai vs JavaScript vs Odin vs Rust vs Zig benchmarks

A small head-to-head benchmark suite comparing **C**, **C++**, **Jai**,
**JavaScript** (Node.js), **Odin**, **Rust** and **Zig** on runtime speed, peak
memory, binary size and compile time. The same six workloads are implemented in
each language; a build script compiles the six native suites (and launches the
JavaScript suite under Node), runs every benchmark under `/usr/bin/time`, and
prints a side-by-side table.

> ⚠️ **This is not the official Jai compiler.** The Jai side is built with
> **OpenJai**, an MIT-licensed clean-room Jai-compatible compiler — *not*
> Jonathan Blow's closed-beta Jai toolchain. Results reflect OpenJai's code
> generation, which is not representative of official Jai. See
> [OpenJai: an MIT-licensed cleanroom Jai compiler](https://github.com/withlang-dev/open-jai)
> and the [compiler notes](#a-note-on-the-jai-compiler-openjai) below.

## Layout

| File         | What it is                                                        |
| ------------ | ----------------------------------------------------------------- |
| `main.c`     | All six benchmarks; runs one, chosen by a command-line argument.  |
| `main.cpp`   | The same six benchmarks in C++.                                   |
| `main.jai`   | The same six benchmarks in Jai.                                  |
| `main.js`    | The same six benchmarks in JavaScript (run with Node.js).         |
| `main.odin`  | The same six benchmarks in Odin.                                  |
| `main.rs`    | The same six benchmarks in Rust.                                  |
| `main.zig`   | The same six benchmarks in Zig.                                   |
| `bench.sh`   | Builds/launches all seven, times each benchmark, prints the table.|

Each program runs exactly one benchmark per process (`./prog fib`,
`./prog sieve`, …) so peak memory is measured in isolation.

## The benchmarks

| Name         | What it stresses                                            |
| ------------ | ---------------------------------------------------------- |
| `collatz`    | Unpredictable branches + integer divide/modulo (Collatz steps for 1..3M). |
| `fib`        | Recursion / function-call overhead (`fib(30..42)`).        |
| `mandelbrot` | Floating-point math, tight scalar loop (1200×1200, 1000 iters). |
| `matmul`     | Integer compute + cache behaviour (512×512 multiply).      |
| `sieve`      | Memory-bound streaming over a 50M-byte array.              |
| `sort`       | Quicksort of 3,000,000 integers (compute + memory).        |

Every benchmark prints a `checksum` line. All seven languages must produce the
**same** checksum — that's how the script proves everyone did identical work
before comparing their timings. JavaScript uses `BigInt` for the `sort`
benchmark's 64-bit wrapping arithmetic so it stays bit-identical with the
native builds. C and C++ are built with `-ffp-contract=off` so the `mandelbrot`
float math doesn't fuse into FMA (which would diverge from the other backends).

## Running

```sh
./bench.sh
```

Useful overrides:

```sh
RUNS=10 ./bench.sh                 # more repeats (best wall-time is kept)
CC=/path/to/cc CXX=/path/to/c++ JAI=/path/to/jai ODIN=/path/to/odin RUSTC=/path/to/rustc ZIG=/path/to/zig NODE=/path/to/node ./bench.sh
```

Output reports, per benchmark, the best-of-N wall time and peak resident memory
for each language and who won, plus binary size and compile time.

## Results

Best of 3 runs on the [test system](#test-system) below (lower is better).

### Wall-clock time (seconds)

| benchmark    |    c |  cpp |  jai |   js | odin | rust |  zig | fastest |
| ------------ | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ------- |
| `collatz`    | 0.43 | 0.43 | 0.43 | 6.54 | 0.42 | 0.42 | 0.42 | odin/rust/zig |
| `fib`        | 2.06 | 2.07 | 2.07 | 6.73 | 2.12 | 2.13 | 2.13 | c       |
| `mandelbrot` | 0.46 | 0.46 | 0.46 | 0.51 | 0.47 | 0.46 | 0.46 | c/cpp/jai/rust/zig |
| `matmul`     | 0.04 | 0.04 | 3.80 | 0.21 | 0.06 | 0.04 | 0.04 | c/cpp/rust/zig |
| `sieve`      | 0.10 | 0.10 | 1.66 | 0.21 | 0.10 | 0.10 | 0.13 | c/cpp/odin/rust |
| `sort`       | 0.20 | 0.20 | 0.26 | 0.50 | 0.20 | 0.21 | 0.20 | c/cpp/odin/zig |

### Peak memory (MB)

| benchmark    |    c |  cpp |  jai |   js | odin | rust |  zig | leanest |
| ------------ | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ------- |
| `collatz`    |  1.0 |  1.0 |  1.6 | 45.9 |  1.1 |  1.2 |  1.2 | c       |
| `fib`        |  1.0 |  1.0 |  1.5 | 44.7 |  1.1 |  1.3 |  1.3 | c       |
| `mandelbrot` |  1.0 |  1.1 |  1.5 | 47.9 |  1.1 |  1.2 |  1.2 | c       |
| `matmul`     |  7.1 |  7.1 |  7.6 | 49.9 |  7.2 |  7.3 |  7.3 | c       |
| `sieve`      | 48.7 | 48.8 | 49.3 | 93.9 | 48.8 | 48.9 | 48.9 | c       |
| `sort`       | 23.9 | 24.0 | 24.5 | 72.2 | 24.0 | 24.1 | 24.1 | c       |

### Binary size & compile time

| metric       | c       | cpp     | jai (OpenJai) | js (Node) | odin   | rust   | zig    |
| ------------ | ------- | ------- | ------------- | --------- | ------ | ------ | ------ |
| binary size  | 0.03 MB | 0.04 MB | 4.6 MB        | n/a       | 0.2 MB | 0.4 MB | 0.4 MB |
| compile time | 0.08 s  | 0.40 s  | 1.12 s        | n/a       | 1.21 s | 0.18 s | 5.83 s |

JavaScript is JIT-compiled by Node at run time, so it has no ahead-of-time
binary or compile step.

**Takeaways:**

- **C, C++, Odin, Rust and Zig are effectively tied** on the LLVM-backed
  workloads. They share the same code-generation backend (Clang/LLVM for C/C++),
  so `collatz`, `fib`, `mandelbrot`, `matmul` and `sort` land within noise of
  each other.
- C, C++, Odin, Rust and Zig **auto-vectorize the tight integer loops**
  (`matmul`, `sieve`); OpenJai 0.1.0 does *not*, so it is ~95× slower on
  `matmul` and ~13–17× slower on `sieve`.
- **`collatz` is where OpenJai catches up** (0.43 vs 0.42 s): its branchy,
  scalar, divide-heavy inner loop has no vectorizable structure, so the LLVM
  backends have no advantage to exploit. It's a good counterweight to `matmul`
  and `sieve`.
- **C is consistently the leanest on peak memory** — it has essentially no
  runtime, so it sits a fraction of a MB below everything else on every
  workload. C and C++ also ship the **smallest binaries** (~0.03–0.04 MB,
  single-file `-O3` with no static libc bloat).
- **C compiles fastest here** (single-file `cc -O3`, 0.08 s); C++ pays a little
  for `<iostream>`/`<vector>` template instantiation (0.40 s), while Zig's full
  `ReleaseFast` LLVM pipeline is the slowest to build.
- **JavaScript (Node V8) is more competitive than expected** on the hot numeric
  loops — `matmul`, `sieve` and `mandelbrot` land within a few× of native — but
  pays heavily on the branchy/recursive workloads (`collatz` and `fib`, both
  ~15× and ~3× slower), on `sort` (`BigInt` overhead), and on memory (a ~45 MB+
  runtime floor regardless of workload).

Numbers are machine-specific — re-run `./bench.sh` for your own hardware. The
Jai numbers reflect **OpenJai 0.1.0**, not the official Jai compiler (see notes
below).

## Reproducibility notes

- **C** is built with `cc -O3 -march=native -ffp-contract=off` (single file).
- **C++** is built with `c++ -O3 -march=native -ffp-contract=off -std=c++17`.
- **Jai** is built with `-release`.
- **JavaScript** runs on **Node.js** (no build step; V8 JIT-compiles at startup).
- **Odin** is built with `-o:speed`.
- **Rust** is built with `rustc -O` (single file, no Cargo).
- **Zig** is built with `-O ReleaseFast` (LLVM backend, full optimization).
- Time is the **best** of `RUNS` runs (least affected by OS noise); memory is the
  **peak** resident set size reported by `/usr/bin/time -l`.
- All seven produce identical checksums, so the comparison reflects code
  generation and runtime, not different algorithms.

## Test system

The numbers in this repo were produced on:

| | |
| --- | --- |
| Machine | Apple MacBook Pro (MacBookPro18,2) |
| CPU | Apple M1 Max (10 cores), arm64 |
| Memory | 64 GB |
| OS | macOS 15.7.7 (build 24G720) |
| C / C++ | Apple Clang 17.0.0 (`-O3 -march=native -ffp-contract=off`) |
| Jai | OpenJai 0.1.0 (`-release`) |
| JavaScript | Node.js v24.7.0 (V8) |
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
be worked around so all five compute identical results. They're documented
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

To keep the `sort` benchmark identical across all five languages, it uses an LCG
(multiply + add only, which is bit-identical everywhere) instead of an xorshift
(which relies on logical `>>`), and masks each sort key's high bit with bitwise
`&` (sign-independent). `u64` *arithmetic* (add/multiply/xor with wraparound) is
correct in this build — only signed-sensitive comparison and shifts differ.

These are properties of this particular compiler build, not of the Jai language.
