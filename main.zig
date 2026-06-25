const std = @import("std");

// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by argv[1],
// so the build script can measure each one's wall-time and peak memory in
// isolation. Every benchmark prints a single "checksum <n>" line; the Zig and
// Jai builds must agree on it, which proves both did the same work.
// ---------------------------------------------------------------------------

fn fib(n: u64) u64 {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

fn benchFib() void {
    var total: u64 = 0;
    var n: u64 = 30;
    while (n <= 42) : (n += 1) total +%= fib(n);
    std.debug.print("checksum {d}\n", .{total});
}

fn benchMandelbrot() void {
    const W: usize = 1200;
    const H: usize = 1200;
    const MAX_IT: u64 = 1000;
    var sum: u64 = 0;
    for (0..H) |py| {
        const y0 = (@as(f64, @floatFromInt(py)) / @as(f64, H)) * 4.0 - 2.0;
        for (0..W) |px| {
            const x0 = (@as(f64, @floatFromInt(px)) / @as(f64, W)) * 4.0 - 2.5;
            var x: f64 = 0;
            var y: f64 = 0;
            var it: u64 = 0;
            while (x * x + y * y <= 4.0 and it < MAX_IT) : (it += 1) {
                const xt = x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
            }
            sum +%= it;
        }
    }
    std.debug.print("checksum {d}\n", .{sum});
}

fn benchMatmul() !void {
    const N: usize = 512;
    const alloc = std.heap.page_allocator;
    const a = try alloc.alloc(i64, N * N);
    defer alloc.free(a);
    const b = try alloc.alloc(i64, N * N);
    defer alloc.free(b);
    const c = try alloc.alloc(i64, N * N);
    defer alloc.free(c);

    for (0..N) |i| {
        for (0..N) |j| {
            a[i * N + j] = @as(i64, @intCast((i * j) % 7)) - 3;
            b[i * N + j] = @as(i64, @intCast((i + j) % 5)) - 2;
            c[i * N + j] = 0;
        }
    }

    for (0..N) |i| {
        for (0..N) |k| {
            const aik = a[i * N + k];
            for (0..N) |j| {
                c[i * N + j] += aik * b[k * N + j];
            }
        }
    }

    var sum: i64 = 0;
    for (0..N * N) |i| {
        sum +%= c[i];
    }
    std.debug.print("checksum {d}\n", .{sum});
}

fn benchSieve() !void {
    const N: usize = 50_000_000;
    const alloc = std.heap.page_allocator;
    const sieve = try alloc.alloc(u8, N);
    defer alloc.free(sieve);
    @memset(sieve, 1);
    sieve[0] = 0;
    sieve[1] = 0;

    var i: usize = 2;
    while (i * i < N) : (i += 1) {
        if (sieve[i] == 1) {
            var j: usize = i * i;
            while (j < N) : (j += i) sieve[j] = 0;
        }
    }

    var count: u64 = 0;
    for (0..N) |k| count += sieve[k];
    std.debug.print("checksum {d}\n", .{count});
}

fn quicksort(arr: []u64, lo: isize, hi: isize) void {
    if (lo >= hi) return;
    const pivot = arr[@intCast(@divTrunc(lo + hi, 2))];
    var i = lo;
    var j = hi;
    while (i <= j) {
        while (arr[@intCast(i)] < pivot) i += 1;
        while (arr[@intCast(j)] > pivot) j -= 1;
        if (i <= j) {
            const t = arr[@intCast(i)];
            arr[@intCast(i)] = arr[@intCast(j)];
            arr[@intCast(j)] = t;
            i += 1;
            j -= 1;
        }
    }
    quicksort(arr, lo, j);
    quicksort(arr, i, hi);
}

fn benchSort() !void {
    const N: usize = 3_000_000;
    const alloc = std.heap.page_allocator;
    const arr = try alloc.alloc(u64, N);
    defer alloc.free(arr);

    var state: u64 = 88172645463325252;
    for (0..N) |i| {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        arr[i] = state & 0x7FFFFFFFFFFFFFFF;
    }

    quicksort(arr, 0, @as(isize, N) - 1);

    var cs: u64 = 0;
    for (0..N) |i| cs = cs *% 1000003 +% arr[i];
    std.debug.print("checksum {d}\n", .{cs});
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

fn rFloor(y: f64) f64 {
    const f: f64 = @floatFromInt(@as(i64, @intFromFloat(y)));
    return if (f > y) f - 1.0 else f;
}

fn rSin(xin: f64) f64 {
    const TWO_PI: f64 = 6.283185307179586;
    const k = rFloor(xin / TWO_PI + 0.5);
    const x = xin - k * TWO_PI;
    const x2 = x * x;
    var p: f64 = -1.0 / 1307674368000.0;
    p = 1.0 / 6227020800.0 + x2 * p;
    p = -1.0 / 39916800.0 + x2 * p;
    p = 1.0 / 362880.0 + x2 * p;
    p = -1.0 / 5040.0 + x2 * p;
    p = 1.0 / 120.0 + x2 * p;
    p = -1.0 / 6.0 + x2 * p;
    p = 1.0 + x2 * p;
    return x * p;
}

fn rCos(x: f64) f64 {
    const HALF_PI: f64 = 1.5707963267948966;
    return rSin(x + HALF_PI);
}

fn edge(ax: f64, ay: f64, bx: f64, by: f64, cx: f64, cy: f64) f64 {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

fn benchRaster() !void {
    const W: usize = 640;
    const H: usize = 480;
    const RINGS: usize = 24;
    const SECTORS: usize = 24;
    const FRAMES: usize = 240;
    const NV: usize = (RINGS + 1) * (SECTORS + 1);
    const FOCAL: f64 = 500.0;
    const CAM_DIST: f64 = 3.0;

    var bx: [NV]f64 = undefined;
    var by: [NV]f64 = undefined;
    var bz: [NV]f64 = undefined;
    var nv: usize = 0;
    for (0..RINGS + 1) |i| {
        const theta = 3.141592653589793 * (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(RINGS)));
        const st = rSin(theta);
        const ct = rCos(theta);
        for (0..SECTORS + 1) |j| {
            const phi = 6.283185307179586 * (@as(f64, @floatFromInt(j)) / @as(f64, @floatFromInt(SECTORS)));
            const sp = rSin(phi);
            const cp = rCos(phi);
            bx[nv] = st * cp;
            by[nv] = ct;
            bz[nv] = st * sp;
            nv += 1;
        }
    }

    var sx: [NV]f64 = undefined;
    var sy: [NV]f64 = undefined;
    var sz: [NV]f64 = undefined;
    var si: [NV]f64 = undefined;

    const alloc = std.heap.page_allocator;
    const color = try alloc.alloc(u8, W * H);
    defer alloc.free(color);
    const zbuf = try alloc.alloc(f64, W * H);
    defer alloc.free(zbuf);

    var checksum: u64 = 0;

    for (0..FRAMES) |f| {
        const ang = @as(f64, @floatFromInt(f)) * 0.0125;
        const cy = rCos(ang);
        const syr = rSin(ang);
        const axx = ang * 0.5;
        const cx = rCos(axx);
        const sxr = rSin(axx);

        for (0..nv) |v| {
            const px0 = bx[v];
            const py0 = by[v];
            const pz0 = bz[v];
            const rx = px0 * cy + pz0 * syr;
            const rz = -px0 * syr + pz0 * cy;
            const ry = py0;
            const ry2 = ry * cx - rz * sxr;
            const rz2 = ry * sxr + rz * cx;
            var inten = -rz2;
            if (inten < 0.0) inten = 0.0;
            const zc = rz2 + CAM_DIST;
            const invz = 1.0 / zc;
            sx[v] = rx * invz * FOCAL + @as(f64, @floatFromInt(W)) * 0.5;
            sy[v] = ry2 * invz * FOCAL + @as(f64, @floatFromInt(H)) * 0.5;
            sz[v] = zc;
            si[v] = inten;
        }

        for (0..W * H) |c| {
            color[c] = 0;
            zbuf[c] = 1.0e30;
        }

        for (0..RINGS) |ri| {
            for (0..SECTORS) |sj| {
                const a = ri * (SECTORS + 1) + sj;
                const b = a + (SECTORS + 1);
                const tris = [2][3]usize{ .{ a, b, a + 1 }, .{ a + 1, b, b + 1 } };
                for (0..2) |t| {
                    const ia = tris[t][0];
                    const ib = tris[t][1];
                    const ic = tris[t][2];
                    const area = edge(sx[ia], sy[ia], sx[ib], sy[ib], sx[ic], sy[ic]);
                    if (area <= 0.0) continue;
                    var mnx = sx[ia];
                    if (sx[ib] < mnx) mnx = sx[ib];
                    if (sx[ic] < mnx) mnx = sx[ic];
                    var mxx = sx[ia];
                    if (sx[ib] > mxx) mxx = sx[ib];
                    if (sx[ic] > mxx) mxx = sx[ic];
                    var mny = sy[ia];
                    if (sy[ib] < mny) mny = sy[ib];
                    if (sy[ic] < mny) mny = sy[ic];
                    var mxy = sy[ia];
                    if (sy[ib] > mxy) mxy = sy[ib];
                    if (sy[ic] > mxy) mxy = sy[ic];
                    if (mnx < 0.0) mnx = 0.0;
                    if (mxx > @as(f64, @floatFromInt(W - 1))) mxx = @as(f64, @floatFromInt(W - 1));
                    if (mny < 0.0) mny = 0.0;
                    if (mxy > @as(f64, @floatFromInt(H - 1))) mxy = @as(f64, @floatFromInt(H - 1));
                    const x0: usize = @intFromFloat(mnx);
                    const x1: usize = @intFromFloat(mxx);
                    const y0: usize = @intFromFloat(mny);
                    const y1: usize = @intFromFloat(mxy);
                    for (y0..y1 + 1) |py| {
                        const pcy = @as(f64, @floatFromInt(py)) + 0.5;
                        for (x0..x1 + 1) |px| {
                            const pcx = @as(f64, @floatFromInt(px)) + 0.5;
                            const w0 = edge(sx[ib], sy[ib], sx[ic], sy[ic], pcx, pcy);
                            const w1 = edge(sx[ic], sy[ic], sx[ia], sy[ia], pcx, pcy);
                            const w2 = edge(sx[ia], sy[ia], sx[ib], sy[ib], pcx, pcy);
                            if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) {
                                const l0 = w0 / area;
                                const l1 = w1 / area;
                                const l2 = w2 / area;
                                const depth = l0 * sz[ia] + l1 * sz[ib] + l2 * sz[ic];
                                const idx = py * W + px;
                                if (depth < zbuf[idx]) {
                                    zbuf[idx] = depth;
                                    var inten = l0 * si[ia] + l1 * si[ib] + l2 * si[ic];
                                    if (inten < 0.0) inten = 0.0;
                                    if (inten > 1.0) inten = 1.0;
                                    color[idx] = @intFromFloat(inten * 255.0);
                                }
                            }
                        }
                    }
                }
            }
        }

        var frame_sum: u64 = 0;
        for (0..W * H) |p| frame_sum +%= color[p];
        checksum = checksum *% 1000003 +% frame_sum;
    }

    std.debug.print("checksum {d}\n", .{checksum});
}

// --- pointer-chasing (random memory latency) --------------------------------

fn benchPtrchase() !void {
    const N: usize = 16000000;
    const HOPS: u64 = 4000000;
    const alloc = std.heap.page_allocator;
    const order = try alloc.alloc(u32, N);
    defer alloc.free(order);
    const next = try alloc.alloc(u32, N);
    defer alloc.free(next);
    for (0..N) |i| order[i] = @intCast(i);
    var x: u32 = 1;
    var i: usize = N - 1;
    while (i >= 1) : (i -= 1) {
        x = x *% 1664525 +% 1013904223;
        const j: usize = (x & 0x7FFFFFFF) % (@as(u32, @intCast(i)) + 1);
        const t = order[i];
        order[i] = order[j];
        order[j] = t;
    }
    for (0..N) |k| next[order[k]] = order[(k + 1) % N];
    var sum: u32 = 0;
    var p: u32 = 0;
    for (0..HOPS) |_| {
        p = next[p];
        sum +%= p;
    }
    std.debug.print("checksum {d}\n", .{sum});
}

// --- FNV-1a hash ------------------------------------------------------------

fn benchHash() !void {
    const N: usize = 32000000;
    const R: usize = 4;
    const alloc = std.heap.page_allocator;
    const buf = try alloc.alloc(u8, N);
    defer alloc.free(buf);
    var x: u32 = 12345;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        buf[i] = @intCast(x & 0xFF);
    }
    var h: u32 = 2166136261;
    for (0..R) |_| {
        for (0..N) |i| {
            h ^= @as(u32, buf[i]);
            h *%= 16777619;
        }
    }
    std.debug.print("checksum {d}\n", .{h});
}

