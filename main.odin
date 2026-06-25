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

// --- binary search tree -----------------------------------------------------

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

// --- run-length encoding ----------------------------------------------------

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

// --- base64 encoding --------------------------------------------------------

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

// --- n-body (dependent floating-point chains) -------------------------------
bench_nbody :: proc() {
	N :: 2048
	STEPS :: 8
	DT :: 0.01
	EPS :: 0.05
	px := make([]f64, N); defer delete(px)
	py := make([]f64, N); defer delete(py)
	pz := make([]f64, N); defer delete(pz)
	vx := make([]f64, N); defer delete(vx)
	vy := make([]f64, N); defer delete(vy)
	vz := make([]f64, N); defer delete(vz)
	m := make([]f64, N); defer delete(m)
	s: u32 = 7777
	for i := 0; i < N; i += 1 {
		s = s * 1664525 + 1013904223
		px[i] = (f64(s & 0xFFFF) / 65536.0) * 2.0 - 1.0
		s = s * 1664525 + 1013904223
		py[i] = (f64(s & 0xFFFF) / 65536.0) * 2.0 - 1.0
		s = s * 1664525 + 1013904223
		pz[i] = (f64(s & 0xFFFF) / 65536.0) * 2.0 - 1.0
		s = s * 1664525 + 1013904223
		m[i] = f64(s & 0xFFFF) / 65536.0 + 0.1
	}
	for step := 0; step < STEPS; step += 1 {
		for i := 0; i < N; i += 1 {
			ax, ay, az: f64 = 0, 0, 0
			xi, yi, zi := px[i], py[i], pz[i]
			for j := 0; j < N; j += 1 {
				if j == i do continue
				dx := px[j] - xi
				dy := py[j] - yi
				dz := pz[j] - zi
				d2 := dx * dx + dy * dy + dz * dz + EPS
				g := (d2 + 1.0) * 0.5
				for k := 0; k < 8; k += 1 do g = (g + d2 / g) * 0.5
				inv3 := 1.0 / (d2 * g)
				f := m[j] * inv3
				ax += dx * f
				ay += dy * f
				az += dz * f
			}
			vx[i] += ax * DT
			vy[i] += ay * DT
			vz[i] += az * DT
		}
		for i := 0; i < N; i += 1 {
			px[i] += vx[i] * DT
			py[i] += vy[i] * DT
			pz[i] += vz[i] * DT
		}
	}
	cs: u32 = 0
	for i := 0; i < N; i += 1 {
		cs = cs * 1000003 + u32(i64(px[i] * 1024.0))
		cs = cs * 1000003 + u32(i64(py[i] * 1024.0))
		cs = cs * 1000003 + u32(i64(pz[i] * 1024.0))
	}
	fmt.printf("checksum %d\n", cs)
}

// --- STREAM triad (memory write bandwidth) ----------------------------------
bench_stream :: proc() {
	N :: 16000000
	R :: 40
	K :: u32(3)
	a := make([]u32, N); defer delete(a)
	b := make([]u32, N); defer delete(b)
	c := make([]u32, N); defer delete(c)
	x: u32 = 11111
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		b[i] = x
		x = x * 1664525 + 1013904223
		c[i] = x
	}
	for r := 0; r < R; r += 1 {
		for i := 0; i < N; i += 1 do a[i] = b[i] + K * c[i]
	}
	cs: u32 = 0
	for i := 0; i < N; i += 1 do cs = cs * 1000003 + a[i]
	fmt.printf("checksum %d\n", cs)
}

// --- N-queens (backtracking recursion) --------------------------------------
nq_solve :: proc(cols, d1, d2, full: u32) -> u64 {
	if cols == full do return 1
	count: u64 = 0
	avail := ~(cols | d1 | d2) & full
	for avail != 0 {
		bit := avail & (~avail + 1)
		avail -= bit
		count += nq_solve(cols | bit, ((d1 | bit) * 2) & full, (d2 | bit) / 2, full)
	}
	return count
}

bench_nqueens :: proc() {
	NQ :: 14
	full: u32 = (1 << NQ) - 1
	total := nq_solve(0, 0, 0, full)
	fmt.printf("checksum %d\n", total)
}

