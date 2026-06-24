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
  if (n < 2) return n
  return fib(n - 1) + fib(n - 2)
}

function benchFib() {
  let total = 0
  for (let n = 30; n <= 42; n++) total += fib(n)
  console.log('checksum ' + total)
}

function benchMandelbrot() {
  const W = 1200,
    H = 1200,
    MAX_IT = 1000
  let sum = 0
  for (let py = 0; py < H; py++) {
    const y0 = (py / H) * 4.0 - 2.0
    for (let px = 0; px < W; px++) {
      const x0 = (px / W) * 4.0 - 2.5
      let x = 0.0,
        y = 0.0,
        it = 0
      while (x * x + y * y <= 4.0 && it < MAX_IT) {
        const xt = x * x - y * y + x0
        y = 2.0 * x * y + y0
        x = xt
        it++
      }
      sum += it
    }
  }
  console.log('checksum ' + sum)
}

function benchMatmul() {
  const N = 512
  const a = new Int32Array(N * N),
    b = new Int32Array(N * N),
    c = new Int32Array(N * N)

  for (let i = 0; i < N; i++) {
    for (let j = 0; j < N; j++) {
      a[i * N + j] = ((i * j) % 7) - 3
      b[i * N + j] = ((i + j) % 5) - 2
      c[i * N + j] = 0
    }
  }

  for (let i = 0; i < N; i++) {
    for (let k = 0; k < N; k++) {
      const aik = a[i * N + k]
      for (let j = 0; j < N; j++) {
        c[i * N + j] += aik * b[k * N + j]
      }
    }
  }

  let sum = 0
  for (let i = 0; i < N * N; i++) sum += c[i]
  console.log('checksum ' + sum)
}

function benchSieve() {
  const N = 50_000_000
  const sieve = new Uint8Array(N)
  sieve.fill(1)
  sieve[0] = 0
  sieve[1] = 0

  for (let i = 2; i * i < N; i++) {
    if (sieve[i] === 1) {
      for (let j = i * i; j < N; j += i) sieve[j] = 0
    }
  }

  let count = 0
  for (let i = 0; i < N; i++) count += sieve[i]
  console.log('checksum ' + count)
}

function quicksort(arr, lo, hi) {
  if (lo >= hi) return
  const pivot = arr[Math.trunc((lo + hi) / 2)]
  let i = lo,
    j = hi
  while (i <= j) {
    while (arr[i] < pivot) i++
    while (arr[j] > pivot) j--
    if (i <= j) {
      const t = arr[i]
      arr[i] = arr[j]
      arr[j] = t
      i++
      j--
    }
  }
  quicksort(arr, lo, j)
  quicksort(arr, i, hi)
}

