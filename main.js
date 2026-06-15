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

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (Math.sin differs per engine) so every
// language produces a bit-identical checksum. The per-frame checksum fold uses
// BigInt to stay 64-bit-exact with the native builds. FPS = frames / wall_time.

function rFloor(y) {
  const f = Math.trunc(y);
  if (f > y) return f - 1.0;
  return f;
}

function rSin(xin) {
  const TWO_PI = 6.283185307179586;
  const k = rFloor(xin / TWO_PI + 0.5);
  const x = xin - k * TWO_PI;
  const x2 = x * x;
  let p = -1.0 / 1307674368000.0;
  p = 1.0 / 6227020800.0 + x2 * p;
  p = -1.0 / 39916800.0 + x2 * p;
  p = 1.0 / 362880.0 + x2 * p;
  p = -1.0 / 5040.0 + x2 * p;
  p = 1.0 / 120.0 + x2 * p;
  p = -1.0 / 6.0 + x2 * p;
  p = 1.0 + x2 * p;
  return x * p;
}

function rCos(x) {
  return rSin(x + 1.5707963267948966);
}

function edge(ax, ay, bx, by, cx, cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

function benchRaster() {
  const W = 640;
  const H = 480;
  const RINGS = 24;
  const SECTORS = 24;
  const FRAMES = 240;
  const NV = (RINGS + 1) * (SECTORS + 1);
  const FOCAL = 500.0;
  const CAM_DIST = 3.0;
  const MASK64 = (1n << 64n) - 1n;

  const bx = new Float64Array(NV);
  const by = new Float64Array(NV);
  const bz = new Float64Array(NV);
  let nv = 0;
  for (let i = 0; i <= RINGS; i++) {
    const theta = 3.141592653589793 * (i / RINGS);
    const st = rSin(theta);
    const ct = rCos(theta);
    for (let j = 0; j <= SECTORS; j++) {
      const phi = 6.283185307179586 * (j / SECTORS);
      const sp = rSin(phi);
      const cp = rCos(phi);
      bx[nv] = st * cp;
      by[nv] = ct;
      bz[nv] = st * sp;
      nv += 1;
    }
  }

  const sx = new Float64Array(NV);
  const sy = new Float64Array(NV);
  const sz = new Float64Array(NV);
  const si = new Float64Array(NV);

  const color = new Uint8Array(W * H);
  const zbuf = new Float64Array(W * H);

  let checksum = 0n;

  for (let f = 0; f < FRAMES; f++) {
    const ang = f * 0.0125;
    const cy = rCos(ang);
    const syr = rSin(ang);
    const axx = ang * 0.5;
    const cx = rCos(axx);
    const sxr = rSin(axx);

    for (let v = 0; v < nv; v++) {
      const px0 = bx[v];
      const py0 = by[v];
      const pz0 = bz[v];
      const rx = px0 * cy + pz0 * syr;
      const rz = -px0 * syr + pz0 * cy;
      const ry = py0;
      const ry2 = ry * cx - rz * sxr;
      const rz2 = ry * sxr + rz * cx;
      let inten = -rz2;
      if (inten < 0.0) inten = 0.0;
      const zc = rz2 + CAM_DIST;
      const invz = 1.0 / zc;
      sx[v] = rx * invz * FOCAL + W * 0.5;
      sy[v] = ry2 * invz * FOCAL + H * 0.5;
      sz[v] = zc;
      si[v] = inten;
    }

    color.fill(0);
    zbuf.fill(1.0e30);

    for (let ri = 0; ri < RINGS; ri++) {
      for (let sj = 0; sj < SECTORS; sj++) {
        const a = ri * (SECTORS + 1) + sj;
        const b = a + (SECTORS + 1);
        const tris = [
          [a, b, a + 1],
          [a + 1, b, b + 1],
        ];
        for (let t = 0; t < 2; t++) {
          const i0 = tris[t][0];
          const i1 = tris[t][1];
          const i2 = tris[t][2];
          const area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2]);
          if (area <= 0.0) continue;
          let mnx = sx[i0];
          if (sx[i1] < mnx) mnx = sx[i1];
          if (sx[i2] < mnx) mnx = sx[i2];
          let mxx = sx[i0];
          if (sx[i1] > mxx) mxx = sx[i1];
          if (sx[i2] > mxx) mxx = sx[i2];
          let mny = sy[i0];
          if (sy[i1] < mny) mny = sy[i1];
          if (sy[i2] < mny) mny = sy[i2];
          let mxy = sy[i0];
          if (sy[i1] > mxy) mxy = sy[i1];
          if (sy[i2] > mxy) mxy = sy[i2];
          if (mnx < 0.0) mnx = 0.0;
          if (mxx > W - 1) mxx = W - 1;
          if (mny < 0.0) mny = 0.0;
          if (mxy > H - 1) mxy = H - 1;
          const x0 = Math.trunc(mnx);
          const x1 = Math.trunc(mxx);
          const y0 = Math.trunc(mny);
          const y1 = Math.trunc(mxy);
          for (let py = y0; py <= y1; py++) {
            const pcy = py + 0.5;
            for (let px = x0; px <= x1; px++) {
              const pcx = px + 0.5;
              const w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
              const w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
              const w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
              if (w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0) {
                const l0 = w0 / area;
                const l1 = w1 / area;
                const l2 = w2 / area;
                const depth = l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2];
                const idx = py * W + px;
                if (depth < zbuf[idx]) {
                  zbuf[idx] = depth;
                  let inten = l0 * si[i0] + l1 * si[i1] + l2 * si[i2];
                  if (inten < 0.0) inten = 0.0;
                  if (inten > 1.0) inten = 1.0;
                  color[idx] = Math.trunc(inten * 255.0);
                }
              }
            }
          }
        }
      }
    }

    let frame_sum = 0;
    for (let i = 0; i < W * H; i++) {
      frame_sum += color[i];
    }
    checksum = (checksum * 1000003n + BigInt(frame_sum)) & MASK64;
  }

  console.log("checksum " + checksum.toString());
}

