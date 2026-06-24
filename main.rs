// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by argv[1],
// so the build script can measure each one's wall-time and peak memory in
// isolation. Every benchmark prints a single "checksum <n>" line; all language
// builds must agree on it, which proves they did the same work.
// ---------------------------------------------------------------------------

use std::env;

fn fib(n: u64) -> u64 {
    if n < 2 {
        return n;
    }
    fib(n - 1) + fib(n - 2)
}

fn bench_fib() {
    let mut total: u64 = 0;
    for n in 30u64..=42 {
        total = total.wrapping_add(fib(n));
    }
    println!("checksum {}", total);
}

fn bench_mandelbrot() {
    const W: usize = 1200;
    const H: usize = 1200;
    const MAX_IT: u64 = 1000;
    let mut sum: u64 = 0;
    for py in 0..H {
        let y0 = (py as f64 / H as f64) * 4.0 - 2.0;
        for px in 0..W {
            let x0 = (px as f64 / W as f64) * 4.0 - 2.5;
            let (mut x, mut y): (f64, f64) = (0.0, 0.0);
            let mut it: u64 = 0;
            while x * x + y * y <= 4.0 && it < MAX_IT {
                let xt = x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
                it += 1;
            }
            sum = sum.wrapping_add(it);
        }
    }
    println!("checksum {}", sum);
}

fn bench_matmul() {
    const N: usize = 512;
    let mut a = vec![0i64; N * N];
    let mut b = vec![0i64; N * N];
    let mut c = vec![0i64; N * N];

    for i in 0..N {
        for j in 0..N {
            a[i * N + j] = ((i * j) % 7) as i64 - 3;
            b[i * N + j] = ((i + j) % 5) as i64 - 2;
            c[i * N + j] = 0;
        }
    }

    for i in 0..N {
        for k in 0..N {
            let aik = a[i * N + k];
            for j in 0..N {
                c[i * N + j] += aik * b[k * N + j];
            }
        }
    }

    let mut sum: i64 = 0;
    for i in 0..N * N {
        sum = sum.wrapping_add(c[i]);
    }
    println!("checksum {}", sum);
}

fn bench_sieve() {
    const N: usize = 50_000_000;
    let mut sieve = vec![1u8; N];
    sieve[0] = 0;
    sieve[1] = 0;

    let mut i: usize = 2;
    while i * i < N {
        if sieve[i] == 1 {
            for j in (i * i..N).step_by(i) {
                sieve[j] = 0;
            }
        }
        i += 1;
    }

    let mut count: u64 = 0;
    for i in 0..N {
        count += sieve[i] as u64;
    }
    println!("checksum {}", count);
}

fn quicksort(arr: &mut [u64], lo: isize, hi: isize) {
    if lo >= hi {
        return;
    }
    let pivot = arr[((lo + hi) / 2) as usize];
    let (mut i, mut j) = (lo, hi);
    while i <= j {
        while arr[i as usize] < pivot {
            i += 1;
        }
        while arr[j as usize] > pivot {
            j -= 1;
        }
        if i <= j {
            arr.swap(i as usize, j as usize);
            i += 1;
            j -= 1;
        }
    }
    quicksort(arr, lo, j);
    quicksort(arr, i, hi);
}