function benchSort() {
  const N = 3_000_000
  const MASK64 = (1n << 64n) - 1n
  const arr = new BigInt64Array(N)

  let state = 88172645463325252n
  for (let i = 0; i < N; i++) {
    state = (state * 6364136223846793005n + 1442695040888963407n) & MASK64
    arr[i] = state & 0x7fffffffffffffffn
  }

  quicksort(arr, 0, N - 1)

  let cs = 0n
  for (let i = 0; i < N; i++) cs = (cs * 1000003n + arr[i]) & MASK64
  console.log('checksum ' + cs.toString())
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (Math.sin differs per engine) so every
// language produces a bit-identical checksum. The per-frame checksum fold uses
// BigInt to stay 64-bit-exact with the native builds. FPS = frames / wall_time.

function rFloor(y) {
  const f = Math.trunc(y)
  return f > y ? f - 1.0 : f
}

function rSin(xin) {
  const TWO_PI = 6.283185307179586
  const k = rFloor(xin / TWO_PI + 0.5)
  const x = xin - k * TWO_PI
  const x2 = x * x
  let p = -1.0 / 1307674368000.0
  p = 1.0 / 6227020800.0 + x2 * p
  p = -1.0 / 39916800.0 + x2 * p
  p = 1.0 / 362880.0 + x2 * p
  p = -1.0 / 5040.0 + x2 * p
  p = 1.0 / 120.0 + x2 * p
  p = -1.0 / 6.0 + x2 * p
  p = 1.0 + x2 * p
  return x * p
}

function rCos(x) {
  return rSin(x + 1.5707963267948966)
}

function edge(ax, ay, bx, by, cx, cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

function benchRaster() {
  const W = 640,
    H = 480,
    RINGS = 24,
    SECTORS = 24,
    FRAMES = 240
  const NV = (RINGS + 1) * (SECTORS + 1),
    FOCAL = 500.0,
    CAM_DIST = 3.0,
    MASK64 = (1n << 64n) - 1n

  const bx = new Float64Array(NV),
    by = new Float64Array(NV),
    bz = new Float64Array(NV)
  let nv = 0
  for (let i = 0; i <= RINGS; i++) {
    const theta = 3.141592653589793 * (i / RINGS)
    const st = rSin(theta)
    const ct = rCos(theta)
    for (let j = 0; j <= SECTORS; j++) {
      const phi = 6.283185307179586 * (j / SECTORS)
      const sp = rSin(phi)
      const cp = rCos(phi)
      bx[nv] = st * cp
      by[nv] = ct
      bz[nv] = st * sp
      nv += 1
    }
  }

  const sx = new Float64Array(NV),
    sy = new Float64Array(NV),
    sz = new Float64Array(NV),
    si = new Float64Array(NV)

  const color = new Uint8Array(W * H)
  const zbuf = new Float64Array(W * H)

  let checksum = 0n

  for (let f = 0; f < FRAMES; f++) {
    const ang = f * 0.0125
    const cy = rCos(ang)
    const syr = rSin(ang)
    const axx = ang * 0.5
    const cx = rCos(axx)
    const sxr = rSin(axx)

    for (let v = 0; v < nv; v++) {
      const px0 = bx[v],
        py0 = by[v],
        pz0 = bz[v]
      const rx = px0 * cy + pz0 * syr
      const rz = -px0 * syr + pz0 * cy
      const ry = py0
      const ry2 = ry * cx - rz * sxr
      const rz2 = ry * sxr + rz * cx
      let inten = -rz2
      if (inten < 0.0) inten = 0.0
      const zc = rz2 + CAM_DIST
      const invz = 1.0 / zc
      sx[v] = rx * invz * FOCAL + W * 0.5
      sy[v] = ry2 * invz * FOCAL + H * 0.5
      sz[v] = zc
      si[v] = inten
    }

    color.fill(0)
    zbuf.fill(1.0e30)

    for (let ri = 0; ri < RINGS; ri++) {
      for (let sj = 0; sj < SECTORS; sj++) {
        const a = ri * (SECTORS + 1) + sj
        const b = a + (SECTORS + 1)
        const tris = [
          [a, b, a + 1],
          [a + 1, b, b + 1],
        ]
        for (let t = 0; t < 2; t++) {
          const i0 = tris[t][0],
            i1 = tris[t][1],
            i2 = tris[t][2]
          const area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2])
          if (area <= 0.0) continue
          let mnx = sx[i0]
          if (sx[i1] < mnx) mnx = sx[i1]
          if (sx[i2] < mnx) mnx = sx[i2]
          let mxx = sx[i0]
          if (sx[i1] > mxx) mxx = sx[i1]
          if (sx[i2] > mxx) mxx = sx[i2]
          let mny = sy[i0]
          if (sy[i1] < mny) mny = sy[i1]
          if (sy[i2] < mny) mny = sy[i2]
          let mxy = sy[i0]
          if (sy[i1] > mxy) mxy = sy[i1]
          if (sy[i2] > mxy) mxy = sy[i2]
          if (mnx < 0.0) mnx = 0.0
          if (mxx > W - 1) mxx = W - 1
          if (mny < 0.0) mny = 0.0
          if (mxy > H - 1) mxy = H - 1
          const x0 = Math.trunc(mnx),
            x1 = Math.trunc(mxx),
            y0 = Math.trunc(mny),
            y1 = Math.trunc(mxy)
          for (let py = y0; py <= y1; py++) {
            const pcy = py + 0.5
            for (let px = x0; px <= x1; px++) {
              const pcx = px + 0.5
              const w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy)
              const w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy)
              const w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy)
              if (w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0) {
                const l0 = w0 / area,
                  l1 = w1 / area,
                  l2 = w2 / area
                const depth = l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2]
                const idx = py * W + px
                if (depth < zbuf[idx]) {
                  zbuf[idx] = depth
                  let inten = l0 * si[i0] + l1 * si[i1] + l2 * si[i2]
                  if (inten < 0.0) inten = 0.0
                  if (inten > 1.0) inten = 1.0
                  color[idx] = Math.trunc(inten * 255.0)
                }
              }
            }
          }
        }
      }
    }

    let frame_sum = 0
    for (let i = 0; i < W * H; i++) frame_sum += color[i]
    checksum = (checksum * 1000003n + BigInt(frame_sum)) & MASK64
  }

  console.log('checksum ' + checksum.toString())
}