// --- binary search tree -----------------------------------------------------

const BstNode = struct {
    key: u32,
    left: ?*BstNode,
    right: ?*BstNode,
};

fn benchBst() !void {
    const M: usize = 1000000;
    const Q: usize = 1000000;
    // page_allocator rounds every allocation up to a page, so a real
    // general-purpose allocator is used for the many small node allocations.
    const alloc = std.heap.smp_allocator;
    var root: ?*BstNode = null;
    var x: u32 = 22222;
    for (0..M) |_| {
        x = x *% 1664525 +% 1013904223;
        const key = x & 0x7FFFFFFF;
        const nn = try alloc.create(BstNode);
        nn.* = .{ .key = key, .left = null, .right = null };
        if (root == null) {
            root = nn;
            continue;
        }
        var cur = root.?;
        while (true) {
            if (key < cur.key) {
                if (cur.left == null) {
                    cur.left = nn;
                    break;
                }
                cur = cur.left.?;
            } else {
                if (cur.right == null) {
                    cur.right = nn;
                    break;
                }
                cur = cur.right.?;
            }
        }
    }
    var y: u32 = 99991;
    var cs: u32 = 0;
    for (0..Q) |_| {
        y = y *% 1664525 +% 1013904223;
        const key = y & 0x7FFFFFFF;
        var steps: u32 = 0;
        var cur = root;
        while (cur) |node| {
            steps +%= 1;
            if (key == node.key) break;
            cur = if (key < node.key) node.left else node.right;
        }
        cs = cs *% 1000003 +% steps;
    }
    std.debug.print("checksum {d}\n", .{cs});
}

