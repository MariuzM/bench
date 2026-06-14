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
        printf("usage: main <fib|mandelbrot|matmul|sieve|sort|collatz>\n");
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
    } else {
        printf("unknown benchmark: %s\n", name);
    }
    return 0;
}
