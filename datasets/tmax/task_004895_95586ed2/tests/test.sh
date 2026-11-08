#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import re
import shutil
import subprocess
import time

import pytest
from packaging.version import Version
from PIL import Image, ImageOps
import pytesseract

PROJECT = "/home/user/math_optimizer"
SO_PATH = os.path.join(PROJECT, "libmathops.so")
METRIC_PATH = os.path.join(PROJECT, "metric.txt")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def read_required_version():
    image_path = "/app/requirements.png"
    assert os.path.isfile(image_path), f"Requirements image missing at {image_path}"
    image = Image.open(image_path).convert("L")
    enlarged = ImageOps.autocontrast(image).resize(
        (image.width * 6, image.height * 6), Image.Resampling.LANCZOS
    )
    candidates = [
        pytesseract.image_to_string(image, config="--psm 6"),
        pytesseract.image_to_string(enlarged, config="--psm 6"),
        pytesseract.image_to_string(enlarged, config="--psm 7"),
    ]
    text = "\n".join(candidates)
    match = re.search(r"(?:v\s*)?(\d+\s*\.\s*\d+\s*\.\s*\d+)", text, re.I)
    assert match, f"Could not OCR a semantic version from requirements.png; OCR output was {text!r}"
    return Version(re.sub(r"\s+", "", match.group(1)))


def load_library(path=SO_PATH):
    lib = ctypes.CDLL(path)
    lib.get_version.argtypes = []
    lib.get_version.restype = ctypes.c_char_p
    lib.matrix_transform.argtypes = [ctypes.POINTER(ctypes.c_double)]
    lib.matrix_transform.restype = None
    return lib


def parse_metric():
    assert os.path.isfile(METRIC_PATH), f"Metric file not found at {METRIC_PATH}"
    content = open(METRIC_PATH, "r", encoding="utf-8").read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse execution time as float from {METRIC_PATH}. Content: {content}")
    assert math.isfinite(value) and value > 0, "Benchmark time must be a positive finite number"
    threshold = 0.5
    assert value <= threshold, f"Execution time {value} is not <= {threshold}. Optimization flags (-O3) might be missing in the Makefile."
    return value


def test_shared_library_built():
    makefile = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile), f"Makefile missing at {makefile}"
    make_text = open(makefile, "r", encoding="utf-8").read()
    for flag in ("-O3", "-fPIC", "-shared", "-lm"):
        assert flag in make_text, f"Makefile does not contain required flag {flag}"

    if os.path.lexists(SO_PATH):
        os.remove(SO_PATH)
    result = run(["make"], cwd=PROJECT, timeout=120)
    assert result.returncode == 0, f"make failed. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(SO_PATH), f"Shared library not built at {SO_PATH}"
    assert os.path.getsize(SO_PATH) > 0, "libmathops.so is empty"

    elf = run(["readelf", "-h", SO_PATH], timeout=30)
    assert elf.returncode == 0 and re.search(r"Type:\s+DYN", elf.stdout), "libmathops.so is not a valid ELF shared object"
    symbols = run(["nm", "-D", SO_PATH], timeout=30)
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"\bget_version$", symbols.stdout, re.M), "get_version is not exported"
    assert re.search(r"\bmatrix_transform$", symbols.stdout, re.M), "matrix_transform is not exported"

    lib = load_library()
    raw_version = lib.get_version()
    assert raw_version, "get_version returned NULL"
    library_version = Version(raw_version.decode("ascii"))
    assert library_version >= read_required_version(), (
        f"Library version {library_version} is below the version in requirements.png"
    )

    rng = random.Random(93821)
    cases = [
        [-10.0, -5.0, -1.0, -0.0, 0.0, 0.25, 1.0, 5.0, 10.0],
        [rng.uniform(-10.0, 10.0) for _ in range(9)],
        [rng.uniform(-10.0, 10.0) for _ in range(9)],
        [rng.uniform(-10.0, 10.0) for _ in range(9)],
    ]
    for values in cases:
        array = (ctypes.c_double * 9)(*values)
        lib.matrix_transform(array)
        expected = [math.sin(x) * math.cos(x) + math.exp(-x) for x in values]
        for index, (actual, wanted) in enumerate(zip(array, expected)):
            assert math.isclose(actual, wanted, rel_tol=1e-12, abs_tol=1e-12), (
                f"matrix_transform produced {actual} instead of {wanted} at index {index}"
            )


