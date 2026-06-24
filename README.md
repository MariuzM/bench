# C vs C++ vs Jai vs JavaScript vs Odin vs Rust vs Zig benchmarks

A small head-to-head benchmark suite comparing **C**, **C++**, **Jai**,
**JavaScript** (Node.js), **Odin**, **Rust** and **Zig** on runtime speed, peak
memory, binary size, compile time and source size. The same twenty-three workloads are implemented in
each language; a build script compiles the six native suites (and launches the
JavaScript suite under Node), runs every benchmark under `/usr/bin/time`, and
prints a side-by-side table.

The Jai side is built with the **official Jai compiler** (Jonathan Blow's
closed-beta toolchain, beta 0.2.009), which uses an LLVM backend — so it lands
right alongside the other LLVM-backed native languages.

## Layout

| File         | What it is                                                        |
| ------------ | ----------------------------------------------------------------- |
| `main.c`     | All twenty-three benchmarks; runs one, chosen by a command-line argument.|
| `main.cpp`   | The same twenty-three benchmarks in C++.                             |
| `main.jai`   | The same twenty-three benchmarks in Jai.                            |
| `main.js`    | The same twenty-three benchmarks in JavaScript (run with Node.js).   |
| `main.odin`  | The same twenty-three benchmarks in Odin.                           |
| `main.rs`    | The same twenty-three benchmarks in Rust.                           |
| `main.zig`   | The same twenty-three benchmarks in Zig.                            |
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
| `nbody`      | Floating-point **latency**: all-pairs gravitational n-body whose per-interaction `1/dist^3` runs a dependent 8-iteration Newton sqrt (only `+ - * /`). Complements `mandelbrot`/`raster`'s FP throughput. |
| `stream`     | Memory **write** bandwidth: STREAM triad `a[i] = b[i] + k*c[i]` over three 64 MB arrays. Complements `sieve`'s streaming reads and `ptrchase`'s latency. |
| `nqueens`    | Backtracking recursion: counts solutions to 14-queens with the classic bitmask solver (deep recursion like `fib` plus unpredictable pruning branches like `collatz`). |
| `life`       | 2D stencil: steps a 1024×1024 toroidal Conway's Game of Life grid 300 generations, summing 8 wrapped neighbours per cell. |
| `hashmap`    | Open-addressing hash map: 8M inserts + 16M lookups with linear probing. Exercises the probe-sequence access pattern, distinct from `bst`'s pointer chasing. |
| `sha256`     | Crypto mixing: full SHA-256 compression over a 4 MB buffer ×16. Heavy 32-bit rotate/shift/xor/add ALU work; a "real" hash next to `hash` (FNV) and `crc32`. |
| `transpose`  | Cache stride / TLB: naive out-of-place transpose of a 4096×4096 matrix, repeated with src/dst swapped (column-strided writes thrash cache). Complements `matmul`. |
| `editdist`   | Dynamic programming: Levenshtein distance between two 16k-symbol strings via the two-row DP (data-dependent min-of-three table fill). |
| `lz`         | Branchy match search: greedy LZ77 over a 4 MB buffer with a 512-byte sliding window. A heavier, more memory-bound cousin of `rle`. |
| `crc32`      | Table-driven hashing: builds the standard CRC32 table (poly `0xEDB88320`) then CRCs a 16 MB buffer ×8 (table-lookup gather + shift/xor). |

Every benchmark prints a `checksum` line. All seven languages must produce the
**same** checksum — that's how the script proves everyone did identical work
before comparing their timings. JavaScript uses `BigInt` for the `sort`
benchmark's 64-bit wrapping arithmetic so it stays bit-identical with the
native builds. C and C++ are built with `-ffp-contract=off` so the `mandelbrot`
float math doesn't fuse into FMA (which would diverge from the other backends).
The newer benchmarks (`ptrchase`, `hash`, `bst`, `rle`, `base64`, `dispatch`,
`stream`, `nqueens`, `life`, `hashmap`, `sha256`, `transpose`, `editdist`, `lz`,
`crc32`) use only 32-bit wrapping integer arithmetic (an LCG built from
multiply + add), so JavaScript stays bit-identical with `Math.imul`/`>>>0`
instead of `BigInt`. `nbody` is floating-point but uses only `+ - * /` and a
hand-rolled Newton-iteration `sqrt` (no `libm`), so its doubles round identically
across all seven backends, the same trick `raster` uses.