// --- Conway's Game of Life --------------------------------------------------
bench_life :: proc() {
	W :: 1024
	H :: 1024
	T :: 300
	cur := make([]u8, W * H); defer delete(cur)
	nxt := make([]u8, W * H); defer delete(nxt)
	x: u32 = 22221
	for i := 0; i < W * H; i += 1 {
		x = x * 1664525 + 1013904223
		cur[i] = u8((x / 65536) & 1)
	}
	for gen := 0; gen < T; gen += 1 {
		for y := 0; y < H; y += 1 {
			ym := y == 0 ? H - 1 : y - 1
			yp := y == H - 1 ? 0 : y + 1
			for xx := 0; xx < W; xx += 1 {
				xm := xx == 0 ? W - 1 : xx - 1
				xp := xx == W - 1 ? 0 : xx + 1
				n := int(cur[ym * W + xm]) + int(cur[ym * W + xx]) + int(cur[ym * W + xp]) +
					int(cur[y * W + xm]) + int(cur[y * W + xp]) +
					int(cur[yp * W + xm]) + int(cur[yp * W + xx]) + int(cur[yp * W + xp])
				alive := cur[y * W + xx]
				nxt[y * W + xx] = (n == 3 || (alive == 1 && n == 2)) ? 1 : 0
			}
		}
		cur, nxt = nxt, cur
	}
	cs: u32 = 0
	for i := 0; i < W * H; i += 1 do cs = cs * 1000003 + u32(cur[i])
	fmt.printf("checksum %d\n", cs)
}

// --- open-addressing hash map (linear probing) ------------------------------
bench_hashmap :: proc() {
	M :: 8000000
	Q :: 16000000
	SIZE :: 1 << 24
	MASK :: u32(SIZE - 1)
	keys := make([]u32, SIZE); defer delete(keys)
	vals := make([]u32, SIZE); defer delete(vals)
	x: u32 = 33331
	for n := 0; n < M; n += 1 {
		x = x * 1664525 + 1013904223
		key := (x & 0x7FFFFFFF) | 1
		idx := key & MASK
		for {
			if keys[idx] == 0 {
				keys[idx] = key
				vals[idx] = x
				break
			}
			if keys[idx] == key {
				vals[idx] += x
				break
			}
			idx = (idx + 1) & MASK
		}
	}
	y: u32 = 99989
	acc: u32 = 0
	for q := 0; q < Q; q += 1 {
		y = y * 1664525 + 1013904223
		key := (y & 0x7FFFFFFF) | 1
		idx := key & MASK
		steps: u32 = 0
		for {
			steps += 1
			if keys[idx] == 0 do break
			if keys[idx] == key {
				acc += vals[idx]
				break
			}
			idx = (idx + 1) & MASK
		}
		acc = acc * 1000003 + steps
	}
	fmt.printf("checksum %d\n", acc)
}

// --- SHA-256 (32-bit crypto mixing) -----------------------------------------
rotr32 :: proc(x: u32, n: u32) -> u32 {
	return (x >> n) | (x << (32 - n))
}

bench_sha256 :: proc() {
	N :: 4000000
	R :: 16
	k := [64]u32{
		0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
		0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
		0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
		0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
		0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
		0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
		0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
		0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
	}
	buf := make([]u8, N); defer delete(buf)
	x: u32 = 44441
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		buf[i] = u8((x / 256) & 0xFF)
	}
	cs: u32 = 0
	for r := 0; r < R; r += 1 {
		h0: u32 = 0x6a09e667
		h1: u32 = 0xbb67ae85
		h2: u32 = 0x3c6ef372
		h3: u32 = 0xa54ff53a
		h4: u32 = 0x510e527f
		h5: u32 = 0x9b05688c
		h6: u32 = 0x1f83d9ab
		h7: u32 = 0x5be0cd19
		nblocks := N / 64
		w: [64]u32
		for blk := 0; blk < nblocks; blk += 1 {
			base := blk * 64
			for t := 0; t < 16; t += 1 {
				o := base + t * 4
				w[t] = (u32(buf[o]) << 24) | (u32(buf[o + 1]) << 16) | (u32(buf[o + 2]) << 8) | u32(buf[o + 3])
			}
			for t := 16; t < 64; t += 1 {
				s0 := rotr32(w[t - 15], 7) ~ rotr32(w[t - 15], 18) ~ (w[t - 15] >> 3)
				s1 := rotr32(w[t - 2], 17) ~ rotr32(w[t - 2], 19) ~ (w[t - 2] >> 10)
				w[t] = w[t - 16] + s0 + w[t - 7] + s1
			}
			a, b, c, d := h0, h1, h2, h3
			e, f, g, hh := h4, h5, h6, h7
			for t := 0; t < 64; t += 1 {
				S1 := rotr32(e, 6) ~ rotr32(e, 11) ~ rotr32(e, 25)
				ch := (e & f) ~ (~e & g)
				t1 := hh + S1 + ch + k[t] + w[t]
				S0 := rotr32(a, 2) ~ rotr32(a, 13) ~ rotr32(a, 22)
				maj := (a & b) ~ (a & c) ~ (b & c)
				t2 := S0 + maj
				hh = g
				g = f
				f = e
				e = d + t1
				d = c
				c = b
				b = a
				a = t1 + t2
			}
			h0 += a
			h1 += b
			h2 += c
			h3 += d
			h4 += e
			h5 += f
			h6 += g
			h7 += hh
		}
		cs = cs * 1000003 + (h0 ~ h1 ~ h2 ~ h3 ~ h4 ~ h5 ~ h6 ~ h7)
	}
	fmt.printf("checksum %d\n", cs)
}

