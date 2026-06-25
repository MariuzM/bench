#import "Basic";

// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by the
// command-line argument, so the build script can measure each one's wall-time
// and peak memory in isolation. Every benchmark prints a single "checksum <n>"
// line; all seven language builds must agree on it, which proves they all did
// the same work.
// ---------------------------------------------------------------------------

fib :: (n: u64) -> u64 {
    if n < 2 return n;
    return fib(n - 1) + fib(n - 2);
}

bench_fib :: () {
    total: u64 = 0;
    n: u64 = 30;
    while n <= 42 {
        total += fib(n);
        n += 1;
    }
    print("checksum %\n", total);
}

bench_mandelbrot :: () {
    W :: 1200;
    H :: 1200;
    MAX_IT: u64 : 1000;
    sum: u64 = 0;
    for py: 0..H-1 {
        y0 := (cast(float64) py / cast(float64) H) * 4.0 - 2.0;
        for px: 0..W-1 {
            x0 := (cast(float64) px / cast(float64) W) * 4.0 - 2.5;
            x: float64 = 0;
            y: float64 = 0;
            it: u64 = 0;
            while x * x + y * y <= 4.0 && it < MAX_IT {
                xt := x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
                it += 1;
            }
            sum += it;
        }
    }
    print("checksum %\n", sum);
}

bench_matmul :: () {
    N :: 512;
    a := NewArray(N * N, s64);
    b := NewArray(N * N, s64);
    c := NewArray(N * N, s64);

    for i: 0..N-1 {
        for j: 0..N-1 {
            a[i * N + j] = cast(s64)((i * j) % 7) - 3;
            b[i * N + j] = cast(s64)((i + j) % 5) - 2;
            c[i * N + j] = 0;
        }
    }

    for i: 0..N-1 {
        for k: 0..N-1 {
            aik := a[i * N + k];
            for j: 0..N-1 {
                c[i * N + j] += aik * b[k * N + j];
            }
        }
    }

    sum: s64 = 0;
    for i: 0..N*N-1  sum += c[i];
    print("checksum %\n", sum);
}

bench_sieve :: () {
    N :: 50_000_000;
    // 0 means prime, 1 means composite (NewArray zero-inits, so all prime).
    sieve := NewArray(N, u8);

    i := 2;
    while i * i < N {
        if sieve[i] == 0 {
            j := i * i;
            while j < N {
                sieve[j] = 1;
                j += i;
            }
        }
        i += 1;
    }

    count: u64 = 0;
    for k: 2..N-1  if sieve[k] == 0  count += 1;
    print("checksum %\n", count);
}

quicksort :: (arr: [] u64, lo: s64, hi: s64) {
    if lo >= hi return;
    pivot := arr[(lo + hi) / 2];
    i, j := lo, hi;
    while i <= j {
        while arr[i] < pivot  i += 1;
        while arr[j] > pivot  j -= 1;
        if i <= j {
            t := arr[i];
            arr[i] = arr[j];
            arr[j] = t;
            i += 1;
            j -= 1;
        }
    }
    quicksort(arr, lo, j);
    quicksort(arr, i, hi);
}

