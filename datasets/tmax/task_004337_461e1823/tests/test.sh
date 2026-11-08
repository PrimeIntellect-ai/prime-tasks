#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path("/home/user/release_prep")
C_SRC = ROOT / "c_src/math_core.c"
LIB = ROOT / "c_src/libmath.so"
RUST_SRC = ROOT / "rust_src/validator.rs"
VALIDATOR = ROOT / "rust_src/validator"
ALGO = ROOT / "python_src/algo.py"
SCRIPT = ROOT / "build_release.sh"
REPORT = ROOT / "release_report.txt"
TRACE = Path("/tmp/release_build_trace.txt")


def run_build():
    result = subprocess.run(
        ["bash", "-x", str(SCRIPT)],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"build_release.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def remove_outputs():
    for path in (LIB, VALIDATOR, REPORT):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_build_pipeline():
    for path in (C_SRC, RUST_SRC, ALGO, SCRIPT):
        assert path.is_file(), f"Required file {path} is missing."

    originals = {
        C_SRC: C_SRC.read_bytes(),
        RUST_SRC: RUST_SRC.read_bytes(),
        ALGO: ALGO.read_bytes(),
    }
    token = secrets.token_hex(8)
    rust_marker = f"RUST_CHALLENGE_{token}"
    python_marker = f"PYTHON_CHALLENGE_{token}"
    challenge_value = 4000 + secrets.randbelow(500)

    challenge_c = f'''#include <stddef.h>
void cumsum(double *input, double *output, int n) {{
    (void)input;
    for (int i = 0; i < n; ++i) output[i] = {challenge_value}.125 + i;
}}
'''
    challenge_rust = f'fn main() {{ println!("{rust_marker}"); }}\n'
    challenge_python = f'''import ctypes
lib = ctypes.CDLL(r"{LIB}")
lib.cumsum.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_double), ctypes.c_int]
a = (ctypes.c_double * 1)(1.0)
out = (ctypes.c_double * 1)()
lib.cumsum(a, out, 1)
print("{python_marker}:" + format(out[0], ".3f"))
'''

    try:
        C_SRC.write_text(challenge_c, encoding="utf-8")
        RUST_SRC.write_text(challenge_rust, encoding="utf-8")
        ALGO.write_text(challenge_python, encoding="utf-8")
        remove_outputs()
        run_build()

        assert LIB.is_file(), "The challenge C source was not built into libmath.so."
        assert VALIDATOR.is_file() and os.access(VALIDATOR, os.X_OK), \
            "The challenge Rust source was not built into an executable."
        validator_result = subprocess.run(
            [str(VALIDATOR)], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert validator_result.returncode == 0
        assert validator_result.stdout.strip() == rust_marker, \
            "build_release.sh did not build the current Rust source."
        assert REPORT.is_file(), "build_release.sh did not create release_report.txt."
        challenge_report = REPORT.read_text(encoding="utf-8")
        expected_python = f"{python_marker}:{challenge_value + 0.125:.3f}"
        assert rust_marker in challenge_report, \
            "build_release.sh did not append the built Rust executable's output."
        assert expected_python in challenge_report, \
            "build_release.sh did not run python_src/algo.py against the built C library."
    finally:
        for path, data in originals.items():
            path.write_bytes(data)

    remove_outputs()
    normal_build = run_build()
    TRACE.write_text(normal_build.stderr, encoding="utf-8")


def test_release_report_exists():
    """Check if the release_report.txt file is created."""
    report_path = "/home/user/release_prep/release_report.txt"
    assert os.path.isfile(report_path), f"{report_path} does not exist."


def test_release_report_content():
    """Verify the contents of the release report."""
    report_path = "/home/user/release_prep/release_report.txt"
    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "Report: Release Candidate 1 has hash: 798" in content, "Rust validator output is missing or incorrect in the report."
    assert "Integral: 8.6667" in content, "Simpson's rule output is missing or incorrect in the report."
    assert "Cumsum: 15.0" in content, "Cumulative sum output is missing or incorrect in the report."
    assert content.splitlines() == [
        "Report: Release Candidate 1 has hash: 798",
        "Integral: 8.6667",
        "Cumsum: 15.0",
    ], "The release report does not contain exactly the required program outputs."


def test_c_shared_library_exists():
    """Check if the compiled C shared library exists."""
    lib_path = "/home/user/release_prep/c_src/libmath.so"
    assert os.path.isfile(lib_path), f"Shared library {lib_path} was not compiled."


def test_c_shared_library_behavior_and_bounds():
    lib = ctypes.CDLL(str(LIB))
    assert hasattr(lib, "cumsum"), "libmath.so does not export cumsum."
    lib.cumsum.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
    ]
    lib.cumsum.restype = None

    cases = [
        [],
        [3.25],
        [1.5, -2.0, 7.25, 0.125, -4.5],
        [float((secrets.randbelow(20001) - 10000) / 1000.0) for _ in range(17)],
    ]
    for values in cases:
        n = len(values)
        input_values = values + [987654.25, -123456.5, 777.0]
        guard = -918273.625
        output_values = [guard] * (n + 3)
        input_array = (ctypes.c_double * len(input_values))(*input_values)
        output_array = (ctypes.c_double * len(output_values))(*output_values)
        lib.cumsum(input_array, output_array, n)

        running = 0.0
        for i, value in enumerate(values):
            running += value
            assert output_array[i] == pytest.approx(running, rel=1e-12, abs=1e-12)
        assert list(output_array[n:]) == [guard, guard, guard], \
            "cumsum wrote beyond the n-element output buffer."


def test_rust_executable_exists():
    """Check if the compiled Rust executable exists."""
    exe_path = "/home/user/release_prep/rust_src/validator"
    assert os.path.isfile(exe_path), f"Rust executable {exe_path} was not compiled."
    assert os.access(exe_path, os.X_OK), f"Rust executable {exe_path} is not executable."


def test_rust_executable_behavior():
    result = subprocess.run(
        [str(VALIDATOR)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "Report: Release Candidate 1 has hash: 798\n"


def test_c_source_fixed():
    """Check if the C source code was fixed (i < n instead of i <= n)."""
    c_src_path = "/home/user/release_prep/c_src/math_core.c"
    assert os.path.isfile(c_src_path), f"{c_src_path} is missing."
    with open(c_src_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert re.search(r"i\s*<\s*n", content) is not None, "The buffer overflow bug in math_core.c (i <= n) was not fixed."


def simpson_expected():
    n = 100
    a, b = 0.0, 2.0
    h = (b - a) / n
    f = lambda x: x**3 - 2*x**2 + 5
    total = f(a) + f(b)
    for i in range(1, n):
        total += (4 if i % 2 else 2) * f(a + i * h)
    return total * h / 3


def test_python_script_execution_and_ctypes_use(tmp_path):
    normal = subprocess.run(
        ["python3", str(ALGO)], cwd=str(ROOT), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert normal.returncode == 0, normal.stderr
    assert normal.stdout.splitlines() == [
        f"Integral: {simpson_expected():.4f}",
        "Cumsum: 15.0",
    ]

    spy_base = 8000 + secrets.randbelow(1000) + 0.5
    spy_source = tmp_path / "spy.c"
    spy_library = tmp_path / "libmath.so"
    spy_source.write_text(
        f"void cumsum(double *in, double *out, int n) {{ "
        f"(void)in; for (int i = 0; i < n; ++i) out[i] = {spy_base} + i; }}\n",
        encoding="utf-8",
    )
    subprocess.run(
        ["gcc", "-shared", "-fPIC", str(spy_source), "-o", str(spy_library)],
        check=True, timeout=30
    )
    backup = tmp_path / "original_libmath.so"
    shutil.copy2(LIB, backup)
    try:
        shutil.copy2(spy_library, LIB)
        challenged = subprocess.run(
            ["python3", str(ALGO)], cwd=str(ROOT), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert challenged.returncode == 0, challenged.stderr
        assert challenged.stdout.splitlines() == [
            f"Integral: {simpson_expected():.4f}",
            f"Cumsum: {spy_base + 4:.1f}",
        ], "algo.py did not obtain the cumulative-sum result from libmath.so via ctypes."
    finally:
        shutil.copy2(backup, LIB)


def test_build_script_exists():
    """Check if the build script exists and is executable."""
    script_path = "/home/user/release_prep/build_release.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "-DRELEASE_MODE=1" in content, "The build script does not include the -DRELEASE_MODE=1 flag for gcc."
    trace_lines = TRACE.read_text(encoding="utf-8").splitlines()
    gcc_lines = [line for line in trace_lines if re.search(r"(?:^|[/ ])gcc(?:\s|$)", line)]
    assert any("-DRELEASE_MODE=1" in line for line in gcc_lines), \
        "The executed gcc command did not use -DRELEASE_MODE=1."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
