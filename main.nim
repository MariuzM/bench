# ---------------------------------------------------------------------------
# Benchmark suite. One process runs exactly one benchmark, selected by the
# command-line argument, so the build script can measure each one's wall-time
# and peak memory in isolation. Every benchmark prints a single "checksum <n>"
# line; all language builds must agree on it, which proves they did the same
# work. Nim unsigned integer arithmetic wraps (two's complement) by spec,
# matching the other builds' explicit wrapping operators.
# ---------------------------------------------------------------------------

import os

proc fib(n: uint64): uint64 =
  if n < 2: return n
  return fib(n - 1) + fib(n - 2)

proc bench_fib() =
  var total: uint64 = 0
  var n: uint64 = 30
  while n <= 42:
    total += fib(n)
    n += 1
  echo "checksum ", total

proc bench_mandelbrot() =
  const W = 1200
  const H = 1200
  const MAX_IT = 1000
  var sum: uint64 = 0
  for py in 0 ..< H:
    let y0 = (float64(py) / float64(H)) * 4.0 - 2.0
    for px in 0 ..< W:
      let x0 = (float64(px) / float64(W)) * 4.0 - 2.5
      var x = 0.0
      var y = 0.0
      var it: uint64 = 0
      while x * x + y * y <= 4.0 and it < MAX_IT:
        let xt = x * x - y * y + x0
        y = 2.0 * x * y + y0
        x = xt
        it += 1
      sum += it
  echo "checksum ", sum

proc bench_matmul() =
  const N = 512
  var a = newSeq[int64](N * N)
  var b = newSeq[int64](N * N)
  var c = newSeq[int64](N * N)
  for i in 0 ..< N:
    for j in 0 ..< N:
      a[i * N + j] = int64((i * j) mod 7) - 3
      b[i * N + j] = int64((i + j) mod 5) - 2
      c[i * N + j] = 0
  for i in 0 ..< N:
    for k in 0 ..< N:
      let aik = a[i * N + k]
      for j in 0 ..< N:
        c[i * N + j] += aik * b[k * N + j]
  var sum: int64 = 0
  for i in 0 ..< N * N: sum += c[i]
  echo "checksum ", sum

proc bench_sieve() =
  const N = 50_000_000
  var sieve = newSeq[uint8](N)
  for i in 0 ..< N: sieve[i] = 1
  sieve[0] = 0
  sieve[1] = 0
  var i = 2
  while i * i < N:
    if sieve[i] == 1:
      var j = i * i
      while j < N:
        sieve[j] = 0
        j += i
    i += 1
  var count: uint64 = 0
  for i in 0 ..< N: count += uint64(sieve[i])
  echo "checksum ", count

proc quicksort(arr: var seq[uint64], lo: int, hi: int) =
  if lo >= hi: return
  let pivot = arr[(lo + hi) div 2]
  var i = lo
  var j = hi
  while i <= j:
    while arr[i] < pivot: i += 1
    while arr[j] > pivot: j -= 1
    if i <= j:
      let t = arr[i]
      arr[i] = arr[j]
      arr[j] = t
      i += 1
      j -= 1
  quicksort(arr, lo, j)
  quicksort(arr, i, hi)

proc bench_sort() =
  const N = 3_000_000
  var arr = newSeq[uint64](N)
  var state: uint64 = 88172645463325252'u64
  for i in 0 ..< N:
    state = state * 6364136223846793005'u64 + 1442695040888963407'u64
    arr[i] = state and 0x7FFFFFFFFFFFFFFF'u64
  quicksort(arr, 0, N - 1)
  var cs: uint64 = 0
  for i in 0 ..< N: cs = cs * 1000003'u64 + arr[i]
  echo "checksum ", cs

# --- software 3D rasterizer -------------------------------------------------
# Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
# with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
# hand-rolled polynomial sin/cos (libm's differ per language) so every
# language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

proc r_floor(y: float64): float64 =
  let f = float64(int64(y))
  return (if f > y: f - 1.0 else: f)

