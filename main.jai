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
        print("usage: main <fib|mandelbrot|matmul|sieve|sort>\n");
        return;
    }
    name := args[1];
    if streq(name, "fib")              bench_fib();
    else if streq(name, "mandelbrot")  bench_mandelbrot();
    else if streq(name, "matmul")      bench_matmul();
    else if streq(name, "sieve")       bench_sieve();
    else if streq(name, "sort")        bench_sort();
    else print("unknown benchmark: %\n", name);
}
