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
    console.log("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>");
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
    default:
      console.log("unknown benchmark: " + name);
  }
}

main();
