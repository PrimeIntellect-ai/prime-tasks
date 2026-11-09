#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import uuid
from pathlib import Path

PROJECT = Path('/home/user/hybrid_image_filter')
FILTER_C = PROJECT / 'c_src/filter.c'
SCRIPT = Path('/home/user/run_validation.sh')
BENCH_RESULT = Path('/home/user/benchmark_result.txt')


def test_filter_c_fixed():
    filter_c_path = "/home/user/hybrid_image_filter/c_src/filter.c"
    assert os.path.exists(filter_c_path), f"{filter_c_path} does not exist"

    with open(filter_c_path, "r") as f:
        content = f.read()

    # Keep the original source-level assertions in addition to behavioral tests.
    assert re.search(r"malloc\s*\(\s*width\s*\*\s*height\s*\*\s*sizeof\s*\(\s*int\s*\)\s*\)", content), "Allocation size in filter.c is still incorrect"
    assert not re.search(r"i\s*<=\s*width\s*\*\s*height", content), "Off-by-one error (<=) is still present in filter.c"
    assert re.search(r"i\s*<\s*width\s*\*\s*height", content), "Loop condition should use < width * height"
    assert re.search(r"free\s*\(\s*temp_buffer\s*\)", content), "temp_buffer is not freed in filter.c"


def test_filter_under_sanitizers_and_for_correct_output(tmp_path):
    harness = tmp_path / 'filter_harness.c'
    binary = tmp_path / 'filter_harness'
    harness.write_text(r'''
#include <stdio.h>
#include <stdlib.h>

extern int* apply_filter(int*, int, int);
extern void free_image(int*);

static int run_case(int w, int h, int seed) {
    int n = w * h;
    int *input = malloc((size_t)n * sizeof(int));
    if (!input) return 20;
    for (int i = 0; i < n; ++i) input[i] = seed + i * 7 - 31;

    int *output = apply_filter(input, w, h);
    if (!output) { free(input); return 21; }
    for (int i = 0; i < n; ++i) {
        if (output[i] != input[i] * 2) {
            free_image(output);
            free(input);
            return 22;
        }
    }
    free_image(output);
    free(input);
    return 0;
}

int main(void) {
    const int cases[][3] = {{1,1,4}, {3,5,-9}, {10,10,2}, {127,3,11}};
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        int rc = run_case(cases[i][0], cases[i][1], cases[i][2]);
        if (rc) return rc;
    }
    return 0;
}
''')
    compile_result = subprocess.run([
        'gcc', '-std=c11', '-g', '-O1', '-fno-omit-frame-pointer',
        '-fsanitize=address,undefined', str(harness), str(FILTER_C), '-o', str(binary)
    ], capture_output=True, text=True)
    assert compile_result.returncode == 0, compile_result.stdout + compile_result.stderr

    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1:abort_on_error=1'
    env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
    run_result = subprocess.run([str(binary)], capture_output=True, text=True, env=env)
    assert run_result.returncode == 0, run_result.stdout + run_result.stderr


def test_run_validation_script_exists_and_executable():
    script_path = "/home/user/run_validation.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"


def test_run_validation_script_success():
    nonce = uuid.uuid4().hex
    sanity_marker = Path('/tmp') / f'sanity-ran-{nonce}'
    bench_marker = Path('/tmp') / f'bench-ran-{nonce}'
    cargo_marker = Path('/tmp') / f'cargo-test-ran-{nonce}'
    sanity_path = PROJECT / 'c_src/sanity_check.c'
    bench_path = PROJECT / 'c_src/bench.c'
    tests_dir = PROJECT / 'tests'
    rust_test = tests_dir / f'verifier_{nonce}.rs'
    old_sanity = sanity_path.read_bytes()
    old_bench = bench_path.read_bytes()

    sanity_source = r'''
#include <stdio.h>
#include <stdlib.h>
extern int* apply_filter(int*, int, int);
extern void free_image(int*);
int main(void) {
    int sizes[][2] = {{1,1}, {7,9}, {10,10}};
    for (unsigned c = 0; c < sizeof(sizes)/sizeof(sizes[0]); ++c) {
        int w = sizes[c][0], h = sizes[c][1], n = w*h;
        int *pixels = malloc((size_t)n * sizeof(int));
        if (!pixels) return 2;
        for (int i = 0; i < n; ++i) pixels[i] = i - 17;
        int *out = apply_filter(pixels, w, h);
        if (!out) { free(pixels); return 3; }
        for (int i = 0; i < n; ++i) {
            if (out[i] != pixels[i] * 2) {
                free_image(out); free(pixels); return 4;
            }
        }
        free_image(out);
        free(pixels);
    }
#ifdef __SANITIZE_ADDRESS__
    FILE *f = fopen("@MARK@", "w");
    if (!f) return 5;
    fputs("asan sanity executed\n", f);
    fclose(f);
#endif
    return 0;
}
'''.replace('@MARK@', str(sanity_marker))

    bench_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#ifndef __OPTIMIZE__
