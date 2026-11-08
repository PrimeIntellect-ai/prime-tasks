#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import subprocess

ROOT = "/home/user/rust_ffi_project"
CRATE = ROOT + "/sorter"
LIB = CRATE + "/target/release/libsorter.so"
SCRIPT = ROOT + "/benchmark.py"


def test_cargo_toml_cdylib():
    path = CRATE + "/Cargo.toml"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "cdylib" in content, "Cargo.toml is missing 'cdylib' crate-type configuration."


def test_lib_rs_fixes():
    path = CRATE + "/src/lib.rs"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "#[no_mangle]" in content, "lib.rs is missing #[no_mangle] directive for the FFI functions."
    assert "extern \"C\"" in content, "lib.rs is missing extern \"C\" directive for the FFI functions."


def test_shared_library_exists():
    subprocess.run(["cargo", "clean"], cwd=CRATE, check=True, timeout=60)
    subprocess.run(["cargo", "build", "--release"], cwd=CRATE, check=True, timeout=180)
    assert os.path.isfile(LIB), f"Compiled shared library not found at {LIB}. Make sure you built it with --release."


def test_exported_rust_functions_sort_correctly():
    library = ctypes.CDLL(LIB)
    functions = [library.merge_sort_ffi, library.quick_sort_ffi]
    cases = [
        [],
        [7],
        [5, -1, 5, 0, -2147483648, 2147483647, 3, -1],
        list(range(100, -101, -1)),
    ]
    rng = random.Random(73129)
    cases.append([rng.randint(-1000000, 1000000) for _ in range(4097)])

    for function in functions:
        function.argtypes = [ctypes.POINTER(ctypes.c_int32), ctypes.c_size_t]
        function.restype = None
        function(None, 0)
        for values in cases:
            expected = sorted(values)
            if values:
                array = (ctypes.c_int32 * len(values))(*values)
                function(array, len(values))
                actual = list(array)
            else:
                actual = []
            assert actual == expected


def test_benchmark_script_exists():
    assert os.path.isfile(SCRIPT), f"Python script not found at {SCRIPT}."
    with open(SCRIPT, "r") as f:
        content = f.read()
    compile(content, SCRIPT, "exec")
    assert "ctypes" in content, "benchmark.py must use ctypes."
    assert "argtypes" in content and "restype" in content, "benchmark.py must define ctypes signatures."
    assert "perf_counter" in content, "benchmark.py must measure with time.perf_counter()."


def _fnv_hash(values):
    value = 1469598103934665603
    for item in values:
        value ^= item & 0xffffffff
        value = (value * 1099511628211) & 0xffffffffffffffff
    return value


def test_benchmark_script_calls_both_algorithms_as_required():
    proxy_source = "/tmp/sorter_proxy.c"
    proxy_library = "/tmp/libsorter_proxy.so"
    call_log = "/tmp/ffi_calls.log"
    backup = "/tmp/libsorter_real.so"

    source = r'''
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

static int compare_i32(const void *a, const void *b) {
    int32_t x = *(const int32_t *)a;
    int32_t y = *(const int32_t *)b;
    return (x > y) - (x < y);
}

static void record_and_sort(const char *name, int32_t *data, size_t len) {
    uint64_t hash = UINT64_C(1469598103934665603);
    for (size_t i = 0; i < len; ++i) {
        hash ^= (uint32_t)data[i];
        hash *= UINT64_C(1099511628211);
    }
    FILE *f = fopen("/tmp/ffi_calls.log", "a");
    if (f) {
        fprintf(f, "%s %zu %016llx\n", name, len, (unsigned long long)hash);
        fclose(f);
    }
    if (data && len > 1) qsort(data, len, sizeof(int32_t), compare_i32);
}

void merge_sort_ffi(int32_t *data, size_t len) {
    record_and_sort("merge", data, len);
}

void quick_sort_ffi(int32_t *data, size_t len) {
    record_and_sort("quick", data, len);
}
'''
    with open(proxy_source, "w") as f:
        f.write(source)
    subprocess.run(["cc", "-shared", "-fPIC", "-O2", proxy_source, "-o", proxy_library], check=True)

    for path in (call_log, backup, ROOT + "/verification.txt", ROOT + "/report.txt"):
        if os.path.exists(path):
            os.remove(path)

    os.replace(LIB, backup)
    os.replace(proxy_library, LIB)
    try:
        result = subprocess.run(
            ["python3", SCRIPT], cwd=ROOT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
        )
        assert result.returncode == 0, "benchmark.py failed:\n" + result.stdout
    finally:
        if os.path.exists(LIB):
            os.remove(LIB)
        os.replace(backup, LIB)

    assert os.path.isfile(call_log), "benchmark.py did not call the shared-library functions."
    calls = {"merge": [], "quick": []}
    with open(call_log, "r") as f:
        for line in f:
            fields = line.split()
            assert len(fields) == 3, f"Malformed instrumentation record: {line!r}"
            name, length, hash_text = fields
            assert name in calls
            calls[name].append((int(length), int(hash_text, 16)))

    # One verification call and five benchmark calls are required per algorithm.
    assert len(calls["merge"]) == 6, f"Expected 6 merge-sort calls, got {len(calls['merge'])}."
    assert len(calls["quick"]) == 6, f"Expected 6 quick-sort calls, got {len(calls['quick'])}."
    assert all(length == 50000 for records in calls.values() for length, _ in records), \
        "Every verification and benchmark call must sort 50,000 elements."

    rng = random.Random(42)
    generated = [rng.randint(0, 1000000) for _ in range(50000)]
    generated_hash = _fnv_hash(generated)
    for name in ("merge", "quick"):
        hashes = [item_hash for _, item_hash in calls[name]]
        assert generated_hash in hashes, f"{name} did not sort a copy of the required seeded input."
        assert sum(item_hash != generated_hash for item_hash in hashes) == 5, \
            f"{name} must benchmark five freshly shuffled copies."


def test_verification_txt():
    path = ROOT + "/verification.txt"
    assert os.path.isfile(path), f"Verification file not found at {path}. Did the benchmark script run successfully?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "MATCH", f"Expected 'MATCH' in verification.txt, but got '{content}'."


def test_report_txt():
    path = ROOT + "/report.txt"
    assert os.path.isfile(path), f"Report file not found at {path}. Did the benchmark script run successfully?"
    with open(path, "r") as f:
        content = f.read().strip()
    pattern = r"^Algorithm: Merge Sort, Avg Time: \d+\.\d{4} seconds\nAlgorithm: Quick Sort, Avg Time: \d+\.\d{4} seconds$"
    assert re.match(pattern, content), "report.txt does not match the expected format with 4 decimal places."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
