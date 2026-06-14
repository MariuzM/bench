// ---------------------------------------------------------------------------
// Benchmark suite. One process runs exactly one benchmark, selected by argv[1],
// so the build script can measure each one's wall-time and peak memory in
// isolation. Every benchmark prints a single "checksum <n>" line; all language
// builds must agree on it, which proves they did the same work.
// ---------------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static uint64_t fib(uint64_t n) {
    if (n < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

static void bench_fib(void) {
    uint64_t total = 0;
    for (uint64_t n = 30; n <= 42; n++) {
        total += fib(n);
    }
    printf("checksum %llu\n", (unsigned long long)total);
}

static void bench_mandelbrot(void) {
    const size_t W = 1200;
    const size_t H = 1200;
    const uint64_t MAX_IT = 1000;
    uint64_t sum = 0;
    for (size_t py = 0; py < H; py++) {
        double y0 = ((double)py / (double)H) * 4.0 - 2.0;
        for (size_t px = 0; px < W; px++) {
            double x0 = ((double)px / (double)W) * 4.0 - 2.5;
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
    printf("checksum %llu\n", (unsigned long long)sum);
}

static void bench_matmul(void) {
    const size_t N = 512;
    int64_t *a = malloc(N * N * sizeof(int64_t));
    int64_t *b = malloc(N * N * sizeof(int64_t));
    int64_t *c = malloc(N * N * sizeof(int64_t));

    for (size_t i = 0; i < N; i++) {
        for (size_t j = 0; j < N; j++) {
            a[i * N + j] = (int64_t)((i * j) % 7) - 3;
            b[i * N + j] = (int64_t)((i + j) % 5) - 2;
            c[i * N + j] = 0;
        }
    }

    for (size_t i = 0; i < N; i++) {
        for (size_t k = 0; k < N; k++) {
            int64_t aik = a[i * N + k];
            for (size_t j = 0; j < N; j++) {
                c[i * N + j] += aik * b[k * N + j];
            }
        }
    }

    int64_t sum = 0;
    for (size_t i = 0; i < N * N; i++) {
        sum += c[i];
    }
    printf("checksum %lld\n", (long long)sum);

    free(a);
    free(b);
    free(c);
}

static void bench_sieve(void) {
    const size_t N = 50000000;
    uint8_t *sieve = malloc(N);
    memset(sieve, 1, N);
    sieve[0] = 0;
    sieve[1] = 0;

    for (size_t i = 2; i * i < N; i++) {
        if (sieve[i] == 1) {
            for (size_t j = i * i; j < N; j += i) {
                sieve[j] = 0;
            }
        }
    }

    uint64_t count = 0;
    for (size_t i = 0; i < N; i++) {
        count += sieve[i];
    }
    printf("checksum %llu\n", (unsigned long long)count);

    free(sieve);
}

static void quicksort(uint64_t *arr, int64_t lo, int64_t hi) {
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
            uint64_t tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
            i += 1;
            j -= 1;
        }
    }
    quicksort(arr, lo, j);
    quicksort(arr, i, hi);
}

static void bench_sort(void) {
    const size_t N = 3000000;
    uint64_t *arr = malloc(N * sizeof(uint64_t));

    uint64_t state = 88172645463325252ULL;
    for (size_t i = 0; i < N; i++) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        arr[i] = state & 0x7FFFFFFFFFFFFFFFULL;
    }

    quicksort(arr, 0, (int64_t)N - 1);

    uint64_t cs = 0;
    for (size_t i = 0; i < N; i++) {
        cs = cs * 1000003ULL + arr[i];
    }
    printf("checksum %llu\n", (unsigned long long)cs);

    free(arr);
}

// --- software 3D rasterizer -------------------------------------------------
// Renders a spinning, Gouraud-shaded UV sphere into an in-memory framebuffer
// with a z-buffer, for a fixed number of frames. Uses only +,-,*,/ and a
// hand-rolled polynomial sin/cos (libm's differ per language) so every
// language produces a bit-identical checksum. FPS = RASTER_FRAMES / wall_time.

