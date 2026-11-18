#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import math
import os
import re
import secrets
import stat
import subprocess
import tempfile

import pytest

HOME = "/home/user"
LIB = f"{HOME}/libanomaly.so"
SOURCE = f"{HOME}/anomaly.c"
PROCESS = f"{HOME}/process_logs.py"
UNIT_TEST = f"{HOME}/test_process.py"
OUTPUT = f"{HOME}/merged_anomalies.txt"
LOG = f"{HOME}/test_results.log"


def assert_regular_file(path):
    assert os.path.isfile(path), f"Required file {path} does not exist."
    assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"{path} must be a regular file."


def load_backend(path):
    lib = ctypes.CDLL(path)
    assert hasattr(lib, "compute_anomaly_score"), "Function compute_anomaly_score not found"
    fn = lib.compute_anomaly_score
    fn.restype = ctypes.c_double
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    return fn


def check_rms_implementation(path):
    fn = load_backend(path)
    rng = secrets.SystemRandom()
    cases = [
        [3.0, 4.0],
        [0.0],
        [-2.5, 7.25, -9.5],
        [rng.uniform(-100.0, 100.0) for _ in range(7)],
        [rng.uniform(-10.0, 10.0) for _ in range(19)],
    ]
    for values in cases:
        arr = (ctypes.c_double * len(values))(*values)
        actual = fn(arr, len(values))
        expected = math.sqrt(sum(v * v for v in values) / len(values))
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), \
            f"Incorrect RMS for {values}: expected {expected}, got {actual}"


def test_libanomaly_exists():
    assert_regular_file(LIB)


def test_c_backend_logic():
    # Preserve the original required [3, 4] assertion.
    fn = load_backend(LIB)
    arr = (ctypes.c_double * 2)(3.0, 4.0)
    result = fn(arr, 2)
    expected = math.sqrt((3.0**2 + 4.0**2) / 2)
    assert math.isclose(result, expected, rel_tol=1e-5), \
        f"Expected RMS approx {expected}, got {result}"