// --- run-length encoding ----------------------------------------------------

fn benchRle() !void {
    const N: usize = 40000000;
    const R: usize = 4;
    const alloc = std.heap.page_allocator;
    const buf = try alloc.alloc(u8, N);
    defer alloc.free(buf);
    const out = try alloc.alloc(u8, 2 * N);
    defer alloc.free(out);
    var x: u32 = 33333;
    var i: usize = 0;
    while (i < N) {
        x = x *% 1664525 +% 1013904223;
        const v: u8 = @intCast(x & 0xFF);
        const rl = ((x & 0x7FFFFFFF) % 16) + 1;
        var c: u32 = 0;
        while (c < rl and i < N) : (c += 1) {
            buf[i] = v;
            i += 1;
        }
    }
    var h: u32 = 2166136261;
    for (0..R) |_| {
        var o: usize = 0;
        var p: usize = 0;
        while (p < N) {
            const v = buf[p];
            var run: usize = 1;
            while (p + run < N and buf[p + run] == v and run < 255) : (run += 1) {}
            out[o] = @intCast(run);
            out[o + 1] = v;
            o += 2;
            p += run;
        }
        for (0..o) |k| {
            h ^= @as(u32, out[k]);
            h *%= 16777619;
        }
        h ^= @as(u32, @intCast(o % 256));
        h *%= 16777619;
        h ^= @as(u32, @intCast((o / 256) % 256));
        h *%= 16777619;
        h ^= @as(u32, @intCast((o / 65536) % 256));
        h *%= 16777619;
        h ^= @as(u32, @intCast((o / 16777216) % 256));
        h *%= 16777619;
    }
    std.debug.print("checksum {d}\n", .{h});
}

