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
    let mut n: u64 = 30;
    while n <= 42 {
        total = total.wrapping_add(fib(n));
        n += 1;
    }
    println!("checksum {}", total);
}

fn bench_mandelbrot() {
    const W: usize = 1200;
    const H: usize = 1200;
    const MAX_IT: u64 = 1000;
    let mut sum: u64 = 0;
    let mut py: usize = 0;
    while py < H {
        let y0 = (py as f64 / H as f64) * 4.0 - 2.0;
        let mut px: usize = 0;
        while px < W {
            let x0 = (px as f64 / W as f64) * 4.0 - 2.5;
            let mut x: f64 = 0.0;
            let mut y: f64 = 0.0;
            let mut it: u64 = 0;
            while x * x + y * y <= 4.0 && it < MAX_IT {
                let xt = x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
                it += 1;
            }
            sum = sum.wrapping_add(it);
            px += 1;
        }
        py += 1;
    }
    println!("checksum {}", sum);
}

fn bench_matmul() {
    const N: usize = 512;
    let mut a = vec![0i64; N * N];
    let mut b = vec![0i64; N * N];
    let mut c = vec![0i64; N * N];

    let mut i: usize = 0;
    while i < N {
        let mut j: usize = 0;
        while j < N {
            a[i * N + j] = ((i * j) % 7) as i64 - 3;
            b[i * N + j] = ((i + j) % 5) as i64 - 2;
            c[i * N + j] = 0;
            j += 1;
        }
        i += 1;
    }

    i = 0;
    while i < N {
        let mut k: usize = 0;
        while k < N {
            let aik = a[i * N + k];
            let mut j: usize = 0;
            while j < N {
                c[i * N + j] += aik * b[k * N + j];
                j += 1;
            }
            k += 1;
        }
        i += 1;
    }

    let mut sum: i64 = 0;
    i = 0;
    while i < N * N {
        sum = sum.wrapping_add(c[i]);
        i += 1;
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
            let mut j: usize = i * i;
            while j < N {
                sieve[j] = 0;
                j += i;
            }
        }
        i += 1;
    }

    let mut count: u64 = 0;
    i = 0;
    while i < N {
        count += sieve[i] as u64;
        i += 1;
    }
    println!("checksum {}", count);
}

fn quicksort(arr: &mut [u64], lo: isize, hi: isize) {
    if lo >= hi {
        return;
    }
    let pivot = arr[((lo + hi) / 2) as usize];
    let mut i = lo;
    let mut j = hi;
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
    let mut i: usize = 0;
    while i < N {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        arr[i] = state & 0x7FFFFFFFFFFFFFFF;
        i += 1;
    }

    quicksort(&mut arr, 0, N as isize - 1);

    let mut cs: u64 = 0;
    i = 0;
    while i < N {
        cs = cs.wrapping_mul(1000003).wrapping_add(arr[i]);
        i += 1;
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

    let mut bx = vec![0f64; NV];
    let mut by = vec![0f64; NV];
    let mut bz = vec![0f64; NV];
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

    let mut sx = vec![0f64; NV];
    let mut sy = vec![0f64; NV];
    let mut sz = vec![0f64; NV];
    let mut si = vec![0f64; NV];

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
            let px0 = bx[v];
            let py0 = by[v];
            let pz0 = bz[v];
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
                    let i0 = tris[t][0];
                    let i1 = tris[t][1];
                    let i2 = tris[t][2];
                    let area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2]);
                    if area <= 0.0 {
                        continue;
                    }
                    let mut mnx = sx[i0];
                    if sx[i1] < mnx { mnx = sx[i1]; }
                    if sx[i2] < mnx { mnx = sx[i2]; }
                    let mut mxx = sx[i0];
                    if sx[i1] > mxx { mxx = sx[i1]; }
                    if sx[i2] > mxx { mxx = sx[i2]; }
                    let mut mny = sy[i0];
                    if sy[i1] < mny { mny = sy[i1]; }
                    if sy[i2] < mny { mny = sy[i2]; }
                    let mut mxy = sy[i0];
                    if sy[i1] > mxy { mxy = sy[i1]; }
                    if sy[i2] > mxy { mxy = sy[i2]; }
                    if mnx < 0.0 { mnx = 0.0; }
                    if mxx > (W - 1) as f64 { mxx = (W - 1) as f64; }
                    if mny < 0.0 { mny = 0.0; }
                    if mxy > (H - 1) as f64 { mxy = (H - 1) as f64; }
                    let x0 = mnx as usize;
                    let x1 = mxx as usize;
                    let y0 = mny as usize;
                    let y1 = mxy as usize;
                    let mut py = y0;
                    while py <= y1 {
                        let pcy = py as f64 + 0.5;
                        let mut px = x0;
                        while px <= x1 {
                            let pcx = px as f64 + 0.5;
                            let w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
                            let w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
                            let w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
                            if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                                let l0 = w0 / area;
                                let l1 = w1 / area;
                                let l2 = w2 / area;
                                let depth = l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2];
                                let idx = py * W + px;
                                if depth < zbuf[idx] {
                                    zbuf[idx] = depth;
                                    let mut inten = l0 * si[i0] + l1 * si[i1] + l2 * si[i2];
                                    if inten < 0.0 { inten = 0.0; }
                                    if inten > 1.0 { inten = 1.0; }
                                    color[idx] = (inten * 255.0) as u8;
                                }
                            }
                            px += 1;
                        }
                        py += 1;
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

fn bench_collatz() {
    const N: u64 = 3_000_000;
    let mut total: u64 = 0;
    let mut i: u64 = 1;
    while i <= N {
        let mut n: u64 = i;
        let mut steps: u64 = 0;
        while n != 1 {
            if n % 2 == 0 {
                n = n / 2;
            } else {
                n = 3 * n + 1;
            }
            steps += 1;
        }
        total = total.wrapping_add(steps);
        i += 1;
    }
    println!("checksum {}", total);
}

fn main() {
    let name = match env::args().nth(1) {
        Some(n) => n,
        None => {
            println!("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>");
            return;
        }
    };
    match name.as_str() {
        "fib" => bench_fib(),
        "mandelbrot" => bench_mandelbrot(),
        "matmul" => bench_matmul(),
        "sieve" => bench_sieve(),
        "sort" => bench_sort(),
        "collatz" => bench_collatz(),
        "raster" => bench_raster(),
        _ => println!("unknown benchmark: {}", name),
    }
}