// --- pointer-chasing (random memory latency) --------------------------------
// Builds one big random permutation cycle, then chases next[p] for many hops.
// Each load depends on the previous one, so the prefetcher can't hide it: this
// measures memory *latency*, unlike the streaming `sieve`. All 32-bit, so it
// uses Math.imul/>>>0 instead of BigInt and stays bit-identical with native.

function benchPtrchase() {
  const N = 16000000
  const HOPS = 4000000
  const order = new Uint32Array(N)
  const next = new Uint32Array(N)
  for (let i = 0; i < N; i++) order[i] = i
  let x = 1
  for (let i = N - 1; i >= 1; i--) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    const j = (x & 0x7fffffff) % (i + 1)
    const t = order[i]
    order[i] = order[j]
    order[j] = t
  }
  for (let k = 0; k < N; k++) next[order[k]] = order[(k + 1) % N]
  let sum = 0,
    p = 0
  for (let h = 0; h < HOPS; h++) {
    p = next[p]
    sum = (sum + p) >>> 0
  }
  console.log('checksum ' + (sum >>> 0))
}

// --- FNV-1a hash ------------------------------------------------------------
// Hashes a byte buffer several times with 32-bit FNV-1a. Stresses the integer
// ALU (xor + wrapping multiply) and a tight sequential read; no SIMD to exploit.

function benchHash() {
  const N = 32000000
  const R = 4
  const buf = new Uint8Array(N)
  let x = 12345
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    buf[i] = x & 0xff
  }
  let h = 2166136261
  for (let r = 0; r < R; r++) {
    for (let i = 0; i < N; i++) {
      h ^= buf[i]
      h = Math.imul(h, 16777619) >>> 0
    }
  }
  console.log('checksum ' + (h >>> 0))
}

// --- binary search tree (heap allocation + pointer chasing) -----------------
// Inserts M keys into a BST (one object allocation per node, branchy descent),
// then runs Q lookups. Measures allocator/GC throughput plus pointer-chasing
// reads. Keys stay below 2^31 so signed/unsigned ordering agree everywhere.

function benchBst() {
  const M = 1000000
  const Q = 1000000
  let root = null
  let x = 22222
  for (let n = 0; n < M; n++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    const key = x & 0x7fffffff
    const nn = { key: key, left: null, right: null }
    if (root === null) {
      root = nn
      continue
    }
    let cur = root
    for (;;) {
      if (key < cur.key) {
        if (cur.left === null) {
          cur.left = nn
          break
        }
        cur = cur.left
      } else {
        if (cur.right === null) {
          cur.right = nn
          break
        }
        cur = cur.right
      }
    }
  }
  let y = 99991
  let cs = 0
  for (let q = 0; q < Q; q++) {
    y = (Math.imul(y, 1664525) + 1013904223) >>> 0
    const key = y & 0x7fffffff
    let steps = 0
    let cur = root
    while (cur !== null) {
      steps++
      if (key === cur.key) break
      cur = key < cur.key ? cur.left : cur.right
    }
    cs = (Math.imul(cs, 1000003) + steps) >>> 0
  }
  console.log('checksum ' + (cs >>> 0))
}

// --- run-length encoding (branchy byte processing) --------------------------
// Builds a buffer of random runs, then RLE-encodes it several times, folding
// the (count,value) output into a 32-bit hash. Data-dependent branchy scan.