// --- base64 encoding --------------------------------------------------------

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn benchBase64() !void {
    const N: usize = 24000000;
    const R: usize = 4;
    const alloc = std.heap.page_allocator;
    const buf = try alloc.alloc(u8, N);
    defer alloc.free(buf);
    var x: u32 = 44444;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        buf[i] = @intCast(x & 0xFF);
    }
    var h: u32 = 2166136261;
    for (0..R) |_| {
        var i: usize = 0;
        while (i + 2 < N) : (i += 3) {
            const b0: u32 = buf[i];
            const b1: u32 = buf[i + 1];
            const b2: u32 = buf[i + 2];
            const idx0 = b0 / 4;
            const idx1 = (b0 & 3) * 16 + b1 / 16;
            const idx2 = (b1 & 15) * 4 + b2 / 64;
            const idx3 = b2 & 63;
            h ^= @as(u32, B64[idx0]);
            h *%= 16777619;
            h ^= @as(u32, B64[idx1]);
            h *%= 16777619;
            h ^= @as(u32, B64[idx2]);
            h *%= 16777619;
            h ^= @as(u32, B64[idx3]);
            h *%= 16777619;
        }
    }
    std.debug.print("checksum {d}\n", .{h});
}

// --- indirect dispatch ------------------------------------------------------

fn opAdd(a: u32, b: u32) u32 {
    return a +% b;
}
fn opXor(a: u32, b: u32) u32 {
    return a ^ b;
}
fn opMul(a: u32, b: u32) u32 {
    return a *% (b | 1);
}
fn opSub(a: u32, b: u32) u32 {
    return a -% b;
}

fn benchDispatch() !void {
    const N: usize = 4000000;
    const R: usize = 32;
    const alloc = std.heap.page_allocator;
    const code = try alloc.alloc(u8, N);
    defer alloc.free(code);
    const operand = try alloc.alloc(u32, N);
    defer alloc.free(operand);
    var x: u32 = 55555;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        code[i] = @intCast((x & 0x7FFFFFFF) % 4);
        operand[i] = x;
    }
    const fns = [_]*const fn (u32, u32) u32{ &opAdd, &opXor, &opMul, &opSub };
    var acc: u32 = 2166136261;
    for (0..R) |_| {
        for (0..N) |i| acc = fns[code[i]](acc, operand[i]);
    }
    std.debug.print("checksum {d}\n", .{acc});
}