// --- pointer-chasing (random memory latency) --------------------------------
// Builds one big random permutation cycle, then chases next[p] for many hops.
// Each load depends on the previous one, so the prefetcher can't hide it: this
// measures memory *latency*, unlike the streaming `sieve`. All 32-bit, so it
// uses Math.imul/>>>0 instead of BigInt and stays bit-identical with native.

function benchPtrchase() {
  const N = 16000000;
  const HOPS = 4000000;
  const order = new Uint32Array(N);
  const next = new Uint32Array(N);
  for (let i = 0; i < N; i++) order[i] = i;
  let x = 1;
  for (let i = N - 1; i >= 1; i--) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    const j = (x & 0x7fffffff) % (i + 1);
    const t = order[i];
    order[i] = order[j];
    order[j] = t;
  }
  for (let k = 0; k < N; k++) next[order[k]] = order[(k + 1) % N];
  let sum = 0;
  let p = 0;
  for (let h = 0; h < HOPS; h++) {
    p = next[p];
    sum = (sum + p) >>> 0;
  }
  console.log("checksum " + (sum >>> 0));
}

// --- FNV-1a hash ------------------------------------------------------------
// Hashes a byte buffer several times with 32-bit FNV-1a. Stresses the integer
// ALU (xor + wrapping multiply) and a tight sequential read; no SIMD to exploit.

function benchHash() {
  const N = 32000000;
  const R = 4;
  const buf = new Uint8Array(N);
  let x = 12345;
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    buf[i] = x & 0xff;
  }
  let h = 2166136261;
  for (let r = 0; r < R; r++) {
    for (let i = 0; i < N; i++) {
      h ^= buf[i];
      h = Math.imul(h, 16777619) >>> 0;
    }
  }
  console.log("checksum " + (h >>> 0));
}

// --- binary search tree (heap allocation + pointer chasing) -----------------
// Inserts M keys into a BST (one object allocation per node, branchy descent),
// then runs Q lookups. Measures allocator/GC throughput plus pointer-chasing
// reads. Keys stay below 2^31 so signed/unsigned ordering agree everywhere.

function benchBst() {
  const M = 1000000;
  const Q = 1000000;
  let root = null;
  let x = 22222;
  for (let n = 0; n < M; n++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    const key = x & 0x7fffffff;
    const nn = { key: key, left: null, right: null };
    if (root === null) {
      root = nn;
      continue;
    }
    let cur = root;
    for (;;) {
      if (key < cur.key) {
        if (cur.left === null) {
          cur.left = nn;
          break;
        }
        cur = cur.left;
      } else {
        if (cur.right === null) {
          cur.right = nn;
          break;
        }
        cur = cur.right;
      }
    }
  }
  let y = 99991;
  let cs = 0;
  for (let q = 0; q < Q; q++) {
    y = (Math.imul(y, 1664525) + 1013904223) >>> 0;
    const key = y & 0x7fffffff;
    let steps = 0;
    let cur = root;
    while (cur !== null) {
      steps++;
      if (key === cur.key) break;
      if (key < cur.key) cur = cur.left;
      else cur = cur.right;
    }
    cs = (Math.imul(cs, 1000003) + steps) >>> 0;
  }
  console.log("checksum " + (cs >>> 0));
}

// --- run-length encoding (branchy byte processing) --------------------------
// Builds a buffer of random runs, then RLE-encodes it several times, folding
// the (count,value) output into a 32-bit hash. Data-dependent branchy scan.