#error "The benchmark must be compiled with optimization enabled"
#endif
extern int* apply_filter(int*, int, int);
extern void free_image(int*);
int main(void) {
    int w = 100, h = 100, n = w*h;
    int *pixels = malloc((size_t)n * sizeof(int));
    if (!pixels) return 2;
    for (int i = 0; i < n; ++i) pixels[i] = i;
    clock_t start = clock();
    for (int k = 0; k < 1000; ++k) {
        int *out = apply_filter(pixels, w, h);
        if (!out) { free(pixels); return 3; }
        free_image(out);
    }
    clock_t end = clock();
    double ms = ((double)(end-start) / CLOCKS_PER_SEC) * 1000.0;
    FILE *f = fopen("@MARK@", "w");
    if (!f) { free(pixels); return 4; }
    fprintf(f, "%.0f\n", ms);
    fclose(f);
    printf("%.0f\n", ms);
    free(pixels);
    return 0;
}
'''.replace('@MARK@', str(bench_marker))

    rust_source = '''#[test]\nfn verifier_cargo_test_was_run() {\n    std::fs::write("@MARK@", "cargo test executed\\n").unwrap();\n}\n'''.replace('@MARK@', str(cargo_marker))

    tests_dir.mkdir(exist_ok=True)
    for path in (sanity_marker, bench_marker, cargo_marker):
        if path.exists(): path.unlink()
    if BENCH_RESULT.exists(): BENCH_RESULT.unlink()

    try:
        sanity_path.write_text(sanity_source)
        bench_path.write_text(bench_source)
        rust_test.write_text(rust_source)
        env = os.environ.copy()
        env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1:abort_on_error=1'
        result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, env=env, timeout=240)
    finally:
        sanity_path.write_bytes(old_sanity)
        bench_path.write_bytes(old_bench)
        if rust_test.exists(): rust_test.unlink()

    assert result.returncode == 0, f"run_validation.sh failed with exit code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert sanity_marker.exists(), 'The script did not compile with AddressSanitizer and execute c_src/sanity_check.c'
    assert cargo_marker.exists(), 'The script did not execute the project tests with cargo test'
    assert bench_marker.exists(), 'The script did not compile with optimization and execute c_src/bench.c'
    assert BENCH_RESULT.exists(), f"{BENCH_RESULT} was not created by the script"
    measured = bench_marker.read_text().strip()
    assert re.fullmatch(r'\d+', measured), f'Invalid benchmark output: {measured!r}'
    assert BENCH_RESULT.read_text().strip() == f'BENCHMARK_MS={measured}', 'benchmark_result.txt does not contain the executed benchmark output'


def test_benchmark_result_format():
    bench_result = "/home/user/benchmark_result.txt"
    assert os.path.exists(bench_result), f"{bench_result} was not created by the script"
    with open(bench_result, "r") as f:
        content = f.read().strip()
    assert re.match(r"^BENCHMARK_MS=\d+$", content), f"Benchmark result format is incorrect. Expected 'BENCHMARK_MS=<value>', got: {content}"


def test_run_validation_returns_one_when_tests_fail():
    nonce = uuid.uuid4().hex
    tests_dir = PROJECT / 'tests'
    tests_dir.mkdir(exist_ok=True)
    failing_test = tests_dir / f'verifier_failure_{nonce}.rs'
    failing_test.write_text('#[test]\nfn deliberate_validation_failure() { panic!("deliberate verifier failure"); }\n')
    try:
        result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=240)
    finally:
        if failing_test.exists(): failing_test.unlink()
    assert result.returncode == 1, f"run_validation.sh must return 1 when cargo test fails; got {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