The `raster` benchmark is a real (if tiny) software 3D renderer with no external
dependencies — it transforms and projects a UV-sphere mesh, rasterizes triangles
with a z-buffer, and Gouraud-shades them into an in-memory framebuffer, then
folds the framebuffer into the per-frame checksum. To stay bit-identical across
all seven languages it uses **only** `+ - * /` and comparisons: it ships its own
polynomial `sin`/`cos` (each language's `libm`/`Math.sin` differs in the last
bits) and avoids `sqrt` entirely (the unit-sphere vertex *is* its own normal).
Because the build script already times each benchmark, **frames-per-second is
simply `240 / wall_time`**, reported in its own table below.

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

Best of 3 runs on the [test system](#test-system) below (lower is better). The
tables below cover the original thirteen workloads; the ten newer ones (`nbody`,
`stream`, `nqueens`, `life`, `hashmap`, `sha256`, `transpose`, `editdist`, `lz`,
`crc32`) are wired into the suite and verified bit-identical across all seven
languages — run `./bench.sh` to measure them on your own hardware.

### Wall-clock time (seconds)

| benchmark    |    c |  cpp |  jai |   js | odin | rust |  zig | fastest |
| ------------ | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ------- |
| `collatz`    | 0.42 | 0.42 | 0.42 | 6.43 | 0.42 | 0.42 | 0.42 | c/cpp/jai/odin/rust/zig |
| `fib`        | 2.04 | 2.05 | 2.66 | 6.68 | 2.11 | 2.10 | 2.11 | c |
| `mandelbrot` | 0.45 | 0.45 | 0.46 | 0.50 | 0.46 | 0.45 | 0.45 | c/cpp/rust/zig |
| `matmul`     | 0.04 | 0.04 | 0.05 | 0.21 | 0.05 | 0.04 | 0.04 | c/cpp/rust/zig |
| `sieve`      | 0.13 | 0.13 | 0.17 | 0.24 | 0.13 | 0.13 | 0.16 | c/cpp/odin/rust |
| `sort`       | 0.20 | 0.20 | 0.21 | 0.49 | 0.20 | 0.20 | 0.20 | c/cpp/odin/rust/zig |
| `raster`     | 0.27 | 0.27 | 0.40 | 0.53 | 0.23 | 0.22 | 0.36 | rust |
| `ptrchase`   | 0.52 | 0.53 | 0.57 | 0.64 | 0.53 | 0.54 | 0.51 | zig |
| `hash`       | 0.19 | 0.19 | 0.19 | 0.23 | 0.19 | 0.19 | 0.19 | c/cpp/jai/odin/rust/zig |
| `bst`        | 0.74 | 0.78 | 0.74 | 1.32 | 1.02 | 0.84 | 0.72 | zig |
| `rle`        | 0.15 | 0.15 | 0.15 | 0.31 | 0.18 | 0.19 | 0.15 | c/cpp/jai/zig |
| `base64`     | 0.18 | 0.18 | 0.18 | 0.23 | 0.18 | 0.18 | 0.18 | c/cpp/jai/odin/rust/zig |
| `dispatch`   | 0.32 | 0.32 | 0.34 | 2.16 | 0.32 | 0.32 | 0.32 | c/cpp/odin/rust/zig |

### Rendering throughput (frames per second)

The `raster` benchmark renders 240 frames, so FPS = `240 / wall_time` (higher is
better).

| metric  |    c |  cpp |  jai |   js | odin | rust |  zig | fastest   |
| ------- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --------- |
| `raster` fps | 888.9 | 888.9 | 600.0 | 452.8 | 1043.5 | 1090.9 | 666.7 | rust |

### Peak memory (MB)

| benchmark    |    c |  cpp |  jai |   js | odin | rust |  zig | leanest |
| ------------ | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ------- |
| `collatz`    |  1.0 |  1.0 |  1.1 | 45.2 |  1.1 |  1.3 |  1.2 | c       |
| `fib`        |  1.0 |  1.0 |  1.1 | 44.6 |  1.1 |  1.3 |  1.2 | c       |
| `mandelbrot` |  1.0 |  1.0 |  1.1 | 46.5 |  1.1 |  1.2 |  1.2 | c       |
| `matmul`     |  7.1 |  7.1 |  7.1 | 49.3 |  7.2 |  7.3 |  7.2 | c       |
| `sieve`      | 48.7 | 48.8 | 48.8 | 93.5 | 48.8 | 49.0 | 48.9 | c       |
| `sort`       | 23.9 | 24.0 | 24.0 | 71.7 | 24.0 | 24.2 | 24.1 | c       |
| `raster`     |  3.8 |  3.8 |  3.8 | 73.7 |  3.8 |  4.0 |  3.8 | c       |
| `ptrchase`   | 123.1 | 123.2 | 123.2 | 170.2 | 123.2 | 123.4 | 123.3 | c     |
| `hash`       | 31.6 | 31.6 | 31.6 | 77.6 | 31.7 | 31.8 | 31.7 | c       |
| `bst`        | 32.2 | 32.2 | 32.1 | 130.7 | 47.7 | 32.3 | 31.8 | zig    |
| `rle`        | 48.2 | 115.5 | 115.5 | 96.9 | 48.3 | 48.4 | 48.3 | c       |
| `base64`     | 23.9 | 24.0 | 24.0 | 77.0 | 24.0 | 24.2 | 24.1 | c       |
| `dispatch`   | 20.2 | 20.2 | 20.2 | 67.9 | 20.3 | 20.4 | 20.3 | c       |

### Binary size & compile time

| metric       | c       | cpp     | jai     | js (Node) | odin   | rust   | zig    |
| ------------ | ------- | ------- | ------- | --------- | ------ | ------ | ------ |
| binary size  | 0.03 MB | 0.04 MB | 0.15 MB | n/a       | 0.2 MB | 0.4 MB | 0.4 MB |
| compile time | 0.14 s  | 0.54 s  | 0.60 s  | n/a       | 1.47 s | 0.59 s | 5.71 s |
| code SLOC    | 469     | 447     | 482     | 488       | 483    | 547    | 524    |

`code SLOC` counts non-blank, non-comment source lines (all seven suites
implement the identical thirteen benchmarks, so this is a fair conciseness
comparison). Lower is more concise.

JavaScript is JIT-compiled by Node at run time, so it has no ahead-of-time
binary or compile step.

**Takeaways:**

- **All six native languages are effectively tied** on the LLVM-backed
  workloads. C, C++, Jai, Odin, Rust and Zig all funnel through an LLVM (or
  Clang/LLVM) backend, so `collatz`, `mandelbrot`, `matmul`, `sort`, `hash`,
  `rle` and `base64` land within noise of each other. With the official Jai
  compiler, Jai is now a peer of the other native backends rather than an
  outlier — its tight integer loops (`matmul`, `sieve`) auto-vectorize just like
  the rest.
- **`fib` is where Jai trails slightly** (2.66 s vs ~2.05 s for the others, ~30%
  back): the deeply recursive call-heavy loop is the one workload where Jai's
  codegen leaves something on the table, while every other native backend ties
  near 2.05–2.11 s. Node is ~3× back at 6.68 s (recursion is hard on the JIT).
- **`raster` is the most demanding workload** — a full software 3D pipeline
  (transform, project, rasterize, z-test, shade) per frame. Rust leads at
  **~1090 FPS**, Odin ~1040, with C/C++ ~890, Zig ~670 and Jai ~600. Jai's
  float-heavy inner loops are a touch behind the fastest LLVM backends but well
  ahead of Node (~453 FPS — respectable for a JIT, but carrying a ~74 MB memory
  floor vs ~4 MB native).
- **`ptrchase` flattens the native field** — it's pure memory *latency* (a
  dependent-load pointer cycle through 64 MB), so all six native backends
  converge at **~0.51–0.57 s**: they're all just waiting on the same DRAM, with
  no codegen advantage to exploit. It's the opposite of `sieve`'s prefetchable
  streaming. Node is close behind here (~0.64 s, one of its best relative
  showings — typed arrays and a tight loop).
