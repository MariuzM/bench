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

fn main() {
    let Some(name) = env::args().nth(1) else {
        println!("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch>");
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
        _ => println!("unknown benchmark: {}", name),
    }
}