fn benchCollatz() void {
    const N: u64 = 3_000_000;
    var total: u64 = 0;
    var i: u64 = 1;
    while (i <= N) : (i += 1) {
        var n: u64 = i;
        var steps: u64 = 0;
        while (n != 1) {
            n = if (n % 2 == 0) n / 2 else 3 * n + 1;
            steps += 1;
        }
        total +%= steps;
    }
    std.debug.print("checksum {d}\n", .{total});
}

// --- n-body (dependent floating-point chains) -------------------------------
fn benchNbody() !void {
    const N: usize = 2048;
    const STEPS: usize = 8;
    const DT: f64 = 0.01;
    const EPS: f64 = 0.05;
    const alloc = std.heap.page_allocator;
    const px = try alloc.alloc(f64, N);
    const py = try alloc.alloc(f64, N);
    const pz = try alloc.alloc(f64, N);
    const vx = try alloc.alloc(f64, N);
    const vy = try alloc.alloc(f64, N);
    const vz = try alloc.alloc(f64, N);
    const m = try alloc.alloc(f64, N);
    defer alloc.free(px);
    defer alloc.free(py);
    defer alloc.free(pz);
    defer alloc.free(vx);
    defer alloc.free(vy);
    defer alloc.free(vz);
    defer alloc.free(m);
    var s: u32 = 7777;
    for (0..N) |i| {
        s = s *% 1664525 +% 1013904223;
        px[i] = (@as(f64, @floatFromInt(s & 0xFFFF)) / 65536.0) * 2.0 - 1.0;
        s = s *% 1664525 +% 1013904223;
        py[i] = (@as(f64, @floatFromInt(s & 0xFFFF)) / 65536.0) * 2.0 - 1.0;
        s = s *% 1664525 +% 1013904223;
        pz[i] = (@as(f64, @floatFromInt(s & 0xFFFF)) / 65536.0) * 2.0 - 1.0;
        s = s *% 1664525 +% 1013904223;
        m[i] = @as(f64, @floatFromInt(s & 0xFFFF)) / 65536.0 + 0.1;
        vx[i] = 0;
        vy[i] = 0;
        vz[i] = 0;
    }
    for (0..STEPS) |_| {
        for (0..N) |i| {
            var ax: f64 = 0;
            var ay: f64 = 0;
            var az: f64 = 0;
            const xi = px[i];
            const yi = py[i];
            const zi = pz[i];
            for (0..N) |j| {
                if (j == i) continue;
                const dx = px[j] - xi;
                const dy = py[j] - yi;
                const dz = pz[j] - zi;
                const d2 = dx * dx + dy * dy + dz * dz + EPS;
                var g = (d2 + 1.0) * 0.5;
                for (0..8) |_| g = (g + d2 / g) * 0.5;
                const inv3 = 1.0 / (d2 * g);
                const f = m[j] * inv3;
                ax += dx * f;
                ay += dy * f;
                az += dz * f;
            }
            vx[i] += ax * DT;
            vy[i] += ay * DT;
            vz[i] += az * DT;
        }
        for (0..N) |i| {
            px[i] += vx[i] * DT;
            py[i] += vy[i] * DT;
            pz[i] += vz[i] * DT;
        }
    }
    var cs: u32 = 0;
    for (0..N) |i| {
        const tx: i64 = @intFromFloat(px[i] * 1024.0);
        const ty: i64 = @intFromFloat(py[i] * 1024.0);
        const tz: i64 = @intFromFloat(pz[i] * 1024.0);
        cs = cs *% 1000003 +% @as(u32, @truncate(@as(u64, @bitCast(tx))));
        cs = cs *% 1000003 +% @as(u32, @truncate(@as(u64, @bitCast(ty))));
        cs = cs *% 1000003 +% @as(u32, @truncate(@as(u64, @bitCast(tz))));
    }
    std.debug.print("checksum {d}\n", .{cs});
}

// --- STREAM triad (memory write bandwidth) ----------------------------------
fn benchStream() !void {
    const N: usize = 16000000;
    const R: usize = 40;
    const K: u32 = 3;
    const alloc = std.heap.page_allocator;
    const a = try alloc.alloc(u32, N);
    const b = try alloc.alloc(u32, N);
    const c = try alloc.alloc(u32, N);
    defer alloc.free(a);
    defer alloc.free(b);
    defer alloc.free(c);
    var x: u32 = 11111;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        b[i] = x;
        x = x *% 1664525 +% 1013904223;
        c[i] = x;
    }
    for (0..R) |_| {
        for (0..N) |i| a[i] = b[i] +% K *% c[i];
    }
    var cs: u32 = 0;
    for (0..N) |i| cs = cs *% 1000003 +% a[i];
    std.debug.print("checksum {d}\n", .{cs});
}

