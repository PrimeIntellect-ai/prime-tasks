#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import statistics
import subprocess
import tempfile
import pytest

CJSON_DIR = '/app/cJSON-1.7.15'
SO_PATH = os.path.join(CJSON_DIR, 'libcjson.so')
BIN_PATH = '/home/user/pipeline/inference_pipeline'
INPUT_PATH = '/home/user/data/input.csv'
LOG_PATH = '/home/user/pipeline/experiment_log.json'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_cjson_built():
    # The package must still build from the repaired source, not merely have a
    # placeholder file bearing the expected name.
    result = run(['make', 'clean'], cwd=CJSON_DIR, timeout=30)
    assert result.returncode == 0, f"make clean failed:\n{result.stdout}\n{result.stderr}"
    result = run(['make', '-j2'], cwd=CJSON_DIR, timeout=60)
    assert result.returncode == 0, f"cJSON build failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SO_PATH), f"{SO_PATH} is missing. cJSON was not built correctly."

    # Load the product and exercise exported cJSON code.
    try:
        lib = ctypes.CDLL(SO_PATH)
        lib.cJSON_Parse.argtypes = [ctypes.c_char_p]
        lib.cJSON_Parse.restype = ctypes.c_void_p
        lib.cJSON_Delete.argtypes = [ctypes.c_void_p]
        obj = lib.cJSON_Parse(b'{"probe":[1,-1,3]}')
        assert obj, 'libcjson.so could not parse valid JSON.'
        lib.cJSON_Delete(obj)
    except OSError as exc:
        pytest.fail(f"libcjson.so could not be loaded: {exc}")


def test_pipeline_binary_exists():
    assert os.path.isfile(BIN_PATH), f"{BIN_PATH} is missing. Pipeline was not compiled."
    assert os.access(BIN_PATH, os.X_OK), f"{BIN_PATH} is not executable."

    linked = run(['ldd', BIN_PATH], timeout=10)
    assert linked.returncode == 0, f"Could not inspect pipeline linkage:\n{linked.stdout}\n{linked.stderr}"
    assert 'libcjson' in (linked.stdout + linked.stderr).lower(), \
        'The pipeline executable is not linked against the repaired cJSON library.'


def integer_leaves(obj):
    out = []
    if isinstance(obj, bool):
        return out
    if isinstance(obj, int):
        out.append(obj)
    elif isinstance(obj, dict):
        for value in obj.values():
            out.extend(integer_leaves(value))
    elif isinstance(obj, list):
        for value in obj:
            out.extend(integer_leaves(value))
    return out


def contains_contiguous(haystack, needle):
    if not needle:
        return True
    return any(haystack[i:i + len(needle)] == needle
               for i in range(len(haystack) - len(needle) + 1))


def assert_no_floats(obj):
    if isinstance(obj, float):
        pytest.fail('Schema violation: Found floating-point numbers in experiment_log.json. Expected strictly integers (e.g., missing values as -1).')
    if isinstance(obj, dict):
        for value in obj.values():
            assert_no_floats(value)
    elif isinstance(obj, list):
        for value in obj:
            assert_no_floats(value)


def exercise_pipeline(rows, expected_values):
    with open(INPUT_PATH, 'w') as f:
        f.write('id,value\n')
        for row_id, token in rows:
            f.write(f'{row_id},{token}\n')

    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = CJSON_DIR + ':' + env.get('LD_LIBRARY_PATH', '')
    result = run([BIN_PATH], cwd='/home/user/pipeline', env=env, timeout=15)
    assert result.returncode == 0, f"Pipeline failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is missing. The pipeline did not generate the log."

    try:
        with open(LOG_PATH) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"{LOG_PATH} is not valid JSON: {exc}")

    assert data not in ({}, []), 'experiment_log.json is empty and does not represent input.csv.'
    assert_no_floats(data)

    ids = [row_id for row_id, _ in rows]
    row_major = [item for pair in zip(ids, expected_values) for item in pair]
    reverse_row_major = [item for pair in zip(expected_values, ids) for item in pair]
    leaves = integer_leaves(data)

    # Accommodate common logs organized as a value column, as row records, or
    # as column arrays, while requiring the randomized input-derived answers.
    represented = (
        contains_contiguous(leaves, expected_values) or
        contains_contiguous(leaves, row_major) or
        contains_contiguous(leaves, reverse_row_major)
    )
    assert represented, (
        'experiment_log.json does not contain the feature values derived from '
        'input.csv with invalid/missing values replaced by integer -1.'
    )
    return data


def test_experiment_log_schema():
    rng = secrets.SystemRandom()
    for _ in range(2):
        ids = rng.sample(range(100000, 900000), 6)
        valid = rng.sample(range(1000000, 9000000), 3)
        rows = [
            (ids[0], str(valid[0])),
            (ids[1], 'NaN'),
            (ids[2], str(valid[1])),
            (ids[3], ''),
            (ids[4], 'bogus'),
            (ids[5], str(valid[2])),
        ]
        exercise_pipeline(rows, [valid[0], -1, valid[1], -1, -1, valid[2]])


