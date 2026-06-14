#!/usr/bin/env bash
#
# Builds the Zig and Jai benchmark suites, runs each benchmark under
# /usr/bin/time, and prints a side-by-side comparison of wall-clock time,
# peak memory (RSS) and binary size. Each benchmark prints a "checksum" line;
# the script verifies Zig and Jai agree on it before trusting the numbers.
#
# Env overrides: ZIG, JAI (compiler paths), RUNS (timed repeats per benchmark).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ZIG="${ZIG:-/Users/marius/Dev/zig-0.16.0/zig}"
JAI="${JAI:-/Users/marius/Dev/jai/bin/jai}"
RUNS="${RUNS:-3}"
BENCHMARKS=(fib mandelbrot matmul sieve sort)

BIN="$ROOT/bin"
mkdir -p "$BIN"
TMP="$(mktemp -d)"
# Clean up the temp dir and all build artifacts (bin/, and Jai's build/) on exit.
trap 'rm -rf "$TMP" "$BIN" "$ROOT/build"' EXIT

# --- helpers ---------------------------------------------------------------

# Run "$@" under /usr/bin/time -l, echo "real_seconds rss_bytes". The program's
# own output (checksum) is discarded here; we only want the timing stats. Zig
# prints to stderr and Jai to stdout, so both are funneled away and we grep the
# time stats out of the combined stream by their unique labels.
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

# --- build -----------------------------------------------------------------

echo "Building (Zig ReleaseFast / Jai release)..."

zig_build_real=$(/usr/bin/time -p "$ZIG" build-exe "$ROOT/main.zig" -O ReleaseFast \
  -femit-bin="$BIN/zig_bench" 2>&1 | awk '/real/ {print $2; exit}')

# Jai's default metaprogram always emits ./build/main and ignores output-path
# flags, so build there and copy the result into bin/.
( cd "$ROOT" && jai_build_real=$(/usr/bin/time -p "$JAI" main.jai -release -quiet \
    >/dev/null 2>"$TMP/jb"; awk '/real/ {print $2; exit}' "$TMP/jb"); \
  echo "$jai_build_real" >"$TMP/jbt" )
jai_build_real=$(cat "$TMP/jbt")
cp "$ROOT/build/main" "$BIN/jai_bench"

ZBIN="$BIN/zig_bench"
JBIN="$BIN/jai_bench"
zig_size=$(stat -f%z "$ZBIN")
jai_size=$(stat -f%z "$JBIN")

# --- measure ---------------------------------------------------------------

ZT=(); ZM=(); JT=(); JM=()
echo "Running each benchmark ${RUNS}x (best wall-time, peak RSS)..."
for i in "${!BENCHMARKS[@]}"; do
  b=${BENCHMARKS[$i]}
  printf "  %-12s" "$b"
  read -r zt zm zck <<<"$(run_bench "$ZBIN" "$b")"
  read -r jt jm jck <<<"$(run_bench "$JBIN" "$b")"
  ZT[$i]=$zt; ZM[$i]=$zm; JT[$i]=$jt; JM[$i]=$jm
  if [ "$zck" = "$jck" ]; then printf " checksum ok (%s)\n" "$zck"; \
  else printf " CHECKSUM MISMATCH zig=%s jai=%s\n" "$zck" "$jck"; fi
done

# --- report ----------------------------------------------------------------

echo
echo "================================ RESULTS ================================="
printf "%-12s | %-19s | %-19s | %s\n" "benchmark" "time (s)  zig / jai" "peak MB   zig / jai" "winner"
echo "-------------------------------------------------------------------------"
for i in "${!BENCHMARKS[@]}"; do
  b=${BENCHMARKS[$i]}
  zt=${ZT[$i]}; jt=${JT[$i]}; zm=${ZM[$i]}; jm=${JM[$i]}
  zmb=$(human_mb "$zm"); jmb=$(human_mb "$jm")
  tline=$(awk -v z="$zt" -v j="$jt" 'BEGIN{
    if (z<j){ printf "zig %.2fx", j/z } else if (j<z){ printf "jai %.2fx", z/j } else printf "tie" }')
  mwin=$(awk -v z="$zm" -v j="$jm" 'BEGIN{ print (z<j)?"zig":((j<z)?"jai":"tie") }')
  printf "%-12s | %8s / %-8s | %8s / %-8s | t:%-9s m:%s\n" \
    "$b" "$zt" "$jt" "$zmb" "$jmb" "$tline" "$mwin"
done
echo "-------------------------------------------------------------------------"
printf "%-12s | zig %-15s | jai %s\n" "binary size" "$(human_mb "$zig_size") MB" "$(human_mb "$jai_size") MB"
printf "%-12s | zig %-15s | jai %s\n" "compile" "${zig_build_real}s" "${jai_build_real}s"
echo "========================================================================="
echo "time = best of $RUNS runs (lower better); peak MB = max resident set size."