// --- matrix transpose (cache stride / TLB) ----------------------------------
bench_transpose :: proc() {
	NDIM :: 4096
	R :: 6
	src := make([]u32, NDIM * NDIM); defer delete(src)
	dst := make([]u32, NDIM * NDIM); defer delete(dst)
	x: u32 = 55551
	for i := 0; i < NDIM * NDIM; i += 1 {
		x = x * 1664525 + 1013904223
		src[i] = x
	}
	for r := 0; r < R; r += 1 {
		for i := 0; i < NDIM; i += 1 {
			for j := 0; j < NDIM; j += 1 do dst[j * NDIM + i] = src[i * NDIM + j]
		}
		src, dst = dst, src
	}
	cs: u32 = 0
	for i := 0; i < NDIM * NDIM; i += 1 do cs = cs * 1000003 + src[i]
	fmt.printf("checksum %d\n", cs)
}

// --- edit distance (dynamic programming) ------------------------------------
edit_min3 :: proc(a, b, c: i32) -> i32 {
	m := a < b ? a : b
	return m < c ? m : c
}

bench_editdist :: proc() {
	LA :: 16000
	LB :: 16000
	a := make([]u8, LA); defer delete(a)
	b := make([]u8, LB); defer delete(b)
	prev := make([]i32, LB + 1); defer delete(prev)
	cur := make([]i32, LB + 1); defer delete(cur)
	x: u32 = 66661
	for i := 0; i < LA; i += 1 {
		x = x * 1664525 + 1013904223
		a[i] = u8((x / 65536) % 4)
	}
	for i := 0; i < LB; i += 1 {
		x = x * 1664525 + 1013904223
		b[i] = u8((x / 65536) % 4)
	}
	for j := 0; j <= LB; j += 1 do prev[j] = i32(j)
	for i := 1; i <= LA; i += 1 {
		cur[0] = i32(i)
		for j := 1; j <= LB; j += 1 {
			cost: i32 = a[i - 1] == b[j - 1] ? 0 : 1
			cur[j] = edit_min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		}
		prev, cur = cur, prev
	}
	fmt.printf("checksum %d\n", u32(prev[LB]))
}

// --- LZ77 greedy compressor -------------------------------------------------
bench_lz :: proc() {
	N :: 4000000
	WIN :: 512
	MAXLEN :: 64
	buf := make([]u8, N); defer delete(buf)
	x: u32 = 77771
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		buf[i] = u8((x / 65536) % 8)
	}
	h: u32 = 2166136261
	p := 0
	for p < N {
		lo := p > WIN ? p - WIN : 0
		bestlen := 0
		bestoff := 0
		for sidx := lo; sidx < p; sidx += 1 {
			length := 0
			for p + length < N && length < MAXLEN && buf[sidx + length] == buf[p + length] do length += 1
			if length > bestlen {
				bestlen = length
				bestoff = p - sidx
			}
		}
		if bestlen >= 3 {
			h ~= u32(bestoff & 0xFF)
			h *= 16777619
			h ~= u32((bestoff / 256) & 0xFF)
			h *= 16777619
			h ~= u32(bestlen & 0xFF)
			h *= 16777619
			p += bestlen
		} else {
			h ~= u32(buf[p])
			h *= 16777619
			p += 1
		}
	}
	fmt.printf("checksum %d\n", h)
}

// --- CRC32 (table-driven hashing) -------------------------------------------
bench_crc32 :: proc() {
	N :: 16000000
	R :: 8
	table: [256]u32
	for i := 0; i < 256; i += 1 {
		c := u32(i)
		for kk := 0; kk < 8; kk += 1 do c = (c & 1) == 1 ? 0xEDB88320 ~ (c >> 1) : (c >> 1)
		table[i] = c
	}
	buf := make([]u8, N); defer delete(buf)
	x: u32 = 88881
	for i := 0; i < N; i += 1 {
		x = x * 1664525 + 1013904223
		buf[i] = u8((x / 65536) & 0xFF)
	}
	cs: u32 = 0
	for r := 0; r < R; r += 1 {
		crc: u32 = 0xFFFFFFFF
		for i := 0; i < N; i += 1 do crc = table[(crc ~ u32(buf[i])) & 0xFF] ~ (crc >> 8)
		crc ~= 0xFFFFFFFF
		cs = cs * 1000003 + crc
	}
	fmt.printf("checksum %d\n", cs)
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>")
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
	case "nbody":
		bench_nbody()
	case "stream":
		bench_stream()
	case "nqueens":
		bench_nqueens()
	case "life":
		bench_life()
	case "hashmap":
		bench_hashmap()
	case "sha256":
		bench_sha256()
	case "transpose":
		bench_transpose()
	case "editdist":
		bench_editdist()
	case "lz":
		bench_lz()
	case "crc32":
		bench_crc32()
	case:
		fmt.printf("unknown benchmark: %s\n", name)
	}
}