proc r_sin(xin: float64): float64 =
  const TWO_PI = 6.283185307179586
  let k = r_floor(xin / TWO_PI + 0.5)
  let x = xin - k * TWO_PI
  let x2 = x * x
  var p = -1.0 / 1307674368000.0
  p = 1.0 / 6227020800.0 + x2 * p
  p = -1.0 / 39916800.0 + x2 * p
  p = 1.0 / 362880.0 + x2 * p
  p = -1.0 / 5040.0 + x2 * p
  p = 1.0 / 120.0 + x2 * p
  p = -1.0 / 6.0 + x2 * p
  p = 1.0 + x2 * p
  return x * p

proc r_cos(x: float64): float64 =
  const HALF_PI = 1.5707963267948966
  return r_sin(x + HALF_PI)

proc edge(ax, ay, bx, by, cx, cy: float64): float64 =
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

proc bench_raster() =
  const W = 640
  const H = 480
  const RINGS = 24
  const SECTORS = 24
  const FRAMES = 240
  const NV = (RINGS + 1) * (SECTORS + 1)
  const FOCAL = 500.0
  const CAM_DIST = 3.0

  var bx: array[NV, float64]
  var by: array[NV, float64]
  var bz: array[NV, float64]
  var nv = 0
  for i in 0 .. RINGS:
    let theta = 3.141592653589793 * (float64(i) / float64(RINGS))
    let st = r_sin(theta)
    let ct = r_cos(theta)
    for j in 0 .. SECTORS:
      let phi = 6.283185307179586 * (float64(j) / float64(SECTORS))
      let sp = r_sin(phi)
      let cp = r_cos(phi)
      bx[nv] = st * cp
      by[nv] = ct
      bz[nv] = st * sp
      nv += 1

  var sx: array[NV, float64]
  var sy: array[NV, float64]
  var sz: array[NV, float64]
  var si: array[NV, float64]

  var color = newSeq[uint8](W * H)
  var zbuf = newSeq[float64](W * H)

  var checksum: uint64 = 0

  for f in 0 ..< FRAMES:
    let ang = float64(f) * 0.0125
    let cy = r_cos(ang)
    let syr = r_sin(ang)
    let axx = ang * 0.5
    let cx = r_cos(axx)
    let sxr = r_sin(axx)

    for v in 0 ..< nv:
      let px0 = bx[v]
      let py0 = by[v]
      let pz0 = bz[v]
      let rx = px0 * cy + pz0 * syr
      let rz = -px0 * syr + pz0 * cy
      let ry = py0
      let ry2 = ry * cx - rz * sxr
      let rz2 = ry * sxr + rz * cx
      var inten = -rz2
      if inten < 0.0: inten = 0.0
      let zc = rz2 + CAM_DIST
      let invz = 1.0 / zc
      sx[v] = rx * invz * FOCAL + float64(W) * 0.5
      sy[v] = ry2 * invz * FOCAL + float64(H) * 0.5
      sz[v] = zc
      si[v] = inten

    for c in 0 ..< W * H:
      color[c] = 0
      zbuf[c] = 1.0e30

    for ri in 0 ..< RINGS:
      for sj in 0 ..< SECTORS:
        let a = ri * (SECTORS + 1) + sj
        let b = a + (SECTORS + 1)
        let tris = [[a, b, a + 1], [a + 1, b, b + 1]]
        for t in 0 ..< 2:
          let i0 = tris[t][0]
          let i1 = tris[t][1]
          let i2 = tris[t][2]
          let area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2])
          if area <= 0.0: continue
          var mnx = sx[i0]
          if sx[i1] < mnx: mnx = sx[i1]
          if sx[i2] < mnx: mnx = sx[i2]
          var mxx = sx[i0]
          if sx[i1] > mxx: mxx = sx[i1]
          if sx[i2] > mxx: mxx = sx[i2]
          var mny = sy[i0]
          if sy[i1] < mny: mny = sy[i1]
          if sy[i2] < mny: mny = sy[i2]
          var mxy = sy[i0]
          if sy[i1] > mxy: mxy = sy[i1]
          if sy[i2] > mxy: mxy = sy[i2]
          if mnx < 0.0: mnx = 0.0
          if mxx > float64(W - 1): mxx = float64(W - 1)
          if mny < 0.0: mny = 0.0
          if mxy > float64(H - 1): mxy = float64(H - 1)
          let x0 = int(mnx)
          let x1 = int(mxx)
          let y0 = int(mny)
          let y1 = int(mxy)
          for py in y0 .. y1:
            let pcy = float64(py) + 0.5
            for px in x0 .. x1:
              let pcx = float64(px) + 0.5
              let w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy)
              let w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy)
              let w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy)
              if w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0:
                let l0 = w0 / area
                let l1 = w1 / area
                let l2 = w2 / area
                let depth = l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2]
                let idx = py * W + px
                if depth < zbuf[idx]:
                  zbuf[idx] = depth
                  var inten = l0 * si[i0] + l1 * si[i1] + l2 * si[i2]
                  if inten < 0.0: inten = 0.0
                  if inten > 1.0: inten = 1.0
                  color[idx] = uint8(inten * 255.0)

    var frame_sum: uint64 = 0
    for c in 0 ..< W * H: frame_sum += uint64(color[c])
    checksum = checksum * 1000003'u64 + frame_sum

  echo "checksum ", checksum

