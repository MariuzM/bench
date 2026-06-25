// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by argv[1],
// so the build script can measure each one's wall-time and peak memory in
// isolation. Every benchmark prints a single "checksum <n>" line; all language
// builds must agree on it, which proves they did the same work.
// ---------------------------------------------------------------------------

#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

static uint64_t fib(uint64_t n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

static void bench_fib() {
    uint64_t total = 0;
    for (uint64_t n = 30; n <= 42; n++) {
        total += fib(n);
    }
    std::cout << "checksum " << total << "\n";
}

static void bench_mandelbrot() {
    const std::size_t W = 1200;
    const std::size_t H = 1200;
    const uint64_t MAX_IT = 1000;
    uint64_t sum = 0;
    for (std::size_t py = 0; py < H; py++) {
        double y0 = (static_cast<double>(py) / static_cast<double>(H)) * 4.0 - 2.0;
        for (std::size_t px = 0; px < W; px++) {
            double x0 = (static_cast<double>(px) / static_cast<double>(W)) * 4.0 - 2.5;
            double x = 0.0, y = 0.0;
            uint64_t it = 0;
            while (x * x + y * y <= 4.0 && it < MAX_IT) {
                double xt = x * x - y * y + x0;
                y = 2.0 * x * y + y0;
                x = xt;
                it += 1;
            }
            sum += it;
        }
    }
    std::cout << "checksum " << sum << "\n";
}

static void bench_matmul() {
    const std::size_t N = 512;
    std::vector<int64_t> a(N * N);
    std::vector<int64_t> b(N * N);
    std::vector<int64_t> c(N * N);

    for (std::size_t i = 0; i < N; i++) {
        for (std::size_t j = 0; j < N; j++) {
            a[i * N + j] = static_cast<int64_t>((i * j) % 7) - 3;
            b[i * N + j] = static_cast<int64_t>((i + j) % 5) - 2;
            c[i * N + j] = 0;
        }
    }

    for (std::size_t i = 0; i < N; i++) {
        for (std::size_t k = 0; k < N; k++) {
            int64_t aik = a[i * N + k];
            for (std::size_t j = 0; j < N; j++) {
                c[i * N + j] += aik * b[k * N + j];
            }
        }
    }

    int64_t sum = 0;
    for (std::size_t i = 0; i < N * N; i++) sum += c[i];
    std::cout << "checksum " << sum << "\n";
}

static void bench_sieve() {
    const std::size_t N = 50000000;
    std::vector<uint8_t> sieve(N, 1);
    sieve[0] = sieve[1] = 0;

    for (std::size_t i = 2; i * i < N; i++)
        if (sieve[i] == 1)
            for (std::size_t j = i * i; j < N; j += i) sieve[j] = 0;

    uint64_t count = 0;
    for (std::size_t i = 0; i < N; i++) count += sieve[i];
    std::cout << "checksum " << count << "\n";
}

static void quicksort(std::vector<uint64_t> &arr, int64_t lo, int64_t hi) {
    if (lo >= hi) return;
    uint64_t pivot = arr[(lo + hi) / 2];
    int64_t i = lo, j = hi;
    while (i <= j) {
        while (arr[i] < pivot) i += 1;
        while (arr[j] > pivot) j -= 1;
        if (i <= j) {
            std::swap(arr[i], arr[j]);
            i += 1;
            j -= 1;
        }
    }
    quicksort(arr, lo, j);
    quicksort(arr, i, hi);
}

static void bench_sort() {
    const std::size_t N = 3000000;
    std::vector<uint64_t> arr(N);

    uint64_t state = 88172645463325252ULL;
    for (std::size_t i = 0; i < N; i++) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        arr[i] = state & 0x7FFFFFFFFFFFFFFFULL;
    }

    quicksort(arr, 0, static_cast<int64_t>(N) - 1);

    uint64_t cs = 0;
    for (std::size_t i = 0; i < N; i++) {
        cs = cs * 1000003ULL + arr[i];
    }
    std::cout << "checksum " << cs << "\n";
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

static const int RASTER_W = 640;
static const int RASTER_H = 480;
static const int RASTER_RINGS = 24;
static const int RASTER_SECTORS = 24;
static const int RASTER_FRAMES = 240;
static const int RASTER_NV = (RASTER_RINGS + 1) * (RASTER_SECTORS + 1);

static double r_floor(double y) {
    double f = static_cast<double>(static_cast<int64_t>(y));
    return f > y ? f - 1.0 : f;
}

static double r_sin(double x) {
    const double TWO_PI = 6.283185307179586;
    double k = r_floor(x / TWO_PI + 0.5);
    x = x - k * TWO_PI;
    double x2 = x * x;
    double p = -1.0 / 1307674368000.0;
    p = 1.0 / 6227020800.0 + x2 * p;
    p = -1.0 / 39916800.0 + x2 * p;
    p = 1.0 / 362880.0 + x2 * p;
    p = -1.0 / 5040.0 + x2 * p;
    p = 1.0 / 120.0 + x2 * p;
    p = -1.0 / 6.0 + x2 * p;
    p = 1.0 + x2 * p;
    return x * p;
}

static double r_cos(double x) {
    const double HALF_PI = 1.5707963267948966;
    return r_sin(x + HALF_PI);
}

static double edge(double ax, double ay, double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

static void bench_raster() {
    const double FOCAL = 500.0;
    const double CAM_DIST = 3.0;

    std::vector<double> bx(RASTER_NV), by(RASTER_NV), bz(RASTER_NV);
    int nv = 0;
    for (int i = 0; i <= RASTER_RINGS; i++) {
        double theta = 3.141592653589793 * (static_cast<double>(i) / static_cast<double>(RASTER_RINGS));
        double st = r_sin(theta);
        double ct = r_cos(theta);
        for (int j = 0; j <= RASTER_SECTORS; j++) {
            double phi = 6.283185307179586 * (static_cast<double>(j) / static_cast<double>(RASTER_SECTORS));
            double sp = r_sin(phi);
            double cp = r_cos(phi);
            bx[nv] = st * cp;
            by[nv] = ct;
            bz[nv] = st * sp;
            nv += 1;
        }
    }

    std::vector<double> sx(RASTER_NV), sy(RASTER_NV), sz(RASTER_NV), si(RASTER_NV);

    std::vector<uint8_t> color(RASTER_W * RASTER_H);
    std::vector<double> zbuf(RASTER_W * RASTER_H);

    uint64_t checksum = 0;

    for (int f = 0; f < RASTER_FRAMES; f++) {
        double ang = static_cast<double>(f) * 0.0125;
        double cy = r_cos(ang);
        double syr = r_sin(ang);
        double axx = ang * 0.5;
        double cx = r_cos(axx);
        double sxr = r_sin(axx);

        for (int v = 0; v < nv; v++) {
            double px0 = bx[v], py0 = by[v], pz0 = bz[v];
            double rx = px0 * cy + pz0 * syr;
            double rz = -px0 * syr + pz0 * cy;
            double ry = py0;
            double ry2 = ry * cx - rz * sxr;
            double rz2 = ry * sxr + rz * cx;
            double inten = -rz2;
            if (inten < 0.0) inten = 0.0;
            double zc = rz2 + CAM_DIST;
            double invz = 1.0 / zc;
            sx[v] = rx * invz * FOCAL + static_cast<double>(RASTER_W) * 0.5;
            sy[v] = ry2 * invz * FOCAL + static_cast<double>(RASTER_H) * 0.5;
            sz[v] = zc;
            si[v] = inten;
        }

        for (int i = 0; i < RASTER_W * RASTER_H; i++) { color[i] = 0; zbuf[i] = 1.0e30; }

        for (int ri = 0; ri < RASTER_RINGS; ri++) {
            for (int sj = 0; sj < RASTER_SECTORS; sj++) {
                int a = ri * (RASTER_SECTORS + 1) + sj;
                int b = a + (RASTER_SECTORS + 1);
                int tris[2][3] = {{a, b, a + 1}, {a + 1, b, b + 1}};
                for (int t = 0; t < 2; t++) {
                    int i0 = tris[t][0], i1 = tris[t][1], i2 = tris[t][2];
                    double area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2]);
                    if (area <= 0.0) continue;
                    double mnx = sx[i0];
                    if (sx[i1] < mnx) mnx = sx[i1];
                    if (sx[i2] < mnx) mnx = sx[i2];
                    double mxx = sx[i0];
                    if (sx[i1] > mxx) mxx = sx[i1];
                    if (sx[i2] > mxx) mxx = sx[i2];
                    double mny = sy[i0];
                    if (sy[i1] < mny) mny = sy[i1];
                    if (sy[i2] < mny) mny = sy[i2];
                    double mxy = sy[i0];
                    if (sy[i1] > mxy) mxy = sy[i1];
                    if (sy[i2] > mxy) mxy = sy[i2];
                    if (mnx < 0.0) mnx = 0.0;
                    if (mxx > static_cast<double>(RASTER_W - 1)) mxx = static_cast<double>(RASTER_W - 1);
                    if (mny < 0.0) mny = 0.0;
                    if (mxy > static_cast<double>(RASTER_H - 1)) mxy = static_cast<double>(RASTER_H - 1);
                    int x0 = static_cast<int>(mnx), x1 = static_cast<int>(mxx);
                    int y0 = static_cast<int>(mny), y1 = static_cast<int>(mxy);
                    for (int py = y0; py <= y1; py++) {
                        double pcy = static_cast<double>(py) + 0.5;
                        for (int px = x0; px <= x1; px++) {
                            double pcx = static_cast<double>(px) + 0.5;
                            double w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
                            double w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
                            double w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
                            if (w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0) {
                                double l0 = w0 / area, l1 = w1 / area, l2 = w2 / area;
                                double depth = l0 * sz[i0] + l1 * sz[i1] + l2 * sz[i2];
                                int idx = py * RASTER_W + px;
                                if (depth < zbuf[idx]) {
                                    zbuf[idx] = depth;
                                    double inten = l0 * si[i0] + l1 * si[i1] + l2 * si[i2];
                                    if (inten < 0.0) inten = 0.0;
                                    if (inten > 1.0) inten = 1.0;
                                    color[idx] = static_cast<uint8_t>(inten * 255.0);
                                }
                            }
                        }
                    }
                }
            }
        }

        uint64_t frame_sum = 0;
        for (int i = 0; i < RASTER_W * RASTER_H; i++) frame_sum += color[i];
        checksum = checksum * 1000003 + frame_sum;
    }

    std::cout << "checksum " << checksum << "\n";
}