function benchRle() {
  const N = 40000000;
  const R = 4;
  const buf = new Uint8Array(N);
  const out = new Uint8Array(2 * N);
  let x = 33333;
  let i = 0;
  while (i < N) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    const v = x & 0xff;
    const rl = ((x & 0x7fffffff) % 16) + 1;
    let c = 0;
    while (c < rl && i < N) {
      buf[i] = v;
      i++;
      c++;
    }
  }
  let h = 2166136261;
  for (let r = 0; r < R; r++) {
    let o = 0;
    let p = 0;
    while (p < N) {
      const v = buf[p];
      let run = 1;
      while (p + run < N && buf[p + run] === v && run < 255) run++;
      out[o] = run;
      out[o + 1] = v;
      o += 2;
      p += run;
    }
    for (let k = 0; k < o; k++) {
      h ^= out[k];
      h = Math.imul(h, 16777619) >>> 0;
    }
    h ^= o % 256;
    h = Math.imul(h, 16777619) >>> 0;
    h ^= Math.floor(o / 256) % 256;
    h = Math.imul(h, 16777619) >>> 0;
    h ^= Math.floor(o / 65536) % 256;
    h = Math.imul(h, 16777619) >>> 0;
    h ^= Math.floor(o / 16777216) % 256;
    h = Math.imul(h, 16777619) >>> 0;
  }
  console.log("checksum " + (h >>> 0));
}

// --- base64 encoding (table lookup + bit shuffling) -------------------------
// Base64-encodes a byte buffer several times, folding the output characters
// into a 32-bit hash. Uses division (not >>) so every language agrees bit for
// bit. Stresses byte-level bit manipulation and a small gather/table lookup.

const B64 =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function benchBase64() {
  const N = 24000000;
  const R = 4;
  const buf = new Uint8Array(N);
  let x = 44444;
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    buf[i] = x & 0xff;
  }
  let h = 2166136261;
  for (let r = 0; r < R; r++) {
    for (let i = 0; i + 2 < N; i += 3) {
      const b0 = buf[i];
      const b1 = buf[i + 1];
      const b2 = buf[i + 2];
      const i0 = (b0 / 4) | 0;
      const i1 = (b0 & 3) * 16 + ((b1 / 16) | 0);
      const i2 = (b1 & 15) * 4 + ((b2 / 64) | 0);
      const i3 = b2 & 63;
      h ^= B64.charCodeAt(i0);
      h = Math.imul(h, 16777619) >>> 0;
      h ^= B64.charCodeAt(i1);
      h = Math.imul(h, 16777619) >>> 0;
      h ^= B64.charCodeAt(i2);
      h = Math.imul(h, 16777619) >>> 0;
      h ^= B64.charCodeAt(i3);
      h = Math.imul(h, 16777619) >>> 0;
    }
  }
  console.log("checksum " + (h >>> 0));
}

// --- indirect dispatch ------------------------------------------------------
// Applies a stream of ops to an accumulator through an array of functions, one
// indirect call per element. Stresses indirect-branch prediction (megamorphic
// call sites for V8). All ops are 32-bit wrapping + ^ * - via Math.imul/>>>0.

function benchDispatch() {
  const N = 4000000;
  const R = 32;
  const code = new Uint8Array(N);
  const operand = new Uint32Array(N);
  let x = 55555;
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    code[i] = (x & 0x7fffffff) % 4;
    operand[i] = x;
  }
  const fns = [
    (a, b) => (a + b) >>> 0,
    (a, b) => (a ^ b) >>> 0,
    (a, b) => Math.imul(a, b | 1) >>> 0,
    (a, b) => (a - b) >>> 0,
  ];
  let acc = 2166136261;
  for (let r = 0; r < R; r++) {
    for (let i = 0; i < N; i++) {
      acc = fns[code[i]](acc, operand[i]);
    }
  }
  console.log("checksum " + (acc >>> 0));
}

function benchCollatz() {
  const N = 3_000_000;
  let total = 0;
  for (let i = 1; i <= N; i++) {
    let n = i;
    let steps = 0;
    // Parity via `% 2`, not bitwise `& 1`: trajectory values exceed 2^31 and
    // JS bitwise operators truncate to 32 bits, which would be wrong here.
    while (n !== 1) {
      if (n % 2 === 0) {
        n = n / 2;
      } else {
        n = 3 * n + 1;
      }
      steps++;
    }
    total += steps;
  }
  console.log("checksum " + total);
}

function main() {
  const name = process.argv[2];
  if (!name) {
    console.log("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch>");
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
    case "collatz":
      benchCollatz();
      break;
    case "raster":
      benchRaster();
      break;
    case "ptrchase":
      benchPtrchase();
      break;
    case "hash":
      benchHash();
      break;
    case "bst":
      benchBst();
      break;
    case "rle":
      benchRle();
      break;
    case "base64":
      benchBase64();
      break;
    case "dispatch":
      benchDispatch();
      break;
    default:
      console.log("unknown benchmark: " + name);
  }
}

main();
