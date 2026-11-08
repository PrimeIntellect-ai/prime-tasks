#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import textwrap

SOURCE = "/home/user/bootstrap_ci.c"
EXECUTABLE = "/home/user/bootstrap_ci"
DATASET = "/home/user/data/experiment.csv"
LOG = "/home/user/experiment_log.txt"
EXPECTED_ORIGINAL = "Feature: measurement_b, Filter: category=X, CI_Lower: 2.0143, CI_Upper: 2.2714"


def test_gsl_installed():
    header_path = "/usr/include/gsl/gsl_rng.h"
    assert os.path.isfile(header_path), (
        f"GSL development libraries do not appear to be installed. Expected to find {header_path}."
    )


def test_c_source_code_exists():
    assert os.path.isfile(SOURCE), f"C source file missing at {SOURCE}."


def test_executable_exists_and_runnable():
    assert os.path.isfile(EXECUTABLE), f"Compiled executable missing at {EXECUTABLE}."
    st = os.stat(EXECUTABLE)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), (
        f"File {EXECUTABLE} is not executable."
    )


def test_experiment_log_exists_and_content():
    assert os.path.isfile(LOG), f"Experiment log missing at {LOG}."
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, f"Log file {LOG} is empty."
    assert lines[-1] == EXPECTED_ORIGINAL, (
        f"The last line of {LOG} does not match the expected output.\n"
        f"Expected: '{EXPECTED_ORIGINAL}'\nFound: '{lines[-1]}'"
    )


def compile_helpers():
    wrapper_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <gsl/gsl_rng.h>

static gsl_rng *tracked = NULL;
static unsigned long long calls = 0;
static int mt_allocated = 0;
static int seeded_42 = 0;
static int bad_n = 0;

gsl_rng *gsl_rng_alloc(const gsl_rng_type *T) {
    static gsl_rng *(*real_fn)(const gsl_rng_type *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "gsl_rng_alloc");
    gsl_rng *result = real_fn(T);
    if (T == gsl_rng_mt19937) {
        mt_allocated = 1;
        tracked = result;
    }
    return result;
}

void gsl_rng_set(const gsl_rng *r, unsigned long int seed) {
    static void (*real_fn)(const gsl_rng *, unsigned long int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "gsl_rng_set");
    if (r == tracked && seed == 42UL) seeded_42 = 1;
    real_fn(r, seed);
}

unsigned long int gsl_rng_uniform_int(const gsl_rng *r, unsigned long int n) {
    static unsigned long int (*real_fn)(const gsl_rng *, unsigned long int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "gsl_rng_uniform_int");
    const char *expected_text = getenv("EXPECTED_N");
    unsigned long expected = expected_text ? strtoul(expected_text, NULL, 10) : 0;
    if (r != tracked || n != expected) bad_n = 1;
    calls++;
    return real_fn(r, n);
}

__attribute__((destructor)) static void report_usage(void) {
    const char *path = getenv("GSL_STATS_FILE");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (!f) return;
    fprintf(f, "%d %d %d %llu\n", mt_allocated, seeded_42, bad_n, calls);
    fclose(f);
}
'''
    oracle_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gsl/gsl_rng.h>

static int cmp_double(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

int main(void) {
    FILE *f = fopen("/home/user/data/experiment.csv", "r");
    if (!f) return 2;
    char line[1024];
    double values[4096];
    size_t n = 0;
    if (!fgets(line, sizeof(line), f)) return 3;
    while (fgets(line, sizeof(line), f)) {
        char *save = NULL;
        char *id = strtok_r(line, ",", &save);
        char *a = strtok_r(NULL, ",", &save);
        char *b = strtok_r(NULL, ",", &save);
        char *cat = strtok_r(NULL, ",\r\n", &save);
        (void)id; (void)a;
        if (b && cat && strcmp(cat, "X") == 0) values[n++] = strtod(b, NULL);
    }
    fclose(f);
    if (n == 0) return 4;
    double means[10000];
    gsl_rng *r = gsl_rng_alloc(gsl_rng_mt19937);
    gsl_rng_set(r, 42);
    for (size_t i = 0; i < 10000; i++) {
        double sum = 0.0;
        for (size_t j = 0; j < n; j++)
            sum += values[gsl_rng_uniform_int(r, n)];
        means[i] = sum / (double)n;
    }
    gsl_rng_free(r);
    qsort(means, 10000, sizeof(double), cmp_double);
    printf("Feature: measurement_b, Filter: category=X, CI_Lower: %.4f, CI_Upper: %.4f\n",
           means[249], means[9749]);
    return 0;
}
'''
    with open("/tmp/gsl_usage_wrapper.c", "w") as f:
        f.write(wrapper_source)
    with open("/tmp/bootstrap_oracle.c", "w") as f:
        f.write(oracle_source)

    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "/tmp/gsl_usage_wrapper.c",
         "-o", "/tmp/gsl_usage_wrapper.so", "-ldl", "-lgsl"],
        check=True, capture_output=True, text=True
    )
    subprocess.run(
        ["gcc", "-O2", "/tmp/bootstrap_oracle.c", "-o", "/tmp/bootstrap_oracle",
         "-lgsl", "-lgslcblas", "-lm"],
        check=True, capture_output=True, text=True
    )
    subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", "/tmp/bootstrap_from_source",
         "-lgsl", "-lgslcblas", "-lm"],
        check=True, capture_output=True, text=True
    )