// --- pointer-chasing (random memory latency) --------------------------------

static void bench_ptrchase() {
    const std::size_t N = 16000000;
    const uint64_t HOPS = 4000000;
    std::vector<uint32_t> order(N);
    std::vector<uint32_t> next(N);
    for (std::size_t i = 0; i < N; i++) order[i] = static_cast<uint32_t>(i);
    uint32_t x = 1;
    for (std::size_t i = N - 1; i >= 1; i--) {
        x = x * 1664525u + 1013904223u;
        std::size_t j = (x & 0x7FFFFFFFu) % (i + 1);
        std::swap(order[i], order[j]);
    }
    for (std::size_t k = 0; k < N; k++) next[order[k]] = order[(k + 1) % N];
    uint32_t sum = 0, p = 0;
    for (uint64_t h = 0; h < HOPS; h++) {
        p = next[p];
        sum += p;
    }
    std::cout << "checksum " << sum << "\n";
}

// --- FNV-1a hash ------------------------------------------------------------

static void bench_hash() {
    const std::size_t N = 32000000;
    const int R = 4;
    std::vector<uint8_t> buf(N);
    uint32_t x = 12345;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = static_cast<uint8_t>(x & 0xFFu);
    }
    uint32_t h = 2166136261u;
    for (int r = 0; r < R; r++) {
        for (std::size_t i = 0; i < N; i++) {
            h ^= buf[i];
            h *= 16777619u;
        }
    }
    std::cout << "checksum " << h << "\n";
}

