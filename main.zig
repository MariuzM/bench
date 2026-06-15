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
// Builds one big random permutation cycle, then chases next[p] for many hops.
// Each load depends on the previous one, so the prefetcher can't hide it: this
// measures memory *latency*, unlike the streaming `sieve`. Pure 32-bit integer.

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
// Hashes a byte buffer several times with 32-bit FNV-1a. Stresses the integer
// ALU (xor + wrapping multiply) and a tight sequential read; no SIMD to exploit.

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

// --- binary search tree (heap allocation + pointer chasing) -----------------
// Inserts M keys into a BST (one heap allocation per node, branchy descent),
// then runs Q lookups. Measures allocator/GC throughput plus pointer-chasing
// reads. Keys stay below 2^31 so signed/unsigned ordering agree everywhere.

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

// --- run-length encoding (branchy byte processing) --------------------------
// Builds a buffer of random runs, then RLE-encodes it several times, folding
// the (count,value) output into a 32-bit hash. Data-dependent branchy scan.

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

// --- base64 encoding (table lookup + bit shuffling) -------------------------
// Base64-encodes a byte buffer several times, folding the output characters
// into a 32-bit hash. Uses division (not >>) so every language agrees bit for
// bit. Stresses byte-level bit manipulation and a small gather/table lookup.

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
// Applies a stream of ops to an accumulator through a function-pointer table,
// one indirect call per element. Stresses indirect-branch prediction. All ops
// are 32-bit wrapping + ^ * - so the result is identical across languages.

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

pub fn main(init: std.process.Init.Minimal) !void {
    var it = init.args.iterate();
    _ = it.skip(); // program name
    const name = it.next() orelse {
        std.debug.print("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch>\n", .{});
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
    std.debug.print("unknown benchmark: {s}\n", .{name});
}