bench_sort :: () {
    N :: 3_000_000;
    arr := NewArray(N, u64);

    state: u64 = 88172645463325252;
    for i: 0..N-1 {
        // Linear congruential generator (multiply + add only). All seven
        // languages use the same LCG and mask off the top bit so the keys stay
        // below 2^63, which keeps the generated stream bit-identical across
        // every backend.
        state = state * 6364136223846793005 + 1442695040888963407;
        arr[i] = state & 9223372036854775807;
    }

    quicksort(arr, 0, N - 1);

    cs: u64 = 0;
    for i: 0..N-1 {
        cs = cs * 1000003 + arr[i];
    }
    print("checksum %\n", cs);
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

r_floor :: (y: float64) -> float64 {
    f := cast(float64)(cast(s64) y);
    if f > y return f - 1.0;
    return f;
}

r_sin :: (xin: float64) -> float64 {
    TWO_PI : float64 : 6.283185307179586;
    k := r_floor(xin / TWO_PI + 0.5);
    x := xin - k * TWO_PI;
    x2 := x * x;
    p := -1.0 / 1307674368000.0;
    p = 1.0 / 6227020800.0 + x2 * p;
    p = -1.0 / 39916800.0 + x2 * p;
    p = 1.0 / 362880.0 + x2 * p;
    p = -1.0 / 5040.0 + x2 * p;
    p = 1.0 / 120.0 + x2 * p;
    p = -1.0 / 6.0 + x2 * p;
    p = 1.0 + x2 * p;
    return x * p;
}

r_cos :: (x: float64) -> float64 {
    HALF_PI : float64 : 1.5707963267948966;
    return r_sin(x + HALF_PI);
}

edge :: (ax: float64, ay: float64, bx: float64, by: float64, cx: float64, cy: float64) -> float64 {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

bench_raster :: () {
    W :: 640;
    H :: 480;
    RINGS :: 24;
    SECTORS :: 24;
    FRAMES :: 240;
    NV :: RINGS * SECTORS + RINGS + SECTORS + 1;
    FOCAL :: 500.0;
    CAM_DIST :: 3.0;

    bx: [NV] float64;
    by: [NV] float64;
    bz: [NV] float64;
    nv := 0;
    for i: 0..RINGS {
        theta := 3.141592653589793 * (cast(float64) i / cast(float64) RINGS);
        st := r_sin(theta);
        ct := r_cos(theta);
        for j: 0..SECTORS {
            phi := 6.283185307179586 * (cast(float64) j / cast(float64) SECTORS);
            sp := r_sin(phi);
            cp := r_cos(phi);
            bx[nv] = st * cp;
            by[nv] = ct;
            bz[nv] = st * sp;
            nv += 1;
        }
    }

    sx: [NV] float64;
    sy: [NV] float64;
    sz: [NV] float64;
    si: [NV] float64;

    color := NewArray(W * H, u8);
    zbuf := NewArray(W * H, float64);

    checksum: u64 = 0;

    for f: 0..FRAMES-1 {
        ang := cast(float64) f * 0.0125;
        cy := r_cos(ang);
        syr := r_sin(ang);
        axx := ang * 0.5;
        cx := r_cos(axx);
        sxr := r_sin(axx);

        for v: 0..nv-1 {
            px0, py0, pz0 := bx[v], by[v], bz[v];
            rx := px0 * cy + pz0 * syr;
            rz := -px0 * syr + pz0 * cy;
            ry := py0;
            ry2 := ry * cx - rz * sxr;
            rz2 := ry * sxr + rz * cx;
            inten := -rz2;
            if inten < 0.0  inten = 0.0;
            zc := rz2 + CAM_DIST;
            invz := 1.0 / zc;
            sx[v] = rx * invz * FOCAL + cast(float64) W * 0.5;
            sy[v] = ry2 * invz * FOCAL + cast(float64) H * 0.5;
            sz[v] = zc;
            si[v] = inten;
        }

        for c: 0..W*H-1 { color[c] = 0; zbuf[c] = 1.0e30; }

        for ri: 0..RINGS-1 {
            for sj: 0..SECTORS-1 {
                a := ri * (SECTORS + 1) + sj;
                b := a + (SECTORS + 1);
                for t: 0..1 {
                    i0, i1, i2: s64;
                    if t == 0 { i0 = a; i1 = b; i2 = a + 1; }
                    else      { i0 = a + 1; i1 = b; i2 = b + 1; }
                    area := edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2]);
                    if area <= 0.0  continue;
                    mnx := sx[i0];
                    if sx[i1] < mnx  mnx = sx[i1];
                    if sx[i2] < mnx  mnx = sx[i2];
                    mxx := sx[i0];
                    if sx[i1] > mxx  mxx = sx[i1];
                    if sx[i2] > mxx  mxx = sx[i2];
                    mny := sy[i0];
                    if sy[i1] < mny  mny = sy[i1];
                    if sy[i2] < mny  mny = sy[i2];
                    mxy := sy[i0];
                    if sy[i1] > mxy  mxy = sy[i1];
                    if sy[i2] > mxy  mxy = sy[i2];
                    if mnx < 0.0  mnx = 0.0;
                    if mxx > cast(float64)(W - 1)  mxx = cast(float64)(W - 1);
                    if mny < 0.0  mny = 0.0;
                    if mxy > cast(float64)(H - 1)  mxy = cast(float64)(H - 1);
                    x0, x1, y0, y1 := cast(s64) mnx, cast(s64) mxx, cast(s64) mny, cast(s64) mxy;
                    for py: y0..y1 {
                        pcy := cast(float64) py + 0.5;
                        for px: x0..x1 {
                            pcx := cast(float64) px + 0.5;
                            w0 := edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
                            w1 := edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
                            w2 := edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
                            if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                                l0, l1, l2 := w0 / area, w1 / area, w2 / area;
                                depth := l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2];
                                idx := py * W + px;
                                if depth < zbuf[idx] {
                                    zbuf[idx] = depth;
                                    inten := l0 * si[i0] + l1 * si[i1] + l2 * si[i2];
                                    if inten < 0.0  inten = 0.0;
                                    if inten > 1.0  inten = 1.0;
                                    color[idx] = cast(u8)(cast(s64)(inten * 255.0));
                                }
                            }
                        }
                    }
                }
            }
        }

        frame_sum: u64 = 0;
        for c: 0..W*H-1  frame_sum += cast(u64) color[c];
        checksum = checksum * 1000003 + frame_sum;
    }

    print("checksum %\n", checksum);
}