function benchRle() {
  const N = 40000000
  const R = 4
  const buf = new Uint8Array(N)
  const out = new Uint8Array(2 * N)
  let x = 33333
  let i = 0
  while (i < N) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    const v = x & 0xff
    const rl = ((x & 0x7fffffff) % 16) + 1
    let c = 0
    while (c < rl && i < N) {
      buf[i] = v
      i++
      c++
    }
  }
  let h = 2166136261
  for (let r = 0; r < R; r++) {
    let o = 0
    let p = 0
    while (p < N) {
      const v = buf[p]
      let run = 1
      while (p + run < N && buf[p + run] === v && run < 255) run++
      out[o] = run
      out[o + 1] = v
      o += 2
      p += run
    }
    for (let k = 0; k < o; k++) {
      h ^= out[k]
      h = Math.imul(h, 16777619) >>> 0
    }
    h ^= o % 256
    h = Math.imul(h, 16777619) >>> 0
    h ^= Math.floor(o / 256) % 256
    h = Math.imul(h, 16777619) >>> 0
    h ^= Math.floor(o / 65536) % 256
    h = Math.imul(h, 16777619) >>> 0
    h ^= Math.floor(o / 16777216) % 256
    h = Math.imul(h, 16777619) >>> 0
  }
  console.log('checksum ' + (h >>> 0))
}

// --- base64 encoding (table lookup + bit shuffling) -------------------------
// Base64-encodes a byte buffer several times, folding the output characters
// into a 32-bit hash. Uses division (not >>) so every language agrees bit for
// bit. Stresses byte-level bit manipulation and a small gather/table lookup.

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function benchBase64() {
  const N = 24000000
  const R = 4
  const buf = new Uint8Array(N)
  let x = 44444
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    buf[i] = x & 0xff
  }
  let h = 2166136261
  for (let r = 0; r < R; r++) {
    for (let i = 0; i + 2 < N; i += 3) {
      const b0 = buf[i]
      const b1 = buf[i + 1]
      const b2 = buf[i + 2]
      const i0 = (b0 / 4) | 0
      const i1 = (b0 & 3) * 16 + ((b1 / 16) | 0)
      const i2 = (b1 & 15) * 4 + ((b2 / 64) | 0)
      const i3 = b2 & 63
      h ^= B64.charCodeAt(i0)
      h = Math.imul(h, 16777619) >>> 0
      h ^= B64.charCodeAt(i1)
      h = Math.imul(h, 16777619) >>> 0
      h ^= B64.charCodeAt(i2)
      h = Math.imul(h, 16777619) >>> 0
      h ^= B64.charCodeAt(i3)
      h = Math.imul(h, 16777619) >>> 0
    }
  }
  console.log('checksum ' + (h >>> 0))
}

// --- indirect dispatch ------------------------------------------------------
// Applies a stream of ops to an accumulator through an array of functions, one
// indirect call per element. Stresses indirect-branch prediction (megamorphic
// call sites for V8). All ops are 32-bit wrapping + ^ * - via Math.imul/>>>0.

function benchDispatch() {
  const N = 4000000
  const R = 32
  const code = new Uint8Array(N)
  const operand = new Uint32Array(N)
  let x = 55555
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    code[i] = (x & 0x7fffffff) % 4
    operand[i] = x
  }
  const fns = [
    (a, b) => (a + b) >>> 0,
    (a, b) => (a ^ b) >>> 0,
    (a, b) => Math.imul(a, b | 1) >>> 0,
    (a, b) => (a - b) >>> 0,
  ]
  let acc = 2166136261
  for (let r = 0; r < R; r++) {
    for (let i = 0; i < N; i++) {
      acc = fns[code[i]](acc, operand[i])
    }
  }
  console.log('checksum ' + (acc >>> 0))
}

function benchCollatz() {
  const N = 3_000_000
  let total = 0
  for (let i = 1; i <= N; i++) {
    let n = i,
      steps = 0
    // Parity via `% 2`, not bitwise `& 1`: trajectory values exceed 2^31 and
    // JS bitwise operators truncate to 32 bits, which would be wrong here.
    while (n !== 1) {
      n = n % 2 === 0 ? n / 2 : 3 * n + 1
      steps++
    }
    total += steps
  }
  console.log('checksum ' + total)
}

