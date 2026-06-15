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
	for n: u64 = 30; n <= 42; n += 1 do total += fib(n)
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
			x, y: f64 = 0, 0
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
	for i := 0; i < N * N; i += 1 do sum += c[i]
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
			for j := i * i; j < N; j += i do sieve[j] = 0
		}
	}

	count: u64 = 0
	for i := 0; i < N; i += 1 do count += u64(sieve[i])
	fmt.printf("checksum %d\n", count)
}

quicksort :: proc(arr: []u64, lo: int, hi: int) {
	if lo >= hi do return
	pivot := arr[(lo + hi) / 2]
	i, j := lo, hi
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
	for i := 0; i < N; i += 1 do cs = cs * 1000003 + arr[i]
	fmt.printf("checksum %d\n", cs)
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

r_floor :: proc(y: f64) -> f64 {
	f := f64(i64(y))
	return f > y ? f - 1.0 : f
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
			px0, py0, pz0 := bx[v], by[v], bz[v]
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

		for c := 0; c < W * H; c += 1 {color[c] = 0; zbuf[c] = 1.0e30}

		for ri := 0; ri < RINGS; ri += 1 {
			for sj := 0; sj < SECTORS; sj += 1 {
				a := ri * (SECTORS + 1) + sj
				b := a + (SECTORS + 1)
				tris := [2][3]int{{a, b, a + 1}, {a + 1, b, b + 1}}
				for t := 0; t < 2; t += 1 {
					i0, i1, i2 := tris[t][0], tris[t][1], tris[t][2]
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
					x0, x1, y0, y1 := int(mnx), int(mxx), int(mny), int(mxy)
					for py := y0; py <= y1; py += 1 {
						pcy := f64(py) + 0.5
						for px := x0; px <= x1; px += 1 {
							pcx := f64(px) + 0.5
							w0 := edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy)
							w1 := edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy)
							w2 := edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy)
							if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
								l0, l1, l2 := w0 / area, w1 / area, w2 / area
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
		for c := 0; c < W * H; c += 1 do frame_sum += u64(color[c])
		checksum = checksum * 1000003 + frame_sum
	}

	fmt.printf("checksum %d\n", checksum)
}

// --- pointer-chasing (random memory latency) --------------------------------
// Builds one big random permutation cycle, then chases next[p] for many hops.
// Each load depends on the previous one, so the prefetcher can't hide it: this
// measures memory *latency*, unlike the streaming `sieve`. Pure 32-bit integer.

bench_ptrchase :: proc() {
	N :: 16000000
	HOPS :: 4000000
	order := make([]u32, N)
	next := make([]u32, N)
	defer delete(order)
	defer delete(next)
	for i := 0; i < N; i += 1 do order[i] = u32(i)
	x: u32 = 1
	for i := N - 1; i >= 1; i -= 1 {
		x = x * 1664525 + 1013904223
		j := int((x & 0x7FFFFFFF) % (u32(i) + 1))
		t := order[i]
		order[i] = order[j]
		order[j] = t
	}
	for k := 0; k < N; k += 1 do next[int(order[k])] = order[(k + 1) % N]
	sum, p: u32 = 0, 0
	for h := 0; h < HOPS; h += 1 {
		p = next[int(p)]
		sum += p
	}
	fmt.printf("checksum %d\n", sum)
}

// --- FNV-1a hash ------------------------------------------------------------
// Hashes a byte buffer several times with 32-bit FNV-1a. Stresses the integer
// ALU (xor + wrapping multiply) and a tight sequential read; no SIMD to exploit.

bench_hash :: proc() {
	N :: 32000000
	R :: 4
	buf := make([]u8, N)
	defer delete(buf)
	x: u32 = 12345
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		buf[i] = u8(x & 0xFF)
	}
	h: u32 = 2166136261
	for r := 0; r < R; r += 1 {
		for i := 0; i < N; i += 1 {
			h ~= u32(buf[i])
			h *= 16777619
		}
	}
	fmt.printf("checksum %d\n", h)
}

// --- binary search tree (heap allocation + pointer chasing) -----------------
// Inserts M keys into a BST (one heap allocation per node, branchy descent),
// then runs Q lookups. Measures allocator/GC throughput plus pointer-chasing
// reads. Keys stay below 2^31 so signed/unsigned ordering agree everywhere.

BstNode :: struct {
	key:   u32,
	left:  ^BstNode,
	right: ^BstNode,
}

bench_bst :: proc() {
	M :: 1000000
	Q :: 1000000
	root: ^BstNode = nil
	x: u32 = 22222
	for n := 0; n < M; n += 1 {
		x = x * 1664525 + 1013904223
		key := x & 0x7FFFFFFF
		nn := new(BstNode)
		nn.key = key
		if root == nil {
			root = nn
			continue
		}
		cur := root
		for {
			if key < cur.key {
				if cur.left == nil {cur.left = nn; break}
				cur = cur.left
			} else {
				if cur.right == nil {cur.right = nn; break}
				cur = cur.right
			}
		}
	}
	y: u32 = 99991
	cs: u32 = 0
	for q := 0; q < Q; q += 1 {
		y = y * 1664525 + 1013904223
		key := y & 0x7FFFFFFF
		steps: u32 = 0
		cur := root
		for cur != nil {
			steps += 1
			if key == cur.key do break
			if key < cur.key do cur = cur.left
			else do cur = cur.right
		}
		cs = cs * 1000003 + steps
	}
	fmt.printf("checksum %d\n", cs)
}

// --- run-length encoding (branchy byte processing) --------------------------
// Builds a buffer of random runs, then RLE-encodes it several times, folding
// the (count,value) output into a 32-bit hash. Data-dependent branchy scan.

bench_rle :: proc() {
	N :: 40000000
	R :: 4
	buf := make([]u8, N)
	out := make([]u8, 2 * N)
	defer delete(buf)
	defer delete(out)
	x: u32 = 33333
	i := 0
	for i < N {
		x = x * 1664525 + 1013904223
		v := u8(x & 0xFF)
		rl := ((x & 0x7FFFFFFF) % 16) + 1
		c: u32 = 0
		for c < rl && i < N {
			buf[i] = v
			i += 1
			c += 1
		}
	}
	h: u32 = 2166136261
	for r := 0; r < R; r += 1 {
		o, p := 0, 0
		for p < N {
			v := buf[p]
			run := 1
			for p + run < N && buf[p + run] == v && run < 255 do run += 1
			out[o] = u8(run)
			out[o + 1] = v
			o += 2
			p += run
		}
		for k := 0; k < o; k += 1 {h ~= u32(out[k]); h *= 16777619}
		h ~= u32(o % 256); h *= 16777619
		h ~= u32((o / 256) % 256); h *= 16777619
		h ~= u32((o / 65536) % 256); h *= 16777619
		h ~= u32((o / 16777216) % 256); h *= 16777619
	}
	fmt.printf("checksum %d\n", h)
}

// --- base64 encoding (table lookup + bit shuffling) -------------------------
// Base64-encodes a byte buffer several times, folding the output characters
// into a 32-bit hash. Uses division (not >>) so every language agrees bit for
// bit. Stresses byte-level bit manipulation and a small gather/table lookup.

bench_base64 :: proc() {
	N :: 24000000
	R :: 4
	b64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	buf := make([]u8, N)
	defer delete(buf)
	x: u32 = 44444
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		buf[i] = u8(x & 0xFF)
	}
	h: u32 = 2166136261
	for r := 0; r < R; r += 1 {
		for i := 0; i + 2 < N; i += 3 {
			b0, b1, b2 := u32(buf[i]), u32(buf[i + 1]), u32(buf[i + 2])
			i0 := b0 / 4
			i1 := (b0 & 3) * 16 + b1 / 16
			i2 := (b1 & 15) * 4 + b2 / 64
			i3 := b2 & 63
			h ~= u32(b64[int(i0)]); h *= 16777619
			h ~= u32(b64[int(i1)]); h *= 16777619
			h ~= u32(b64[int(i2)]); h *= 16777619
			h ~= u32(b64[int(i3)]); h *= 16777619
		}
	}
	fmt.printf("checksum %d\n", h)
}

