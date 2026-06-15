#!/usr/bin/env bash
#
# Builds the Jai, Odin, Rust and Zig benchmark suites (and the JavaScript suite,
# run under Node.js), runs each benchmark under /usr/bin/time, and prints a
# side-by-side comparison of wall-clock time, peak memory (RSS), binary size and
# compile time. Each benchmark prints a "checksum" line; the script verifies
# every language agrees on it before trusting the numbers.
#
# JavaScript is interpreted/JIT-compiled by Node at run time, so it has no
# ahead-of-time binary or compile step (shown as "n/a" in those rows).
#
# Env overrides: CC, CXX, JAI, ODIN, RUSTC, ZIG (compiler paths), NODE (runtime),
# RUNS (timed repeats). Written for bash 3.2 (macOS default), so it uses
# indirect variable references instead of associative arrays.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Defaults assume each tool is on your PATH. Override any of them with an env
# var if yours lives elsewhere, e.g. ZIG=/opt/zig/zig ./bench.sh
ZIG="${ZIG:-zig}"
JAI="${JAI:-jai}"
RUSTC="${RUSTC:-rustc}"
ODIN="${ODIN:-odin}"
CC="${CC:-cc}"
CXX="${CXX:-c++}"
NODE="${NODE:-node}"
RUNS="${RUNS:-3}"
BENCHMARKS=(collatz fib mandelbrot matmul sieve sort raster ptrchase hash bst rle base64 dispatch)
LANGS=(c cpp jai js odin rust zig)
# Frames rendered by the `raster` benchmark (must match RASTER_FRAMES in the
# source files); used to derive frames-per-second from the measured wall time.
RASTER_FRAMES=240

BIN="$ROOT/bin"
mkdir -p "$BIN"
TMP="$(mktemp -d)"
# Clean up the temp dir and all build artifacts (bin/, and Jai's build/) on exit.
trap 'rm -rf "$TMP" "$BIN" "$ROOT/build"' EXIT

# --- helpers ---------------------------------------------------------------

# Run "$@" under /usr/bin/time -l, echo "real_seconds rss_bytes". The program's
# own output (checksum) is discarded here; we only want the timing stats.
time_once() {
  /usr/bin/time -l "$@" >/dev/null 2>"$TMP/t"
  local real rss
  real=$(awk '/ real/ {print $1; exit}' "$TMP/t")
  rss=$(awk '/maximum resident set size/ {print $1; exit}' "$TMP/t")
  echo "$real $rss"
}

# Run a benchmark RUNS times; echo "min_real max_rss checksum".
run_bench() {
  local times="" rsss="" ck=""
  ck=$("$@" 2>&1 | awk '/checksum/ {print $2; exit}')
  local r
  for ((r = 0; r < RUNS; r++)); do
    read -r real rss <<<"$(time_once "$@")"
    times+="$real"$'\n'
    rsss+="$rss"$'\n'
  done
  local mint maxr
  mint=$(printf '%s' "$times" | sort -n | head -1)
  maxr=$(printf '%s' "$rsss" | grep -v '^$' | sort -n | tail -1)
  echo "$mint $maxr $ck"
}

human_mb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1048576 }'; }

# Map a language to its single source file.
src_of() {
  case "$1" in
    c) echo "$ROOT/main.c" ;;
    cpp) echo "$ROOT/main.cpp" ;;
    jai) echo "$ROOT/main.jai" ;;
    js) echo "$ROOT/main.js" ;;
    odin) echo "$ROOT/main.odin" ;;
    rust) echo "$ROOT/main.rs" ;;
    zig) echo "$ROOT/main.zig" ;;
  esac
}

# Source lines of code: non-blank lines that aren't pure `//` comments. All
# seven suites use `//` line comments and no block comments, so this is a fair
# conciseness measure across languages.
sloc_of() {
  grep -vE '^[[:space:]]*//' "$1" | grep -vcE '^[[:space:]]*$'
}

# Echo the language with the smallest value for benchmark $2, reading from the
# variables named "$1_<lang>_<bench>" (e.g. T_zig_fib).
min_lang() {
  local prefix=$1 bench=$2 best="" bestv="" l vname v
  for l in "${LANGS[@]}"; do
    vname="${prefix}_${l}_${bench}"
    v=${!vname}
    if [ -z "$bestv" ] || awk -v a="$v" -v b="$bestv" 'BEGIN{exit !(a<b)}'; then
      bestv=$v
      best=$l
    fi
  done
  echo "$best"
}

# --- build -----------------------------------------------------------------

echo "Building (C -O3 / C++ -O3 / Jai release / Odin -o:speed / Rust -O / Zig ReleaseFast; JS = Node)..."

# -ffp-contract=off keeps mandelbrot's float math bit-identical with the other
# LLVM backends, which don't fuse multiply-add by default.
BINOF_c="$BIN/c_bench"
BUILD_c=$(/usr/bin/time -p "$CC" -O3 -march=native -ffp-contract=off "$ROOT/main.c" \
  -o "$BINOF_c" 2>&1 | awk '/real/ {print $2; exit}')

BINOF_cpp="$BIN/cpp_bench"
BUILD_cpp=$(/usr/bin/time -p "$CXX" -O3 -march=native -ffp-contract=off -std=c++17 "$ROOT/main.cpp" \
  -o "$BINOF_cpp" 2>&1 | awk '/real/ {print $2; exit}')