// --- pointer-chasing (random memory latency) --------------------------------

bench_ptrchase :: () {
    N :: 16000000;
    HOPS :: 4000000;
    order := NewArray(N, u32);
    next := NewArray(N, u32);
    for i: 0..N-1  order[i] = cast(u32) i;
    x: u64 = 1;
    i := N - 1;
    while i >= 1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        j := cast(s64)((x & 0x7FFFFFFF) % cast(u64)(i + 1));
        t := order[i];
        order[i] = order[j];
        order[j] = t;
        i -= 1;
    }
    for k: 0..N-1  next[cast(s64) order[k]] = order[(k + 1) % N];
    sum: u64 = 0;
    p: s64 = 0;
    for 0..HOPS-1 {
        p = cast(s64) next[p];
        sum = (sum + cast(u64) p) & 0xFFFFFFFF;
    }
    print("checksum %\n", sum);
}

// --- FNV-1a hash ------------------------------------------------------------

bench_hash :: () {
    N :: 32000000;
    R :: 4;
    buf := NewArray(N, u8);
    x: u64 = 12345;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        buf[i] = cast(u8)(x & 0xFF);
    }
    h: u64 = 2166136261;
    for r: 0..R-1 {
        for i: 0..N-1 {
            h = h ^ cast(u64) buf[i];
            h = (h * 16777619) & 0xFFFFFFFF;
        }
    }
    print("checksum %\n", h);
}

// --- binary search tree -----------------------------------------------------

BstNode :: struct {
    key: u64;
    left: *BstNode;
    right: *BstNode;
}

bench_bst :: () {
    M :: 1000000;
    Q :: 1000000;
    root: *BstNode = null;
    x: u64 = 22222;
    for n: 0..M-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        key := x & 0x7FFFFFFF;
        nn := New(BstNode);
        nn.key = key;
        if root == null {
            root = nn;
            continue;
        }
        cur := root;
        while true {
            if key < cur.key {
                if cur.left == null { cur.left = nn; break; }
                cur = cur.left;
            } else {
                if cur.right == null { cur.right = nn; break; }
                cur = cur.right;
            }
        }
    }
    y: u64 = 99991;
    cs: u64 = 0;
    for q: 0..Q-1 {
        y = (y * 1664525 + 1013904223) & 0xFFFFFFFF;
        key := y & 0x7FFFFFFF;
        steps: u64 = 0;
        cur := root;
        while cur != null {
            steps += 1;
            if key == cur.key break;
            if key < cur.key  cur = cur.left;
            else              cur = cur.right;
        }
        cs = (cs * 1000003 + steps) & 0xFFFFFFFF;
    }
    print("checksum %\n", cs);
}