fn bench_sort() {
    const N: usize = 3_000_000;
    let mut arr = vec![0u64; N];

    let mut state: u64 = 88172645463325252;
    for i in 0..N {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        arr[i] = state & 0x7FFFFFFFFFFFFFFF;
    }

    quicksort(&mut arr, 0, N as isize - 1);

    let mut cs: u64 = 0;
    for i in 0..N {
        cs = cs.wrapping_mul(1000003).wrapping_add(arr[i]);
    }
    println!("checksum {}", cs);
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

fn r_floor(y: f64) -> f64 {
    let f = (y as i64) as f64;
    if f > y {
        f - 1.0
    } else {
        f
    }
}

fn r_sin(mut x: f64) -> f64 {
    const TWO_PI: f64 = 6.283185307179586;
    let k = r_floor(x / TWO_PI + 0.5);
    x = x - k * TWO_PI;
    let x2 = x * x;
    let mut p = -1.0 / 1307674368000.0;
    p = 1.0 / 6227020800.0 + x2 * p;
    p = -1.0 / 39916800.0 + x2 * p;
    p = 1.0 / 362880.0 + x2 * p;
    p = -1.0 / 5040.0 + x2 * p;
    p = 1.0 / 120.0 + x2 * p;
    p = -1.0 / 6.0 + x2 * p;
    p = 1.0 + x2 * p;
    x * p
}

fn r_cos(x: f64) -> f64 {
    const HALF_PI: f64 = 1.5707963267948966;
    r_sin(x + HALF_PI)
}

fn edge(ax: f64, ay: f64, bx: f64, by: f64, cx: f64, cy: f64) -> f64 {
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

fn bench_raster() {
    const W: usize = 640;
    const H: usize = 480;
    const RINGS: usize = 24;
    const SECTORS: usize = 24;
    const FRAMES: usize = 240;
    const NV: usize = (RINGS + 1) * (SECTORS + 1);
    const FOCAL: f64 = 500.0;
    const CAM_DIST: f64 = 3.0;

    let (mut bx, mut by, mut bz) = (vec![0f64; NV], vec![0f64; NV], vec![0f64; NV]);
    let mut nv: usize = 0;
    for i in 0..=RINGS {
        let theta = 3.141592653589793 * (i as f64 / RINGS as f64);
        let st = r_sin(theta);
        let ct = r_cos(theta);
        for j in 0..=SECTORS {
            let phi = 6.283185307179586 * (j as f64 / SECTORS as f64);
            let sp = r_sin(phi);
            let cp = r_cos(phi);
            bx[nv] = st * cp;
            by[nv] = ct;
            bz[nv] = st * sp;
            nv += 1;
        }
    }

    let (mut sx, mut sy, mut sz, mut si) = (
        vec![0f64; NV],
        vec![0f64; NV],
        vec![0f64; NV],
        vec![0f64; NV],
    );

    let mut color = vec![0u8; W * H];
    let mut zbuf = vec![0f64; W * H];

    let mut checksum: u64 = 0;

    for f in 0..FRAMES {
        let ang = f as f64 * 0.0125;
        let cy = r_cos(ang);
        let syr = r_sin(ang);
        let axx = ang * 0.5;
        let cx = r_cos(axx);
        let sxr = r_sin(axx);

        for v in 0..nv {
            let (px0, py0, pz0) = (bx[v], by[v], bz[v]);
            let rx = px0 * cy + pz0 * syr;
            let rz = -px0 * syr + pz0 * cy;
            let ry = py0;
            let ry2 = ry * cx - rz * sxr;
            let rz2 = ry * sxr + rz * cx;
            let mut inten = -rz2;
            if inten < 0.0 {
                inten = 0.0;
            }
            let zc = rz2 + CAM_DIST;
            let invz = 1.0 / zc;
            sx[v] = rx * invz * FOCAL + W as f64 * 0.5;
            sy[v] = ry2 * invz * FOCAL + H as f64 * 0.5;
            sz[v] = zc;
            si[v] = inten;
        }

        for i in 0..W * H {
            color[i] = 0;
            zbuf[i] = 1.0e30;
        }

        for ri in 0..RINGS {
            for sj in 0..SECTORS {
                let a = ri * (SECTORS + 1) + sj;
                let b = a + (SECTORS + 1);
                let tris = [[a, b, a + 1], [a + 1, b, b + 1]];
                for t in 0..2 {
                    let (i0, i1, i2) = (tris[t][0], tris[t][1], tris[t][2]);
                    let area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2]);
                    if area <= 0.0 {
                        continue;
                    }
                    let mut mnx = sx[i0];
                    if sx[i1] < mnx {
                        mnx = sx[i1];
                    }
                    if sx[i2] < mnx {
                        mnx = sx[i2];
                    }
                    let mut mxx = sx[i0];
                    if sx[i1] > mxx {
                        mxx = sx[i1];
                    }
                    if sx[i2] > mxx {
                        mxx = sx[i2];
                    }
                    let mut mny = sy[i0];
                    if sy[i1] < mny {
                        mny = sy[i1];
                    }
                    if sy[i2] < mny {
                        mny = sy[i2];
                    }
                    let mut mxy = sy[i0];
                    if sy[i1] > mxy {
                        mxy = sy[i1];
                    }
                    if sy[i2] > mxy {
                        mxy = sy[i2];
                    }
                    if mnx < 0.0 {
                        mnx = 0.0;
                    }
                    if mxx > (W - 1) as f64 {
                        mxx = (W - 1) as f64;
                    }
                    if mny < 0.0 {
                        mny = 0.0;
                    }
                    if mxy > (H - 1) as f64 {
                        mxy = (H - 1) as f64;
                    }
                    let (x0, x1) = (mnx as usize, mxx as usize);
                    let (y0, y1) = (mny as usize, mxy as usize);
                    for py in y0..=y1 {
                        let pcy = py as f64 + 0.5;
                        for px in x0..=x1 {
                            let pcx = px as f64 + 0.5;
                            let w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
                            let w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
                            let w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
                            if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                                let (l0, l1, l2) = (w0 / area, w1 / area, w2 / area);
                                let depth = l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2];
                                let idx = py * W + px;
                                if depth < zbuf[idx] {
                                    zbuf[idx] = depth;
                                    let mut inten = l0 * si[i0] + l1 * si[i1] + l2 * si[i2];
                                    if inten < 0.0 {
                                        inten = 0.0;
                                    }
                                    if inten > 1.0 {
                                        inten = 1.0;
                                    }
                                    color[idx] = (inten * 255.0) as u8;
                                }
                            }
                        }
                    }
                }
            }
        }

        let mut frame_sum: u64 = 0;
        for i in 0..W * H {
            frame_sum = frame_sum.wrapping_add(color[i] as u64);
        }
        checksum = checksum.wrapping_mul(1000003).wrapping_add(frame_sum);
    }

    println!("checksum {}", checksum);
}