BINOF_zig="$BIN/zig_bench"
BUILD_zig=$(/usr/bin/time -p "$ZIG" build-exe "$ROOT/main.zig" -O ReleaseFast \
  -femit-bin="$BINOF_zig" 2>&1 | awk '/real/ {print $2; exit}')

# Jai's default metaprogram always emits ./build/main and ignores output-path
# flags, so build there and copy the result into bin/.
( cd "$ROOT" && /usr/bin/time -p "$JAI" main.jai -release -quiet >/dev/null 2>"$TMP/jb"
  awk '/real/ {print $2; exit}' "$TMP/jb" >"$TMP/jbt" )
BUILD_jai=$(cat "$TMP/jbt")
BINOF_jai="$BIN/jai_bench"
cp "$ROOT/build/main" "$BINOF_jai"

BINOF_rust="$BIN/rust_bench"
BUILD_rust=$(/usr/bin/time -p "$RUSTC" -O "$ROOT/main.rs" \
  -o "$BINOF_rust" 2>&1 | awk '/real/ {print $2; exit}')

BINOF_odin="$BIN/odin_bench"
BUILD_odin=$(cd "$TMP" && /usr/bin/time -p "$ODIN" build "$ROOT/main.odin" -file \
  -o:speed -out:"$BINOF_odin" 2>&1 | awk '/real/ {print $2; exit}')

# JavaScript has no compile step: wrap "node main.js" in a tiny launcher so the
# generic runner can invoke it like any other benchmark binary.
BINOF_js="$BIN/js_bench"
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$NODE" "$ROOT/main.js" >"$BINOF_js"
chmod +x "$BINOF_js"
BUILD_js="n/a"

for l in "${LANGS[@]}"; do
  if [ "$l" = "js" ]; then SIZE_js="n/a"; continue; fi
  bvar="BINOF_$l"
  eval "SIZE_$l=\$(stat -f%z \"\${$bvar}\")"
done

# --- measure ---------------------------------------------------------------

echo "Running each benchmark ${RUNS}x (best wall-time, peak RSS)..."
for b in "${BENCHMARKS[@]}"; do
  printf "  %-12s" "$b"
  ck0=""; ok=1
  for l in "${LANGS[@]}"; do
    bvar="BINOF_$l"
    read -r t m c <<<"$(run_bench "${!bvar}" "$b")"
    eval "T_${l}_${b}=$t"
    eval "M_${l}_${b}=$m"
    [ -z "$ck0" ] && ck0=$c
    [ "$c" != "$ck0" ] && ok=0
  done
  if [ "$ok" = 1 ]; then printf " checksum ok (%s)\n" "$ck0"
  else printf " CHECKSUM MISMATCH\n"; fi
done

# --- report ----------------------------------------------------------------

echo
echo "================================== TIME (s) =================================="
printf "%-12s" "benchmark"
for l in "${LANGS[@]}"; do printf " | %8s" "$l"; done
printf " | %s\n" "fastest"
echo "------------------------------------------------------------------------------"
for b in "${BENCHMARKS[@]}"; do
  printf "%-12s" "$b"
  for l in "${LANGS[@]}"; do vname="T_${l}_${b}"; printf " | %8s" "${!vname}"; done
  printf " | %s\n" "$(min_lang T "$b")"
done

echo
echo "================================ RASTER FPS =================================="
echo "Software 3D rasterizer: $RASTER_FRAMES frames / best wall time (higher better)."
printf "%-12s" "frames/s"
for l in "${LANGS[@]}"; do
  vname="T_${l}_raster"; t=${!vname}
  printf " | %8s" "$(awk -v f="$RASTER_FRAMES" -v t="$t" 'BEGIN { if (t > 0) printf "%.1f", f / t; else printf "n/a" }')"
done
printf " | %s\n" "$(min_lang T raster)"
echo "(fastest wall-time on raster = highest FPS: $(min_lang T raster))"

echo
echo "================================= PEAK (MB) =================================="
printf "%-12s" "benchmark"
for l in "${LANGS[@]}"; do printf " | %8s" "$l"; done
printf " | %s\n" "leanest"
echo "------------------------------------------------------------------------------"
for b in "${BENCHMARKS[@]}"; do
  printf "%-12s" "$b"
  for l in "${LANGS[@]}"; do vname="M_${l}_${b}"; printf " | %8s" "$(human_mb "${!vname}")"; done
  printf " | %s\n" "$(min_lang M "$b")"
done

echo
echo "============================ BINARY SIZE / COMPILE ==========================="
printf "%-12s" "binary MB"
for l in "${LANGS[@]}"; do
  vname="SIZE_$l"; v=${!vname}
  if [ "$v" = "n/a" ]; then printf " | %8s" "n/a"; else printf " | %8s" "$(human_mb "$v")"; fi
done
printf "\n"
printf "%-12s" "compile s"
for l in "${LANGS[@]}"; do vname="BUILD_$l"; printf " | %8s" "${!vname}"; done
printf "\n"
printf "%-12s" "code SLOC"
for l in "${LANGS[@]}"; do printf " | %8s" "$(sloc_of "$(src_of "$l")")"; done
printf "\n"
echo "=============================================================================="
echo "time = best of $RUNS runs (lower better); peak MB = max resident set size."
echo "code SLOC = non-blank, non-comment source lines (lower = more concise)."