// --- binary search tree -----------------------------------------------------

struct BstNode {
    uint32_t key;
    BstNode *left;
    BstNode *right;
};

static void bench_bst() {
    const std::size_t M = 1000000;
    const std::size_t Q = 1000000;
    BstNode *root = nullptr;
    uint32_t x = 22222;
    for (std::size_t n = 0; n < M; n++) {
        x = x * 1664525u + 1013904223u;
        uint32_t key = x & 0x7FFFFFFFu;
        BstNode *nn = new BstNode{key, nullptr, nullptr};
        if (root == nullptr) { root = nn; continue; }
        BstNode *cur = root;
        for (;;) {
            if (key < cur->key) {
                if (cur->left == nullptr) { cur->left = nn; break; }
                cur = cur->left;
            } else {
                if (cur->right == nullptr) { cur->right = nn; break; }
                cur = cur->right;
            }
        }
    }
    uint32_t y = 99991;
    uint32_t cs = 0;
    for (std::size_t q = 0; q < Q; q++) {
        y = y * 1664525u + 1013904223u;
        uint32_t key = y & 0x7FFFFFFFu;
        uint32_t steps = 0;
        BstNode *cur = root;
        while (cur != nullptr) {
            steps += 1;
            if (key == cur->key) break;
            cur = key < cur->key ? cur->left : cur->right;
        }
        cs = cs * 1000003u + steps;
    }
    std::cout << "checksum " << cs << "\n";
}