// --- pointer-chasing (random memory latency) --------------------------------
// Builds one big random permutation cycle, then chases next[p] for many hops.
// Each load depends on the previous one, so the prefetcher can't hide it: this
// measures memory *latency*, unlike the streaming `sieve`. Pure 32-bit integer.

fn bench_ptrchase() {
    const N: usize = 16000000;
    const HOPS: u64 = 4000000;
    let mut order = vec![0u32; N];
    let mut next = vec![0u32; N];
    for i in 0..N {
        order[i] = i as u32;
    }
    let mut x: u32 = 1;
    for i in (1..N).rev() {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        let j = ((x & 0x7FFFFFFF) % (i as u32 + 1)) as usize;
        order.swap(i, j);
    }
    for k in 0..N {
        next[order[k] as usize] = order[(k + 1) % N];
    }
    let (mut sum, mut p): (u32, u32) = (0, 0);
    for _ in 0..HOPS {
        p = next[p as usize];
        sum = sum.wrapping_add(p);
    }
    println!("checksum {}", sum);
}

// --- FNV-1a hash ------------------------------------------------------------
// Hashes a byte buffer several times with 32-bit FNV-1a. Stresses the integer
// ALU (xor + wrapping multiply) and a tight sequential read; no SIMD to exploit.

fn bench_hash() {
    const N: usize = 32000000;
    const R: usize = 4;
    let mut buf = vec![0u8; N];
    let mut x: u32 = 12345;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        buf[i] = (x & 0xFF) as u8;
    }
    let mut h: u32 = 2166136261;
    for _ in 0..R {
        for i in 0..N {
            h ^= buf[i] as u32;
            h = h.wrapping_mul(16777619);
        }
    }
    println!("checksum {}", h);
}

// --- binary search tree (heap allocation + pointer chasing) -----------------
// Inserts M keys into a BST (one heap allocation per node, branchy descent),
// then runs Q lookups. Measures allocator/GC throughput plus pointer-chasing
// reads. Keys stay below 2^31 so signed/unsigned ordering agree everywhere.

struct BstNode {
    key: u32,
    left: Option<Box<BstNode>>,
    right: Option<Box<BstNode>>,
}

fn bench_bst() {
    const M: usize = 1000000;
    const Q: usize = 1000000;
    let mut root: Option<Box<BstNode>> = None;
    let mut x: u32 = 22222;
    for _ in 0..M {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        let key = x & 0x7FFFFFFF;
        let mut cur = &mut root;
        loop {
            match cur {
                None => {
                    *cur = Some(Box::new(BstNode {
                        key,
                        left: None,
                        right: None,
                    }));
                    break;
                }
                Some(node) => {
                    cur = if key < node.key {
                        &mut node.left
                    } else {
                        &mut node.right
                    }
                }
            }
        }
    }
    let mut y: u32 = 99991;
    let mut cs: u32 = 0;
    for _ in 0..Q {
        y = y.wrapping_mul(1664525).wrapping_add(1013904223);
        let key = y & 0x7FFFFFFF;
        let mut steps: u32 = 0;
        let mut cur = &root;
        while let Some(node) = cur {
            steps = steps.wrapping_add(1);
            if key == node.key {
                break;
            }
            cur = if key < node.key {
                &node.left
            } else {
                &node.right
            };
        }
        cs = cs.wrapping_mul(1000003).wrapping_add(steps);
    }
    println!("checksum {}", cs);
}

