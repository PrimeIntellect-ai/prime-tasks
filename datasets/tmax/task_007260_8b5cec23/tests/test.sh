#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'C_EOF' > /tmp/verifier_cleaner.c
static double global_sum = 0.0;
static int global_count = 0;

void clean_batch_isolated(float *data, int size) {
    double sum = 0.0;
    for (int i = 0; i < size; i++) sum += data[i];
    float mean = (float)(sum / size);
    for (int i = 0; i < size; i++) data[i] -= mean;
}

void clean_batch_leaky(float *data, int size) {
    for (int i = 0; i < size; i++) {
        global_sum += data[i];
        global_count++;
    }
    float mean = (float)(global_sum / global_count);
    for (int i = 0; i < size; i++) data[i] -= mean;
}
C_EOF

cat << 'C_EOF' > /tmp/verifier_wrap.c
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#include <stddef.h>
#include <stdio.h>

int __real_clock_gettime(clockid_t, struct timespec *);
void *__real_malloc(size_t);
void *__real_calloc(size_t, size_t);
void __real_free(void *);

static long clock_calls = 0;
static long long synthetic_ns = 0;
static long target_allocs = 0;
static long target_frees = 0;
static void *target_ptrs[512];

int __wrap_clock_gettime(clockid_t id, struct timespec *ts) {
    if (id != CLOCK_MONOTONIC)
        return __real_clock_gettime(id, ts);

    long measurement = clock_calls / 2;
    if ((clock_calls & 1) != 0)
        synthetic_ns += (measurement + 1) * 1000LL;

    ts->tv_sec = (time_t)(synthetic_ns / 1000000000LL);
    ts->tv_nsec = (long)(synthetic_ns % 1000000000LL);
    clock_calls++;
    return 0;
}

static void remember_target(void *p, size_t bytes) {
    if (p != NULL && bytes == 10000U * sizeof(float)) {
        if (target_allocs < 512) target_ptrs[target_allocs] = p;
        target_allocs++;
    }
}

void *__wrap_malloc(size_t bytes) {
    void *p = __real_malloc(bytes);
    remember_target(p, bytes);
    return p;
}

void *__wrap_calloc(size_t n, size_t bytes) {
    void *p = __real_calloc(n, bytes);
    if (bytes != 0 && n <= (size_t)-1 / bytes)
        remember_target(p, n * bytes);
    return p;
}

void __wrap_free(void *p) {
    for (long i = 0; i < target_allocs && i < 512; i++) {
        if (target_ptrs[i] == p) {
            target_ptrs[i] = NULL;
            target_frees++;
            break;
        }
    }
    __real_free(p);
}

__attribute__((destructor)) static void write_counts(void) {
    FILE *f = fopen("/tmp/test_bench_counts.txt", "w");
    if (f != NULL) {
        fprintf(f, "%ld %ld %ld\n", clock_calls, target_allocs, target_frees);
        fclose(f);
    }
}
C_EOF

cat << 'C_EOF' > /tmp/reference_means.c
#include <stdio.h>
#include <stdlib.h>

#define N 10000

static double global_sum = 0.0;
static int global_count = 0;

static void isolated(float *data) {
    double sum = 0.0;
    for (int i = 0; i < N; i++) sum += data[i];
    float mean = (float)(sum / N);
    for (int i = 0; i < N; i++) data[i] -= mean;
}

static void leaky(float *data) {
    for (int i = 0; i < N; i++) {
        global_sum += data[i];
        global_count++;
    }
    float mean = (float)(global_sum / global_count);
    for (int i = 0; i < N; i++) data[i] -= mean;
}

static void fill(float *data) {
    for (int i = 0; i < N; i++)
        data[i] = (float)rand() / (float)(RAND_MAX / 100);
}

static double data_mean(float *data) {
    double sum = 0.0;
    for (int i = 0; i < N; i++) sum += data[i];
    return sum / N;
}