// --- run-length encoding ----------------------------------------------------

static void bench_rle() {
    const std::size_t N = 40000000;
    const int R = 4;
    std::vector<uint8_t> buf(N);
    std::vector<uint8_t> out(2 * N);
    uint32_t x = 33333;
    std::size_t i = 0;
    while (i < N) {
        x = x * 1664525u + 1013904223u;
        uint8_t v = static_cast<uint8_t>(x & 0xFFu);
        uint32_t rl = ((x & 0x7FFFFFFFu) % 16u) + 1u;
        for (uint32_t c = 0; c < rl && i < N; c++) buf[i++] = v;
    }
    uint32_t h = 2166136261u;
    for (int r = 0; r < R; r++) {
        std::size_t o = 0;
        std::size_t p = 0;
        while (p < N) {
            uint8_t v = buf[p];
            std::size_t run = 1;
            while (p + run < N && buf[p + run] == v && run < 255) run++;
            out[o++] = static_cast<uint8_t>(run);
            out[o++] = v;
            p += run;
        }
        for (std::size_t k = 0; k < o; k++) {
            h ^= out[k];
            h *= 16777619u;
        }
        h ^= static_cast<uint8_t>(o % 256);
        h *= 16777619u;
        h ^= static_cast<uint8_t>((o / 256) % 256);
        h *= 16777619u;
        h ^= static_cast<uint8_t>((o / 65536) % 256);
        h *= 16777619u;
        h ^= static_cast<uint8_t>((o / 16777216) % 256);
        h *= 16777619u;
    }
    std::cout << "checksum " << h << "\n";
}

// --- base64 encoding --------------------------------------------------------

static const char B64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void bench_base64() {
    const std::size_t N = 24000000;
    const int R = 4;
    std::vector<uint8_t> buf(N);
    uint32_t x = 44444;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = static_cast<uint8_t>(x & 0xFFu);
    }
    uint32_t h = 2166136261u;
    for (int r = 0; r < R; r++) {
        for (std::size_t i = 0; i + 2 < N; i += 3) {
            uint32_t b0 = buf[i];
            uint32_t b1 = buf[i + 1];
            uint32_t b2 = buf[i + 2];
            uint32_t i0 = b0 / 4;
            uint32_t i1 = (b0 & 3) * 16 + b1 / 16;
            uint32_t i2 = (b1 & 15) * 4 + b2 / 64;
            uint32_t i3 = b2 & 63;
            h ^= static_cast<uint8_t>(B64[i0]);
            h *= 16777619u;
            h ^= static_cast<uint8_t>(B64[i1]);
            h *= 16777619u;
            h ^= static_cast<uint8_t>(B64[i2]);
            h *= 16777619u;
            h ^= static_cast<uint8_t>(B64[i3]);
            h *= 16777619u;
        }
    }
    std::cout << "checksum " << h << "\n";
}

// --- indirect dispatch ------------------------------------------------------

static uint32_t op_add(uint32_t a, uint32_t b) { return a + b; }
static uint32_t op_xor(uint32_t a, uint32_t b) { return a ^ b; }
static uint32_t op_mul(uint32_t a, uint32_t b) { return a * (b | 1u); }
static uint32_t op_sub(uint32_t a, uint32_t b) { return a - b; }

