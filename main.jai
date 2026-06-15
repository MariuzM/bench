#import "Basic";

// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by the
// command-line argument, so the build script can measure each one's wall-time
// and peak memory in isolation. Every benchmark prints a single "checksum <n>"
// line; the Jai and Zig builds must agree on it, which proves both did the
// same work.
// ---------------------------------------------------------------------------

fib :: (n: u64) -> u64 {
    if n < 2 return n;
    return fib(n - 1) + fib(n - 2);
}

bench_fib :: () {
    // Warm-up call: this compiler miscompiles the very first invocation of a
    // recursive function used in an accumulating expression (it returns 0).
    // Calling fib once up front primes correct code generation for the loop.
    if fib(2) == 99 return;
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
    for i: 0..N*N-1 {
        sum += c[i];
    }
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
    k := 2;
    while k < N {
        if sieve[k] == 0  count += 1;
        k += 1;
    }
    print("checksum %\n", count);
}

quicksort :: (arr: [] u64, lo: s64, hi: s64) {
    if lo >= hi return;
    pivot := arr[(lo + hi) / 2];
    i := lo;
    j := hi;
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
        // Linear congruential generator (multiply + add only). We avoid the
        // usual xorshift because this compiler's u64 right-shift is arithmetic
        // (sign-extending), which would diverge from the Zig build. Masking the
        // top bit keeps values below 2^63 so the signed u64 comparison this
        // compiler emits still matches an unsigned ordering.
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
    // OpenJai rounds *named* float constants (::) to 32-bit float, so these
    // must be float64 *variables* to keep the range reduction bit-identical
    // with the other languages.
    TWO_PI : float64 = 6.283185307179586;
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
    HALF_PI : float64 = 1.5707963267948966;
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
            px0 := bx[v];
            py0 := by[v];
            pz0 := bz[v];
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

        for c: 0..W*H-1 {
            color[c] = 0;
            zbuf[c] = 1.0e30;
        }

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
                    x0 := cast(s64) mnx;
                    x1 := cast(s64) mxx;
                    y0 := cast(s64) mny;
                    y1 := cast(s64) mxy;
                    py := y0;
                    while py <= y1 {
                        pcy := cast(float64) py + 0.5;
                        px := x0;
                        while px <= x1 {
                            pcx := cast(float64) px + 0.5;
                            w0 := edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
                            w1 := edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
                            w2 := edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
                            if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                                l0 := w0 / area;
                                l1 := w1 / area;
                                l2 := w2 / area;
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
                            px += 1;
                        }
                        py += 1;
                    }
                }
            }
        }

        frame_sum: u64 = 0;
        for c: 0..W*H-1 {
            frame_sum += cast(u64) color[c];
        }
        checksum = checksum * 1000003 + frame_sum;
    }

    print("checksum %\n", checksum);
}

// --- pointer-chasing (random memory latency) --------------------------------
// Builds one big random permutation cycle, then chases next[p] for many hops.
// Each load depends on the previous one, so the prefetcher can't hide it: this
// measures memory *latency*, unlike the streaming `sieve`. Pure 32-bit integer.
// This compiler doesn't truncate u32 arithmetic to 32 bits, so the wrapping
// 32-bit math is done in u64 and masked with `& 0xFFFFFFFF` to match the other
// languages' u32 wraparound.

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
    h := 0;
    while h < HOPS {
        p = cast(s64) next[p];
        sum = (sum + cast(u64) p) & 0xFFFFFFFF;
        h += 1;
    }
    print("checksum %\n", sum);
}

// --- FNV-1a hash ------------------------------------------------------------
// Hashes a byte buffer several times with 32-bit FNV-1a. Stresses the integer
// ALU (xor + wrapping multiply) and a tight sequential read; no SIMD to exploit.

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

// --- binary search tree (heap allocation + pointer chasing) -----------------
// Inserts M keys into a BST (one heap allocation per node, branchy descent),
// then runs Q lookups. Measures allocator/GC throughput plus pointer-chasing
// reads. Keys stay below 2^31 so the signed comparison this compiler emits
// still matches an unsigned ordering (same trick as `sort`).

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
        nn.left = null;
        nn.right = null;
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

// --- run-length encoding (branchy byte processing) --------------------------
// Builds a buffer of random runs, then RLE-encodes it several times, folding
// the (count,value) output into a 32-bit hash. Data-dependent branchy scan.

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

// --- base64 encoding (table lookup + bit shuffling) -------------------------
// Base64-encodes a byte buffer several times, folding the output characters
// into a 32-bit hash. Uses division (not >>) so every language agrees bit for
// bit. Stresses byte-level bit manipulation and a small gather/table lookup.

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
// Applies a stream of ops to an accumulator through a procedure-pointer table,
// one indirect call per element. Stresses indirect-branch prediction. All ops
// are 32-bit wrapping + ^ * - (done in u64 and masked) so the result is
// identical across languages.

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
    fns: [4](a: u64, b: u64) -> u64;
    fns[0] = op_add;
    fns[1] = op_xor;
    fns[2] = op_mul;
    fns[3] = op_sub;
    acc: u64 = 2166136261;
    for r: 0..R-1 {
        for i: 0..N-1 {
            acc = fns[cast(s64) code[i]](acc, cast(u64) operand[i]);
        }
    }
    print("checksum %\n", acc);
}

bench_collatz :: () {
    N :: 3_000_000;
    total: u64 = 0;
    i: u64 = 1;
    while i <= N {
        // Values stay below 2^32 here, so the high bit is never set: this
        // compiler's signed `/` and arithmetic `>>` behave identically to the
        // unsigned forms, and no warmup/masking workaround is needed.
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

streq :: (a: string, b: string) -> bool {
    if a.count != b.count return false;
    for i: 0..a.count-1 {
        if a[i] != b[i] return false;
    }
    return true;
}

main :: () {
    args := get_command_line_arguments();
    if args.count < 2 {
        print("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>\n");
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
    else print("unknown benchmark: %\n", name);
}