int main(void) {
    float *data = malloc(N * sizeof(float));
    if (!data) return 1;

    srand(42);
    fill(data); isolated(data);
    fill(data); isolated(data);
    double iso = data_mean(data);

    srand(42);
    fill(data); leaky(data);
    fill(data); leaky(data);
    double leak = data_mean(data);

    printf("%.2f %.2f\n", iso, leak);
    free(data);
    return 0;
}
C_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import pytest

SOURCE_PATH = '/home/user/test_bench.c'
REPORT_PATH = '/home/user/report.txt'

@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    assert os.path.isfile(SOURCE_PATH), f"C benchmark source not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, "test_bench.c is empty"

    subprocess.run([
        'gcc', '-std=c11', '-D_POSIX_C_SOURCE=200809L', '-I/home/user',
        '-c', SOURCE_PATH, '-o', '/tmp/test_bench.o'
    ], check=True, timeout=30, capture_output=True, text=True)

    symbols = subprocess.run(
        ['nm', '-u', '/tmp/test_bench.o'], check=True,
        capture_output=True, text=True, timeout=10
    ).stdout
    for symbol in ('clean_batch_isolated', 'clean_batch_leaky',
                   'clock_gettime', 'srand', 'rand'):
        assert re.search(r'\b' + re.escape(symbol) + r'\b', symbols), \
            f"test_bench.c must call {symbol}"

    subprocess.run([
        'gcc', '-std=c11', '-D_POSIX_C_SOURCE=200809L',
        '/tmp/test_bench.o', '/tmp/verifier_cleaner.c', '/tmp/verifier_wrap.c',
        '-Wl,--wrap=clock_gettime', '-Wl,--wrap=malloc',
        '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-lm',
        '-o', '/tmp/test_bench_verified'
    ], check=True, timeout=30, capture_output=True, text=True)

    for path in (REPORT_PATH, '/tmp/test_bench_counts.txt'):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run(['/tmp/test_bench_verified'], cwd='/home/user', check=True,
                   timeout=30, capture_output=True, text=True)

    assert os.path.isfile('/tmp/test_bench_counts.txt'), \
        'Instrumented benchmark did not finish normally'
    with open('/tmp/test_bench_counts.txt') as f:
        clock_calls, allocations, frees = map(int, f.read().split())
    assert clock_calls == 400, \
        f'Expected two CLOCK_MONOTONIC readings for each of 200 batches, got {clock_calls}'
    assert allocations == 200, \
        f'Expected one fresh 10,000-float allocation for each batch, got {allocations}'
    assert frees == 200, \
        f'Expected all 200 batch arrays to be freed, got {frees}'


def read_report():
    with open(REPORT_PATH, 'r') as f:
        return f.read()


def parsed_report():
    content = read_report()
    pattern = (
        r'^Isolated Mean Time: (-?\d+\.\d{2}) us\n'
        r'Isolated Time 95% CI: \[\[(-?\d+\.\d{2})\], \[(-?\d+\.\d{2})\]\]\n'
        r'Isolated Batch 2 Data Mean: (-?\d+\.\d{2})\n'
        r'Leaky Mean Time: (-?\d+\.\d{2}) us\n'
        r'Leaky Time 95% CI: \[\[(-?\d+\.\d{2})\], \[(-?\d+\.\d{2})\]\]\n'
        r'Leaky Batch 2 Data Mean: (-?\d+\.\d{2})\n?$'
    )
    match = re.fullmatch(pattern, content)
    assert match is not None, 'Report must contain exactly the six required lines with two decimal places'
    return tuple(map(float, match.groups()))


def expected_ci(values, sample):
    mean = sum(values) / len(values)
    divisor = len(values) - 1 if sample else len(values)
    variance = sum((x - mean) ** 2 for x in values) / divisor
    margin = 1.96 * math.sqrt(variance) / math.sqrt(len(values))
    return mean - margin, mean + margin