// --- run-length encoding ----------------------------------------------------

bench_rle :: () {
    N :: 40000000;
    R :: 4;
    buf := NewArray(N, u8);
    out := NewArray(2 * N, u8);
    x: u64 = 33333;
    i := 0;
    while i < N {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        v := cast(u8)(x & 0xFF);
        rl := cast(s64)((x & 0x7FFFFFFF) % 16) + 1;
        c := 0;
        while c < rl && i < N {
            buf[i] = v;
            i += 1;
            c += 1;
        }
    }
    h: u64 = 2166136261;
    for r: 0..R-1 {
        o := 0;
        p := 0;
        while p < N {
            v := buf[p];
            run := 1;
            while p + run < N && buf[p + run] == v && run < 255  run += 1;
            out[o] = cast(u8) run;
            out[o + 1] = v;
            o += 2;
            p += run;
        }
        for k: 0..o-1 {
            h = h ^ cast(u64) out[k];
            h = (h * 16777619) & 0xFFFFFFFF;
        }
        h = h ^ cast(u64)(o % 256);             h = (h * 16777619) & 0xFFFFFFFF;
        h = h ^ cast(u64)((o / 256) % 256);     h = (h * 16777619) & 0xFFFFFFFF;
        h = h ^ cast(u64)((o / 65536) % 256);   h = (h * 16777619) & 0xFFFFFFFF;
        h = h ^ cast(u64)((o / 16777216) % 256); h = (h * 16777619) & 0xFFFFFFFF;
    }
    print("checksum %\n", h);
}

// --- base64 encoding --------------------------------------------------------

bench_base64 :: () {
    N :: 24000000;
    R :: 4;
    B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    buf := NewArray(N, u8);
    x: u64 = 44444;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        buf[i] = cast(u8)(x & 0xFF);
    }
    h: u64 = 2166136261;
    for r: 0..R-1 {
        i := 0;
        while i + 2 < N {
            b0 := cast(s64) buf[i];
            b1 := cast(s64) buf[i + 1];
            b2 := cast(s64) buf[i + 2];
            i0 := b0 / 4;
            i1 := (b0 & 3) * 16 + b1 / 16;
            i2 := (b1 & 15) * 4 + b2 / 64;
            i3 := b2 & 63;
            h = h ^ cast(u64) B64[i0]; h = (h * 16777619) & 0xFFFFFFFF;
            h = h ^ cast(u64) B64[i1]; h = (h * 16777619) & 0xFFFFFFFF;
            h = h ^ cast(u64) B64[i2]; h = (h * 16777619) & 0xFFFFFFFF;
            h = h ^ cast(u64) B64[i3]; h = (h * 16777619) & 0xFFFFFFFF;
            i += 3;
        }
    }
    print("checksum %\n", h);
}

// --- indirect dispatch ------------------------------------------------------

op_add :: (a: u64, b: u64) -> u64 { return (a + b) & 0xFFFFFFFF; }
op_xor :: (a: u64, b: u64) -> u64 { return a ^ b; }
op_mul :: (a: u64, b: u64) -> u64 { return (a * (b | 1)) & 0xFFFFFFFF; }
op_sub :: (a: u64, b: u64) -> u64 { return (a - b) & 0xFFFFFFFF; }

bench_dispatch :: () {
    N :: 4000000;
    R :: 32;
    code := NewArray(N, u8);
    operand := NewArray(N, u32);
    x: u64 = 55555;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        code[i] = cast(u8)((x & 0x7FFFFFFF) % 4);
        operand[i] = cast(u32) x;
    }
    fns: [4](a: u64, b: u64) -> u64 = .[op_add, op_xor, op_mul, op_sub];
    acc: u64 = 2166136261;
    for r: 0..R-1 {
        for i: 0..N-1  acc = fns[cast(s64) code[i]](acc, cast(u64) operand[i]);
    }
    print("checksum %\n", acc);
}

