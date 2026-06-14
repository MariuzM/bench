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
    while (n <= 42) : (n += 1) {
        total +%= fib(n);
    }
    std.debug.print("checksum {d}\n", .{total});
}

fn benchMandelbrot() void {
    const W: usize = 1200;
    const H: usize = 1200;
    const MAX_IT: u64 = 1000;
    var sum: u64 = 0;
    var py: usize = 0;
    while (py < H) : (py += 1) {
        const y0 = (@as(f64, @floatFromInt(py)) / @as(f64, H)) * 4.0 - 2.0;
        var px: usize = 0;
        while (px < W) : (px += 1) {
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

    var i: usize = 0;
    while (i < N) : (i += 1) {
        var j: usize = 0;
        while (j < N) : (j += 1) {
            a[i * N + j] = @as(i64, @intCast((i * j) % 7)) - 3;
            b[i * N + j] = @as(i64, @intCast((i + j) % 5)) - 2;
            c[i * N + j] = 0;
        }
    }

    i = 0;
    while (i < N) : (i += 1) {
        var k: usize = 0;
        while (k < N) : (k += 1) {
            const aik = a[i * N + k];
            var j: usize = 0;
            while (j < N) : (j += 1) {
                c[i * N + j] += aik * b[k * N + j];
            }
        }
    }

    var sum: i64 = 0;
    i = 0;
    while (i < N * N) : (i += 1) {
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
            while (j < N) : (j += i) {
                sieve[j] = 0;
            }
        }
    }

    var count: u64 = 0;
    i = 0;
    while (i < N) : (i += 1) {
        count += sieve[i];
    }
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
    var i: usize = 0;
    while (i < N) : (i += 1) {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        arr[i] = state & 0x7FFFFFFFFFFFFFFF;
    }

    quicksort(arr, 0, @as(isize, N) - 1);

    var cs: u64 = 0;
    i = 0;
    while (i < N) : (i += 1) {
        cs = cs *% 1000003 +% arr[i];
    }
    std.debug.print("checksum {d}\n", .{cs});
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

fn rFloor(y: f64) f64 {
    const f: f64 = @floatFromInt(@as(i64, @intFromFloat(y)));
    if (f > y) return f - 1.0;
    return f;
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
    var i: usize = 0;
    while (i <= RINGS) : (i += 1) {
        const theta = 3.141592653589793 * (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(RINGS)));
        const st = rSin(theta);
        const ct = rCos(theta);
        var j: usize = 0;
        while (j <= SECTORS) : (j += 1) {
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

    var f: usize = 0;
    while (f < FRAMES) : (f += 1) {
        const ang = @as(f64, @floatFromInt(f)) * 0.0125;
        const cy = rCos(ang);
        const syr = rSin(ang);
        const axx = ang * 0.5;
        const cx = rCos(axx);
        const sxr = rSin(axx);

        var v: usize = 0;
        while (v < nv) : (v += 1) {
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

        var c: usize = 0;
        while (c < W * H) : (c += 1) {
            color[c] = 0;
            zbuf[c] = 1.0e30;
        }

        var ri: usize = 0;
        while (ri < RINGS) : (ri += 1) {
            var sj: usize = 0;
            while (sj < SECTORS) : (sj += 1) {
                const a = ri * (SECTORS + 1) + sj;
                const b = a + (SECTORS + 1);
                const tris = [2][3]usize{ .{ a, b, a + 1 }, .{ a + 1, b, b + 1 } };
                var t: usize = 0;
                while (t < 2) : (t += 1) {
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
                    var py: usize = y0;
                    while (py <= y1) : (py += 1) {
                        const pcy = @as(f64, @floatFromInt(py)) + 0.5;
                        var px: usize = x0;
                        while (px <= x1) : (px += 1) {
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
        var p: usize = 0;
        while (p < W * H) : (p += 1) {
            frame_sum +%= color[p];
        }
        checksum = checksum *% 1000003 +% frame_sum;
    }

    std.debug.print("checksum {d}\n", .{checksum});
}

fn benchCollatz() void {
    const N: u64 = 3_000_000;
    var total: u64 = 0;
    var i: u64 = 1;
    while (i <= N) : (i += 1) {
        var n: u64 = i;
        var steps: u64 = 0;
        while (n != 1) {
            if (n % 2 == 0) {
                n = n / 2;
            } else {
                n = 3 * n + 1;
            }
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
        std.debug.print("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>\n", .{});
        return;
    };
    if (std.mem.eql(u8, name, "fib")) {
        benchFib();
    } else if (std.mem.eql(u8, name, "mandelbrot")) {
        benchMandelbrot();
    } else if (std.mem.eql(u8, name, "matmul")) {
        try benchMatmul();
    } else if (std.mem.eql(u8, name, "sieve")) {
        try benchSieve();
    } else if (std.mem.eql(u8, name, "sort")) {
        try benchSort();
    } else if (std.mem.eql(u8, name, "collatz")) {
        benchCollatz();
    } else if (std.mem.eql(u8, name, "raster")) {
        try benchRaster();
    } else {
        std.debug.print("unknown benchmark: {s}\n", .{name});
    }
}