static void bench_dispatch() {
    const std::size_t N = 4000000;
    const int R = 32;
    std::vector<uint8_t> code(N);
    std::vector<uint32_t> operand(N);
    uint32_t x = 55555;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u;
        code[i] = static_cast<uint8_t>((x & 0x7FFFFFFFu) % 4u);
        operand[i] = x;
    }
    uint32_t (*fns[4])(uint32_t, uint32_t) = {op_add, op_xor, op_mul, op_sub};
    uint32_t acc = 2166136261u;
    for (int r = 0; r < R; r++) {
        for (std::size_t i = 0; i < N; i++) {
            acc = fns[code[i]](acc, operand[i]);
        }
    }
    std::cout << "checksum " << acc << "\n";
}

static void bench_collatz() {
    const uint64_t N = 3000000;
    uint64_t total = 0;
    for (uint64_t i = 1; i <= N; i++) {
        uint64_t n = i, steps = 0;
        while (n != 1) {
            n = n % 2 == 0 ? n / 2 : 3 * n + 1;
            steps += 1;
        }
        total += steps;
    }
    std::cout << "checksum " << total << "\n";
}

// --- n-body (dependent floating-point chains) -------------------------------

static void bench_nbody() {
    const int N = 2048;
    const int STEPS = 8;
    const double DT = 0.01;
    const double EPS = 0.05;
    std::vector<double> px(N), py(N), pz(N), vx(N), vy(N), vz(N), m(N);
    uint32_t s = 7777;
    for (int i = 0; i < N; i++) {
        s = s * 1664525u + 1013904223u; px[i] = (static_cast<double>(s & 0xFFFFu) / 65536.0) * 2.0 - 1.0;
        s = s * 1664525u + 1013904223u; py[i] = (static_cast<double>(s & 0xFFFFu) / 65536.0) * 2.0 - 1.0;
        s = s * 1664525u + 1013904223u; pz[i] = (static_cast<double>(s & 0xFFFFu) / 65536.0) * 2.0 - 1.0;
        s = s * 1664525u + 1013904223u; m[i] = static_cast<double>(s & 0xFFFFu) / 65536.0 + 0.1;
        vx[i] = 0.0; vy[i] = 0.0; vz[i] = 0.0;
    }
    for (int step = 0; step < STEPS; step++) {
        for (int i = 0; i < N; i++) {
            double ax = 0.0, ay = 0.0, az = 0.0;
            double xi = px[i], yi = py[i], zi = pz[i];
            for (int j = 0; j < N; j++) {
                if (j == i) continue;
                double dx = px[j] - xi, dy = py[j] - yi, dz = pz[j] - zi;
                double d2 = dx * dx + dy * dy + dz * dz + EPS;
                double g = (d2 + 1.0) * 0.5;
                for (int k = 0; k < 8; k++) g = (g + d2 / g) * 0.5;
                double inv3 = 1.0 / (d2 * g);
                double f = m[j] * inv3;
                ax += dx * f; ay += dy * f; az += dz * f;
            }
            vx[i] += ax * DT; vy[i] += ay * DT; vz[i] += az * DT;
        }
        for (int i = 0; i < N; i++) { px[i] += vx[i] * DT; py[i] += vy[i] * DT; pz[i] += vz[i] * DT; }
    }
    uint32_t cs = 0;
    for (int i = 0; i < N; i++) {
        cs = cs * 1000003u + static_cast<uint32_t>(static_cast<int64_t>(px[i] * 1024.0));
        cs = cs * 1000003u + static_cast<uint32_t>(static_cast<int64_t>(py[i] * 1024.0));
        cs = cs * 1000003u + static_cast<uint32_t>(static_cast<int64_t>(pz[i] * 1024.0));
    }
    std::cout << "checksum " << cs << "\n";
}

// --- STREAM triad (memory write bandwidth) ----------------------------------