// --- n-body (dependent floating-point chains) -------------------------------
// All-pairs gravitational n-body. Each interaction needs 1/dist^3, so it leans
// on a hand-rolled Newton-iteration sqrt (8 fixed iterations from g0=(d2+1)/2,
// which is >= sqrt(d2) by AM-GM, so it converges monotonically). Only +,-,*,/
// so every language is bit-identical; the dependent Newton chain stresses FP
// latency, unlike mandelbrot/raster which are FP throughput.
function benchNbody() {
  const N = 2048
  const STEPS = 8
  const DT = 0.01
  const EPS = 0.05
  const px = new Float64Array(N)
  const py = new Float64Array(N)
  const pz = new Float64Array(N)
  const vx = new Float64Array(N)
  const vy = new Float64Array(N)
  const vz = new Float64Array(N)
  const m = new Float64Array(N)
  let s = 7777
  for (let i = 0; i < N; i++) {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    px[i] = ((s & 0xffff) / 65536) * 2 - 1
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    py[i] = ((s & 0xffff) / 65536) * 2 - 1
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    pz[i] = ((s & 0xffff) / 65536) * 2 - 1
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    m[i] = (s & 0xffff) / 65536 + 0.1
  }
  for (let step = 0; step < STEPS; step++) {
    for (let i = 0; i < N; i++) {
      let ax = 0,
        ay = 0,
        az = 0
      const xi = px[i],
        yi = py[i],
        zi = pz[i]
      for (let j = 0; j < N; j++) {
        if (j === i) continue
        const dx = px[j] - xi,
          dy = py[j] - yi,
          dz = pz[j] - zi
        const d2 = dx * dx + dy * dy + dz * dz + EPS
        let g = (d2 + 1) * 0.5
        for (let k = 0; k < 8; k++) g = (g + d2 / g) * 0.5
        const inv3 = 1 / (d2 * g)
        const f = m[j] * inv3
        ax += dx * f
        ay += dy * f
        az += dz * f
      }
      vx[i] += ax * DT
      vy[i] += ay * DT
      vz[i] += az * DT
    }
    for (let i = 0; i < N; i++) {
      px[i] += vx[i] * DT
      py[i] += vy[i] * DT
      pz[i] += vz[i] * DT
    }
  }
  let cs = 0
  for (let i = 0; i < N; i++) {
    let u = ((Math.trunc(px[i] * 1024) % 4294967296) + 4294967296) % 4294967296
    cs = (Math.imul(cs, 1000003) + u) >>> 0
    u = ((Math.trunc(py[i] * 1024) % 4294967296) + 4294967296) % 4294967296
    cs = (Math.imul(cs, 1000003) + u) >>> 0
    u = ((Math.trunc(pz[i] * 1024) % 4294967296) + 4294967296) % 4294967296
    cs = (Math.imul(cs, 1000003) + u) >>> 0
  }
  console.log('checksum ' + (cs >>> 0))
}

// --- STREAM triad (memory write bandwidth) ----------------------------------
// a[i] = b[i] + k*c[i] over big arrays, repeated. Complements sieve (streaming
// reads) and ptrchase (latency) by stressing sustained writes. 32-bit wrapping.
function benchStream() {
  const N = 16000000
  const R = 40
  const K = 3
  const a = new Uint32Array(N)
  const b = new Uint32Array(N)
  const c = new Uint32Array(N)
  let x = 11111
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    b[i] = x
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    c[i] = x
  }
  for (let r = 0; r < R; r++) {
    for (let i = 0; i < N; i++) a[i] = (b[i] + Math.imul(K, c[i])) >>> 0
  }
  let cs = 0
  for (let i = 0; i < N; i++) cs = (Math.imul(cs, 1000003) + a[i]) >>> 0
  console.log('checksum ' + (cs >>> 0))
}

// --- N-queens (backtracking recursion) --------------------------------------
// Counts solutions to the N-queens problem with the classic bitmask solver.
// Combines deep recursion (like fib) with unpredictable pruning branches (like
// collatz). Pure integer; checksum is the solution count.
function nqSolve(cols, d1, d2, full) {
  if (cols === full) return 1
  let count = 0
  let avail = ~(cols | d1 | d2) & full
  while (avail !== 0) {
    const bit = avail & -avail
    avail -= bit
    count += nqSolve(cols | bit, ((d1 | bit) * 2) & full, (d2 | bit) >> 1, full)
  }
  return count
}

