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

fn main() {
    let name = match env::args().nth(1) {
        Some(n) => n,
        None => {
            println!("usage: main <fib|mandelbrot|matmul|sieve|sort>");
            return;
        }
    };
    match name.as_str() {
        "fib" => bench_fib(),
        "mandelbrot" => bench_mandelbrot(),
        "matmul" => bench_matmul(),
        "sieve" => bench_sieve(),
        "sort" => bench_sort(),
        _ => println!("unknown benchmark: {}", name),
    }
}