def test_c_source_exists_compiles_and_generalizes():
    assert_regular_file(SOURCE)
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    assert "compute_anomaly_score" in source_text, "anomaly.c does not define the required function"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "libanomaly_rebuilt.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", SOURCE, "-o", rebuilt, "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert result.returncode == 0, f"anomaly.c does not compile:\n{result.stderr}"

        symbols = subprocess.run(
            ["nm", "-D", "--defined-only", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert symbols.returncode == 0, f"Could not inspect rebuilt library: {symbols.stderr}"
        exported_functions = []
        for line in symbols.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[-2].upper() in {"T", "W"}:
                exported_functions.append(parts[-1])
        assert "compute_anomaly_score" in exported_functions, "Required function is not exported"
        assert exported_functions == ["compute_anomaly_score"], \
            f"Unexpected additional exposed functions: {exported_functions}"
        check_rms_implementation(rebuilt)

    # Also exercise the library the utility is actually instructed to load.
    check_rms_implementation(LIB)


def test_merged_anomalies_exists_and_content():
    assert_regular_file(OUTPUT)
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
    except UnicodeDecodeError:
        pytest.fail(f"{OUTPUT} is not valid UTF-8.")

    expected_lines = [
        "SENS_C: 10.0000",
        "SENS_F: 10.0000",
        "SENS_B: 5.0662",
        "SENS_A: 2.1602",
        "SENS_D: 2.0000",
        "SENS_E: 0.0000"
    ]
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, got {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"


def test_test_results_log():
    assert_regular_file(LOG)
    with open(LOG, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "OK" in content or "Ran" in content, \
        f"Test results log does not indicate successful test execution. Content: {content}"


def test_unit_test_source_and_execution():
    assert_regular_file(UNIT_TEST)
    with open(UNIT_TEST, "r", encoding="utf-8") as f:
        text = f.read()
    tree = ast.parse(text, filename=UNIT_TEST)

    classes = [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef)]
    has_test_case = any(
        any(
            (isinstance(base, ast.Name) and base.id == "TestCase") or
            (isinstance(base, ast.Attribute) and base.attr == "TestCase")
            for base in cls.bases
        ) for cls in classes
    )
    assert has_test_case, "test_process.py must define a unittest.TestCase subclass"

    attrs = [n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)]
    strings = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    numbers = [float(n.value) for n in ast.walk(tree)
               if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)) and not isinstance(n.value, bool)]
    assert "CDLL" in attrs or "LoadLibrary" in attrs, "Unit tests must load libanomaly.so with ctypes"
    assert any("libanomaly.so" in s for s in strings), "Unit tests do not reference libanomaly.so"
    assert "compute_anomaly_score" in attrs or any("compute_anomaly_score" in s for s in strings), \
        "Unit tests do not call compute_anomaly_score directly"
    assert 3.0 in numbers and 4.0 in numbers, "Unit tests must exercise the [3.0, 4.0] input"
    assert any(isinstance(n, ast.Assert) for n in ast.walk(tree)) or any(
        isinstance(n, ast.Attribute) and n.attr.startswith("assert") for n in ast.walk(tree)
    ), "Unit test does not contain an assertion"

    run = subprocess.run(
        ["python3", UNIT_TEST], cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert run.returncode == 0, f"test_process.py failed when executed:\n{run.stdout}"
    match = re.search(r"Ran\s+(\d+)\s+tests?", run.stdout)
    assert match and int(match.group(1)) >= 1 and "OK" in run.stdout, \
        f"test_process.py did not execute a successful unittest suite:\n{run.stdout}"


def test_process_logs_on_unpredictable_inputs():
    assert_regular_file(PROCESS)
    with open(PROCESS, "r", encoding="utf-8") as f:
        process_text = f.read()
    process_tree = ast.parse(process_text, filename=PROCESS)
    attrs = [n.attr for n in ast.walk(process_tree) if isinstance(n, ast.Attribute)]
    strings = [n.value for n in ast.walk(process_tree)
               if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    assert "CDLL" in attrs or "LoadLibrary" in attrs, "process_logs.py must load the C library using ctypes"
    assert "compute_anomaly_score" in attrs or any("compute_anomaly_score" in s for s in strings), \
        "process_logs.py must call compute_anomaly_score"

    rng = secrets.SystemRandom()
    shared = [rng.randint(20, 80) / 7.0, -rng.randint(10, 60) / 9.0]
    records = [
        ("TIE_Z", list(shared)),
        ("RANDOM_A", [rng.uniform(-30, 30) for _ in range(3)]),
        ("LOW", [rng.uniform(-1, 1) for _ in range(5)]),
        ("RANDOM_B", [rng.uniform(-50, 50) for _ in range(6)]),
        ("TIE_A", list(shared)),
        ("SINGLE", [rng.uniform(60, 90)]),
        ("NEGATIVE", [-rng.uniform(5, 15), -rng.uniform(15, 25)]),
        ("ZERO", [0.0, 0.0, 0.0]),
    ]

    data1 = os.path.join(HOME, "data1.txt")
    data2 = os.path.join(HOME, "data2.txt")
    saved = {}
    for path in (data1, data2, OUTPUT):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()

    def encode_lines(items):
        return "".join(sensor + "," + ",".join(repr(v) for v in values) + "\n"
                       for sensor, values in items)

    try:
        with open(data1, "w", encoding="utf-16") as f:
            f.write(encode_lines(records[:4]))
        with open(data2, "w", encoding="utf-16") as f:
            f.write(encode_lines(records[4:]))
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        run = subprocess.run(
            ["python3", PROCESS], cwd=HOME,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert run.returncode == 0, f"process_logs.py failed:\nstdout: {run.stdout}\nstderr: {run.stderr}"
        assert_regular_file(OUTPUT)

        scored = []
        for sensor, values in records:
            score = math.sqrt(sum(v * v for v in values) / len(values))
            scored.append((sensor, score))
        scored.sort(key=lambda item: (-item[1], item[0]))
        expected = [f"{sensor}: {score:.4f}" for sensor, score in scored]

        with open(OUTPUT, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()
        assert actual == expected, f"Unexpected output for generated UTF-16 inputs.\nExpected: {expected}\nActual: {actual}"
    finally:
        for path in (data1, data2, OUTPUT):
            if path in saved:
                with open(path, "wb") as f:
                    f.write(saved[path])
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