function benchNqueens() {
  const NQ = 14
  const full = (1 << NQ) - 1
  const total = nqSolve(0, 0, 0, full)
  console.log('checksum ' + total)
}

// --- Conway's Game of Life (2D stencil + branches) --------------------------
// Steps a toroidal WxH grid through T generations, summing 8 wrapped neighbours
// per cell. A stencil/neighbour memory pattern none of the other benchmarks
// cover. Integer grid -> bit-identical.
function benchLife() {
  const W = 1024
  const H = 1024
  const T = 300
  let cur = new Uint8Array(W * H)
  let nxt = new Uint8Array(W * H)
  let x = 22221
  for (let i = 0; i < W * H; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    cur[i] = (x >>> 16) & 1
  }
  for (let gen = 0; gen < T; gen++) {
    for (let y = 0; y < H; y++) {
      const ym = y === 0 ? H - 1 : y - 1
      const yp = y === H - 1 ? 0 : y + 1
      for (let cx = 0; cx < W; cx++) {
        const xm = cx === 0 ? W - 1 : cx - 1
        const xp = cx === W - 1 ? 0 : cx + 1
        const n =
          cur[ym * W + xm] + cur[ym * W + cx] + cur[ym * W + xp] +
          cur[y * W + xm] + cur[y * W + xp] +
          cur[yp * W + xm] + cur[yp * W + cx] + cur[yp * W + xp]
        const alive = cur[y * W + cx]
        nxt[y * W + cx] = n === 3 || (alive && n === 2) ? 1 : 0
      }
    }
    const tmp = cur
    cur = nxt
    nxt = tmp
  }
  let cs = 0
  for (let i = 0; i < W * H; i++) cs = (Math.imul(cs, 1000003) + cur[i]) >>> 0
  console.log('checksum ' + (cs >>> 0))
}

// --- open-addressing hash map (linear probing) ------------------------------
// Inserts M keys into a power-of-two table with linear probing (summing values
// on duplicate keys), then runs Q lookups. Exercises the probe-sequence access
// pattern real hash maps use, distinct from bst's pointer chasing.
function benchHashmap() {
  const M = 8000000
  const Q = 16000000
  const SIZE = 1 << 24
  const MASK = SIZE - 1
  const keys = new Uint32Array(SIZE)
  const vals = new Uint32Array(SIZE)
  let x = 33331
  for (let n = 0; n < M; n++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    const key = ((x & 0x7fffffff) | 1) >>> 0
    let idx = key & MASK
    for (;;) {
      if (keys[idx] === 0) {
        keys[idx] = key
        vals[idx] = x
        break
      }
      if (keys[idx] === key) {
        vals[idx] = (vals[idx] + x) >>> 0
        break
      }
      idx = (idx + 1) & MASK
    }
  }
  let y = 99989
  let acc = 0
  for (let q = 0; q < Q; q++) {
    y = (Math.imul(y, 1664525) + 1013904223) >>> 0
    const key = ((y & 0x7fffffff) | 1) >>> 0
    let idx = key & MASK
    let steps = 0
    for (;;) {
      steps++
      if (keys[idx] === 0) break
      if (keys[idx] === key) {
        acc = (acc + vals[idx]) >>> 0
        break
      }
      idx = (idx + 1) & MASK
    }
    acc = (Math.imul(acc, 1000003) + steps) >>> 0
  }
  console.log('checksum ' + (acc >>> 0))
}

// --- SHA-256 (32-bit crypto mixing) -----------------------------------------
// Hashes a byte buffer in 64-byte blocks with the full SHA-256 compression.
// Heavy 32-bit rotate/shift/xor/add ALU work; bit-identical by spec. A "real"
// hash next to FNV (hash) and CRC32 (crc32).
const SHA_K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

function rotr32(x, n) {
  return ((x >>> n) | (x << (32 - n))) >>> 0
}

