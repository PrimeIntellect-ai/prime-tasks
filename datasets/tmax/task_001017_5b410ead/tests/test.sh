#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import subprocess
import sys
import textwrap

SOLVER_DIR = "/home/user/solver"
SO_PATH = os.path.join(SOLVER_DIR, "libsolver.so")
API_PATH = "/home/user/solve_api.py"
RESULTS_PATH = "/home/user/results.json"
ADS = [15, 30, 45, 60, 90, 120]
TARGETS = [105, 110, 135, 140, 210, 250]
EXPECTED = {
    "105": True,
    "110": False,
    "135": True,
    "140": False,
    "210": True,
    "250": False,
}


def run_make():
    if os.path.exists(SO_PATH):
        os.remove(SO_PATH)
    proc = subprocess.run(
        ["make"], cwd=SOLVER_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f"make failed:\n{proc.stdout}"
    assert os.path.isfile(SO_PATH), "make did not create libsolver.so"


def run_api():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    proc = subprocess.run(
        [sys.executable, API_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f"solve_api.py failed:\n{proc.stdout}"
    assert os.path.isfile(RESULTS_PATH), "solve_api.py did not create results.json"
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"{RESULTS_PATH} is not valid JSON: {exc}"


def python_subset_sum(arr, target):
    reachable = {0}
    for value in arr:
        reachable |= {subtotal + value for subtotal in list(reachable)}
    return target in reachable


def test_make_and_shared_object():
    run_make()

    # Preserve the original shared-object assertions.
    assert os.path.isfile(SO_PATH), f"{SO_PATH} does not exist. The Makefile might not have compiled it."
    with open(SO_PATH, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"{SO_PATH} is not a valid ELF file."
        f.seek(16)
        e_type = int.from_bytes(f.read(2), byteorder="little")
        assert e_type == 3, f"{SO_PATH} is not compiled as a shared object library. Ensure -shared and -fPIC were used."


def test_solve_api_exists_and_uses_ctypes_and_calls_c():
    assert os.path.isfile(API_PATH), f"{API_PATH} does not exist."
    with open(API_PATH, "r") as f:
        content = f.read()
    assert "ctypes" in content, f"{API_PATH} does not appear to use the 'ctypes' module."

    # Temporarily replace the built library with an instrumented implementation.
    # Its answers intentionally differ from the task answers, proving the Python
    # output comes from calls to subset_sum rather than a hardcoded dictionary.
    spy_source = r'''
#include <stdio.h>
int subset_sum(int* arr, int n, int target) {
    FILE *f = fopen("/tmp/solver_calls.log", "a");
    if (f) {
        fprintf(f, "%d %d", target, n);
        for (int i = 0; i < n; i++) fprintf(f, " %d", arr[i]);
        fprintf(f, "\n");
        fclose(f);
    }
    return target % 3 != 0;
}
'''
    with open("/tmp/spy_solver.c", "w") as f:
        f.write(spy_source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", "/tmp/spy_solver.so", "/tmp/spy_solver.c"],
        check=True, timeout=30
    )
    if os.path.exists("/tmp/solver_calls.log"):
        os.remove("/tmp/solver_calls.log")

    spy_data = None
    try:
        os.replace("/tmp/spy_solver.so", SO_PATH)
        spy_data = run_api()
    finally:
        # Restore the actual artifact produced by the submitted Makefile.
        run_make()

    for target in TARGETS:
        expected = (target % 3 != 0)
        assert str(target) in spy_data, f"Key '{target}' missing from instrumented run"
        assert spy_data[str(target)] is expected, (
            f"solve_api.py did not use subset_sum's return value for target {target}"
        )

    assert os.path.isfile("/tmp/solver_calls.log"), "solve_api.py never called subset_sum"
    calls = []
    with open("/tmp/solver_calls.log", "r") as f:
        for line in f:
            fields = [int(x) for x in line.split()]
            assert len(fields) >= 2
            target, n = fields[:2]
            values = fields[2:]
            assert len(values) == n
            calls.append((target, values))

    for target in TARGETS:
        assert (target, ADS) in calls, (
            f"subset_sum was not called with ads {ADS} and target {target}"
        )


def test_c_solver_on_derived_cases():
    lib = ctypes.CDLL(SO_PATH)
    subset_sum = lib.subset_sum
    subset_sum.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int, ctypes.c_int]
    subset_sum.restype = ctypes.c_int

    rng = random.Random(8431)
    cases = [([], 0), ([], 17), ([1], 0), ([7], 7), ([7], 8), (ADS, 250)]
    for _ in range(80):
        arr = [rng.randint(1, 50) for _ in range(rng.randint(0, 11))]
        target = rng.randint(0, 220)
        cases.append((arr, target))

    for arr, target in cases:
        c_arr = (ctypes.c_int * len(arr))(*arr)
        actual = subset_sum(c_arr, len(arr), target)
        expected = python_subset_sum(arr, target)
        assert actual in (0, 1), f"subset_sum returned non-boolean value {actual}"
        assert bool(actual) == expected, (
            f"subset_sum({arr}, {len(arr)}, {target}) returned {actual}, expected {expected}"
        )


def test_solver_memory_safety_with_asan():
    harness = r'''
#include <stdio.h>
extern int subset_sum(int* arr, int n, int target);
int main(void) {
    int a[] = {15, 30, 45, 60, 90, 120};
    for (int target = 0; target <= 512; target++) {
        int result = subset_sum(a, 6, target);
        if (result != 0 && result != 1) return 2;
    }
    return 0;
}
'''
    with open("/tmp/asan_harness.c", "w") as f:
        f.write(harness)
    compile_proc = subprocess.run(
        ["gcc", "-O1", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
         "-fno-sanitize-recover=all", "/home/user/solver/solver.c",
         "/tmp/asan_harness.c", "-o", "/tmp/asan_solver_test"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert compile_proc.returncode == 0, f"ASan compilation failed:\n{compile_proc.stdout}"
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "halt_on_error=1:detect_leaks=1"
    run_proc = subprocess.run(
        ["/tmp/asan_solver_test"], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert run_proc.returncode == 0, f"Memory-safety test failed:\n{run_proc.stdout}"


def test_results_json_from_real_execution():
    data = run_api()

    # Preserve the original results assertions, now against freshly generated output.
    for k, v in EXPECTED.items():
        assert str(k) in data, f"Key '{k}' missing in results.json"
        assert data[str(k)] is v, f"Expected target '{k}' to be {v}, got {data[str(k)]}."


def test_solver_c_fixed():
    c_path = "/home/user/solver/solver.c"
    assert os.path.isfile(c_path), f"{c_path} does not exist."
    with open(c_path, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    buggy_malloc = "malloc(target * sizeof(int))"
    assert buggy_malloc not in content, "solver.c still contains the memory safety bug (allocating exactly 'target' elements instead of 'target + 1')."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