static void bench_stream() {
    const std::size_t N = 16000000;
    const int R = 40;
    const uint32_t K = 3u;
    std::vector<uint32_t> a(N), b(N), c(N);
    uint32_t x = 11111;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u; b[i] = x;
        x = x * 1664525u + 1013904223u; c[i] = x;
        a[i] = 0;
    }
    for (int r = 0; r < R; r++)
        for (std::size_t i = 0; i < N; i++) a[i] = b[i] + K * c[i];
    uint32_t cs = 0;
    for (std::size_t i = 0; i < N; i++) cs = cs * 1000003u + a[i];
    std::cout << "checksum " << cs << "\n";
}

// --- N-queens (backtracking recursion) --------------------------------------

static uint64_t nq_solve(uint32_t cols, uint32_t d1, uint32_t d2, uint32_t full) {
    if (cols == full) return 1;
    uint64_t count = 0;
    uint32_t avail = (~(cols | d1 | d2)) & full;
    while (avail != 0) {
        uint32_t bit = avail & (0u - avail);
        avail -= bit;
        count += nq_solve(cols | bit, ((d1 | bit) * 2u) & full, (d2 | bit) / 2u, full);
    }
    return count;
}

static void bench_nqueens() {
    const int NQ = 14;
    uint32_t full = (1u << NQ) - 1u;
    uint64_t total = nq_solve(0, 0, 0, full);
    std::cout << "checksum " << total << "\n";
}

// --- Conway's Game of Life --------------------------------------------------

static void bench_life() {
    const int W = 1024, H = 1024, T = 300;
    std::vector<uint8_t> cur(static_cast<std::size_t>(W) * H), nxt(static_cast<std::size_t>(W) * H);
    uint32_t x = 22221;
    for (int i = 0; i < W * H; i++) {
        x = x * 1664525u + 1013904223u;
        cur[i] = static_cast<uint8_t>((x / 65536u) & 1u);
    }
    for (int gen = 0; gen < T; gen++) {
        for (int y = 0; y < H; y++) {
            int ym = y == 0 ? H - 1 : y - 1;
            int yp = y == H - 1 ? 0 : y + 1;
            for (int xx = 0; xx < W; xx++) {
                int xm = xx == 0 ? W - 1 : xx - 1;
                int xp = xx == W - 1 ? 0 : xx + 1;
                int n = cur[ym * W + xm] + cur[ym * W + xx] + cur[ym * W + xp]
                      + cur[y * W + xm] + cur[y * W + xp]
                      + cur[yp * W + xm] + cur[yp * W + xx] + cur[yp * W + xp];
                uint8_t alive = cur[y * W + xx];
                nxt[y * W + xx] = (n == 3 || (alive && n == 2)) ? 1 : 0;
            }
        }
        std::swap(cur, nxt);
    }
    uint32_t cs = 0;
    for (int i = 0; i < W * H; i++) cs = cs * 1000003u + cur[i];
    std::cout << "checksum " << cs << "\n";
}

// --- open-addressing hash map (linear probing) ------------------------------

static void bench_hashmap() {
    const std::size_t M = 8000000, Q = 16000000;
    const uint32_t SIZE = 1u << 24;
    const uint32_t MASK = SIZE - 1u;
    std::vector<uint32_t> keys(SIZE, 0), vals(SIZE, 0);
    uint32_t x = 33331;
    for (std::size_t n = 0; n < M; n++) {
        x = x * 1664525u + 1013904223u;
        uint32_t key = (x & 0x7FFFFFFFu) | 1u;
        uint32_t idx = key & MASK;
        for (;;) {
            if (keys[idx] == 0) { keys[idx] = key; vals[idx] = x; break; }
            if (keys[idx] == key) { vals[idx] += x; break; }
            idx = (idx + 1u) & MASK;
        }
    }
    uint32_t y = 99989, acc = 0;
    for (std::size_t q = 0; q < Q; q++) {
        y = y * 1664525u + 1013904223u;
        uint32_t key = (y & 0x7FFFFFFFu) | 1u;
        uint32_t idx = key & MASK;
        uint32_t steps = 0;
        for (;;) {
            steps += 1;
            if (keys[idx] == 0) break;
            if (keys[idx] == key) { acc += vals[idx]; break; }
            idx = (idx + 1u) & MASK;
        }
        acc = acc * 1000003u + steps;
    }
    std::cout << "checksum " << acc << "\n";
}