def nonempty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def run_and_check(executable, expected, n, label):
    with open(LOG, "w"):
        pass
    os.chown(LOG, 1000, 1000)
    os.chmod(LOG, 0o666)

    stats_path = f"/tmp/gsl_stats_{label}"
    with open(stats_path, "w"):
        pass
    os.chmod(stats_path, 0o666)

    command = [
        "runuser", "-u", "user", "--", "env",
        f"LD_PRELOAD=/tmp/gsl_usage_wrapper.so",
        f"EXPECTED_N={n}",
        f"GSL_STATS_FILE={stats_path}",
        executable,
    ]
    result = subprocess.run(
        command, cwd="/home/user", capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{executable} failed on verifier data with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    output_lines = nonempty_lines(result.stdout)
    with open(LOG, "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]
    observed = []
    if output_lines:
        observed.append(output_lines[-1])
    if log_lines:
        observed.append(log_lines[-1])
    assert expected in observed, (
        f"{executable} did not produce the required result for verifier data. "
        f"Expected '{expected}', observed {observed}."
    )

    with open(stats_path, "r") as f:
        stats = f.read().strip().split()
    assert len(stats) == 4, f"Could not verify GSL calls made by {executable}."
    mt_allocated, seeded_42, bad_n, calls = map(int, stats)
    assert mt_allocated == 1, "Program did not allocate gsl_rng_mt19937."
    assert seeded_42 == 1, "Program did not seed the MT19937 RNG with 42."
    assert bad_n == 0, "Program did not consistently call gsl_rng_uniform_int(r, N)."
    assert calls == n * 10000, (
        f"Expected exactly {n * 10000} gsl_rng_uniform_int calls for 10000 resamples; got {calls}."
    )


def test_source_and_executable_behavior():
    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    assert "gsl_rng_mt19937" in source_text, "Source does not use gsl_rng_mt19937."
    assert "gsl_rng_uniform_int" in source_text, "Source does not use gsl_rng_uniform_int."
    assert re.search(r"gsl_rng_set\s*\([^,]+,\s*42(?:[uUlL]*)\s*\)", source_text), (
        "Source does not call gsl_rng_set with seed 42."
    )
    assert re.search(r"(?<![0-9])10000(?![0-9])", source_text), (
        "Source does not specify 10000 bootstrap iterations."
    )

    compile_helpers()
    challenges = [
        textwrap.dedent("""\
            id,measurement_a,measurement_b,category
            1,1.0,10.25,X
            2,2.0,-3.50,Y
            3,3.0,4.75,X
            4,4.0,8.00,X
            5,5.0,100.0,XX
            6,6.0,-1.25,X
            7,7.0,13.50,X
        """),
        textwrap.dedent("""\
            id,measurement_a,measurement_b,category
            11,0.1,1.1,X
            12,0.2,9.4,Y
            13,0.3,2.7,X
            14,0.4,3.9,X
            15,0.5,5.2,X
            16,0.6,6.8,X
            17,0.7,8.3,X
            18,0.8,11.6,X
            19,0.9,14.2,X
            20,1.0,20.5,X
        """),
    ]
    counts = [5, 9]

    with open(DATASET, "rb") as f:
        original_data = f.read()
    with open(LOG, "rb") as f:
        original_log = f.read()
    data_stat = os.stat(DATASET)
    log_stat = os.stat(LOG)

    try:
        for index, (csv_text, n) in enumerate(zip(challenges, counts)):
            with open(DATASET, "w") as f:
                f.write(csv_text)
            os.chown(DATASET, 1000, 1000)
            os.chmod(DATASET, 0o644)

            oracle = subprocess.run(
                ["/tmp/bootstrap_oracle"], capture_output=True, text=True,
                check=True, timeout=30
            )
            expected_lines = nonempty_lines(oracle.stdout)
            assert len(expected_lines) == 1
            expected = expected_lines[0]

            run_and_check(EXECUTABLE, expected, n, f"installed_{index}")
            run_and_check("/tmp/bootstrap_from_source", expected, n, f"source_{index}")
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_data)
        os.chown(DATASET, data_stat.st_uid, data_stat.st_gid)
        os.chmod(DATASET, stat.S_IMODE(data_stat.st_mode))
        with open(LOG, "wb") as f:
            f.write(original_log)
        os.chown(LOG, log_stat.st_uid, log_stat.st_gid)
        os.chmod(LOG, stat.S_IMODE(log_stat.st_mode))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
