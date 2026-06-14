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

pub fn main(init: std.process.Init.Minimal) !void {
    var it = init.args.iterate();
    _ = it.skip(); // program name
    const name = it.next() orelse {
        std.debug.print("usage: main <fib|mandelbrot|matmul|sieve|sort>\n", .{});
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
    } else {
        std.debug.print("unknown benchmark: {s}\n", .{name});
    }
}