- **`hash` and `base64` are integer-ALU / bit-twiddling tests** (32-bit FNV-1a
  and base64): the native backends, Jai included, all tie at **~0.18–0.19 s**,
  and Node is within ~1.2× of native — V8 is genuinely good at 32-bit integer
  work via `Math.imul`.
- **`bst` leans on each language's heap allocator** (one allocation per node).
  Zig (`smp_allocator`) and C/C++/Jai lead at **~0.72–0.78 s** (Jai's default
  allocator now keeps pace and sits at ~32 MB, same ballpark as C/Zig), Rust
  ~0.84 s, Odin ~1.02 s, then Node ~1.32 s (GC + object headers, ~131 MB). A
  good reminder that "the allocator" is part of a language's performance story.
- **`dispatch` is a trap for the JIT.** Calling four different functions through
  one pointer table makes the call site megamorphic, and **Node can't inline it
  — 2.16 s, ~7× native** (worse, relatively, than any other benchmark). The
  native backends predict the indirect call and tie at ~0.32–0.34 s.
- **C is consistently the leanest on peak memory** — it has essentially no
  runtime, so it sits a fraction of a MB below everything else on every
  workload, with Jai now right alongside it (~0.1 MB more). C and C++ also ship
  the **smallest binaries** (~0.03–0.04 MB, single-file `-O3` with no static
  libc bloat); Jai is ~0.15 MB, between the C family and Odin/Rust/Zig. (On
  `rle`, C++ and Jai use ~2× the memory because `std::vector`/`NewArray`
  zero-initialize the worst-case output buffer, making it resident, while
  C/Odin/Rust/Zig leave the untouched tail non-resident.)