// --- SHA-256 (32-bit crypto mixing) -----------------------------------------

static const uint32_t SHA_K[64] = {
    0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
    0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
    0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
    0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
    0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
    0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
    0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
    0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u };

static uint32_t rotr32(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

static void bench_sha256() {
    const std::size_t N = 4000000;
    const int R = 16;
    std::vector<uint8_t> buf(N);
    uint32_t x = 44441;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = static_cast<uint8_t>((x / 256u) & 0xFFu);
    }
    uint32_t cs = 0;
    for (int r = 0; r < R; r++) {
        uint32_t h0 = 0x6a09e667u, h1 = 0xbb67ae85u, h2 = 0x3c6ef372u, h3 = 0xa54ff53au;
        uint32_t h4 = 0x510e527fu, h5 = 0x9b05688cu, h6 = 0x1f83d9abu, h7 = 0x5be0cd19u;
        std::size_t nblocks = N / 64;
        uint32_t w[64];
        for (std::size_t blk = 0; blk < nblocks; blk++) {
            std::size_t base = blk * 64;
            for (int t = 0; t < 16; t++) {
                std::size_t o = base + static_cast<std::size_t>(t) * 4;
                w[t] = (static_cast<uint32_t>(buf[o]) << 24) | (static_cast<uint32_t>(buf[o + 1]) << 16) | (static_cast<uint32_t>(buf[o + 2]) << 8) | static_cast<uint32_t>(buf[o + 3]);
            }
            for (int t = 16; t < 64; t++) {
                uint32_t s0 = rotr32(w[t - 15], 7) ^ rotr32(w[t - 15], 18) ^ (w[t - 15] >> 3);
                uint32_t s1 = rotr32(w[t - 2], 17) ^ rotr32(w[t - 2], 19) ^ (w[t - 2] >> 10);
                w[t] = w[t - 16] + s0 + w[t - 7] + s1;
            }
            uint32_t a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, hh = h7;
            for (int t = 0; t < 64; t++) {
                uint32_t S1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
                uint32_t ch = (e & f) ^ ((~e) & g);
                uint32_t t1 = hh + S1 + ch + SHA_K[t] + w[t];
                uint32_t S0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
                uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
                uint32_t t2 = S0 + maj;
                hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
            }
            h0 += a; h1 += b; h2 += c; h3 += d; h4 += e; h5 += f; h6 += g; h7 += hh;
        }
        cs = cs * 1000003u + (h0 ^ h1 ^ h2 ^ h3 ^ h4 ^ h5 ^ h6 ^ h7);
    }
    std::cout << "checksum " << cs << "\n";
}

// --- matrix transpose (cache stride / TLB) ----------------------------------

static void bench_transpose() {
    const std::size_t Ndim = 4096;
    const int R = 6;
    std::vector<uint32_t> src(Ndim * Ndim), dst(Ndim * Ndim);
    uint32_t x = 55551;
    for (std::size_t i = 0; i < Ndim * Ndim; i++) {
        x = x * 1664525u + 1013904223u; src[i] = x;
    }
    for (int r = 0; r < R; r++) {
        for (std::size_t i = 0; i < Ndim; i++)
            for (std::size_t j = 0; j < Ndim; j++)
                dst[j * Ndim + i] = src[i * Ndim + j];
        std::swap(src, dst);
    }
    uint32_t cs = 0;
    for (std::size_t i = 0; i < Ndim * Ndim; i++) cs = cs * 1000003u + src[i];
    std::cout << "checksum " << cs << "\n";
}

// --- edit distance (dynamic programming) ------------------------------------

static int edit_min3(int a, int b, int c) {
    int m = a < b ? a : b;
    return m < c ? m : c;
}