// --- run-length encoding (branchy byte processing) --------------------------
// Builds a buffer of random runs, then RLE-encodes it several times, folding
// the (count,value) output into a 32-bit hash. Data-dependent branchy scan.

fn bench_rle() {
    const N: usize = 40000000;
    const R: usize = 4;
    let mut buf = vec![0u8; N];
    let mut out = vec![0u8; 2 * N];
    let mut x: u32 = 33333;
    let mut i: usize = 0;
    while i < N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        let v = (x & 0xFF) as u8;
        let rl = ((x & 0x7FFFFFFF) % 16) + 1;
        let mut c: u32 = 0;
        while c < rl && i < N {
            buf[i] = v;
            i += 1;
            c += 1;
        }
    }
    let mut h: u32 = 2166136261;
    for _ in 0..R {
        let (mut o, mut p): (usize, usize) = (0, 0);
        while p < N {
            let v = buf[p];
            let mut run: usize = 1;
            while p + run < N && buf[p + run] == v && run < 255 {
                run += 1;
            }
            out[o] = run as u8;
            out[o + 1] = v;
            o += 2;
            p += run;
        }
        for k in 0..o {
            h ^= out[k] as u32;
            h = h.wrapping_mul(16777619);
        }
        h ^= (o % 256) as u32;
        h = h.wrapping_mul(16777619);
        h ^= ((o / 256) % 256) as u32;
        h = h.wrapping_mul(16777619);
        h ^= ((o / 65536) % 256) as u32;
        h = h.wrapping_mul(16777619);
        h ^= ((o / 16777216) % 256) as u32;
        h = h.wrapping_mul(16777619);
    }
    println!("checksum {}", h);
}

// --- base64 encoding (table lookup + bit shuffling) -------------------------
// Base64-encodes a byte buffer several times, folding the output characters
// into a 32-bit hash. Uses division (not >>) so every language agrees bit for
// bit. Stresses byte-level bit manipulation and a small gather/table lookup.

const B64: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn bench_base64() {
    const N: usize = 24000000;
    const R: usize = 4;
    let mut buf = vec![0u8; N];
    let mut x: u32 = 44444;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        buf[i] = (x & 0xFF) as u8;
    }
    let mut h: u32 = 2166136261;
    for _ in 0..R {
        for i in (0..N - 2).step_by(3) {
            let b0 = buf[i] as u32;
            let b1 = buf[i + 1] as u32;
            let b2 = buf[i + 2] as u32;
            let i0 = b0 / 4;
            let i1 = (b0 & 3) * 16 + b1 / 16;
            let i2 = (b1 & 15) * 4 + b2 / 64;
            let i3 = b2 & 63;
            h ^= B64[i0 as usize] as u32;
            h = h.wrapping_mul(16777619);
            h ^= B64[i1 as usize] as u32;
            h = h.wrapping_mul(16777619);
            h ^= B64[i2 as usize] as u32;
            h = h.wrapping_mul(16777619);
            h ^= B64[i3 as usize] as u32;
            h = h.wrapping_mul(16777619);
        }
    }
    println!("checksum {}", h);
}

// --- indirect dispatch ------------------------------------------------------
// Applies a stream of ops to an accumulator through a function-pointer table,
// one indirect call per element. Stresses indirect-branch prediction. All ops
// are 32-bit wrapping + ^ * - so the result is identical across languages.

fn op_add(a: u32, b: u32) -> u32 {
    a.wrapping_add(b)
}
fn op_xor(a: u32, b: u32) -> u32 {
    a ^ b
}
fn op_mul(a: u32, b: u32) -> u32 {
    a.wrapping_mul(b | 1)
}
fn op_sub(a: u32, b: u32) -> u32 {
    a.wrapping_sub(b)
}

fn bench_dispatch() {
    const N: usize = 4000000;
    const R: usize = 32;
    let mut code = vec![0u8; N];
    let mut operand = vec![0u32; N];
    let mut x: u32 = 55555;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        code[i] = ((x & 0x7FFFFFFF) % 4) as u8;
        operand[i] = x;
    }
    let fns: [fn(u32, u32) -> u32; 4] = [op_add, op_xor, op_mul, op_sub];
    let mut acc: u32 = 2166136261;
    for _ in 0..R {
        for i in 0..N {
            acc = fns[code[i] as usize](acc, operand[i]);
        }
    }
    println!("checksum {}", acc);
}