// --- N-queens (backtracking recursion) --------------------------------------
fn nqSolve(cols: u32, d1: u32, d2: u32, full: u32) u64 {
    if (cols == full) return 1;
    var count: u64 = 0;
    var avail = ~(cols | d1 | d2) & full;
    while (avail != 0) {
        const bit = avail & (~avail +% 1);
        avail -%= bit;
        count += nqSolve(cols | bit, ((d1 | bit) *% 2) & full, (d2 | bit) / 2, full);
    }
    return count;
}

fn benchNqueens() void {
    const NQ = 14;
    const full: u32 = (1 << NQ) - 1;
    const total = nqSolve(0, 0, 0, full);
    std.debug.print("checksum {d}\n", .{total});
}

// --- Conway's Game of Life --------------------------------------------------
fn benchLife() !void {
    const W: usize = 1024;
    const H: usize = 1024;
    const T: usize = 300;
    const alloc = std.heap.page_allocator;
    var cur = try alloc.alloc(u8, W * H);
    var nxt = try alloc.alloc(u8, W * H);
    defer alloc.free(cur);
    defer alloc.free(nxt);
    var x: u32 = 22221;
    for (0..W * H) |i| {
        x = x *% 1664525 +% 1013904223;
        cur[i] = @intCast((x / 65536) & 1);
    }
    for (0..T) |_| {
        for (0..H) |y| {
            const ym = if (y == 0) H - 1 else y - 1;
            const yp = if (y == H - 1) 0 else y + 1;
            for (0..W) |xx| {
                const xm = if (xx == 0) W - 1 else xx - 1;
                const xp = if (xx == W - 1) 0 else xx + 1;
                const n = @as(i32, cur[ym * W + xm]) + @as(i32, cur[ym * W + xx]) + @as(i32, cur[ym * W + xp]) +
                    @as(i32, cur[y * W + xm]) + @as(i32, cur[y * W + xp]) +
                    @as(i32, cur[yp * W + xm]) + @as(i32, cur[yp * W + xx]) + @as(i32, cur[yp * W + xp]);
                const alive = cur[y * W + xx];
                nxt[y * W + xx] = if (n == 3 or (alive == 1 and n == 2)) 1 else 0;
            }
        }
        const tmp = cur;
        cur = nxt;
        nxt = tmp;
    }
    var cs: u32 = 0;
    for (0..W * H) |i| cs = cs *% 1000003 +% @as(u32, cur[i]);
    std.debug.print("checksum {d}\n", .{cs});
}

// --- open-addressing hash map (linear probing) ------------------------------
fn benchHashmap() !void {
    const M: usize = 8000000;
    const Q: usize = 16000000;
    const SIZE: usize = 1 << 24;
    const MASK: usize = SIZE - 1;
    const alloc = std.heap.page_allocator;
    const keys = try alloc.alloc(u32, SIZE);
    const vals = try alloc.alloc(u32, SIZE);
    defer alloc.free(keys);
    defer alloc.free(vals);
    @memset(keys, 0);
    @memset(vals, 0);
    var x: u32 = 33331;
    for (0..M) |_| {
        x = x *% 1664525 +% 1013904223;
        const key: u32 = (x & 0x7FFFFFFF) | 1;
        var idx: usize = @as(usize, key) & MASK;
        while (true) {
            if (keys[idx] == 0) {
                keys[idx] = key;
                vals[idx] = x;
                break;
            }
            if (keys[idx] == key) {
                vals[idx] +%= x;
                break;
            }
            idx = (idx + 1) & MASK;
        }
    }
    var y: u32 = 99989;
    var acc: u32 = 0;
    for (0..Q) |_| {
        y = y *% 1664525 +% 1013904223;
        const key: u32 = (y & 0x7FFFFFFF) | 1;
        var idx: usize = @as(usize, key) & MASK;
        var steps: u32 = 0;
        while (true) {
            steps += 1;
            if (keys[idx] == 0) break;
            if (keys[idx] == key) {
                acc +%= vals[idx];
                break;
            }
            idx = (idx + 1) & MASK;
        }
        acc = acc *% 1000003 +% steps;
    }
    std.debug.print("checksum {d}\n", .{acc});
}