def test_inference_speedup():
    # Preserve the original verifier-script assertion.
    verify_path = '/app/verify.py'
    assert os.path.isfile(verify_path), f"{verify_path} is missing."
    result = run(['python3', verify_path], timeout=15)
    assert result.returncode == 0, f"Verifier failed. Output:\n{result.stdout}\nError:\n{result.stderr}"
    speedup_from_script = None
    for line in result.stdout.splitlines():
        if 'speedup' in line.lower():
            for word in line.split():
                try:
                    value = float(word.strip(','))
                    if value > 0:
                        speedup_from_script = value
                        break
                except ValueError:
                    pass
    if speedup_from_script is not None:
        assert speedup_from_script >= 2.0, f"Speedup is {speedup_from_script:.2f}, below 2.0."

    # Use a small functional workload so the measured hot-loop cost corresponds
    # to the original 100,000 repeated 1024-byte allocations.
    rows = [(1, '10'), (2, 'NaN'), (3, '20'), (4, ''), (5, '30')]
    exercise_pipeline(rows, [10, -1, 20, -1, 30])

    with tempfile.TemporaryDirectory() as td:
        counter_c = os.path.join(td, 'count_alloc.c')
        counter_so = os.path.join(td, 'count_alloc.so')
        counter_file = os.path.join(td, 'count.txt')
        with open(counter_c, 'w') as f:
            f.write(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned long calls;
static void *(*real_malloc)(size_t);
static void *(*real_calloc)(size_t,size_t);
static void *(*real_realloc)(void*,size_t);
void *malloc(size_t n) { if (!real_malloc) real_malloc=dlsym(RTLD_NEXT,"malloc"); calls++; return real_malloc(n); }
void *calloc(size_t a,size_t b) { if (!real_calloc) real_calloc=dlsym(RTLD_NEXT,"calloc"); calls++; return real_calloc(a,b); }
void *realloc(void *p,size_t n) { if (!real_realloc) real_realloc=dlsym(RTLD_NEXT,"realloc"); calls++; return real_realloc(p,n); }
__attribute__((destructor)) static void report(void) {
    const char *p=getenv("ALLOC_COUNT_FILE");
    if (p) { FILE *f=fopen(p,"w"); if (f) { fprintf(f,"%lu\n",calls); fclose(f); } }
}
''')
        build = run(['cc', '-shared', '-fPIC', '-O2', counter_c, '-ldl', '-o', counter_so], timeout=20)
        assert build.returncode == 0, f"Allocation counter build failed:\n{build.stderr}"

        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = CJSON_DIR + ':' + env.get('LD_LIBRARY_PATH', '')
        env['LD_PRELOAD'] = counter_so
        env['ALLOC_COUNT_FILE'] = counter_file
        counted = run([BIN_PATH], cwd='/home/user/pipeline', env=env, timeout=15)
        assert counted.returncode == 0, f"Instrumented pipeline failed:\n{counted.stderr}"
        assert os.path.isfile(counter_file), 'Could not measure pipeline allocations.'
        with open(counter_file) as f:
            allocation_calls = int(f.read().strip())
        assert allocation_calls < 5000, (
            f'Pipeline made {allocation_calls} dynamic allocations on five rows; '
            'the repeated allocations remain in the hot loop.'
        )

        bench_c = os.path.join(td, 'alloc_bench.c')
        bench_bin = os.path.join(td, 'alloc_bench')
        with open(bench_c, 'w') as f:
            f.write(r'''
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define BLOCKS 20
int main(void) {
    struct timespec a,b;
    volatile unsigned char sink=0;
    clock_gettime(CLOCK_MONOTONIC,&a);
    for (int r=0;r<BLOCKS;r++) for (int i=0;i<100000;i++) {
        unsigned char *p=(unsigned char*)malloc(1024);
        if (!p) return 2;
        p[0]=(unsigned char)i;
        sink ^= p[0];
        free(p);
    }
    clock_gettime(CLOCK_MONOTONIC,&b);
    double sec=(b.tv_sec-a.tv_sec)+(b.tv_nsec-a.tv_nsec)/1e9;
    printf("%.12f\n",sec/BLOCKS);
    return sink == 255;
}
''')
        build = run(['cc', '-O0', bench_c, '-o', bench_bin], timeout=20)
        assert build.returncode == 0, f"Reference benchmark build failed:\n{build.stderr}"
        allocation_run = run([bench_bin], timeout=30)
        assert allocation_run.returncode == 0, allocation_run.stderr
        allocation_time = float(allocation_run.stdout.strip())

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = CJSON_DIR + ':' + env.get('LD_LIBRARY_PATH', '')
    timings = []
    for _ in range(7):
        start = __import__('time').perf_counter()
        measured = run([BIN_PATH], cwd='/home/user/pipeline', env=env, timeout=15)
        timings.append(__import__('time').perf_counter() - start)
        assert measured.returncode == 0, measured.stderr
    optimized_time = statistics.median(timings)
    speedup = (optimized_time + allocation_time) / optimized_time
    assert speedup >= 2.0, (
        f'Measured speedup is {speedup:.2f}x (optimized {optimized_time:.6f}s, '
        f'original allocation cost {allocation_time:.6f}s), below 2.0x.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