// --- indirect dispatch ------------------------------------------------------
// Applies a stream of ops to an accumulator through a proc-pointer table, one
// indirect call per element. Stresses indirect-branch prediction. All ops are
// 32-bit wrapping + ^ * - so the result is identical across languages.

op_add :: proc(a, b: u32) -> u32 {return a + b}
op_xor :: proc(a, b: u32) -> u32 {return a ~ b}
op_mul :: proc(a, b: u32) -> u32 {return a * (b | 1)}
op_sub :: proc(a, b: u32) -> u32 {return a - b}

bench_dispatch :: proc() {
	N :: 4000000
	R :: 32
	code := make([]u8, N)
	operand := make([]u32, N)
	defer delete(code)
	defer delete(operand)
	x: u32 = 55555
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		code[i] = u8((x & 0x7FFFFFFF) % 4)
		operand[i] = x
	}
	fns := [4]proc(_: u32, _: u32) -> u32{op_add, op_xor, op_mul, op_sub}
	acc: u32 = 2166136261
	for r := 0; r < R; r += 1 {
		for i := 0; i < N; i += 1 do acc = fns[int(code[i])](acc, operand[i])
	}
	fmt.printf("checksum %d\n", acc)
}

bench_collatz :: proc() {
	N :: 3_000_000
	total: u64 = 0
	for i: u64 = 1; i <= N; i += 1 {
		n := i
		steps: u64 = 0
		for n != 1 {
			n = n % 2 == 0 ? n / 2 : 3 * n + 1
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
	case "ptrchase":
		bench_ptrchase()
	case "hash":
		bench_hash()
	case "bst":
		bench_bst()
	case "rle":
		bench_rle()
	case "base64":
		bench_base64()
	case "dispatch":
		bench_dispatch()
	case:
		fmt.printf("unknown benchmark: %s\n", name)
	}
}