// --- SHA-256 (32-bit crypto mixing) -----------------------------------------
const SHA_K = [_]u32{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

fn benchSha256() !void {
    const N: usize = 4000000;
    const R: usize = 16;
    const alloc = std.heap.page_allocator;
    const buf = try alloc.alloc(u8, N);
    defer alloc.free(buf);
    var x: u32 = 44441;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        buf[i] = @intCast((x / 256) & 0xFF);
    }
    var cs: u32 = 0;
    for (0..R) |_| {
        var h0: u32 = 0x6a09e667;
        var h1: u32 = 0xbb67ae85;
        var h2: u32 = 0x3c6ef372;
        var h3: u32 = 0xa54ff53a;
        var h4: u32 = 0x510e527f;
        var h5: u32 = 0x9b05688c;
        var h6: u32 = 0x1f83d9ab;
        var h7: u32 = 0x5be0cd19;
        const nblocks = N / 64;
        var w: [64]u32 = undefined;
        for (0..nblocks) |blk| {
            const base = blk * 64;
            for (0..16) |t| {
                const o = base + t * 4;
                w[t] = (@as(u32, buf[o]) << 24) | (@as(u32, buf[o + 1]) << 16) | (@as(u32, buf[o + 2]) << 8) | @as(u32, buf[o + 3]);
            }
            for (16..64) |t| {
                const s0 = std.math.rotr(u32, w[t - 15], 7) ^ std.math.rotr(u32, w[t - 15], 18) ^ (w[t - 15] >> 3);
                const s1 = std.math.rotr(u32, w[t - 2], 17) ^ std.math.rotr(u32, w[t - 2], 19) ^ (w[t - 2] >> 10);
                w[t] = w[t - 16] +% s0 +% w[t - 7] +% s1;
            }
            var a = h0;
            var b = h1;
            var c = h2;
            var d = h3;
            var e = h4;
            var f = h5;
            var g = h6;
            var hh = h7;
            for (0..64) |t| {
                const S1 = std.math.rotr(u32, e, 6) ^ std.math.rotr(u32, e, 11) ^ std.math.rotr(u32, e, 25);
                const ch = (e & f) ^ (~e & g);
                const t1 = hh +% S1 +% ch +% SHA_K[t] +% w[t];
                const S0 = std.math.rotr(u32, a, 2) ^ std.math.rotr(u32, a, 13) ^ std.math.rotr(u32, a, 22);
                const maj = (a & b) ^ (a & c) ^ (b & c);
                const t2 = S0 +% maj;
                hh = g;
                g = f;
                f = e;
                e = d +% t1;
                d = c;
                c = b;
                b = a;
                a = t1 +% t2;
            }
            h0 +%= a;
            h1 +%= b;
            h2 +%= c;
            h3 +%= d;
            h4 +%= e;
            h5 +%= f;
            h6 +%= g;
            h7 +%= hh;
        }
        cs = cs *% 1000003 +% (h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7);
    }
    std.debug.print("checksum {d}\n", .{cs});
}

// --- matrix transpose (cache stride / TLB) ----------------------------------
fn benchTranspose() !void {
    const NDIM: usize = 4096;
    const R: usize = 6;
    const alloc = std.heap.page_allocator;
    var src = try alloc.alloc(u32, NDIM * NDIM);
    var dst = try alloc.alloc(u32, NDIM * NDIM);
    defer alloc.free(src);
    defer alloc.free(dst);
    var x: u32 = 55551;
    for (0..NDIM * NDIM) |i| {
        x = x *% 1664525 +% 1013904223;
        src[i] = x;
    }
    for (0..R) |_| {
        for (0..NDIM) |i| {
            for (0..NDIM) |j| dst[j * NDIM + i] = src[i * NDIM + j];
        }
        const tmp = src;
        src = dst;
        dst = tmp;
    }
    var cs: u32 = 0;
    for (0..NDIM * NDIM) |i| cs = cs *% 1000003 +% src[i];
    std.debug.print("checksum {d}\n", .{cs});
}

// --- edit distance (dynamic programming) ------------------------------------
fn editMin3(a: i32, b: i32, c: i32) i32 {
    const m = if (a < b) a else b;
    return if (m < c) m else c;
}

fn benchEditdist() !void {
    const LA: usize = 16000;
    const LB: usize = 16000;
    const alloc = std.heap.page_allocator;
    const a = try alloc.alloc(u8, LA);
    const b = try alloc.alloc(u8, LB);
    var prev = try alloc.alloc(i32, LB + 1);
    var cur = try alloc.alloc(i32, LB + 1);
    defer alloc.free(a);
    defer alloc.free(b);
    defer alloc.free(prev);
    defer alloc.free(cur);
    var x: u32 = 66661;
    for (0..LA) |i| {
        x = x *% 1664525 +% 1013904223;
        a[i] = @intCast((x / 65536) % 4);
    }
    for (0..LB) |i| {
        x = x *% 1664525 +% 1013904223;
        b[i] = @intCast((x / 65536) % 4);
    }
    for (0..LB + 1) |j| prev[j] = @intCast(j);
    for (1..LA + 1) |i| {
        cur[0] = @intCast(i);
        for (1..LB + 1) |j| {
            const cost: i32 = if (a[i - 1] == b[j - 1]) 0 else 1;
            cur[j] = editMin3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        }
        const tmp = prev;
        prev = cur;
        cur = tmp;
    }
    std.debug.print("checksum {d}\n", .{@as(u32, @intCast(prev[LB]))});
}

