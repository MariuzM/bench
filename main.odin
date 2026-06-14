package main

// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by the
// command-line argument, so the build script can measure each one's wall-time
// and peak memory in isolation. Every benchmark prints a single "checksum <n>"
// line; all language builds must agree on it, which proves they did the same
// work. Odin integer arithmetic wraps (two's complement), matching the Zig
// build's explicit wrapping operators.
// ---------------------------------------------------------------------------

import "core:fmt"
import "core:os"

fib :: proc(n: u64) -> u64 {
	if n < 2 do return n
	return fib(n - 1) + fib(n - 2)
}

bench_fib :: proc() {
	total: u64 = 0
	n: u64 = 30
	for n <= 42 {
		total += fib(n)
		n += 1
	}
	fmt.printf("checksum %d\n", total)
}

bench_mandelbrot :: proc() {
	W :: 1200
	H :: 1200
	MAX_IT :: 1000
	sum: u64 = 0
	for py := 0; py < H; py += 1 {
		y0 := (f64(py) / f64(H)) * 4.0 - 2.0
		for px := 0; px < W; px += 1 {
			x0 := (f64(px) / f64(W)) * 4.0 - 2.5
			x: f64 = 0
			y: f64 = 0
			it: u64 = 0
			for x * x + y * y <= 4.0 && it < MAX_IT {
				xt := x * x - y * y + x0
				y = 2.0 * x * y + y0
				x = xt
				it += 1
			}
			sum += it
		}
	}
	fmt.printf("checksum %d\n", sum)
}

bench_matmul :: proc() {
	N :: 512
	a := make([]i64, N * N)
	b := make([]i64, N * N)
	c := make([]i64, N * N)
	defer delete(a)
	defer delete(b)
	defer delete(c)

	for i := 0; i < N; i += 1 {
		for j := 0; j < N; j += 1 {
			a[i * N + j] = i64((i * j) % 7) - 3
			b[i * N + j] = i64((i + j) % 5) - 2
			c[i * N + j] = 0
		}
	}

	for i := 0; i < N; i += 1 {
		for k := 0; k < N; k += 1 {
			aik := a[i * N + k]
			for j := 0; j < N; j += 1 {
				c[i * N + j] += aik * b[k * N + j]
			}
		}
	}

	sum: i64 = 0
	for i := 0; i < N * N; i += 1 {
		sum += c[i]
	}
	fmt.printf("checksum %d\n", sum)
}

bench_sieve :: proc() {
	N :: 50_000_000
	sieve := make([]u8, N)
	defer delete(sieve)
	for i := 0; i < N; i += 1 do sieve[i] = 1
	sieve[0] = 0
	sieve[1] = 0

	for i := 2; i * i < N; i += 1 {
		if sieve[i] == 1 {
			for j := i * i; j < N; j += i {
				sieve[j] = 0
			}
		}
	}

	count: u64 = 0
	for i := 0; i < N; i += 1 {
		count += u64(sieve[i])
	}
	fmt.printf("checksum %d\n", count)
}

quicksort :: proc(arr: []u64, lo: int, hi: int) {
	if lo >= hi do return
	pivot := arr[(lo + hi) / 2]
	i := lo
	j := hi
	for i <= j {
		for arr[i] < pivot do i += 1
		for arr[j] > pivot do j -= 1
		if i <= j {
			t := arr[i]
			arr[i] = arr[j]
			arr[j] = t
			i += 1
			j -= 1
		}
	}
	quicksort(arr, lo, j)
	quicksort(arr, i, hi)
}

bench_sort :: proc() {
	N :: 3_000_000
	arr := make([]u64, N)
	defer delete(arr)

	state: u64 = 88172645463325252
	for i := 0; i < N; i += 1 {
		state = state * 6364136223846793005 + 1442695040888963407
		arr[i] = state & 0x7FFFFFFFFFFFFFFF
	}

	quicksort(arr, 0, N - 1)

	cs: u64 = 0
	for i := 0; i < N; i += 1 {
		cs = cs * 1000003 + arr[i]
	}
	fmt.printf("checksum %d\n", cs)
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usage: main <fib|mandelbrot|matmul|sieve|sort>")
		return
	}
	name := os.args[1]
	switch name {
	case "fib":
		bench_fib()
	case "mandelbrot":
		bench_mandelbrot()
	case "matmul":
		bench_matmul()
	case "sieve":
		bench_sieve()
	case "sort":
		bench_sort()
	case:
		fmt.printf("unknown benchmark: %s\n", name)
	}
}