fn bench_collatz() {
    const N: u64 = 3_000_000;
    let mut total: u64 = 0;
    for i in 1..=N {
        let (mut n, mut steps): (u64, u64) = (i, 0);
        while n != 1 {
            n = if n % 2 == 0 { n / 2 } else { 3 * n + 1 };
            steps += 1;
        }
        total = total.wrapping_add(steps);
    }
    println!("checksum {}", total);
}

// --- n-body (dependent floating-point chains) -------------------------------
// All-pairs gravitational n-body. Each interaction needs 1/dist^3, so it leans
// on a hand-rolled Newton-iteration sqrt (8 fixed iterations from g0=(d2+1)/2,
// which is >= sqrt(d2) by AM-GM, so it converges monotonically). Only +,-,*,/
// so every language is bit-identical; the dependent Newton chain stresses FP
// latency, unlike mandelbrot/raster which are FP throughput.
fn bench_nbody() {
    const N: usize = 2048;
    const STEPS: usize = 8;
    const DT: f64 = 0.01;
    const EPS: f64 = 0.05;
    let mut px = vec![0.0f64; N];
    let mut py = vec![0.0f64; N];
    let mut pz = vec![0.0f64; N];
    let mut vx = vec![0.0f64; N];
    let mut vy = vec![0.0f64; N];
    let mut vz = vec![0.0f64; N];
    let mut m = vec![0.0f64; N];
    let mut s: u32 = 7777;
    for i in 0..N {
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        px[i] = ((s & 0xFFFF) as f64 / 65536.0) * 2.0 - 1.0;
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        py[i] = ((s & 0xFFFF) as f64 / 65536.0) * 2.0 - 1.0;
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        pz[i] = ((s & 0xFFFF) as f64 / 65536.0) * 2.0 - 1.0;
        s = s.wrapping_mul(1664525).wrapping_add(1013904223);
        m[i] = (s & 0xFFFF) as f64 / 65536.0 + 0.1;
    }
    for _ in 0..STEPS {
        for i in 0..N {
            let (mut ax, mut ay, mut az) = (0.0f64, 0.0f64, 0.0f64);
            let (xi, yi, zi) = (px[i], py[i], pz[i]);
            for j in 0..N {
                if j == i {
                    continue;
                }
                let dx = px[j] - xi;
                let dy = py[j] - yi;
                let dz = pz[j] - zi;
                let d2 = dx * dx + dy * dy + dz * dz + EPS;
                let mut g = (d2 + 1.0) * 0.5;
                for _ in 0..8 {
                    g = (g + d2 / g) * 0.5;
                }
                let inv3 = 1.0 / (d2 * g);
                let f = m[j] * inv3;
                ax += dx * f;
                ay += dy * f;
                az += dz * f;
            }
            vx[i] += ax * DT;
            vy[i] += ay * DT;
            vz[i] += az * DT;
        }
        for i in 0..N {
            px[i] += vx[i] * DT;
            py[i] += vy[i] * DT;
            pz[i] += vz[i] * DT;
        }
    }
    let mut cs: u32 = 0;
    for i in 0..N {
        cs = cs
            .wrapping_mul(1000003)
            .wrapping_add((px[i] * 1024.0) as i64 as u32);
        cs = cs
            .wrapping_mul(1000003)
            .wrapping_add((py[i] * 1024.0) as i64 as u32);
        cs = cs
            .wrapping_mul(1000003)
            .wrapping_add((pz[i] * 1024.0) as i64 as u32);
    }
    println!("checksum {}", cs);
}

// --- STREAM triad (memory write bandwidth) ----------------------------------
// a[i] = b[i] + k*c[i] over big arrays, repeated. Complements sieve (streaming
// reads) and ptrchase (latency) by stressing sustained writes. 32-bit wrapping.
fn bench_stream() {
    const N: usize = 16000000;
    const R: usize = 40;
    const K: u32 = 3;
    let mut a = vec![0u32; N];
    let mut b = vec![0u32; N];
    let mut c = vec![0u32; N];
    let mut x: u32 = 11111;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        b[i] = x;
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        c[i] = x;
    }
    for _ in 0..R {
        for i in 0..N {
            a[i] = b[i].wrapping_add(K.wrapping_mul(c[i]));
        }
    }
    let mut cs: u32 = 0;
    for i in 0..N {
        cs = cs.wrapping_mul(1000003).wrapping_add(a[i]);
    }
    println!("checksum {}", cs);
}