// --- LZ77 greedy compressor -------------------------------------------------
fn benchLz() !void {
    const N: usize = 4000000;
    const WIN: usize = 512;
    const MAXLEN: usize = 64;
    const alloc = std.heap.page_allocator;
    const buf = try alloc.alloc(u8, N);
    defer alloc.free(buf);
    var x: u32 = 77771;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        buf[i] = @intCast((x / 65536) % 8);
    }
    var h: u32 = 2166136261;
    var p: usize = 0;
    while (p < N) {
        const lo = if (p > WIN) p - WIN else 0;
        var bestlen: usize = 0;
        var bestoff: usize = 0;
        var sidx = lo;
        while (sidx < p) : (sidx += 1) {
            var len: usize = 0;
            while (p + len < N and len < MAXLEN and buf[sidx + len] == buf[p + len]) len += 1;
            if (len > bestlen) {
                bestlen = len;
                bestoff = p - sidx;
            }
        }
        if (bestlen >= 3) {
            h ^= @as(u32, @intCast(bestoff & 0xFF));
            h *%= 16777619;
            h ^= @as(u32, @intCast((bestoff / 256) & 0xFF));
            h *%= 16777619;
            h ^= @as(u32, @intCast(bestlen & 0xFF));
            h *%= 16777619;
            p += bestlen;
        } else {
            h ^= @as(u32, buf[p]);
            h *%= 16777619;
            p += 1;
        }
    }
    std.debug.print("checksum {d}\n", .{h});
}

// --- CRC32 (table-driven hashing) -------------------------------------------
fn benchCrc32() !void {
    const N: usize = 16000000;
    const R: usize = 8;
    var table: [256]u32 = undefined;
    for (0..256) |i| {
        var c: u32 = @intCast(i);
        for (0..8) |_| c = if (c & 1 == 1) 0xEDB88320 ^ (c >> 1) else c >> 1;
        table[i] = c;
    }
    const alloc = std.heap.page_allocator;
    const buf = try alloc.alloc(u8, N);
    defer alloc.free(buf);
    var x: u32 = 88881;
    for (0..N) |i| {
        x = x *% 1664525 +% 1013904223;
        buf[i] = @intCast((x / 65536) & 0xFF);
    }
    var cs: u32 = 0;
    for (0..R) |_| {
        var crc: u32 = 0xFFFFFFFF;
        for (0..N) |i| crc = table[@as(usize, (crc ^ @as(u32, buf[i])) & 0xFF)] ^ (crc >> 8);
        crc ^= 0xFFFFFFFF;
        cs = cs *% 1000003 +% crc;
    }
    std.debug.print("checksum {d}\n", .{cs});
}

pub fn main(init: std.process.Init.Minimal) !void {
    var it = init.args.iterate();
    _ = it.skip(); // program name
    const name = it.next() orelse {
        std.debug.print("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>\n", .{});
        return;
    };
    if (std.mem.eql(u8, name, "fib")) return benchFib();
    if (std.mem.eql(u8, name, "mandelbrot")) return benchMandelbrot();
    if (std.mem.eql(u8, name, "matmul")) return benchMatmul();
    if (std.mem.eql(u8, name, "sieve")) return benchSieve();
    if (std.mem.eql(u8, name, "sort")) return benchSort();
    if (std.mem.eql(u8, name, "collatz")) return benchCollatz();
    if (std.mem.eql(u8, name, "raster")) return benchRaster();
    if (std.mem.eql(u8, name, "ptrchase")) return benchPtrchase();
    if (std.mem.eql(u8, name, "hash")) return benchHash();
    if (std.mem.eql(u8, name, "bst")) return benchBst();
    if (std.mem.eql(u8, name, "rle")) return benchRle();
    if (std.mem.eql(u8, name, "base64")) return benchBase64();
    if (std.mem.eql(u8, name, "dispatch")) return benchDispatch();
    if (std.mem.eql(u8, name, "nbody")) return benchNbody();
    if (std.mem.eql(u8, name, "stream")) return benchStream();
    if (std.mem.eql(u8, name, "nqueens")) return benchNqueens();
    if (std.mem.eql(u8, name, "life")) return benchLife();
    if (std.mem.eql(u8, name, "hashmap")) return benchHashmap();
    if (std.mem.eql(u8, name, "sha256")) return benchSha256();
    if (std.mem.eql(u8, name, "transpose")) return benchTranspose();
    if (std.mem.eql(u8, name, "editdist")) return benchEditdist();
    if (std.mem.eql(u8, name, "lz")) return benchLz();
    if (std.mem.eql(u8, name, "crc32")) return benchCrc32();
    std.debug.print("unknown benchmark: {s}\n", .{name});
}
