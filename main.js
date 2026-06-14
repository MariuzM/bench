// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by argv[2],
// so the build script can measure each one's wall-time and peak memory in
// isolation. Every benchmark prints a single "checksum <n>" line; all language
// builds must agree on it, which proves they did the same work.
//
// Run with: node main.js <fib|mandelbrot|matmul|sieve|sort>
//
// The `sort` benchmark relies on 64-bit wrapping integer arithmetic that JS
// numbers (f64) cannot represent exactly, so it uses BigInt masked to 64 bits
// to stay bit-identical with the Zig/Jai/Rust/Odin builds.
// ---------------------------------------------------------------------------

function fib(n) {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
}

function benchFib() {
  let total = 0;
  for (let n = 30; n <= 42; n++) {
    total += fib(n);
  }
  console.log("checksum " + total);
}

function benchMandelbrot() {
  const W = 1200;
  const H = 1200;
  const MAX_IT = 1000;
  let sum = 0;
  for (let py = 0; py < H; py++) {
    const y0 = (py / H) * 4.0 - 2.0;
    for (let px = 0; px < W; px++) {
      const x0 = (px / W) * 4.0 - 2.5;
      let x = 0.0;
      let y = 0.0;
      let it = 0;
      while (x * x + y * y <= 4.0 && it < MAX_IT) {
        const xt = x * x - y * y + x0;
        y = 2.0 * x * y + y0;
        x = xt;
        it++;
      }
      sum += it;
    }
  }
  console.log("checksum " + sum);
}

function benchMatmul() {
  const N = 512;
  const a = new Int32Array(N * N);
  const b = new Int32Array(N * N);
  const c = new Int32Array(N * N);

  for (let i = 0; i < N; i++) {
    for (let j = 0; j < N; j++) {
      a[i * N + j] = ((i * j) % 7) - 3;
      b[i * N + j] = ((i + j) % 5) - 2;
      c[i * N + j] = 0;
    }
  }

  for (let i = 0; i < N; i++) {
    for (let k = 0; k < N; k++) {
      const aik = a[i * N + k];
      for (let j = 0; j < N; j++) {
        c[i * N + j] += aik * b[k * N + j];
      }
    }
  }

  let sum = 0;
  for (let i = 0; i < N * N; i++) {
    sum += c[i];
  }
  console.log("checksum " + sum);
}

function benchSieve() {
  const N = 50_000_000;
  const sieve = new Uint8Array(N);
  sieve.fill(1);
  sieve[0] = 0;
  sieve[1] = 0;

  for (let i = 2; i * i < N; i++) {
    if (sieve[i] === 1) {
      for (let j = i * i; j < N; j += i) {
        sieve[j] = 0;
      }
    }
  }

  let count = 0;
  for (let i = 0; i < N; i++) {
    count += sieve[i];
  }
  console.log("checksum " + count);
}

function quicksort(arr, lo, hi) {
  if (lo >= hi) return;
  const pivot = arr[Math.trunc((lo + hi) / 2)];
  let i = lo;
  let j = hi;
  while (i <= j) {
    while (arr[i] < pivot) i++;
    while (arr[j] > pivot) j--;
    if (i <= j) {
      const t = arr[i];
      arr[i] = arr[j];
      arr[j] = t;
      i++;
      j--;
    }
  }
  quicksort(arr, lo, j);
  quicksort(arr, i, hi);
}

function benchSort() {
  const N = 3_000_000;
  const MASK64 = (1n << 64n) - 1n;
  const arr = new BigInt64Array(N);

  let state = 88172645463325252n;
  for (let i = 0; i < N; i++) {
    state = (state * 6364136223846793005n + 1442695040888963407n) & MASK64;
    arr[i] = state & 0x7fffffffffffffffn;
  }

  quicksort(arr, 0, N - 1);

  let cs = 0n;
  for (let i = 0; i < N; i++) {
    cs = (cs * 1000003n + arr[i]) & MASK64;
  }
  console.log("checksum " + cs.toString());
}

function main() {
  const name = process.argv[2];
  if (!name) {
    console.log("usage: main <fib|mandelbrot|matmul|sieve|sort>");
    return;
  }
  switch (name) {
    case "fib":
      benchFib();
      break;
    case "mandelbrot":
      benchMandelbrot();
      break;
    case "matmul":
      benchMatmul();
      break;
    case "sieve":
      benchSieve();
      break;
    case "sort":
      benchSort();
      break;
    default:
      console.log("unknown benchmark: " + name);
  }
}

main();
