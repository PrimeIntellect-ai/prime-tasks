#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import shutil
import subprocess

import numpy as np
import pytest

MODULE = "/home/user/math_module"
LIB = os.path.join(MODULE, "libmathops.so")
FFI = os.path.join(MODULE, "ffi_test.py")
RESULT = "/home/user/result.txt"


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    makefile = os.path.join(MODULE, "Makefile")
    assert os.path.isfile(makefile), "Missing Makefile"
    text = open(makefile, encoding="utf-8").read()
    assert "-fPIC" in text, "Makefile must compile position-independent code with -fPIC"
    assert "-shared" in text, "Makefile must link libmathops.so as a shared library with -shared"

    if os.path.exists(LIB):
        os.remove(LIB)
    proc = subprocess.run(
        ["make", "-C", MODULE], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f"Running make failed:\n{proc.stdout}"
    assert os.path.isfile(LIB), "make did not create libmathops.so"

    elf = subprocess.run(
        ["readelf", "-h", LIB], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert elf.returncode == 0 and re.search(r"Type:\s+DYN", elf.stdout), \
        "libmathops.so is not an ELF shared object"

    assert os.path.isfile(FFI), f"Missing Python FFI script at {FFI}"

    # Replace the library temporarily with an instrumented ABI-compatible probe.
    # This proves that ffi_test.py loads libmathops.so and calls compute_poly with
    # the required float32 linspace input and size, rather than creating result.txt
    # solely in Python.
    probe_c = "/tmp/ffi_probe.c"
    probe_so = "/tmp/ffi_probe.so"
    marker = "/tmp/compute_poly_called"
    with open(probe_c, "w", encoding="utf-8") as f:
        f.write(r'''
#include <math.h>
#include <stdio.h>
void compute_poly(const float* input, float* output, int size) {
    if (!input || !output || size != 100000) return;
    for (int i = 0; i < size; i += 997) {
        float expected = (10.0f * (float)i) / 99999.0f;
        if (fabsf(input[i] - expected) > 0.00003f) return;
    }
    if (fabsf(input[0]) > 0.000001f || fabsf(input[99999] - 10.0f) > 0.000001f) return;
    FILE *m = fopen("/tmp/compute_poly_called", "w");
    if (!m) return;
    fputs("called", m);
    fclose(m);
    for (int i = 0; i < size; i++) {
        float x = input[i];
        output[i] = 2.5f*x*x*x - 1.2f*x*x + 0.5f*x - 3.1f;
    }
}
''')
    cc = subprocess.run(
        ["gcc", "-shared", "-fPIC", probe_c, "-o", probe_so],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert cc.returncode == 0, f"Could not build verifier probe:\n{cc.stdout}"

    backup = os.path.join(MODULE, ".agent-libmathops.so")
    if os.path.exists(marker):
        os.remove(marker)
    os.replace(LIB, backup)
    try:
        shutil.copy2(probe_so, LIB)
        if os.path.exists(RESULT):
            os.remove(RESULT)
        run = subprocess.run(
            ["python3", FFI], cwd=MODULE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert run.returncode == 0, f"ffi_test.py failed with the probe library:\n{run.stdout}"
        assert os.path.isfile(marker), \
            "ffi_test.py did not call compute_poly through libmathops.so with the required float32 input"
    finally:
        if os.path.exists(LIB):
            os.remove(LIB)
        os.replace(backup, LIB)

    # Generate the final submitted result using the agent's actual rebuilt library.
    if os.path.exists(RESULT):
        os.remove(RESULT)
    run = subprocess.run(
        ["python3", FFI], cwd=MODULE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert run.returncode == 0, f"ffi_test.py failed with the submitted library:\n{run.stdout}"


def test_patch_was_applied():
    source = os.path.join(MODULE, "mathops.c")
    assert os.path.isfile(source), "Missing mathops.c"
    text = open(source, encoding="utf-8").read()
    assert "unrolled loop or optimization marker" in text, \
        "fast_math.patch was not applied to mathops.c"

    version = open(os.path.join(MODULE, "version.txt"), encoding="utf-8").read().strip()
    parts = tuple(int(p) for p in version.split("."))
    assert parts >= (1, 4, 0), "Build core version does not satisfy the specification"


def test_libmathops_so_exists():
    assert os.path.isfile(LIB), f"Missing shared library at {LIB}. Did the Makefile run successfully?"


def test_ffi_test_py_exists():
    assert os.path.isfile(FFI), f"Missing Python FFI script at {FFI}"


def test_compiled_compute_poly_on_derived_inputs():
    lib = ctypes.CDLL(LIB)
    fn = lib.compute_poly
    fn.argtypes = [
        np.ctypeslib.ndpointer(dtype=np.float32, flags="C_CONTIGUOUS"),
        np.ctypeslib.ndpointer(dtype=np.float32, flags="C_CONTIGUOUS"),
        ctypes.c_int,
    ]
    fn.restype = None

    rng = np.random.default_rng(73921)
    x = rng.uniform(-7.0, 13.0, size=4099).astype(np.float32)
    output = np.full(x.shape, np.nan, dtype=np.float32)
    fn(x, output, x.size)

    expected = (2.5 * x.astype(np.float64) ** 3
                - 1.2 * x.astype(np.float64) ** 2
                + 0.5 * x.astype(np.float64) - 3.1)
    assert np.all(np.isfinite(output)), "compute_poly did not populate every output element"
    assert np.allclose(output.astype(np.float64), expected, rtol=2e-6, atol=0.003), \
        "The compute_poly symbol in libmathops.so computes the wrong polynomial"


def test_result_file_exists():
    assert os.path.isfile(RESULT), f"Missing result file at {RESULT}"


def test_result_has_required_format():
    with open(RESULT, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert len(lines) == 100000, f"Expected 100,000 lines in {RESULT}, got {len(lines)}"
    pattern = re.compile(r"^[+-]?\d+\.\d{4}$")
    assert all(pattern.fullmatch(line) for line in lines), \
        "Every result line must contain one finite float formatted to exactly 4 decimal places"


def test_result_mse():
    path = RESULT
    assert os.path.isfile(path), f"Result file {path} not found."

    try:
        with open(path, "r") as f:
            agent_out = np.array([float(line.strip()) for line in f.readlines()])
    except Exception as e:
        pytest.fail(f"Failed to read and parse {path}: {e}")

    assert len(agent_out) == 100000, f"Expected 100,000 lines in {path}, got {len(agent_out)}"

    x = np.linspace(0.0, 10.0, 100000, dtype=np.float32)
    expected = 2.5 * (x**3) - 1.2 * (x**2) + 0.5 * x - 3.1
    mse = np.mean((agent_out - expected)**2)

    threshold = 0.001
    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}. The polynomial calculation is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