def test_metric_file_exists_and_threshold_met():
    benchmark = os.path.join(PROJECT, "benchmark.py")
    assert os.path.isfile(benchmark), f"Benchmark script missing at {benchmark}"
    benchmark_source = open(benchmark, "r", encoding="utf-8").read().lower()
    assert "matrix_transform" in benchmark_source, "benchmark.py does not reference matrix_transform"
    assert "random" in benchmark_source, "benchmark.py does not create a random matrix"

    result = run(["python3", benchmark], cwd=PROJECT, timeout=180)
    assert result.returncode == 0, f"benchmark.py failed. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    reported = parse_metric()
    saved_metric = open(METRIC_PATH, "r", encoding="utf-8").read()

    # Independently estimate a ctypes call time and reject implausible self-reports.
    lib = load_library()
    matrix = (ctypes.c_double * 9)(*[0.1 * i for i in range(9)])
    calls = 20000
    start = time.perf_counter()
    for _ in range(calls):
        lib.matrix_transform(matrix)
    observed = (time.perf_counter() - start) / calls
    assert observed / 100 <= reported <= observed * 100, (
        f"Reported average {reported} is not plausible compared with independently observed {observed}"
    )

    # Replace the library temporarily with an instrumented ABI-compatible library
    # to verify that benchmark.py really invokes matrix_transform one million times.
    counter_c = "/tmp/count_mathops.c"
    counter_so = "/tmp/count_mathops.so"
    counter_file = "/tmp/mathops_call_count.txt"
    backup_so = "/tmp/original_libmathops.so"
    with open(counter_c, "w", encoding="utf-8") as f:
        f.write(r'''
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static uint64_t calls = 0;
static double first[9];
const char* get_version(void) { return "1.5.0"; }
void matrix_transform(double *matrix) {
    if (calls == 0) for (int i = 0; i < 9; ++i) first[i] = matrix[i];
    ++calls;
    for (int i = 0; i < 9; ++i)
        matrix[i] = sin(matrix[i]) * cos(matrix[i]) + exp(-matrix[i]);
}
__attribute__((destructor)) static void report(void) {
    const char *path = getenv("BENCH_COUNT_FILE");
    if (!path) return;
    FILE *fp = fopen(path, "w");
    if (!fp) return;
    fprintf(fp, "%llu", (unsigned long long)calls);
    for (int i = 0; i < 9; ++i) fprintf(fp, " %.17g", first[i]);
    fputc('\n', fp);
    fclose(fp);
}
''')
    compile_result = run(["gcc", "-O3", "-fPIC", "-shared", counter_c, "-lm", "-o", counter_so], timeout=60)
    assert compile_result.returncode == 0, compile_result.stderr
    if os.path.exists(counter_file):
        os.remove(counter_file)

    shutil.copy2(SO_PATH, backup_so)
    try:
        shutil.copy2(counter_so, SO_PATH)
        env = os.environ.copy()
        env["BENCH_COUNT_FILE"] = counter_file
        counted = run(["python3", benchmark], cwd=PROJECT, env=env, timeout=180)
        assert counted.returncode == 0, f"Instrumented benchmark failed. stdout:\n{counted.stdout}\nstderr:\n{counted.stderr}"
        assert os.path.isfile(counter_file), "benchmark.py did not load and call the project shared library"
        fields = open(counter_file, "r", encoding="utf-8").read().split()
        count = int(fields[0])
        assert count >= 1_000_000, f"benchmark.py called matrix_transform only {count} times"
        first_matrix = [float(x) for x in fields[1:]]
        assert len(first_matrix) == 9 and all(math.isfinite(x) for x in first_matrix), "benchmark did not pass a valid 3x3 matrix"
    finally:
        shutil.copy2(backup_so, SO_PATH)
        with open(METRIC_PATH, "w", encoding="utf-8") as f:
            f.write(saved_metric)


def test_test_ops_runs_successfully():
    test_script = os.path.join(PROJECT, "test_ops.py")
    assert os.path.isfile(test_script), f"Test script missing at {test_script}"
    source = open(test_script, "r", encoding="utf-8").read().lower()
    for required in ("hypothesis", "get_version", "matrix_transform", "/app/requirements.png"):
        assert required in source, f"test_ops.py does not implement required integration: missing {required}"

    result = run(["python3", test_script], cwd=PROJECT, timeout=180)
    assert result.returncode == 0, f"test_ops.py failed to run. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    pytest_result = run(["python3", "-m", "pytest", "-q", test_script], cwd=PROJECT, timeout=240)
    assert pytest_result.returncode == 0, (
        f"Property-based tests did not pass. stdout:\n{pytest_result.stdout}\nstderr:\n{pytest_result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
