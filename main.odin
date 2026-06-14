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

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

r_floor :: proc(y: f64) -> f64 {
	f := f64(i64(y))
	if f > y do return f - 1.0
	return f
}

r_sin :: proc(xin: f64) -> f64 {
	TWO_PI :: 6.283185307179586
	k := r_floor(xin / TWO_PI + 0.5)
	x := xin - k * TWO_PI
	x2 := x * x
	p := -1.0 / 1307674368000.0
	p = 1.0 / 6227020800.0 + x2 * p
	p = -1.0 / 39916800.0 + x2 * p
	p = 1.0 / 362880.0 + x2 * p
	p = -1.0 / 5040.0 + x2 * p
	p = 1.0 / 120.0 + x2 * p
	p = -1.0 / 6.0 + x2 * p
	p = 1.0 + x2 * p
	return x * p
}

r_cos :: proc(x: f64) -> f64 {
	HALF_PI :: 1.5707963267948966
	return r_sin(x + HALF_PI)
}

edge :: proc(ax, ay, bx, by, cx, cy: f64) -> f64 {
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

bench_raster :: proc() {
	W :: 640
	H :: 480
	RINGS :: 24
	SECTORS :: 24
	FRAMES :: 240
	NV :: (RINGS + 1) * (SECTORS + 1)
	FOCAL :: 500.0
	CAM_DIST :: 3.0

	bx: [NV]f64
	by: [NV]f64
	bz: [NV]f64
	nv := 0
	for i := 0; i <= RINGS; i += 1 {
		theta := 3.141592653589793 * (f64(i) / f64(RINGS))
		st := r_sin(theta)
		ct := r_cos(theta)
		for j := 0; j <= SECTORS; j += 1 {
			phi := 6.283185307179586 * (f64(j) / f64(SECTORS))
			sp := r_sin(phi)
			cp := r_cos(phi)
			bx[nv] = st * cp
			by[nv] = ct
			bz[nv] = st * sp
			nv += 1
		}
	}

	sx: [NV]f64
	sy: [NV]f64
	sz: [NV]f64
	si: [NV]f64

	color := make([]u8, W * H)
	zbuf := make([]f64, W * H)
	defer delete(color)
	defer delete(zbuf)

	checksum: u64 = 0

	for f := 0; f < FRAMES; f += 1 {
		ang := f64(f) * 0.0125
		cy := r_cos(ang)
		syr := r_sin(ang)
		axx := ang * 0.5
		cx := r_cos(axx)
		sxr := r_sin(axx)

		for v := 0; v < nv; v += 1 {
			px0 := bx[v]
			py0 := by[v]
			pz0 := bz[v]
			rx := px0 * cy + pz0 * syr
			rz := -px0 * syr + pz0 * cy
			ry := py0
			ry2 := ry * cx - rz * sxr
			rz2 := ry * sxr + rz * cx
			inten := -rz2
			if inten < 0.0 do inten = 0.0
			zc := rz2 + CAM_DIST
			invz := 1.0 / zc
			sx[v] = rx * invz * FOCAL + f64(W) * 0.5
			sy[v] = ry2 * invz * FOCAL + f64(H) * 0.5
			sz[v] = zc
			si[v] = inten
		}

		for c := 0; c < W * H; c += 1 {
			color[c] = 0
			zbuf[c] = 1.0e30
		}

		for ri := 0; ri < RINGS; ri += 1 {
			for sj := 0; sj < SECTORS; sj += 1 {
				a := ri * (SECTORS + 1) + sj
				b := a + (SECTORS + 1)
				tris := [2][3]int{{a, b, a + 1}, {a + 1, b, b + 1}}
				for t := 0; t < 2; t += 1 {
					i0 := tris[t][0]
					i1 := tris[t][1]
					i2 := tris[t][2]
					area := edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2])
					if area <= 0.0 do continue
					mnx := sx[i0]
					if sx[i1] < mnx do mnx = sx[i1]
					if sx[i2] < mnx do mnx = sx[i2]
					mxx := sx[i0]
					if sx[i1] > mxx do mxx = sx[i1]
					if sx[i2] > mxx do mxx = sx[i2]
					mny := sy[i0]
					if sy[i1] < mny do mny = sy[i1]
					if sy[i2] < mny do mny = sy[i2]
					mxy := sy[i0]
					if sy[i1] > mxy do mxy = sy[i1]
					if sy[i2] > mxy do mxy = sy[i2]
					if mnx < 0.0 do mnx = 0.0
					if mxx > f64(W - 1) do mxx = f64(W - 1)
					if mny < 0.0 do mny = 0.0
					if mxy > f64(H - 1) do mxy = f64(H - 1)
					x0 := int(mnx)
					x1 := int(mxx)
					y0 := int(mny)
					y1 := int(mxy)
					for py := y0; py <= y1; py += 1 {
						pcy := f64(py) + 0.5
						for px := x0; px <= x1; px += 1 {
							pcx := f64(px) + 0.5
							w0 := edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy)
							w1 := edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy)
							w2 := edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy)
							if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
								l0 := w0 / area
								l1 := w1 / area
								l2 := w2 / area
								depth := l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2]
								idx := py * W + px
								if depth < zbuf[idx] {
									zbuf[idx] = depth
									inten := l0 * si[i0] + l1 * si[i1] + l2 * si[i2]
									if inten < 0.0 do inten = 0.0
									if inten > 1.0 do inten = 1.0
									color[idx] = u8(inten * 255.0)
								}
							}
						}
					}
				}
			}
		}

		frame_sum: u64 = 0
		for c := 0; c < W * H; c += 1 {
			frame_sum += u64(color[c])
		}
		checksum = checksum * 1000003 + frame_sum
	}

	fmt.printf("checksum %d\n", checksum)
}

bench_collatz :: proc() {
	N :: 3_000_000
	total: u64 = 0
	for i: u64 = 1; i <= N; i += 1 {
		n := i
		steps: u64 = 0
		for n != 1 {
			if n % 2 == 0 {
				n = n / 2
			} else {
				n = 3 * n + 1
			}
			steps += 1
		}
		total += steps
	}
	fmt.printf("checksum %d\n", total)
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>")
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
	case "collatz":
		bench_collatz()
	case "raster":
		bench_raster()
	case:
		fmt.printf("unknown benchmark: %s\n", name)
	}
}