- **C compiles fastest here** (single-file `cc -O3`, ~0.14 s); C++, Rust and Jai
  cluster around ~0.5–0.6 s, Odin ~1.5 s, and Zig's full `ReleaseFast` LLVM
  pipeline is the slowest at ~5.7 s. (The official Jai compiler builds in ~0.6 s,
  a world away from the ~9.7 s the OpenJai build used to take.)
- **C++ is the most concise** at 447 SLOC, just ahead of C (469) and the
  Jai/Odin pair (482/483), with JavaScript close behind (488); **Rust is the
  most verbose** (547), past Zig (524). The gap is mostly bookkeeping and
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
Jai numbers reflect the **official Jai compiler, beta 0.2.009** (see notes
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
- Most newer benchmarks (`ptrchase`, `hash`, `bst`, `rle`, `base64`,
  `dispatch`, `stream`, `nqueens`, `life`, `hashmap`, `sha256`, `transpose`,
  `editdist`, `lz`, `crc32`) use only **32-bit wrapping** integer arithmetic, so
  JavaScript stays bit-identical with `Math.imul`/`>>>0` (no `BigInt`). `bst`
  allocates one node per insert to exercise each language's heap allocator, and
  `dispatch` calls through a function-pointer table to exercise indirect-branch
  prediction. `nbody` is the lone floating-point addition here; like `raster` it
  ships its own polynomial-free Newton `sqrt` and touches only `+ - * /`, so all
  seven backends agree to the bit.

## Test system

The numbers in this repo were produced on:

| | |
| --- | --- |
| Machine | Apple MacBook Pro (MacBookPro18,2) |
| CPU | Apple M1 Max (10 cores), arm64 |
| Memory | 64 GB |
| OS | macOS 15.7.7 (build 24G720) |
| C / C++ | Apple Clang 17.0.0 (`-O3 -march=native -ffp-contract=off`) |
| Jai | Jai beta 0.2.009 (`-release`) |
| JavaScript | Node.js v24.7.0 (V8) |
| Odin | dev-2026-06-nightly:7ab61e4 (`-o:speed`) |
| Rust | 1.90.0 (`rustc -O`) |
| Zig | 0.16.0 (LLVM backend, `-O ReleaseFast`) |

Absolute timings are machine-specific; re-run `./bench.sh` to get numbers for
your own hardware.

## A note on the Jai compiler

The Jai toolchain here is the **official Jai compiler** (Jonathan Blow's
closed-beta toolchain, **beta 0.2.009**), built with `-release`. It uses an LLVM
backend, so it generates code on par with the other native languages and needs
no special handling — the suite compiles and runs identically to the C, Odin,
Rust and Zig builds.

> **History:** earlier versions of this repo built the Jai suite with
> [OpenJai](https://github.com/withlang-dev/open-jai), an MIT-licensed clean-room
> Jai-compatible compiler. That build needed several workarounds (a `fib`
> warm-up call, float64 *variables* instead of named constants, and a
> ~15.6 GB-peak `bst` from its simple `New` allocator) and was much slower
> (e.g. ~94× on `matmul`, ~24 FPS on `raster`). Those workarounds have been
> **removed** now that the official compiler is used.

A few details of the shared algorithm remain, and they keep the **checksums
bit-identical across all seven languages** — they are not Jai-specific:

- **`sort`** uses an LCG (multiply + add only) rather than an xorshift, and masks
  each key's high bit (`& 0x7FFFFFFF_FFFFFFFF`) so the keys stay below 2^63. Every
  language does the same, which keeps the generated stream and the comparison
  order identical everywhere.
- **`bst`** masks its keys to below 2^31 (`& 0x7FFFFFFF`) for the same reason.
- The six **32-bit** benchmarks (`ptrchase`, `hash`, `bst`, `rle`, `base64`,
  `dispatch`) do their wrapping arithmetic in `u64` and mask with `& 0xFFFFFFFF`,
  matching the other languages' `u32` wraparound (and JavaScript's
  `Math.imul`/`>>>0`).

These are choices in the **cross-language benchmark design**, not properties of
the Jai compiler.