function benchSha256() {
  const N = 4000000
  const R = 16
  const buf = new Uint8Array(N)
  let x = 44441
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    buf[i] = (x >>> 8) & 0xff
  }
  let cs = 0
  const w = new Uint32Array(64)
  for (let r = 0; r < R; r++) {
    let h0 = 0x6a09e667,
      h1 = 0xbb67ae85,
      h2 = 0x3c6ef372,
      h3 = 0xa54ff53a,
      h4 = 0x510e527f,
      h5 = 0x9b05688c,
      h6 = 0x1f83d9ab,
      h7 = 0x5be0cd19
    const nblocks = (N / 64) | 0
    for (let blk = 0; blk < nblocks; blk++) {
      const base = blk * 64
      for (let t = 0; t < 16; t++) {
        const o = base + t * 4
        w[t] = ((buf[o] << 24) | (buf[o + 1] << 16) | (buf[o + 2] << 8) | buf[o + 3]) >>> 0
      }
      for (let t = 16; t < 64; t++) {
        const s0 = (rotr32(w[t - 15], 7) ^ rotr32(w[t - 15], 18) ^ (w[t - 15] >>> 3)) >>> 0
        const s1 = (rotr32(w[t - 2], 17) ^ rotr32(w[t - 2], 19) ^ (w[t - 2] >>> 10)) >>> 0
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) >>> 0
      }
      let a = h0,
        b = h1,
        c = h2,
        d = h3,
        e = h4,
        f = h5,
        g = h6,
        hh = h7
      for (let t = 0; t < 64; t++) {
        const S1 = (rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)) >>> 0
        const ch = ((e & f) ^ (~e & g)) >>> 0
        const t1 = (hh + S1 + ch + SHA_K[t] + w[t]) >>> 0
        const S0 = (rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)) >>> 0
        const maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0
        const t2 = (S0 + maj) >>> 0
        hh = g
        g = f
        f = e
        e = (d + t1) >>> 0
        d = c
        c = b
        b = a
        a = (t1 + t2) >>> 0
      }
      h0 = (h0 + a) >>> 0
      h1 = (h1 + b) >>> 0
      h2 = (h2 + c) >>> 0
      h3 = (h3 + d) >>> 0
      h4 = (h4 + e) >>> 0
      h5 = (h5 + f) >>> 0
      h6 = (h6 + g) >>> 0
      h7 = (h7 + hh) >>> 0
    }
    cs = (Math.imul(cs, 1000003) + ((h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7) >>> 0)) >>> 0
  }
  console.log('checksum ' + (cs >>> 0))
}

// --- matrix transpose (cache stride / TLB) ----------------------------------
// Naive out-of-place transpose of a big NxN matrix, repeated with src/dst
// swapped. The column-strided writes thrash cache and TLB, complementing
// matmul's dense compute. 32-bit folded in linear order so layout matters.
function benchTranspose() {
  const NDIM = 4096
  const R = 6
  let src = new Uint32Array(NDIM * NDIM)
  let dst = new Uint32Array(NDIM * NDIM)
  let x = 55551
  for (let i = 0; i < NDIM * NDIM; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    src[i] = x
  }
  for (let r = 0; r < R; r++) {
    for (let i = 0; i < NDIM; i++) {
      for (let j = 0; j < NDIM; j++) dst[j * NDIM + i] = src[i * NDIM + j]
    }
    const tmp = src
    src = dst
    dst = tmp
  }
  let cs = 0
  for (let i = 0; i < NDIM * NDIM; i++) cs = (Math.imul(cs, 1000003) + src[i]) >>> 0
  console.log('checksum ' + (cs >>> 0))
}