// --- N-queens (backtracking recursion) --------------------------------------
// Counts solutions to the N-queens problem with the classic bitmask solver.
// Combines deep recursion (like fib) with unpredictable pruning branches (like
// collatz). Pure integer; checksum is the solution count.
fn nq_solve(cols: u32, d1: u32, d2: u32, full: u32) -> u64 {
    if cols == full {
        return 1;
    }
    let mut count: u64 = 0;
    let mut avail = !(cols | d1 | d2) & full;
    while avail != 0 {
        let bit = avail & avail.wrapping_neg();
        avail -= bit;
        count += nq_solve(cols | bit, (d1 | bit).wrapping_mul(2) & full, (d2 | bit) / 2, full);
    }
    count
}

fn bench_nqueens() {
    const NQ: u32 = 14;
    let full = (1u32 << NQ) - 1;
    let total = nq_solve(0, 0, 0, full);
    println!("checksum {}", total);
}

// --- Conway's Game of Life (2D stencil + branches) --------------------------
// Steps a toroidal WxH grid through T generations, summing 8 wrapped neighbours
// per cell. A stencil/neighbour memory pattern none of the other benchmarks
// cover. Integer grid -> bit-identical.
fn bench_life() {
    const W: usize = 1024;
    const H: usize = 1024;
    const T: usize = 300;
    let mut cur = vec![0u8; W * H];
    let mut nxt = vec![0u8; W * H];
    let mut x: u32 = 22221;
    for i in 0..W * H {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        cur[i] = ((x / 65536) & 1) as u8;
    }
    for _ in 0..T {
        for y in 0..H {
            let ym = if y == 0 { H - 1 } else { y - 1 };
            let yp = if y == H - 1 { 0 } else { y + 1 };
            for xx in 0..W {
                let xm = if xx == 0 { W - 1 } else { xx - 1 };
                let xp = if xx == W - 1 { 0 } else { xx + 1 };
                let n = cur[ym * W + xm] as i32
                    + cur[ym * W + xx] as i32
                    + cur[ym * W + xp] as i32
                    + cur[y * W + xm] as i32
                    + cur[y * W + xp] as i32
                    + cur[yp * W + xm] as i32
                    + cur[yp * W + xx] as i32
                    + cur[yp * W + xp] as i32;
                let alive = cur[y * W + xx];
                nxt[y * W + xx] = if n == 3 || (alive == 1 && n == 2) { 1 } else { 0 };
            }
        }
        std::mem::swap(&mut cur, &mut nxt);
    }
    let mut cs: u32 = 0;
    for i in 0..W * H {
        cs = cs.wrapping_mul(1000003).wrapping_add(cur[i] as u32);
    }
    println!("checksum {}", cs);
}

// --- open-addressing hash map (linear probing) ------------------------------
// Inserts M keys into a power-of-two table with linear probing (summing values
// on duplicate keys), then runs Q lookups. Exercises the probe-sequence access
// pattern real hash maps use, distinct from bst's pointer chasing.
fn bench_hashmap() {
    const M: usize = 8000000;
    const Q: usize = 16000000;
    const SIZE: u32 = 1 << 24;
    const MASK: u32 = SIZE - 1;
    let mut keys = vec![0u32; SIZE as usize];
    let mut vals = vec![0u32; SIZE as usize];
    let mut x: u32 = 33331;
    for _ in 0..M {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        let key = (x & 0x7FFFFFFF) | 1;
        let mut idx = key & MASK;
        loop {
            if keys[idx as usize] == 0 {
                keys[idx as usize] = key;
                vals[idx as usize] = x;
                break;
            }
            if keys[idx as usize] == key {
                vals[idx as usize] = vals[idx as usize].wrapping_add(x);
                break;
            }
            idx = (idx + 1) & MASK;
        }
    }
    let mut y: u32 = 99989;
    let mut acc: u32 = 0;
    for _ in 0..Q {
        y = y.wrapping_mul(1664525).wrapping_add(1013904223);
        let key = (y & 0x7FFFFFFF) | 1;
        let mut idx = key & MASK;
        let mut steps: u32 = 0;
        loop {
            steps += 1;
            if keys[idx as usize] == 0 {
                break;
            }
            if keys[idx as usize] == key {
                acc = acc.wrapping_add(vals[idx as usize]);
                break;
            }
            idx = (idx + 1) & MASK;
        }
        acc = acc.wrapping_mul(1000003).wrapping_add(steps);
    }
    println!("checksum {}", acc);
}