bench_collatz :: () {
    N :: 3_000_000;
    total: u64 = 0;
    i: u64 = 1;
    while i <= N {
        n: u64 = i;
        steps: u64 = 0;
        while n != 1 {
            if n % 2 == 0  n = n / 2;
            else           n = 3 * n + 1;
            steps += 1;
        }
        total += steps;
        i += 1;
    }
    print("checksum %\n", total);
}

// --- n-body (dependent floating-point chains) -------------------------------
bench_nbody :: () {
    N :: 2048;
    STEPS :: 8;
    DT : float64 : 0.01;
    EPS : float64 : 0.05;
    px := NewArray(N, float64);
    py := NewArray(N, float64);
    pz := NewArray(N, float64);
    vx := NewArray(N, float64);
    vy := NewArray(N, float64);
    vz := NewArray(N, float64);
    m := NewArray(N, float64);
    s: u64 = 7777;
    for i: 0..N-1 {
        s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
        px[i] = (cast(float64)(s & 0xFFFF) / 65536.0) * 2.0 - 1.0;
        s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
        py[i] = (cast(float64)(s & 0xFFFF) / 65536.0) * 2.0 - 1.0;
        s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
        pz[i] = (cast(float64)(s & 0xFFFF) / 65536.0) * 2.0 - 1.0;
        s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
        m[i] = cast(float64)(s & 0xFFFF) / 65536.0 + 0.1;
    }
    for step: 0..STEPS-1 {
        for i: 0..N-1 {
            ax: float64 = 0;
            ay: float64 = 0;
            az: float64 = 0;
            xi := px[i];
            yi := py[i];
            zi := pz[i];
            for j: 0..N-1 {
                if j == i continue;
                dx := px[j] - xi;
                dy := py[j] - yi;
                dz := pz[j] - zi;
                d2 := dx * dx + dy * dy + dz * dz + EPS;
                g := (d2 + 1.0) * 0.5;
                for k: 0..7  g = (g + d2 / g) * 0.5;
                inv3 := 1.0 / (d2 * g);
                f := m[j] * inv3;
                ax += dx * f;
                ay += dy * f;
                az += dz * f;
            }
            vx[i] += ax * DT;
            vy[i] += ay * DT;
            vz[i] += az * DT;
        }
        for i: 0..N-1 {
            px[i] += vx[i] * DT;
            py[i] += vy[i] * DT;
            pz[i] += vz[i] * DT;
        }
    }
    cs: u64 = 0;
    for i: 0..N-1 {
        cs = (cs * 1000003 + (cast(u64)(cast(s64)(px[i] * 1024.0)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
        cs = (cs * 1000003 + (cast(u64)(cast(s64)(py[i] * 1024.0)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
        cs = (cs * 1000003 + (cast(u64)(cast(s64)(pz[i] * 1024.0)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    }
    print("checksum %\n", cs);
}

// --- STREAM triad (memory write bandwidth) ----------------------------------
bench_stream :: () {
    N :: 16000000;
    R :: 40;
    a := NewArray(N, u32);
    b := NewArray(N, u32);
    c := NewArray(N, u32);
    x: u64 = 11111;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        b[i] = cast(u32) x;
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        c[i] = cast(u32) x;
    }
    for r: 0..R-1 {
        for i: 0..N-1  a[i] = cast(u32)((cast(u64)b[i] + 3 * cast(u64)c[i]) & 0xFFFFFFFF);
    }
    cs: u64 = 0;
    for i: 0..N-1  cs = (cs * 1000003 + cast(u64)a[i]) & 0xFFFFFFFF;
    print("checksum %\n", cs);
}

// --- N-queens (backtracking recursion) --------------------------------------
nq_solve :: (cols: u64, d1: u64, d2: u64, full: u64) -> u64 {
    if cols == full return 1;
    count: u64 = 0;
    avail := (0xFFFFFFFF ^ (cols | d1 | d2)) & full;
    while avail != 0 {
        neg := ((0xFFFFFFFF ^ avail) + 1) & 0xFFFFFFFF;
        bit := avail & neg;
        avail -= bit;
        count += nq_solve(cols | bit, ((d1 | bit) * 2) & full, (d2 | bit) / 2, full);
    }
    return count;
}

bench_nqueens :: () {
    full: u64 = (1 << 14) - 1;
    total := nq_solve(0, 0, 0, full);
    print("checksum %\n", total);
}

// --- Conway's Game of Life --------------------------------------------------
bench_life :: () {
    W :: 1024;
    H :: 1024;
    T :: 300;
    cur := NewArray(W * H, u8);
    nxt := NewArray(W * H, u8);
    x: u64 = 22221;
    for i: 0..W*H-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        cur[i] = cast(u8)((x / 65536) & 1);
    }
    for gen: 0..T-1 {
        for y: 0..H-1 {
            ym := ifx y == 0 then H - 1 else y - 1;
            yp := ifx y == H - 1 then 0 else y + 1;
            for cx: 0..W-1 {
                xm := ifx cx == 0 then W - 1 else cx - 1;
                xp := ifx cx == W - 1 then 0 else cx + 1;
                n := cast(int) cur[ym * W + xm] + cast(int) cur[ym * W + cx] + cast(int) cur[ym * W + xp]
                   + cast(int) cur[y * W + xm] + cast(int) cur[y * W + xp]
                   + cast(int) cur[yp * W + xm] + cast(int) cur[yp * W + cx] + cast(int) cur[yp * W + xp];
                alive := cur[y * W + cx];
                nxt[y * W + cx] = cast(u8)(ifx (n == 3) || (alive == 1 && n == 2) then 1 else 0);
            }
        }
        tmp := cur;
        cur = nxt;
        nxt = tmp;
    }
    cs: u64 = 0;
    for i: 0..W*H-1  cs = (cs * 1000003 + cast(u64) cur[i]) & 0xFFFFFFFF;
    print("checksum %\n", cs);
}

// --- open-addressing hash map (linear probing) ------------------------------
bench_hashmap :: () {
    M :: 8000000;
    Q :: 16000000;
    SIZE :: 1 << 24;
    MASK :: SIZE - 1;
    keys := NewArray(SIZE, u32);
    vals := NewArray(SIZE, u32);
    x: u64 = 33331;
    for n: 0..M-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        key := (x & 0x7FFFFFFF) | 1;
        idx := cast(s64)(key & MASK);
        while true {
            if keys[idx] == 0 { keys[idx] = cast(u32) key; vals[idx] = cast(u32) x; break; }
            if keys[idx] == cast(u32) key { vals[idx] = cast(u32)((cast(u64)vals[idx] + x) & 0xFFFFFFFF); break; }
            idx = (idx + 1) & MASK;
        }
    }
    y: u64 = 99989;
    acc: u64 = 0;
    for q: 0..Q-1 {
        y = (y * 1664525 + 1013904223) & 0xFFFFFFFF;
        key := (y & 0x7FFFFFFF) | 1;
        idx := cast(s64)(key & MASK);
        steps: u64 = 0;
        while true {
            steps += 1;
            if keys[idx] == 0 break;
            if keys[idx] == cast(u32) key { acc = (acc + cast(u64)vals[idx]) & 0xFFFFFFFF; break; }
            idx = (idx + 1) & MASK;
        }
        acc = (acc * 1000003 + steps) & 0xFFFFFFFF;
    }
    print("checksum %\n", acc);
}

// --- SHA-256 (32-bit crypto mixing) -----------------------------------------
rotr32 :: (x: u64, n: u64) -> u64 {
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;
}

bench_sha256 :: () {
    N :: 4000000;
    R :: 16;
    k: [64]u64 = .[
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    buf := NewArray(N, u8);
    x: u64 = 44441;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        buf[i] = cast(u8)((x / 256) & 0xFF);
    }
    cs: u64 = 0;
    for r: 0..R-1 {
        h0: u64 = 0x6a09e667;
        h1: u64 = 0xbb67ae85;
        h2: u64 = 0x3c6ef372;
        h3: u64 = 0xa54ff53a;
        h4: u64 = 0x510e527f;
        h5: u64 = 0x9b05688c;
        h6: u64 = 0x1f83d9ab;
        h7: u64 = 0x5be0cd19;
        nblocks := N / 64;
        w: [64]u64;
        for blk: 0..nblocks-1 {
            base := blk * 64;
            for t: 0..15 {
                o := base + t * 4;
                w[t] = ((cast(u64) buf[o]) << 24) | ((cast(u64) buf[o + 1]) << 16) | ((cast(u64) buf[o + 2]) << 8) | (cast(u64) buf[o + 3]);
            }
            for t: 16..63 {
                s0 := rotr32(w[t - 15], 7) ^ rotr32(w[t - 15], 18) ^ (w[t - 15] >> 3);
                s1 := rotr32(w[t - 2], 17) ^ rotr32(w[t - 2], 19) ^ (w[t - 2] >> 10);
                w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xFFFFFFFF;
            }
            a := h0; b := h1; c := h2; d := h3;
            e := h4; f := h5; g := h6; hh := h7;
            for t: 0..63 {
                S1 := rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
                ch := (e & f) ^ ((0xFFFFFFFF ^ e) & g);
                t1 := (hh + S1 + ch + k[t] + w[t]) & 0xFFFFFFFF;
                S0 := rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
                maj := (a & b) ^ (a & c) ^ (b & c);
                t2 := (S0 + maj) & 0xFFFFFFFF;
                hh = g;
                g = f;
                f = e;
                e = (d + t1) & 0xFFFFFFFF;
                d = c;
                c = b;
                b = a;
                a = (t1 + t2) & 0xFFFFFFFF;
            }
            h0 = (h0 + a) & 0xFFFFFFFF;
            h1 = (h1 + b) & 0xFFFFFFFF;
            h2 = (h2 + c) & 0xFFFFFFFF;
            h3 = (h3 + d) & 0xFFFFFFFF;
            h4 = (h4 + e) & 0xFFFFFFFF;
            h5 = (h5 + f) & 0xFFFFFFFF;
            h6 = (h6 + g) & 0xFFFFFFFF;
            h7 = (h7 + hh) & 0xFFFFFFFF;
        }
        cs = (cs * 1000003 + (h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7)) & 0xFFFFFFFF;
    }
    print("checksum %\n", cs);
}

// --- matrix transpose (cache stride / TLB) ----------------------------------
bench_transpose :: () {
    NDIM :: 4096;
    R :: 6;
    src := NewArray(NDIM * NDIM, u32);
    dst := NewArray(NDIM * NDIM, u32);
    x: u64 = 55551;
    for i: 0..NDIM*NDIM-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        src[i] = cast(u32) x;
    }
    for r: 0..R-1 {
        for i: 0..NDIM-1 {
            for j: 0..NDIM-1  dst[j * NDIM + i] = src[i * NDIM + j];
        }
        tmp := src;
        src = dst;
        dst = tmp;
    }
    cs: u64 = 0;
    for i: 0..NDIM*NDIM-1  cs = (cs * 1000003 + cast(u64) src[i]) & 0xFFFFFFFF;
    print("checksum %\n", cs);
}

// --- edit distance (dynamic programming) ------------------------------------
edit_min3 :: (a: s64, b: s64, c: s64) -> s64 {
    m := ifx a < b then a else b;
    return ifx m < c then m else c;
}

bench_editdist :: () {
    LA :: 16000;
    LB :: 16000;
    a := NewArray(LA, u8);
    b := NewArray(LB, u8);
    prev := NewArray(LB + 1, s64);
    cur := NewArray(LB + 1, s64);
    x: u64 = 66661;
    for i: 0..LA-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        a[i] = cast(u8)((x / 65536) % 4);
    }
    for i: 0..LB-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        b[i] = cast(u8)((x / 65536) % 4);
    }
    for j: 0..LB  prev[j] = cast(s64) j;
    for i: 1..LA {
        cur[0] = cast(s64) i;
        for j: 1..LB {
            cost: s64 = ifx a[i - 1] == b[j - 1] then 0 else 1;
            cur[j] = edit_min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        }
        tmp := prev;
        prev = cur;
        cur = tmp;
    }
    print("checksum %\n", cast(u64) prev[LB]);
}

// --- LZ77 greedy compressor -------------------------------------------------
bench_lz :: () {
    N :: 4000000;
    WIN :: 512;
    MAXLEN :: 64;
    buf := NewArray(N, u8);
    x: u64 = 77771;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        buf[i] = cast(u8)((x / 65536) % 8);
    }
    h: u64 = 2166136261;
    p := 0;
    while p < N {
        lo := ifx p > WIN then p - WIN else 0;
        bestlen := 0;
        bestoff := 0;
        sidx := lo;
        while sidx < p {
            ln := 0;
            while p + ln < N && ln < MAXLEN && buf[sidx + ln] == buf[p + ln]  ln += 1;
            if ln > bestlen { bestlen = ln; bestoff = p - sidx; }
            sidx += 1;
        }
        if bestlen >= 3 {
            h = h ^ cast(u64)(bestoff & 0xFF);        h = (h * 16777619) & 0xFFFFFFFF;
            h = h ^ cast(u64)((bestoff / 256) & 0xFF); h = (h * 16777619) & 0xFFFFFFFF;
            h = h ^ cast(u64)(bestlen & 0xFF);         h = (h * 16777619) & 0xFFFFFFFF;
            p += bestlen;
        } else {
            h = h ^ cast(u64) buf[p];                  h = (h * 16777619) & 0xFFFFFFFF;
            p += 1;
        }
    }
    print("checksum %\n", h);
}

// --- CRC32 (table-driven hashing) -------------------------------------------
bench_crc32 :: () {
    N :: 16000000;
    R :: 8;
    table: [256]u64;
    for i: 0..255 {
        c: u64 = cast(u64) i;
        for kk: 0..7 {
            if (c & 1) == 1  c = (0xEDB88320 ^ (c >> 1)) & 0xFFFFFFFF;
            else             c = c >> 1;
        }
        table[i] = c;
    }
    buf := NewArray(N, u8);
    x: u64 = 88881;
    for i: 0..N-1 {
        x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
        buf[i] = cast(u8)((x / 65536) & 0xFF);
    }
    cs: u64 = 0;
    for r: 0..R-1 {
        crc: u64 = 0xFFFFFFFF;
        for i: 0..N-1  crc = table[cast(s64)((crc ^ cast(u64) buf[i]) & 0xFF)] ^ (crc >> 8);
        crc = crc ^ 0xFFFFFFFF;
        cs = (cs * 1000003 + crc) & 0xFFFFFFFF;
    }
    print("checksum %\n", cs);
}

streq :: (a: string, b: string) -> bool {
    if a.count != b.count return false;
    for i: 0..a.count-1  if a[i] != b[i] return false;
    return true;
}

main :: () {
    args := get_command_line_arguments();
    if args.count < 2 {
        print("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>\n");
        return;
    }
    name := args[1];
    if streq(name, "fib")              bench_fib();
    else if streq(name, "mandelbrot")  bench_mandelbrot();
    else if streq(name, "matmul")      bench_matmul();
    else if streq(name, "sieve")       bench_sieve();
    else if streq(name, "sort")        bench_sort();
    else if streq(name, "collatz")     bench_collatz();
    else if streq(name, "raster")      bench_raster();
    else if streq(name, "ptrchase")    bench_ptrchase();
    else if streq(name, "hash")        bench_hash();
    else if streq(name, "bst")         bench_bst();
    else if streq(name, "rle")         bench_rle();
    else if streq(name, "base64")      bench_base64();
    else if streq(name, "dispatch")    bench_dispatch();
    else if streq(name, "nbody")       bench_nbody();
    else if streq(name, "stream")      bench_stream();
    else if streq(name, "nqueens")     bench_nqueens();
    else if streq(name, "life")        bench_life();
    else if streq(name, "hashmap")     bench_hashmap();
    else if streq(name, "sha256")      bench_sha256();
    else if streq(name, "transpose")   bench_transpose();
    else if streq(name, "editdist")    bench_editdist();
    else if streq(name, "lz")          bench_lz();
    else if streq(name, "crc32")       bench_crc32();
    else print("unknown benchmark: %\n", name);
}
