#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid
import pytest

LIB_DIR = "/app/vendored/c_matrix_lib-1.0"
SO_PATH = os.path.join(LIB_DIR, "libmatrix.so")
WRAPPER_PATH = "/home/user/ffi_wrapper.py"
SANITIZER_PATH = "/home/user/sanitizer.py"


def determinant(data, n):
    if n == 2:
        return data[0] * data[3] - data[1] * data[2]
    if n == 3:
        return (data[0] * (data[4] * data[8] - data[5] * data[7])
                - data[1] * (data[3] * data[8] - data[5] * data[6])
                + data[2] * (data[3] * data[7] - data[4] * data[6]))
    raise ValueError(n)


def test_libmatrix_built():
    """Verify the Makefile rebuilds a usable shared library with the required symbol."""
    assert os.path.isfile(os.path.join(LIB_DIR, "Makefile")), "Makefile is missing"

    if os.path.exists(SO_PATH):
        os.remove(SO_PATH)
    proc = subprocess.run(
        ["make", "-B"], cwd=LIB_DIR, capture_output=True, text=True, timeout=30
    )
    assert proc.returncode == 0, f"make failed:\nSTDOUT: {proc.stdout}\nSTDERR: {proc.stderr}"
    assert "-fPIC" in proc.stdout + proc.stderr, "The shared-library build does not compile with -fPIC"
    assert os.path.exists(SO_PATH), f"Shared library not built: {SO_PATH}"

    try:
        nm_out = subprocess.check_output(["nm", "-D", SO_PATH], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run nm on {SO_PATH}: {e}")
    assert "calculate_determinant" in nm_out, "calculate_determinant symbol not found in libmatrix.so"

    try:
        lib = ctypes.CDLL(SO_PATH)
        fn = lib.calculate_determinant
    except (OSError, AttributeError) as e:
        pytest.fail(f"libmatrix.so is not a loadable library with calculate_determinant: {e}")
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    fn.restype = ctypes.c_double

    cases = []
    for n in (2, 3):
        for _ in range(5):
            data = [float(secrets.randbelow(15) - 7) for _ in range(n * n)]
            cases.append((data, n, determinant(data, n)))
    for data, n, expected in cases:
        arr = (ctypes.c_double * len(data))(*data)
        actual = fn(arr, n)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"C determinant incorrect for n={n}, data={data}: {actual} != {expected}"


def test_ffi_wrapper_exists_and_calls_working_api():
    assert os.path.isfile(WRAPPER_PATH), f"FFI wrapper missing: {WRAPPER_PATH}"

    cases = []
    for n in (2, 3):
        for _ in range(6):
            data = [float(secrets.randbelow(19) - 9) for _ in range(n * n)]
            cases.append({"data": data, "n": n, "expected": determinant(data, n)})

    with tempfile.TemporaryDirectory() as tmpdir:
        cases_path = os.path.join(tmpdir, "cases.json")
        probe_path = os.path.join(tmpdir, "probe.py")
        with open(cases_path, "w") as f:
            json.dump(cases, f)
        with open(probe_path, "w") as f:
            f.write(r'''
import importlib.util
import json
import math
import sys

spec = importlib.util.spec_from_file_location("submitted_ffi_wrapper", "/home/user/ffi_wrapper.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
fn = getattr(module, "calculate_determinant", None)
assert callable(fn), "ffi_wrapper.py must expose calculate_determinant"
with open(sys.argv[1]) as stream:
    cases = json.load(stream)
for case in cases:
    actual = fn(case["data"], case["n"])
    assert isinstance(actual, (int, float)), f"non-numeric result: {actual!r}"
    assert math.isclose(float(actual), case["expected"], rel_tol=1e-12, abs_tol=1e-12), \
        f"wrong determinant for {case}: {actual}"
''')
        proc = subprocess.run(
            ["python3", probe_path, cases_path], capture_output=True, text=True, timeout=30
        )
        assert proc.returncode == 0, f"ffi_wrapper.py failed behavioral tests:\nSTDOUT: {proc.stdout}\nSTDERR: {proc.stderr}"


def run_sanitizer(input_dir, output_json):
    try:
        subprocess.run(
            ["python3", SANITIZER_PATH, input_dir, output_json],
            check=True, capture_output=True, text=True, timeout=30
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"sanitizer.py failed to execute:\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("sanitizer.py timed out")

    assert os.path.exists(output_json), f"Output JSON not created at {output_json}"
    try:
        with open(output_json) as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("Output file is not valid JSON.")
    assert isinstance(results, dict), "Output JSON must be a dictionary"
    return results


def test_sanitizer_adversarial_corpus():
    """Retain the original corpus assertions."""
    assert os.path.exists(SANITIZER_PATH), f"Sanitizer script missing: {SANITIZER_PATH}"

    evil_dir = "/app/tests/corpus/evil"
    clean_dir = "/app/tests/corpus/clean"
    assert os.path.exists(evil_dir), f"Evil corpus missing: {evil_dir}"
    assert os.path.exists(clean_dir), f"Clean corpus missing: {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".json")]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".json")]

    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, "input")
        os.makedirs(input_dir)
        for name in evil_files:
            shutil.copy(os.path.join(evil_dir, name), os.path.join(input_dir, name))
        for name in clean_files:
            shutil.copy(os.path.join(clean_dir, name), os.path.join(input_dir, name))

        results = run_sanitizer(input_dir, os.path.join(tmpdir, "output.json"))
        evil_bypassed = [name for name in evil_files if results.get(name) != "reject"]
        clean_modified = [name for name in clean_files if results.get(name) != "accept"]
        errors = []
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
        if errors:
            pytest.fail(" | ".join(errors))


def test_sanitizer_runtime_generated_matrices():
    """Exercise unpredictable filenames, values, dimensions, and threshold cases."""
    assert os.path.isfile(SANITIZER_PATH), f"Sanitizer script missing: {SANITIZER_PATH}"
    matrices = [
        (2, [1.0, 2.0, 2.0, 4.0]),
        (2, [1.0, 0.0, 0.0, 0.000009]),
        (2, [1.0, 0.0, 0.0, 0.00001]),
        (2, [1.0, 0.0, 0.0, -0.00002]),
        (3, [1.0, 2.0, 3.0, 2.0, 4.0, 6.0, 7.0, 8.0, 9.0]),
        (3, [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.000004]),
    ]
    for n in (2, 3):
        for _ in range(10):
            matrices.append((n, [float(secrets.randbelow(21) - 10) for _ in range(n * n)]))

    expected = {}
    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, "generated-input")
        os.makedirs(input_dir)
        for n, data in matrices:
            base = f"case_{uuid.uuid4().hex}.json"
            payload = {
                "filename": f"decoy_{uuid.uuid4().hex}.json",
                "n": n,
                "data": data,
            }
            with open(os.path.join(input_dir, base), "w") as f:
                json.dump(payload, f)
            expected[base] = "reject" if abs(determinant(data, n)) < 1e-5 else "accept"

        results = run_sanitizer(input_dir, os.path.join(tmpdir, "generated-output.json"))
        assert set(results) == set(expected), \
            f"Output keys must be exactly the input base filenames; got {set(results)}, expected {set(expected)}"
        for name, label in expected.items():
            assert results[name] == label, f"Incorrect classification for {name}: {results[name]} != {label}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