// --- SHA-256 (32-bit crypto mixing) -----------------------------------------
// Hashes a byte buffer in 64-byte blocks with the full SHA-256 compression.
// Heavy 32-bit rotate/shift/xor/add ALU work; bit-identical by spec. A "real"
// hash next to FNV (hash) and CRC32 (crc32).
const SHA_K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn bench_sha256() {
    const N: usize = 4000000;
    const R: usize = 16;
    let mut buf = vec![0u8; N];
    let mut x: u32 = 44441;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        buf[i] = ((x / 256) & 0xFF) as u8;
    }
    let mut cs: u32 = 0;
    for _ in 0..R {
        let mut h0: u32 = 0x6a09e667;
        let mut h1: u32 = 0xbb67ae85;
        let mut h2: u32 = 0x3c6ef372;
        let mut h3: u32 = 0xa54ff53a;
        let mut h4: u32 = 0x510e527f;
        let mut h5: u32 = 0x9b05688c;
        let mut h6: u32 = 0x1f83d9ab;
        let mut h7: u32 = 0x5be0cd19;
        let nblocks = N / 64;
        let mut w = [0u32; 64];
        for blk in 0..nblocks {
            let base = blk * 64;
            for t in 0..16 {
                let o = base + t * 4;
                w[t] = (buf[o] as u32) << 24
                    | (buf[o + 1] as u32) << 16
                    | (buf[o + 2] as u32) << 8
                    | (buf[o + 3] as u32);
            }
            for t in 16..64 {
                let s0 = w[t - 15].rotate_right(7) ^ w[t - 15].rotate_right(18) ^ (w[t - 15] >> 3);
                let s1 = w[t - 2].rotate_right(17) ^ w[t - 2].rotate_right(19) ^ (w[t - 2] >> 10);
                w[t] = w[t - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[t - 7])
                    .wrapping_add(s1);
            }
            let (mut a, mut b, mut c, mut d) = (h0, h1, h2, h3);
            let (mut e, mut f, mut g, mut hh) = (h4, h5, h6, h7);
            for t in 0..64 {
                let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
                let ch = (e & f) ^ ((!e) & g);
                let t1 = hh
                    .wrapping_add(s1)
                    .wrapping_add(ch)
                    .wrapping_add(SHA_K[t])
                    .wrapping_add(w[t]);
                let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
                let maj = (a & b) ^ (a & c) ^ (b & c);
                let t2 = s0.wrapping_add(maj);
                hh = g;
                g = f;
                f = e;
                e = d.wrapping_add(t1);
                d = c;
                c = b;
                b = a;
                a = t1.wrapping_add(t2);
            }
            h0 = h0.wrapping_add(a);
            h1 = h1.wrapping_add(b);
            h2 = h2.wrapping_add(c);
            h3 = h3.wrapping_add(d);
            h4 = h4.wrapping_add(e);
            h5 = h5.wrapping_add(f);
            h6 = h6.wrapping_add(g);
            h7 = h7.wrapping_add(hh);
        }
        cs = cs
            .wrapping_mul(1000003)
            .wrapping_add(h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7);
    }
    println!("checksum {}", cs);
}

// --- matrix transpose (cache stride / TLB) ----------------------------------
// Naive out-of-place transpose of a big NxN matrix, repeated with src/dst
// swapped. The column-strided writes thrash cache and TLB, complementing
// matmul's dense compute. 32-bit folded in linear order so layout matters.
fn bench_transpose() {
    const NDIM: usize = 4096;
    const R: usize = 6;
    let mut src = vec![0u32; NDIM * NDIM];
    let mut dst = vec![0u32; NDIM * NDIM];
    let mut x: u32 = 55551;
    for i in 0..NDIM * NDIM {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        src[i] = x;
    }
    for _ in 0..R {
        for i in 0..NDIM {
            for j in 0..NDIM {
                dst[j * NDIM + i] = src[i * NDIM + j];
            }
        }
        std::mem::swap(&mut src, &mut dst);
    }
    let mut cs: u32 = 0;
    for i in 0..NDIM * NDIM {
        cs = cs.wrapping_mul(1000003).wrapping_add(src[i]);
    }
    println!("checksum {}", cs);
}

// --- edit distance (dynamic programming) ------------------------------------
// Levenshtein distance between two pseudo-random small-alphabet strings via the
// classic two-row DP. A data-dependent min-of-three table fill; no other
// benchmark exercises 2D dynamic programming. Checksum is the distance.
fn edit_min3(a: i32, b: i32, c: i32) -> i32 {
    let m = if a < b { a } else { b };
    if m < c {
        m
    } else {
        c
    }
}