# --- pointer-chasing (random memory latency) --------------------------------
proc bench_ptrchase() =
  const N = 16000000
  const HOPS = 4000000
  var order = newSeq[uint32](N)
  var next = newSeq[uint32](N)
  for i in 0 ..< N: order[i] = uint32(i)
  var x: uint32 = 1
  var i = N - 1
  while i >= 1:
    x = x * 1664525'u32 + 1013904223'u32
    let j = int((x and 0x7FFFFFFF'u32) mod (uint32(i) + 1))
    let t = order[i]
    order[i] = order[j]
    order[j] = t
    i -= 1
  for k in 0 ..< N: next[int(order[k])] = order[(k + 1) mod N]
  var sum: uint32 = 0
  var p: uint32 = 0
  for h in 0 ..< HOPS:
    p = next[int(p)]
    sum += p
  echo "checksum ", sum

# --- FNV-1a hash ------------------------------------------------------------
proc bench_hash() =
  const N = 32000000
  const R = 4
  var buf = newSeq[uint8](N)
  var x: uint32 = 12345
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    buf[i] = uint8(x and 0xFF)
  var h: uint32 = 2166136261'u32
  for r in 0 ..< R:
    for i in 0 ..< N:
      h = h xor uint32(buf[i])
      h = h * 16777619'u32
  echo "checksum ", h

# --- binary search tree -----------------------------------------------------
type BstNode = ref object
  key: uint32
  left: BstNode
  right: BstNode

proc bench_bst() =
  const M = 1000000
  const Q = 1000000
  var root: BstNode = nil
  var x: uint32 = 22222
  for n in 0 ..< M:
    x = x * 1664525'u32 + 1013904223'u32
    let key = x and 0x7FFFFFFF'u32
    var nn = BstNode(key: key)
    if root == nil:
      root = nn
      continue
    var cur = root
    while true:
      if key < cur.key:
        if cur.left == nil:
          cur.left = nn
          break
        cur = cur.left
      else:
        if cur.right == nil:
          cur.right = nn
          break
        cur = cur.right
  var y: uint32 = 99991
  var cs: uint32 = 0
  for q in 0 ..< Q:
    y = y * 1664525'u32 + 1013904223'u32
    let key = y and 0x7FFFFFFF'u32
    var steps: uint32 = 0
    var cur = root
    while cur != nil:
      steps += 1
      if key == cur.key: break
      if key < cur.key: cur = cur.left
      else: cur = cur.right
    cs = cs * 1000003'u32 + steps
  echo "checksum ", cs

# --- run-length encoding ----------------------------------------------------
proc bench_rle() =
  const N = 40000000
  const R = 4
  var buf = newSeq[uint8](N)
  var outp = newSeq[uint8](2 * N)
  var x: uint32 = 33333
  var i = 0
  while i < N:
    x = x * 1664525'u32 + 1013904223'u32
    let v = uint8(x and 0xFF)
    let rl = ((x and 0x7FFFFFFF'u32) mod 16) + 1
    var c: uint32 = 0
    while c < rl and i < N:
      buf[i] = v
      i += 1
      c += 1
  var h: uint32 = 2166136261'u32
  for r in 0 ..< R:
    var o = 0
    var p = 0
    while p < N:
      let v = buf[p]
      var run = 1
      while p + run < N and buf[p + run] == v and run < 255: run += 1
      outp[o] = uint8(run)
      outp[o + 1] = v
      o += 2
      p += run
    for k in 0 ..< o:
      h = h xor uint32(outp[k])
      h = h * 16777619'u32
    h = h xor uint32(o mod 256); h = h * 16777619'u32
    h = h xor uint32((o div 256) mod 256); h = h * 16777619'u32
    h = h xor uint32((o div 65536) mod 256); h = h * 16777619'u32
    h = h xor uint32((o div 16777216) mod 256); h = h * 16777619'u32
  echo "checksum ", h

# --- base64 encoding --------------------------------------------------------
proc bench_base64() =
  const N = 24000000
  const R = 4
  const b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  var buf = newSeq[uint8](N)
  var x: uint32 = 44444
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    buf[i] = uint8(x and 0xFF)
  var h: uint32 = 2166136261'u32
  for r in 0 ..< R:
    var i = 0
    while i + 2 < N:
      let b0 = uint32(buf[i])
      let b1 = uint32(buf[i + 1])
      let b2 = uint32(buf[i + 2])
      let i0 = b0 div 4
      let i1 = (b0 and 3) * 16 + b1 div 16
      let i2 = (b1 and 15) * 4 + b2 div 64
      let i3 = b2 and 63
      h = h xor uint32(ord(b64[int(i0)])); h = h * 16777619'u32
      h = h xor uint32(ord(b64[int(i1)])); h = h * 16777619'u32
      h = h xor uint32(ord(b64[int(i2)])); h = h * 16777619'u32
      h = h xor uint32(ord(b64[int(i3)])); h = h * 16777619'u32
      i += 3
  echo "checksum ", h

# --- indirect dispatch ------------------------------------------------------
proc op_add(a, b: uint32): uint32 = a + b
proc op_xor(a, b: uint32): uint32 = a xor b
proc op_mul(a, b: uint32): uint32 = a * (b or 1)
proc op_sub(a, b: uint32): uint32 = a - b

proc bench_dispatch() =
  const N = 4000000
  const R = 32
  var code = newSeq[uint8](N)
  var operand = newSeq[uint32](N)
  var x: uint32 = 55555
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    code[i] = uint8((x and 0x7FFFFFFF'u32) mod 4)
    operand[i] = x
  let fns = [op_add, op_xor, op_mul, op_sub]
  var acc: uint32 = 2166136261'u32
  for r in 0 ..< R:
    for i in 0 ..< N: acc = fns[int(code[i])](acc, operand[i])
  echo "checksum ", acc

proc bench_collatz() =
  const N = 3_000_000
  var total: uint64 = 0
  var i: uint64 = 1
  while i <= N:
    var n = i
    var steps: uint64 = 0
    while n != 1:
      n = (if n mod 2 == 0: n div 2 else: 3 * n + 1)
      steps += 1
    total += steps
    i += 1
  echo "checksum ", total

# --- n-body (dependent floating-point chains) -------------------------------
proc bench_nbody() =
  const N = 2048
  const STEPS = 8
  const DT = 0.01
  const EPS = 0.05
  var px = newSeq[float64](N)
  var py = newSeq[float64](N)
  var pz = newSeq[float64](N)
  var vx = newSeq[float64](N)
  var vy = newSeq[float64](N)
  var vz = newSeq[float64](N)
  var m = newSeq[float64](N)
  var s: uint32 = 7777
  for i in 0 ..< N:
    s = s * 1664525'u32 + 1013904223'u32
    px[i] = (float64(s and 0xFFFF) / 65536.0) * 2.0 - 1.0
    s = s * 1664525'u32 + 1013904223'u32
    py[i] = (float64(s and 0xFFFF) / 65536.0) * 2.0 - 1.0
    s = s * 1664525'u32 + 1013904223'u32
    pz[i] = (float64(s and 0xFFFF) / 65536.0) * 2.0 - 1.0
    s = s * 1664525'u32 + 1013904223'u32
    m[i] = float64(s and 0xFFFF) / 65536.0 + 0.1
  for step in 0 ..< STEPS:
    for i in 0 ..< N:
      var ax = 0.0
      var ay = 0.0
      var az = 0.0
      let xi = px[i]
      let yi = py[i]
      let zi = pz[i]
      for j in 0 ..< N:
        if j == i: continue
        let dx = px[j] - xi
        let dy = py[j] - yi
        let dz = pz[j] - zi
        let d2 = dx * dx + dy * dy + dz * dz + EPS
        var g = (d2 + 1.0) * 0.5
        for k in 0 ..< 8: g = (g + d2 / g) * 0.5
        let inv3 = 1.0 / (d2 * g)
        let f = m[j] * inv3
        ax += dx * f
        ay += dy * f
        az += dz * f
      vx[i] += ax * DT
      vy[i] += ay * DT
      vz[i] += az * DT
    for i in 0 ..< N:
      px[i] += vx[i] * DT
      py[i] += vy[i] * DT
      pz[i] += vz[i] * DT
  var cs: uint32 = 0
  for i in 0 ..< N:
    cs = cs * 1000003'u32 + uint32(int64(px[i] * 1024.0))
    cs = cs * 1000003'u32 + uint32(int64(py[i] * 1024.0))
    cs = cs * 1000003'u32 + uint32(int64(pz[i] * 1024.0))
  echo "checksum ", cs

# --- STREAM triad (memory write bandwidth) ----------------------------------
proc bench_stream() =
  const N = 16000000
  const R = 40
  const K: uint32 = 3
  var a = newSeq[uint32](N)
  var b = newSeq[uint32](N)
  var c = newSeq[uint32](N)
  var x: uint32 = 11111
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    b[i] = x
    x = x * 1664525'u32 + 1013904223'u32
    c[i] = x
  for r in 0 ..< R:
    for i in 0 ..< N: a[i] = b[i] + K * c[i]
  var cs: uint32 = 0
  for i in 0 ..< N: cs = cs * 1000003'u32 + a[i]
  echo "checksum ", cs

# --- N-queens (backtracking recursion) --------------------------------------
proc nq_solve(cols, d1, d2, full: uint32): uint64 =
  if cols == full: return 1
  var count: uint64 = 0
  var avail = (not (cols or d1 or d2)) and full
  while avail != 0:
    let bit = avail and ((not avail) + 1'u32)
    avail -= bit
    count += nq_solve(cols or bit, ((d1 or bit) * 2) and full, (d2 or bit) div 2, full)
  return count

proc bench_nqueens() =
  const NQ = 14
  let full: uint32 = (1'u32 shl NQ) - 1
  let total = nq_solve(0, 0, 0, full)
  echo "checksum ", total

# --- Conway's Game of Life --------------------------------------------------
proc bench_life() =
  const W = 1024
  const H = 1024
  const T = 300
  var cur = newSeq[uint8](W * H)
  var nxt = newSeq[uint8](W * H)
  var x: uint32 = 22221
  for i in 0 ..< W * H:
    x = x * 1664525'u32 + 1013904223'u32
    cur[i] = uint8((x div 65536) and 1)
  for gen in 0 ..< T:
    for y in 0 ..< H:
      let ym = (if y == 0: H - 1 else: y - 1)
      let yp = (if y == H - 1: 0 else: y + 1)
      for xx in 0 ..< W:
        let xm = (if xx == 0: W - 1 else: xx - 1)
        let xp = (if xx == W - 1: 0 else: xx + 1)
        let n = int(cur[ym * W + xm]) + int(cur[ym * W + xx]) + int(cur[ym * W + xp]) +
          int(cur[y * W + xm]) + int(cur[y * W + xp]) +
          int(cur[yp * W + xm]) + int(cur[yp * W + xx]) + int(cur[yp * W + xp])
        let alive = cur[y * W + xx]
        nxt[y * W + xx] = (if n == 3 or (alive == 1 and n == 2): 1 else: 0)
    swap(cur, nxt)
  var cs: uint32 = 0
  for i in 0 ..< W * H: cs = cs * 1000003'u32 + uint32(cur[i])
  echo "checksum ", cs

# --- open-addressing hash map (linear probing) ------------------------------
proc bench_hashmap() =
  const M = 8000000
  const Q = 16000000
  const SIZE = 1 shl 24
  const MASK: uint32 = SIZE - 1
  var keys = newSeq[uint32](SIZE)
  var vals = newSeq[uint32](SIZE)
  var x: uint32 = 33331
  for n in 0 ..< M:
    x = x * 1664525'u32 + 1013904223'u32
    let key = (x and 0x7FFFFFFF'u32) or 1
    var idx = key and MASK
    while true:
      if keys[int(idx)] == 0:
        keys[int(idx)] = key
        vals[int(idx)] = x
        break
      if keys[int(idx)] == key:
        vals[int(idx)] += x
        break
      idx = (idx + 1) and MASK
  var y: uint32 = 99989
  var acc: uint32 = 0
  for q in 0 ..< Q:
    y = y * 1664525'u32 + 1013904223'u32
    let key = (y and 0x7FFFFFFF'u32) or 1
    var idx = key and MASK
    var steps: uint32 = 0
    while true:
      steps += 1
      if keys[int(idx)] == 0: break
      if keys[int(idx)] == key:
        acc += vals[int(idx)]
        break
      idx = (idx + 1) and MASK
    acc = acc * 1000003'u32 + steps
  echo "checksum ", acc

# --- SHA-256 (32-bit crypto mixing) -----------------------------------------
proc rotr32(x: uint32, n: uint32): uint32 =
  return (x shr n) or (x shl (32'u32 - n))

proc bench_sha256() =
  const N = 4000000
  const R = 16
  const k = [
    0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
    0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32, 0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
    0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
    0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
    0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32, 0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
    0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
    0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
    0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32, 0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32,
  ]
  var buf = newSeq[uint8](N)
  var x: uint32 = 44441
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    buf[i] = uint8((x div 256) and 0xFF)
  var cs: uint32 = 0
  for r in 0 ..< R:
    var h0: uint32 = 0x6a09e667'u32
    var h1: uint32 = 0xbb67ae85'u32
    var h2: uint32 = 0x3c6ef372'u32
    var h3: uint32 = 0xa54ff53a'u32
    var h4: uint32 = 0x510e527f'u32
    var h5: uint32 = 0x9b05688c'u32
    var h6: uint32 = 0x1f83d9ab'u32
    var h7: uint32 = 0x5be0cd19'u32
    let nblocks = N div 64
    var w: array[64, uint32]
    for blk in 0 ..< nblocks:
      let base = blk * 64
      for t in 0 ..< 16:
        let o = base + t * 4
        w[t] = (uint32(buf[o]) shl 24) or (uint32(buf[o + 1]) shl 16) or (uint32(buf[o + 2]) shl 8) or uint32(buf[o + 3])
      for t in 16 ..< 64:
        let s0 = rotr32(w[t - 15], 7) xor rotr32(w[t - 15], 18) xor (w[t - 15] shr 3)
        let s1 = rotr32(w[t - 2], 17) xor rotr32(w[t - 2], 19) xor (w[t - 2] shr 10)
        w[t] = w[t - 16] + s0 + w[t - 7] + s1
      var a = h0
      var b = h1
      var c = h2
      var d = h3
      var e = h4
      var f = h5
      var g = h6
      var hh = h7
      for t in 0 ..< 64:
        let S1 = rotr32(e, 6) xor rotr32(e, 11) xor rotr32(e, 25)
        let ch = (e and f) xor ((not e) and g)
        let t1 = hh + S1 + ch + k[t] + w[t]
        let S0 = rotr32(a, 2) xor rotr32(a, 13) xor rotr32(a, 22)
        let maj = (a and b) xor (a and c) xor (b and c)
        let t2 = S0 + maj
        hh = g
        g = f
        f = e
        e = d + t1
        d = c
        c = b
        b = a
        a = t1 + t2
      h0 += a
      h1 += b
      h2 += c
      h3 += d
      h4 += e
      h5 += f
      h6 += g
      h7 += hh
    cs = cs * 1000003'u32 + (h0 xor h1 xor h2 xor h3 xor h4 xor h5 xor h6 xor h7)
  echo "checksum ", cs

# --- matrix transpose (cache stride / TLB) ----------------------------------
proc bench_transpose() =
  const NDIM = 4096
  const R = 6
  var src = newSeq[uint32](NDIM * NDIM)
  var dst = newSeq[uint32](NDIM * NDIM)
  var x: uint32 = 55551
  for i in 0 ..< NDIM * NDIM:
    x = x * 1664525'u32 + 1013904223'u32
    src[i] = x
  for r in 0 ..< R:
    for i in 0 ..< NDIM:
      for j in 0 ..< NDIM: dst[j * NDIM + i] = src[i * NDIM + j]
    swap(src, dst)
  var cs: uint32 = 0
  for i in 0 ..< NDIM * NDIM: cs = cs * 1000003'u32 + src[i]
  echo "checksum ", cs

# --- edit distance (dynamic programming) ------------------------------------
proc edit_min3(a, b, c: int32): int32 =
  let m = (if a < b: a else: b)
  return (if m < c: m else: c)

proc bench_editdist() =
  const LA = 16000
  const LB = 16000
  var a = newSeq[uint8](LA)
  var b = newSeq[uint8](LB)
  var prev = newSeq[int32](LB + 1)
  var cur = newSeq[int32](LB + 1)
  var x: uint32 = 66661
  for i in 0 ..< LA:
    x = x * 1664525'u32 + 1013904223'u32
    a[i] = uint8((x div 65536) mod 4)
  for i in 0 ..< LB:
    x = x * 1664525'u32 + 1013904223'u32
    b[i] = uint8((x div 65536) mod 4)
  for j in 0 .. LB: prev[j] = int32(j)
  for i in 1 .. LA:
    cur[0] = int32(i)
    for j in 1 .. LB:
      let cost: int32 = (if a[i - 1] == b[j - 1]: 0 else: 1)
      cur[j] = edit_min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    swap(prev, cur)
  echo "checksum ", uint32(prev[LB])

# --- LZ77 greedy compressor -------------------------------------------------
proc bench_lz() =
  const N = 4000000
  const WIN = 512
  const MAXLEN = 64
  var buf = newSeq[uint8](N)
  var x: uint32 = 77771
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    buf[i] = uint8((x div 65536) mod 8)
  var h: uint32 = 2166136261'u32
  var p = 0
  while p < N:
    let lo = (if p > WIN: p - WIN else: 0)
    var bestlen = 0
    var bestoff = 0
    for sidx in lo ..< p:
      var length = 0
      while p + length < N and length < MAXLEN and buf[sidx + length] == buf[p + length]: length += 1
      if length > bestlen:
        bestlen = length
        bestoff = p - sidx
    if bestlen >= 3:
      h = h xor uint32(bestoff and 0xFF); h = h * 16777619'u32
      h = h xor uint32((bestoff div 256) and 0xFF); h = h * 16777619'u32
      h = h xor uint32(bestlen and 0xFF); h = h * 16777619'u32
      p += bestlen
    else:
      h = h xor uint32(buf[p]); h = h * 16777619'u32
      p += 1
  echo "checksum ", h

# --- CRC32 (table-driven hashing) -------------------------------------------
proc bench_crc32() =
  const N = 16000000
  const R = 8
  var table: array[256, uint32]
  for i in 0 ..< 256:
    var c = uint32(i)
    for kk in 0 ..< 8: c = (if (c and 1) == 1: 0xEDB88320'u32 xor (c shr 1) else: (c shr 1))
    table[i] = c
  var buf = newSeq[uint8](N)
  var x: uint32 = 88881
  for i in 0 ..< N:
    x = x * 1664525'u32 + 1013904223'u32
    buf[i] = uint8((x div 65536) and 0xFF)
  var cs: uint32 = 0
  for r in 0 ..< R:
    var crc: uint32 = 0xFFFFFFFF'u32
    for i in 0 ..< N: crc = table[int((crc xor uint32(buf[i])) and 0xFF)] xor (crc shr 8)
    crc = crc xor 0xFFFFFFFF'u32
    cs = cs * 1000003'u32 + crc
  echo "checksum ", cs

proc main() =
  if paramCount() < 1:
    echo "usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>"
    return
  let name = paramStr(1)
  case name
  of "fib": bench_fib()
  of "mandelbrot": bench_mandelbrot()
  of "matmul": bench_matmul()
  of "sieve": bench_sieve()
  of "sort": bench_sort()
  of "collatz": bench_collatz()
  of "raster": bench_raster()
  of "ptrchase": bench_ptrchase()
  of "hash": bench_hash()
  of "bst": bench_bst()
  of "rle": bench_rle()
  of "base64": bench_base64()
  of "dispatch": bench_dispatch()
  of "nbody": bench_nbody()
  of "stream": bench_stream()
  of "nqueens": bench_nqueens()
  of "life": bench_life()
  of "hashmap": bench_hashmap()
  of "sha256": bench_sha256()
  of "transpose": bench_transpose()
  of "editdist": bench_editdist()
  of "lz": bench_lz()
  of "crc32": bench_crc32()
  else: echo "unknown benchmark: ", name

main()
