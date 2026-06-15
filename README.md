# C vs C++ vs Jai vs JavaScript vs Odin vs Rust vs Zig benchmarks

A small head-to-head benchmark suite comparing **C**, **C++**, **Jai**,
**JavaScript** (Node.js), **Odin**, **Rust** and **Zig** on runtime speed, peak
memory, binary size, compile time and source size. The same thirteen workloads are implemented in
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
| `main.c`     | All thirteen benchmarks; runs one, chosen by a command-line argument.|
| `main.cpp`   | The same thirteen benchmarks in C++.                                 |
| `main.jai`   | The same thirteen benchmarks in Jai.                                |
| `main.js`    | The same thirteen benchmarks in JavaScript (run with Node.js).       |
| `main.odin`  | The same thirteen benchmarks in Odin.                                |
| `main.rs`    | The same thirteen benchmarks in Rust.                                |
| `main.zig`   | The same thirteen benchmarks in Zig.                                 |
| `bench.sh`   | Builds/launches all seven language builds, times each benchmark, prints the table.|

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
| `raster`     | Software 3D renderer: spins a Gouraud-shaded sphere into a 640×480 z-buffered framebuffer for 240 frames (float transform + triangle rasterization). |
| `ptrchase`   | Memory **latency**: chases a single random pointer cycle through a 64 MB array (dependent loads the prefetcher can't hide). Complements `sieve`'s streaming bandwidth. |
| `hash`       | Integer ALU: 32-bit FNV-1a hashing of a byte buffer (xor + wrapping multiply, no SIMD to exploit). |
| `bst`        | Heap allocation + pointer chasing: builds a 1M-node binary search tree (one allocation per node) then runs 1M lookups. |
| `rle`        | Branchy byte processing: run-length-encodes a buffer of random runs. |
| `base64`     | Bit manipulation + table lookup: base64-encodes a byte buffer (gather through a 64-entry table). |
| `dispatch`   | Indirect-branch prediction: applies a stream of ops to an accumulator through a function-pointer table (one indirect call per element). |

Every benchmark prints a `checksum` line. All seven languages must produce the
**same** checksum — that's how the script proves everyone did identical work
before comparing their timings. JavaScript uses `BigInt` for the `sort`
benchmark's 64-bit wrapping arithmetic so it stays bit-identical with the
native builds. C and C++ are built with `-ffp-contract=off` so the `mandelbrot`
float math doesn't fuse into FMA (which would diverge from the other backends).
The six newer benchmarks (`ptrchase`, `hash`, `bst`, `rle`, `base64`,
`dispatch`) use only 32-bit wrapping integer arithmetic (an LCG built from
multiply + add, division instead of right-shift), so JavaScript stays
bit-identical with `Math.imul`/`>>>0` instead of `BigInt`.

The `raster` benchmark is a real (if tiny) software 3D renderer with no external
dependencies — it transforms and projects a UV-sphere mesh, rasterizes triangles
with a z-buffer, and Gouraud-shades them into an in-memory framebuffer, then
folds the framebuffer into the per-frame checksum. To stay bit-identical across
all seven languages it uses **only** `+ - * /` and comparisons: it ships its own
polynomial `sin`/`cos` (each language's `libm`/`Math.sin` differs in the last
bits) and avoids `sqrt` entirely (the unit-sphere vertex *is* its own normal).
Because the build script already times each benchmark, **frames-per-second is
simply `240 / wall_time`**, reported in its own table below. One OpenJai quirk
surfaced here: it rounds *named* float constants (`X :: 3.14…`) to 32-bit
`float`, so the angle constants in its `sin`/`cos` are float64 *variables*
instead — otherwise the range reduction would drift and break the checksum.

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
for each language and who won, plus binary size, compile time and source lines
of code.

## Results

Best of 3 runs on the [test system](#test-system) below (lower is better).

### Wall-clock time (seconds)

| benchmark    |    c |  cpp |  jai |   js | odin | rust |  zig | fastest |
| ------------ | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ------- |
| `collatz`    | 0.43 | 0.43 | 0.43 | 6.55 | 0.42 | 0.42 | 0.43 | odin/rust |
| `fib`        | 2.07 | 2.07 | 2.08 | 6.72 | 2.13 | 2.13 | 2.13 | c/cpp |
| `mandelbrot` | 0.46 | 0.46 | 0.46 | 0.50 | 0.46 | 0.46 | 0.46 | c/cpp/jai/odin/rust/zig |
| `matmul`     | 0.04 | 0.04 | 3.82 | 0.21 | 0.05 | 0.04 | 0.04 | c/cpp/rust/zig |
| `sieve`      | 0.10 | 0.10 | 1.66 | 0.20 | 0.10 | 0.10 | 0.13 | c/cpp/odin/rust |
| `sort`       | 0.20 | 0.20 | 0.26 | 0.50 | 0.20 | 0.20 | 0.20 | c/cpp/odin/rust/zig |
| `raster`     | 0.27 | 0.27 | 10.31 | 0.53 | 0.23 | 0.23 | 0.37 | odin/rust |
| `ptrchase`   | 0.45 | 0.44 | 2.64 | 0.60 | 0.45 | 0.45 | 0.44 | cpp/zig |
| `hash`       | 0.19 | 0.19 | 1.49 | 0.23 | 0.19 | 0.19 | 0.19 | c/cpp/odin/rust/zig |
| `bst`        | 0.71 | 0.73 | 6.21 | 1.14 | 0.99 | 0.87 | 0.70 | zig |
| `rle`        | 0.15 | 0.15 | 3.27 | 0.31 | 0.18 | 0.19 | 0.15 | c/cpp/zig |
| `base64`     | 0.18 | 0.18 | 1.24 | 0.23 | 0.18 | 0.18 | 0.18 | c/cpp/odin/rust/zig |
| `dispatch`   | 0.33 | 0.33 | 4.44 | 2.21 | 0.32 | 0.33 | 0.33 | odin |

### Rendering throughput (frames per second)

The `raster` benchmark renders 240 frames, so FPS = `240 / wall_time` (higher is
better).

| metric  |    c |  cpp |  jai |   js | odin | rust |  zig | fastest   |
| ------- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --------- |
| `raster` fps | 888.9 | 888.9 | 23.3 | 452.8 | 1043.5 | 1043.5 | 648.6 | odin/rust |

### Peak memory (MB)

| benchmark    |    c |  cpp |  jai |   js | odin | rust |  zig | leanest |
| ------------ | ---: | ---: | ------: | ---: | ---: | ---: | ---: | ------- |
| `collatz`    |  1.0 |  1.0 |     1.6 | 45.8 |  1.1 |  1.2 |  1.2 | c       |
| `fib`        |  1.0 |  1.1 |     1.5 | 44.8 |  1.1 |  1.3 |  1.2 | c       |
| `mandelbrot` |  1.0 |  1.0 |     1.5 | 47.6 |  1.1 |  1.2 |  1.2 | c       |
| `matmul`     |  7.1 |  7.1 |     7.7 | 49.9 |  7.2 |  7.3 |  7.2 | c       |
| `sieve`      | 48.7 | 48.8 |    49.3 | 93.7 | 48.8 | 49.0 | 48.9 | c       |
| `sort`       | 23.9 | 24.0 |    24.5 | 72.1 | 24.0 | 24.2 | 24.1 | c       |
| `raster`     |  3.8 |  3.8 |     4.4 | 73.3 |  3.8 |  4.0 |  3.8 | c       |
| `ptrchase`   | 123.1 | 123.2 | 123.8 | 170.4 | 123.2 | 123.4 | 123.3 | c     |
| `hash`       | 31.6 | 31.6 |    32.3 | 78.0 | 31.7 | 31.8 | 31.7 | c       |
| `bst`        | 32.2 | 32.2 | 15626.8 | 131.2 | 47.8 | 32.4 | 31.8 | zig    |
| `rle`        | 48.2 | 115.5 |  116.3 | 97.0 | 48.3 | 48.4 | 48.3 | c       |
| `base64`     | 23.9 | 24.0 |    24.8 | 77.2 | 24.0 | 24.2 | 24.1 | c       |
| `dispatch`   | 20.2 | 20.2 |    21.1 | 68.4 | 20.3 | 20.4 | 20.3 | c       |

### Binary size & compile time

| metric       | c       | cpp     | jai (OpenJai) | js (Node) | odin   | rust   | zig    |
| ------------ | ------- | ------- | ------------- | --------- | ------ | ------ | ------ |
| binary size  | 0.03 MB | 0.04 MB | 4.6 MB        | n/a       | 0.2 MB | 0.4 MB | 0.4 MB |
| compile time | 0.14 s  | 0.48 s  | 10.00 s       | n/a       | 1.44 s | 0.33 s | 5.83 s |
| code SLOC    | 469     | 447     | 483           | 488       | 483    | 547    | 524    |

`code SLOC` counts non-blank, non-comment source lines (all seven suites
implement the identical thirteen benchmarks, so this is a fair conciseness
comparison). Lower is more concise.

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
- **`collatz` is where OpenJai catches up** (0.43 vs 0.42 s, effectively tied):
  its branchy, scalar, divide-heavy inner loop has no vectorizable structure, so
  the LLVM backends have no advantage to exploit. It's a good counterweight to
  `matmul` and `sieve`.
- **`raster` is the most demanding workload** — a full software 3D pipeline
  (transform, project, rasterize, z-test, shade) per frame. The LLVM backends
  push **~650–1040 FPS** (Odin and Rust fastest at ~1040), while **OpenJai
  manages only ~23 FPS** (~45× slower): its float-heavy inner loops get none of
  the scalar optimization the LLVM backends apply, the same weakness seen on
  `matmul`/`sieve`. Node lands in the middle at ~453 FPS — respectable for a JIT,
  but still ~2.3× behind native and carrying a ~73 MB memory floor vs ~4 MB.
- **`ptrchase` flattens the native field** — it's pure memory *latency* (a
  dependent-load pointer cycle through 64 MB), so all six native backends
  converge at **~0.44–0.45 s**: they're all just waiting on the same DRAM, with
  no codegen advantage to exploit. It's the opposite of `sieve`'s prefetchable
  streaming. Node is surprisingly close here (~0.60 s, its best relative
  showing — typed arrays and a tight loop), while OpenJai still trails ~6×.
- **`hash` and `base64` are integer-ALU / bit-twiddling tests** (32-bit FNV-1a
  and base64): the native backends tie at **~0.18–0.19 s**, OpenJai is ~7–8×
  back, and Node is within ~1.2× of native — V8 is genuinely good at 32-bit
  integer work via `Math.imul`.
- **`bst` is the one workload where the native languages diverge**, because it
  leans on each language's **heap allocator** (one allocation per node).
  Zig (`smp_allocator`) and C/C++ (system `malloc`) lead at **~0.70–0.73 s**,
  Rust ~0.87 s, Odin ~0.99 s, then Node ~1.14 s (GC + object headers, ~130 MB).
  OpenJai is a dramatic outlier: **~6.2 s and ~15.6 GB peak** — its default
  `New` has no small-object free list and grabs roughly a page per node. A good
  reminder that "the allocator" is part of a language's performance story.
- **`dispatch` is a trap for the JIT.** Calling four different functions through
  one pointer table makes the call site megamorphic, and **Node can't inline it
  — 2.21 s, ~7× native** (worse, relatively, than any other benchmark). The
  native backends predict the indirect call and tie at ~0.32–0.33 s; OpenJai is
  ~4.4 s.
- **C is consistently the leanest on peak memory** — it has essentially no
  runtime, so it sits a fraction of a MB below everything else on every
  workload. C and C++ also ship the **smallest binaries** (~0.03–0.04 MB,
  single-file `-O3` with no static libc bloat). (On `rle`, C++ and Jai use ~2×
  the memory because `std::vector`/`NewArray` zero-initialize the worst-case
  output buffer, making it resident, while C/Odin/Rust/Zig leave the untouched
  tail non-resident.)
- **C compiles fastest here** (single-file `cc -O3`, ~0.1 s); C++ pays a little
  for `<iostream>`/`<vector>` template instantiation (~0.5 s). OpenJai is the
  slowest to build (~10 s), followed by Zig's full `ReleaseFast` LLVM pipeline
  (~5.8 s).
- **C++ is the most concise** at 447 SLOC, just ahead of C (469) and the
  Jai/Odin pair (both 483), with JavaScript close behind (488); **Rust is now
  the most verbose** (547), past Zig (524). The gap is mostly bookkeeping and
  formatting: Rust spells out `let mut` and `.wrapping_*()` and `rustfmt` puts
  every guard and binding on its own line, while Zig needs explicit
  `@intCast`/`@floatFromInt` casts on the integer benchmarks. The C family, Odin
  and Jai lean on terser implicit conversions, wrapping arithmetic, and
  brace-less single-statement bodies.
- **JavaScript (Node V8) is more competitive than expected** on the hot numeric
  and integer loops — `matmul`, `sieve`, `mandelbrot`, `hash` and `base64` land
  within a few× of native — but pays heavily on branchy/recursive work
  (`collatz`, `fib`), on **megamorphic dispatch** (`dispatch`, ~7×), and on
  memory (a ~45 MB+ runtime floor regardless of workload).

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
- The `raster` benchmark renders a fixed **240 frames**; its FPS row is just
  `240 / best wall time`. It is self-contained (own polynomial `sin`/`cos`, no
  `sqrt`, only `+ - * /`) so every language renders bit-identical frames.
- The six newer benchmarks (`ptrchase`, `hash`, `bst`, `rle`, `base64`,
  `dispatch`) use only **32-bit wrapping** integer arithmetic, so JavaScript
  stays bit-identical with `Math.imul`/`>>>0` (no `BigInt`) and the OpenJai
  build's signed-shift/compare quirks don't bite. `bst` allocates one node per
  insert to exercise each language's heap allocator, and `dispatch` calls
  through a function-pointer table to exercise indirect-branch prediction.

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
| Odin | dev-2026-06-nightly:7ab61e4 (`-o:speed`) |
| Rust | 1.90.0 (`rustc -O`) |
| Zig | 0.16.0 (LLVM backend, `-O ReleaseFast`) |

Absolute timings are machine-specific; re-run `./bench.sh` to get numbers for
your own hardware.

## A note on the Jai compiler (OpenJai)

The Jai toolchain here is **[OpenJai](https://github.com/withlang-dev/open-jai)**,
an MIT-licensed clean-room Jai-compatible compiler — a separate project from the
official (closed-beta) Jai compiler. While writing the suite I hit five
behaviours in this build that differ from the LLVM-backed languages and had to
be worked around so all seven compute identical results. They're documented
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
4. **Named float constants are rounded to 32-bit `float`.** A `TWO_PI ::
   6.283185307179586` (or even `TWO_PI : float64 : …`) keeps only `float`
   precision when later used in `float64` math, whereas float64 *variables* and
   inline literals keep full precision. The `raster` benchmark's `sin`/`cos`
   range-reduction constants are therefore float64 variables; as named constants
   they drifted by ~1 ULP and broke the cross-language checksum.
5. **`u32` arithmetic isn't truncated to 32 bits.** Wrapping 32-bit math (the
   LCG and FNV hashes in `ptrchase`/`hash`/`bst`/`rle`/`base64`/`dispatch`) kept
   full 64-bit intermediate values instead of wrapping at 2³², so those
   benchmarks do the math in `u64` and mask with `& 0xFFFFFFFF` to match the
   other languages' `u32` wraparound.

Separately, OpenJai's default `New` allocator has no small-object free list, so
the `bst` benchmark's one-allocation-per-node pattern balloons to **~15.6 GB**
of resident memory (≈ a page per node) and ~6 s, versus ~32 MB and ~0.7 s for
the C/Zig builds. This is a property of the allocator, not the language — but
it's a striking demonstration of how much the allocator matters, and means `bst`
needs a machine with plenty of RAM to run the Jai build.

To keep the `sort` benchmark identical across all seven languages, it uses an LCG
(multiply + add only, which is bit-identical everywhere) instead of an xorshift
(which relies on logical `>>`), and masks each sort key's high bit with bitwise
`&` (sign-independent). `u64` *arithmetic* (add/multiply/xor with wraparound) is
correct in this build — only signed-sensitive comparison and shifts differ.

These are properties of this particular compiler build, not of the Jai language.
