#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import ctypes
import io
import math
import os
import random
import runpy
import subprocess

BASE = "/home/user/polyglot"
LIB_PATH = os.path.join(BASE, "libalgo.so")
WRAPPER_PATH = os.path.join(BASE, "wrapper.py")
SUCCESS_PATH = os.path.join(BASE, "success.txt")
EXPECTED_OUTPUT = "2.0,3.0,4.0"


def test_libalgo_so_exists():
    assert os.path.isfile(LIB_PATH), (
        f"Shared library {LIB_PATH} does not exist. Did you compile algo.c?"
    )
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB_PATH} is not an ELF shared library."


def test_compiled_library_behavior():
    lib = ctypes.CDLL(LIB_PATH)
    fn = lib.moving_average
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_int]
    fn.restype = ctypes.POINTER(ctypes.c_double)

    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]
    libc.free.restype = None

    rng = random.Random(84721)
    for length, window in [(7, 1), (8, 3), (11, 5), (6, 6)]:
        values = [rng.uniform(-50.0, 50.0) for _ in range(length)]
        data = (ctypes.c_double * length)(*values)
        result = fn(data, length, window)
        assert bool(result), "moving_average unexpectedly returned NULL"
        try:
            expected = [
                sum(values[i:i + window]) / window
                for i in range(length - window + 1)
            ]
            actual = [result[i] for i in range(len(expected))]
            for got, want in zip(actual, expected):
                assert math.isclose(got, want, rel_tol=1e-12, abs_tol=1e-12), (
                    f"moving_average returned {actual}; expected {expected}"
                )
        finally:
            libc.free(ctypes.cast(result, ctypes.c_void_p))

    data = (ctypes.c_double * 2)(1.0, 2.0)
    assert not bool(fn(data, 2, 3)), "moving_average must return NULL when len < window"
    assert not bool(fn(data, 2, 0)), "moving_average must return NULL for a nonpositive window"


def test_wrapper_executes_and_saved_stdout_matches():
    assert os.path.isfile(WRAPPER_PATH), f"File {WRAPPER_PATH} does not exist."
    proc = subprocess.run(
        ["python3", WRAPPER_PATH],
        cwd=BASE,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"wrapper.py did not execute successfully (exit {proc.returncode}). "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert EXPECTED_OUTPUT in proc.stdout, (
        f"wrapper.py did not produce expected output {EXPECTED_OUTPUT!r}. "
        f"Found: {proc.stdout!r}"
    )

    assert os.path.isfile(SUCCESS_PATH), (
        f"Output file {SUCCESS_PATH} does not exist. Did you run wrapper.py and save its output?"
    )
    with open(SUCCESS_PATH, "r") as f:
        content = f.read().strip()
    assert EXPECTED_OUTPUT in content, (
        f"File {SUCCESS_PATH} does not contain the expected output "
        f"{EXPECTED_OUTPUT!r}. Found: {content!r}"
    )
    assert content == proc.stdout.strip(), (
        "success.txt is not the standard output produced by the patched wrapper.py"
    )


def test_wrapper_ffi_and_rate_limit_behavior():
    old_cwd = os.getcwd()
    captured = io.StringIO()
    try:
        os.chdir(BASE)
        with contextlib.redirect_stdout(captured):
            namespace = runpy.run_path(WRAPPER_PATH, run_name="__verifier_wrapper__")
    finally:
        os.chdir(old_cwd)

    assert EXPECTED_OUTPUT in captured.getvalue(), "Import-time wrapper execution failed"
    assert "lib" in namespace, "wrapper.py did not load the C library"
    fn = namespace["lib"].moving_average
    expected_argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
        ctypes.c_int,
    ]
    assert fn.argtypes == expected_argtypes, (
        f"Incorrect moving_average argtypes: {fn.argtypes!r}"
    )
    assert fn.restype == ctypes.POINTER(ctypes.c_double), (
        f"Incorrect moving_average restype: {fn.restype!r}"
    )

    limiter = namespace.get("validate_and_limit")
    assert callable(limiter), "validate_and_limit is missing or not callable"
    second_output = io.StringIO()
    try:
        with contextlib.redirect_stdout(second_output):
            limiter()
    except SystemExit as exc:
        assert exc.code not in (None, 0), "A rate-limited request must fail"
    else:
        raise AssertionError("A second immediate request was not rate-limited")
    assert "Rate limited!" in second_output.getvalue()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