fn bench_editdist() {
    const LA: usize = 16000;
    const LB: usize = 16000;
    let mut a = vec![0u8; LA];
    let mut b = vec![0u8; LB];
    let mut x: u32 = 66661;
    for i in 0..LA {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        a[i] = ((x / 65536) % 4) as u8;
    }
    for i in 0..LB {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        b[i] = ((x / 65536) % 4) as u8;
    }
    let mut prev = vec![0i32; LB + 1];
    let mut cur = vec![0i32; LB + 1];
    for j in 0..=LB {
        prev[j] = j as i32;
    }
    for i in 1..=LA {
        cur[0] = i as i32;
        for j in 1..=LB {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            cur[j] = edit_min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    println!("checksum {}", prev[LB] as u32);
}

// --- LZ77 greedy compressor (branchy match search) --------------------------
// Greedily matches each position against a sliding window, emitting (offset,
// length) tokens or literals folded into an FNV hash. The nested longest-match
// scan is branchy and memory-bound, a heavier cousin of rle.
fn bench_lz() {
    const N: usize = 4000000;
    const WIN: usize = 512;
    const MAXLEN: usize = 64;
    let mut buf = vec![0u8; N];
    let mut x: u32 = 77771;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        buf[i] = ((x / 65536) % 8) as u8;
    }
    let mut h: u32 = 2166136261;
    let mut p = 0usize;
    while p < N {
        let lo = if p > WIN { p - WIN } else { 0 };
        let mut bestlen = 0usize;
        let mut bestoff = 0usize;
        for sidx in lo..p {
            let mut len = 0usize;
            while p + len < N && len < MAXLEN && buf[sidx + len] == buf[p + len] {
                len += 1;
            }
            if len > bestlen {
                bestlen = len;
                bestoff = p - sidx;
            }
        }
        if bestlen >= 3 {
            h ^= (bestoff & 0xFF) as u32;
            h = h.wrapping_mul(16777619);
            h ^= ((bestoff / 256) & 0xFF) as u32;
            h = h.wrapping_mul(16777619);
            h ^= (bestlen & 0xFF) as u32;
            h = h.wrapping_mul(16777619);
            p += bestlen;
        } else {
            h ^= buf[p] as u32;
            h = h.wrapping_mul(16777619);
            p += 1;
        }
    }
    println!("checksum {}", h);
}

// --- CRC32 (table-driven hashing) -------------------------------------------
// Builds the standard CRC32 table (poly 0xEDB88320) then CRCs a byte buffer
// several times. Table-lookup gather plus shift/xor, distinct from FNV's pure
// ALU and SHA's wide mixing.
fn bench_crc32() {
    const N: usize = 16000000;
    const R: usize = 8;
    let mut table = [0u32; 256];
    for i in 0..256u32 {
        let mut c = i;
        for _ in 0..8 {
            c = if c & 1 == 1 { 0xEDB88320 ^ (c >> 1) } else { c >> 1 };
        }
        table[i as usize] = c;
    }
    let mut buf = vec![0u8; N];
    let mut x: u32 = 88881;
    for i in 0..N {
        x = x.wrapping_mul(1664525).wrapping_add(1013904223);
        buf[i] = ((x / 65536) & 0xFF) as u8;
    }
    let mut cs: u32 = 0;
    for _ in 0..R {
        let mut crc: u32 = 0xFFFFFFFF;
        for i in 0..N {
            crc = table[((crc ^ buf[i] as u32) & 0xFF) as usize] ^ (crc >> 8);
        }
        crc ^= 0xFFFFFFFF;
        cs = cs.wrapping_mul(1000003).wrapping_add(crc);
    }
    println!("checksum {}", cs);
}

fn main() {
    let Some(name) = env::args().nth(1) else {
        println!("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>");
        return;
    };
    match name.as_str() {
        "fib" => bench_fib(),
        "mandelbrot" => bench_mandelbrot(),
        "matmul" => bench_matmul(),
        "sieve" => bench_sieve(),
        "sort" => bench_sort(),
        "collatz" => bench_collatz(),
        "raster" => bench_raster(),
        "ptrchase" => bench_ptrchase(),
        "hash" => bench_hash(),
        "bst" => bench_bst(),
        "rle" => bench_rle(),
        "base64" => bench_base64(),
        "dispatch" => bench_dispatch(),
        "nbody" => bench_nbody(),
        "stream" => bench_stream(),
        "nqueens" => bench_nqueens(),
        "life" => bench_life(),
        "hashmap" => bench_hashmap(),
        "sha256" => bench_sha256(),
        "transpose" => bench_transpose(),
        "editdist" => bench_editdist(),
        "lz" => bench_lz(),
        "crc32" => bench_crc32(),
        _ => println!("unknown benchmark: {}", name),
    }
}
