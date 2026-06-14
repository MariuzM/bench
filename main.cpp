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
    if (n < 2) {
        return n;
    }
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
            double x = 0.0;
            double y = 0.0;
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
    for (std::size_t i = 0; i < N * N; i++) {
        sum += c[i];
    }
    std::cout << "checksum " << sum << "\n";
}

static void bench_sieve() {
    const std::size_t N = 50000000;
    std::vector<uint8_t> sieve(N, 1);
    sieve[0] = 0;
    sieve[1] = 0;

    for (std::size_t i = 2; i * i < N; i++) {
        if (sieve[i] == 1) {
            for (std::size_t j = i * i; j < N; j += i) {
                sieve[j] = 0;
            }
        }
    }

    uint64_t count = 0;
    for (std::size_t i = 0; i < N; i++) {
        count += sieve[i];
    }
    std::cout << "checksum " << count << "\n";
}

static void quicksort(std::vector<uint64_t> &arr, int64_t lo, int64_t hi) {
    if (lo >= hi) {
        return;
    }
    uint64_t pivot = arr[(lo + hi) / 2];
    int64_t i = lo;
    int64_t j = hi;
    while (i <= j) {
        while (arr[i] < pivot) {
            i += 1;
        }
        while (arr[j] > pivot) {
            j -= 1;
        }
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
    if (f > y) {
        return f - 1.0;
    }
    return f;
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

    std::vector<double> bx(RASTER_NV);
    std::vector<double> by(RASTER_NV);
    std::vector<double> bz(RASTER_NV);
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

    std::vector<double> sx(RASTER_NV);
    std::vector<double> sy(RASTER_NV);
    std::vector<double> sz(RASTER_NV);
    std::vector<double> si(RASTER_NV);

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
            double px0 = bx[v];
            double py0 = by[v];
            double pz0 = bz[v];
            double rx = px0 * cy + pz0 * syr;
            double rz = -px0 * syr + pz0 * cy;
            double ry = py0;
            double ry2 = ry * cx - rz * sxr;
            double rz2 = ry * sxr + rz * cx;
            double inten = -rz2;
            if (inten < 0.0) {
                inten = 0.0;
            }
            double zc = rz2 + CAM_DIST;
            double invz = 1.0 / zc;
            sx[v] = rx * invz * FOCAL + static_cast<double>(RASTER_W) * 0.5;
            sy[v] = ry2 * invz * FOCAL + static_cast<double>(RASTER_H) * 0.5;
            sz[v] = zc;
            si[v] = inten;
        }

        for (int i = 0; i < RASTER_W * RASTER_H; i++) {
            color[i] = 0;
            zbuf[i] = 1.0e30;
        }

        for (int ri = 0; ri < RASTER_RINGS; ri++) {
            for (int sj = 0; sj < RASTER_SECTORS; sj++) {
                int a = ri * (RASTER_SECTORS + 1) + sj;
                int b = a + (RASTER_SECTORS + 1);
                int tris[2][3] = {{a, b, a + 1}, {a + 1, b, b + 1}};
                for (int t = 0; t < 2; t++) {
                    int i0 = tris[t][0];
                    int i1 = tris[t][1];
                    int i2 = tris[t][2];
                    double area = edge(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2]);
                    if (area <= 0.0) {
                        continue;
                    }
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
                    int x0 = static_cast<int>(mnx);
                    int x1 = static_cast<int>(mxx);
                    int y0 = static_cast<int>(mny);
                    int y1 = static_cast<int>(mxy);
                    for (int py = y0; py <= y1; py++) {
                        double pcy = static_cast<double>(py) + 0.5;
                        for (int px = x0; px <= x1; px++) {
                            double pcx = static_cast<double>(px) + 0.5;
                            double w0 = edge(sx[i1], sy[i1], sx[i2], sy[i2], pcx, pcy);
                            double w1 = edge(sx[i2], sy[i2], sx[i0], sy[i0], pcx, pcy);
                            double w2 = edge(sx[i0], sy[i0], sx[i1], sy[i1], pcx, pcy);
                            if (w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0) {
                                double l0 = w0 / area;
                                double l1 = w1 / area;
                                double l2 = w2 / area;
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
        for (int i = 0; i < RASTER_W * RASTER_H; i++) {
            frame_sum += color[i];
        }
        checksum = checksum * 1000003 + frame_sum;
    }

    std::cout << "checksum " << checksum << "\n";
}

static void bench_collatz() {
    const uint64_t N = 3000000;
    uint64_t total = 0;
    for (uint64_t i = 1; i <= N; i++) {
        uint64_t n = i;
        uint64_t steps = 0;
        while (n != 1) {
            if (n % 2 == 0) {
                n = n / 2;
            } else {
                n = 3 * n + 1;
            }
            steps += 1;
        }
        total += steps;
    }
    std::cout << "checksum " << total << "\n";
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cout << "usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>\n";
        return 0;
    }
    std::string name = argv[1];
    if (name == "fib") {
        bench_fib();
    } else if (name == "mandelbrot") {
        bench_mandelbrot();
    } else if (name == "matmul") {
        bench_matmul();
    } else if (name == "sieve") {
        bench_sieve();
    } else if (name == "sort") {
        bench_sort();
    } else if (name == "collatz") {
        bench_collatz();
    } else if (name == "raster") {
        bench_raster();
    } else {
        std::cout << "unknown benchmark: " << name << "\n";
    }
    return 0;
}