def close_to_rounded(actual, expected):
    return abs(actual - round(expected + 1e-12, 2)) < 0.006


def test_report_exists():
    """Verify that the report file was created."""
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"


def test_isolated_batch_mean():
    """Verify that the isolated second-batch mean is zero."""
    content = read_report()
    match = re.search(r'Isolated Batch 2 Data Mean:\s*(-?\d+\.\d+)', content)
    assert match is not None, "Could not find 'Isolated Batch 2 Data Mean' in the report."
    val = float(match.group(1))
    assert val == 0.0, f"Isolated Batch 2 Data Mean should be 0.00, but got {match.group(1)}"


def test_leaky_batch_mean():
    """Preserve the original leaky-mean correctness assertion."""
    content = read_report()
    match = re.search(r'Leaky Batch 2 Data Mean:\s*(-?\d+\.\d+)', content)
    assert match is not None, "Could not find 'Leaky Batch 2 Data Mean' in the report."
    val = float(match.group(1))
    assert 0.10 < val < 0.20, \
        f"Leaky Batch 2 Data Mean should be between 0.10 and 0.20, but got {val}"


def test_data_means_against_generated_reference():
    subprocess.run(['gcc', '-std=c11', '/tmp/reference_means.c',
                    '-o', '/tmp/reference_means'], check=True,
                   timeout=20, capture_output=True, text=True)
    output = subprocess.run(['/tmp/reference_means'], check=True, timeout=20,
                            capture_output=True, text=True).stdout.split()
    expected_iso, expected_leak = map(float, output)
    values = parsed_report()
    actual_iso, actual_leak = values[3], values[7]
    assert actual_iso == expected_iso
    assert actual_leak == expected_leak


def test_confidence_intervals_format():
    """Verify the confidence intervals are formatted correctly and ordered."""
    content = read_report()
    isolated = re.search(r'Isolated Time 95% CI:\s*\[\[(-?\d+\.\d+)\],\s*\[(-?\d+\.\d+)\]\]', content)
    leaky = re.search(r'Leaky Time 95% CI:\s*\[\[(-?\d+\.\d+)\],\s*\[(-?\d+\.\d+)\]\]', content)
    assert isolated is not None, 'Isolated Time 95% CI format is incorrect or missing.'
    assert leaky is not None, 'Leaky Time 95% CI format is incorrect or missing.'
    iso_lower, iso_upper = map(float, isolated.groups())
    leaky_lower, leaky_upper = map(float, leaky.groups())
    assert iso_lower <= iso_upper
    assert leaky_lower <= leaky_upper


def test_mean_time_format():
    """Verify the mean time fields retain the required format."""
    content = read_report()
    assert re.search(r'Isolated Mean Time:\s*(-?\d+\.\d+)\s*us', content)
    assert re.search(r'Leaky Mean Time:\s*(-?\d+\.\d+)\s*us', content)


def test_timing_statistics_are_computed_from_measurements():
    values = parsed_report()
    iso_mean, iso_low, iso_high = values[0], values[1], values[2]
    leak_mean, leak_low, leak_high = values[4], values[5], values[6]

    iso_times = [float(i) for i in range(1, 101)]
    leak_times = [float(i) for i in range(101, 201)]
    assert close_to_rounded(iso_mean, sum(iso_times) / 100.0)
    assert close_to_rounded(leak_mean, sum(leak_times) / 100.0)

    iso_options = [expected_ci(iso_times, False), expected_ci(iso_times, True)]
    leak_options = [expected_ci(leak_times, False), expected_ci(leak_times, True)]
    assert any(close_to_rounded(iso_low, low) and close_to_rounded(iso_high, high)
               for low, high in iso_options), 'Isolated CI was not calculated from the 100 timings'
    assert any(close_to_rounded(leak_low, low) and close_to_rounded(leak_high, high)
               for low, high in leak_options), 'Leaky CI was not calculated from the 100 timings'
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