// --- edit distance (dynamic programming) ------------------------------------
// Levenshtein distance between two pseudo-random small-alphabet strings via the
// classic two-row DP. A data-dependent min-of-three table fill; no other
// benchmark exercises 2D dynamic programming. Checksum is the distance.
function benchEditdist() {
  const LA = 16000
  const LB = 16000
  const a = new Uint8Array(LA)
  const b = new Uint8Array(LB)
  let x = 66661
  for (let i = 0; i < LA; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    a[i] = (x >>> 16) % 4
  }
  for (let i = 0; i < LB; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    b[i] = (x >>> 16) % 4
  }
  let prev = new Int32Array(LB + 1)
  let cur = new Int32Array(LB + 1)
  for (let j = 0; j <= LB; j++) prev[j] = j
  for (let i = 1; i <= LA; i++) {
    cur[0] = i
    for (let j = 1; j <= LB; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      const del = prev[j] + 1
      const ins = cur[j - 1] + 1
      const sub = prev[j - 1] + cost
      const mn = del < ins ? del : ins
      cur[j] = mn < sub ? mn : sub
    }
    const tmp = prev
    prev = cur
    cur = tmp
  }
  console.log('checksum ' + (prev[LB] >>> 0))
}

// --- LZ77 greedy compressor (branchy match search) --------------------------
// Greedily matches each position against a sliding window, emitting (offset,
// length) tokens or literals folded into an FNV hash. The nested longest-match
// scan is branchy and memory-bound, a heavier cousin of rle.
function benchLz() {
  const N = 4000000
  const WIN = 512
  const MAXLEN = 64
  const buf = new Uint8Array(N)
  let x = 77771
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    buf[i] = (x >>> 16) % 8
  }
  let h = 2166136261
  let p = 0
  while (p < N) {
    const lo = p > WIN ? p - WIN : 0
    let bestlen = 0
    let bestoff = 0
    for (let sidx = lo; sidx < p; sidx++) {
      let len = 0
      while (p + len < N && len < MAXLEN && buf[sidx + len] === buf[p + len]) len++
      if (len > bestlen) {
        bestlen = len
        bestoff = p - sidx
      }
    }
    if (bestlen >= 3) {
      h ^= bestoff & 0xff
      h = Math.imul(h, 16777619) >>> 0
      h ^= (bestoff >>> 8) & 0xff
      h = Math.imul(h, 16777619) >>> 0
      h ^= bestlen & 0xff
      h = Math.imul(h, 16777619) >>> 0
      p += bestlen
    } else {
      h ^= buf[p]
      h = Math.imul(h, 16777619) >>> 0
      p += 1
    }
  }
  console.log('checksum ' + (h >>> 0))
}

// --- CRC32 (table-driven hashing) -------------------------------------------
// Builds the standard CRC32 table (poly 0xEDB88320) then CRCs a byte buffer
// several times. Table-lookup gather plus shift/xor, distinct from FNV's pure
// ALU and SHA's wide mixing.
function benchCrc32() {
  const N = 16000000
  const R = 8
  const table = new Uint32Array(256)
  for (let i = 0; i < 256; i++) {
    let c = i
    for (let k = 0; k < 8; k++) c = c & 1 ? (0xedb88320 ^ (c >>> 1)) >>> 0 : c >>> 1
    table[i] = c
  }
  const buf = new Uint8Array(N)
  let x = 88881
  for (let i = 0; i < N; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0
    buf[i] = (x >>> 16) & 0xff
  }
  let cs = 0
  for (let r = 0; r < R; r++) {
    let crc = 0xffffffff
    for (let i = 0; i < N; i++) crc = (table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8)) >>> 0
    crc = (crc ^ 0xffffffff) >>> 0
    cs = (Math.imul(cs, 1000003) + crc) >>> 0
  }
  console.log('checksum ' + (cs >>> 0))
}

function main() {
  const name = process.argv[2]
  if (!name) {
    console.log(
      'usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>',
    )
    return
  }
  const benches = {
    fib: benchFib,
    mandelbrot: benchMandelbrot,
    matmul: benchMatmul,
    sieve: benchSieve,
    sort: benchSort,
    collatz: benchCollatz,
    raster: benchRaster,
    ptrchase: benchPtrchase,
    hash: benchHash,
    bst: benchBst,
    rle: benchRle,
    base64: benchBase64,
    dispatch: benchDispatch,
    nbody: benchNbody,
    stream: benchStream,
    nqueens: benchNqueens,
    life: benchLife,
    hashmap: benchHashmap,
    sha256: benchSha256,
    transpose: benchTranspose,
    editdist: benchEditdist,
    lz: benchLz,
    crc32: benchCrc32,
  }
  if (benches[name]) benches[name]()
  else console.log('unknown benchmark: ' + name)
}

main()