static void bench_editdist() {
    const int LA = 16000, LB = 16000;
    std::vector<uint8_t> A(LA), B(LB);
    uint32_t x = 66661;
    for (int i = 0; i < LA; i++) { x = x * 1664525u + 1013904223u; A[i] = static_cast<uint8_t>((x / 65536u) % 4u); }
    for (int i = 0; i < LB; i++) { x = x * 1664525u + 1013904223u; B[i] = static_cast<uint8_t>((x / 65536u) % 4u); }
    std::vector<int> prev(LB + 1), cur(LB + 1);
    for (int j = 0; j <= LB; j++) prev[j] = j;
    for (int i = 1; i <= LA; i++) {
        cur[0] = i;
        for (int j = 1; j <= LB; j++) {
            int cost = A[i - 1] == B[j - 1] ? 0 : 1;
            cur[j] = edit_min3(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        }
        std::swap(prev, cur);
    }
    std::cout << "checksum " << static_cast<uint32_t>(prev[LB]) << "\n";
}

// --- LZ77 greedy compressor -------------------------------------------------

static void bench_lz() {
    const std::size_t N = 4000000;
    const std::size_t WIN = 512;
    const std::size_t MAXLEN = 64;
    std::vector<uint8_t> buf(N);
    uint32_t x = 77771;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = static_cast<uint8_t>((x / 65536u) % 8u);
    }
    uint32_t h = 2166136261u;
    std::size_t p = 0;
    while (p < N) {
        std::size_t lo = p > WIN ? p - WIN : 0;
        std::size_t bestlen = 0, bestoff = 0;
        for (std::size_t sidx = lo; sidx < p; sidx++) {
            std::size_t len = 0;
            while (p + len < N && len < MAXLEN && buf[sidx + len] == buf[p + len]) len++;
            if (len > bestlen) { bestlen = len; bestoff = p - sidx; }
        }
        if (bestlen >= 3) {
            h ^= static_cast<uint8_t>(bestoff & 0xFFu); h *= 16777619u;
            h ^= static_cast<uint8_t>((bestoff / 256u) & 0xFFu); h *= 16777619u;
            h ^= static_cast<uint8_t>(bestlen & 0xFFu); h *= 16777619u;
            p += bestlen;
        } else {
            h ^= buf[p]; h *= 16777619u;
            p += 1;
        }
    }
    std::cout << "checksum " << h << "\n";
}

// --- CRC32 (table-driven hashing) -------------------------------------------

static void bench_crc32() {
    const std::size_t N = 16000000;
    const int R = 8;
    uint32_t table[256];
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        table[i] = c;
    }
    std::vector<uint8_t> buf(N);
    uint32_t x = 88881;
    for (std::size_t i = 0; i < N; i++) {
        x = x * 1664525u + 1013904223u;
        buf[i] = static_cast<uint8_t>((x / 65536u) & 0xFFu);
    }
    uint32_t cs = 0;
    for (int r = 0; r < R; r++) {
        uint32_t crc = 0xFFFFFFFFu;
        for (std::size_t i = 0; i < N; i++)
            crc = table[(crc ^ buf[i]) & 0xFFu] ^ (crc >> 8);
        crc ^= 0xFFFFFFFFu;
        cs = cs * 1000003u + crc;
    }
    std::cout << "checksum " << cs << "\n";
}

static const struct { const char *name; void (*fn)(); } BENCHES[] = {
    {"fib", bench_fib}, {"mandelbrot", bench_mandelbrot}, {"matmul", bench_matmul},
    {"sieve", bench_sieve}, {"sort", bench_sort}, {"collatz", bench_collatz},
    {"raster", bench_raster}, {"ptrchase", bench_ptrchase}, {"hash", bench_hash},
    {"bst", bench_bst}, {"rle", bench_rle}, {"base64", bench_base64},
    {"dispatch", bench_dispatch}, {"nbody", bench_nbody}, {"stream", bench_stream},
    {"nqueens", bench_nqueens}, {"life", bench_life}, {"hashmap", bench_hashmap},
    {"sha256", bench_sha256}, {"transpose", bench_transpose}, {"editdist", bench_editdist},
    {"lz", bench_lz}, {"crc32", bench_crc32},
};

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cout << "usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster|ptrchase|hash|bst|rle|base64|dispatch|nbody|stream|nqueens|life|hashmap|sha256|transpose|editdist|lz|crc32>\n";
        return 0;
    }
    std::string name = argv[1];
    for (const auto &b : BENCHES)
        if (name == b.name) { b.fn(); return 0; }
    std::cout << "unknown benchmark: " << name << "\n";
    return 0;
}