#define RASTER_W 640
#define RASTER_H 480
#define RASTER_RINGS 24
#define RASTER_SECTORS 24
#define RASTER_FRAMES 240
#define RASTER_NV ((RASTER_RINGS + 1) * (RASTER_SECTORS + 1))

static double r_floor(double y) {
    double f = (double)(int64_t)y;
    if (f > y) {
        return f - 1.0;
    }
    return f;
}

static double r_sin(double x) {
    const double PI = 3.141592653589793;
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
    (void)PI;
    return x * p;
}

static double r_cos(double x) {
    const double HALF_PI = 1.5707963267948966;
    return r_sin(x + HALF_PI);
}

static double edge(double ax, double ay, double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

static void bench_raster(void) {
    const double FOCAL = 500.0;
    const double CAM_DIST = 3.0;

    static double bx[RASTER_NV];
    static double by[RASTER_NV];
    static double bz[RASTER_NV];
    int nv = 0;
    for (int i = 0; i <= RASTER_RINGS; i++) {
        double theta = 3.141592653589793 * ((double)i / (double)RASTER_RINGS);
        double st = r_sin(theta);
        double ct = r_cos(theta);
        for (int j = 0; j <= RASTER_SECTORS; j++) {
            double phi = 6.283185307179586 * ((double)j / (double)RASTER_SECTORS);
            double sp = r_sin(phi);
            double cp = r_cos(phi);
            bx[nv] = st * cp;
            by[nv] = ct;
            bz[nv] = st * sp;
            nv += 1;
        }
    }

    static double sx[RASTER_NV];
    static double sy[RASTER_NV];
    static double sz[RASTER_NV];
    static double si[RASTER_NV];

    unsigned char *color = malloc(RASTER_W * RASTER_H);
    double *zbuf = malloc(RASTER_W * RASTER_H * sizeof(double));

    uint64_t checksum = 0;

    for (int f = 0; f < RASTER_FRAMES; f++) {
        double ang = (double)f * 0.0125;
        double cy = r_cos(ang);
        double syr = r_sin(ang);
        double ax = ang * 0.5;
        double cx = r_cos(ax);
        double sxr = r_sin(ax);

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
            sx[v] = rx * invz * FOCAL + (double)RASTER_W * 0.5;
            sy[v] = ry2 * invz * FOCAL + (double)RASTER_H * 0.5;
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
                    if (mxx > (double)(RASTER_W - 1)) mxx = (double)(RASTER_W - 1);
                    if (mny < 0.0) mny = 0.0;
                    if (mxy > (double)(RASTER_H - 1)) mxy = (double)(RASTER_H - 1);
                    int x0 = (int)mnx;
                    int x1 = (int)mxx;
                    int y0 = (int)mny;
                    int y1 = (int)mxy;
                    for (int py = y0; py <= y1; py++) {
                        double pcy = (double)py + 0.5;
                        for (int px = x0; px <= x1; px++) {
                            double pcx = (double)px + 0.5;
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
                                    color[idx] = (unsigned char)(inten * 255.0);
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

    printf("checksum %llu\n", (unsigned long long)checksum);

    free(color);
    free(zbuf);
}

static void bench_collatz(void) {
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
    printf("checksum %llu\n", (unsigned long long)total);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz|raster>\n");
        return 0;
    }
    const char *name = argv[1];
    if (strcmp(name, "fib") == 0) {
        bench_fib();
    } else if (strcmp(name, "mandelbrot") == 0) {
        bench_mandelbrot();
    } else if (strcmp(name, "matmul") == 0) {
        bench_matmul();
    } else if (strcmp(name, "sieve") == 0) {
        bench_sieve();
    } else if (strcmp(name, "sort") == 0) {
        bench_sort();
    } else if (strcmp(name, "collatz") == 0) {
        bench_collatz();
    } else if (strcmp(name, "raster") == 0) {
        bench_raster();
    } else {
        printf("unknown benchmark: %s\n", name);
    }
    return 0;
}
