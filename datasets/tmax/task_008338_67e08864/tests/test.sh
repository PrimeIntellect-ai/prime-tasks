#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import secrets
import stat
import string
import subprocess
import sys
import tempfile

import pytest

APP_DIR = "/home/user/app"
REQUESTS_FILE = os.path.join(APP_DIR, "requests.json")
RESULTS_FILE = os.path.join(APP_DIR, "results.log")
LIBCALC_C = os.path.join(APP_DIR, "libcalc.c")
LIBCALC_SO = os.path.join(APP_DIR, "libcalc.so")
API_PY = os.path.join(APP_DIR, "api.py")


def compute_expected_results(requests_path):
    with open(requests_path, "r") as f:
        requests = json.load(f)

    user_counts = {}
    expected_lines = []

    for req in requests:
        user = req["user"]
        data = req["data"]

        is_valid = data.isalnum()
        user_counts[user] = user_counts.get(user, 0) + 1
        is_rate_limited = user_counts[user] > 2

        if is_valid and not is_rate_limited:
            truncated_data = data[:10]
            res = sum(ord(c) for c in truncated_data)
            expected_lines.append(
                f"USER:{user} STATUS:ACCEPTED RESULT:{res}"
            )
        else:
            expected_lines.append(
                f"USER:{user} STATUS:REJECTED RESULT:NONE"
            )

    return expected_lines


def run_api_and_check(requests):
    with open(REQUESTS_FILE, "w") as f:
        json.dump(requests, f)

    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)

    try:
        proc = subprocess.run(
            [sys.executable, API_PY],
            cwd=APP_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("api.py did not terminate within 15 seconds")

    assert proc.returncode == 0, (
        "Running api.py failed.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )
    assert os.path.exists(RESULTS_FILE), (
        f"The file {RESULTS_FILE} was not created by api.py."
    )

    expected_lines = compute_expected_results(REQUESTS_FILE)
    with open(RESULTS_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in results.log, "
        f"but found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} in results.log.\n"
            f"Expected: {expected}\nActual:   {actual}"
        )


def load_library(path):
    try:
        lib = ctypes.CDLL(path)
        lib.process_data.argtypes = [ctypes.c_char_p]
        lib.process_data.restype = ctypes.c_int
        return lib
    except Exception as e:
        pytest.fail(f"Failed to load {path}: {e}")


def exercise_library(path):
    lib = load_library(path)

    # Preserve the original fixed checks.
    exact_str = b"1234567890"
    expected_exact = sum(exact_str)
    assert lib.process_data(exact_str) == expected_exact

    long_str = b"A" * 200
    expected_long = sum(b"A" * 10)
    assert lib.process_data(long_str) == expected_long

    # Randomized lengths and contents prevent a fixed-subset implementation.
    rng = random.SystemRandom()
    alphabet = bytes(range(1, 256))
    lengths = [0, 1, 2, 9, 10, 11, 12, 31, 127, 511]
    lengths.extend(rng.randrange(13, 400) for _ in range(20))
    for length in lengths:
        value = bytes(rng.choice(alphabet) for _ in range(length))
        expected = sum(value[:10])
        actual = lib.process_data(value)
        assert actual == expected, (
            f"process_data returned {actual} for a {length}-byte randomized "
            f"input; expected {expected} after truncation to 10 bytes"
        )


def test_api_py_is_python3_and_is_a_file():
    assert os.path.exists(API_PY), f"{API_PY} does not exist."
    assert stat.S_ISREG(os.stat(API_PY).st_mode), f"{API_PY} is not a regular file."

    with open(API_PY, "r") as f:
        source = f.read()
    try:
        compile(source, API_PY, "exec")
    except SyntaxError as e:
        pytest.fail(f"{API_PY} is not valid Python 3 code. SyntaxError: {e}")


def test_results_log_content_by_executing_api():
    assert os.path.exists(REQUESTS_FILE), f"{REQUESTS_FILE} does not exist."
    with open(REQUESTS_FILE, "r") as f:
        requests = json.load(f)
    assert isinstance(requests, list), "requests.json must contain a request list"
    run_api_and_check(requests)


def test_api_on_unpredictable_batch():
    token = secrets.token_hex(8)
    u1 = "userA" + token
    u2 = "userB" + token
    u3 = "userC" + token

    a = secrets.token_hex(12)
    b = "Z" + secrets.token_hex(10)
    c = secrets.token_hex(7)
    d = secrets.token_hex(9)

    requests = [
        {"user": u1, "data": a},
        {"user": u2, "data": b},
        {"user": u1, "data": "bad value"},
        {"user": u3, "data": "Alpha9"},
        {"user": u2, "data": c},
        {"user": u1, "data": d},
        {"user": u2, "data": "punctuation!"},
        {"user": u3, "data": ""},
        {"user": u3, "data": secrets.token_hex(6)},
        {"user": u3, "data": secrets.token_hex(5)},
    ]
    run_api_and_check(requests)


def test_libcalc_memory_safety_and_truncation():
    assert os.path.exists(LIBCALC_SO), (
        f"{LIBCALC_SO} does not exist. Was it recompiled?"
    )
    assert stat.S_ISREG(os.stat(LIBCALC_SO).st_mode), (
        f"{LIBCALC_SO} is not a regular file."
    )
    exercise_library(LIBCALC_SO)


def test_submitted_c_source_builds_and_is_safe():
    assert os.path.exists(LIBCALC_C), f"{LIBCALC_C} does not exist."
    assert stat.S_ISREG(os.stat(LIBCALC_C).st_mode), (
        f"{LIBCALC_C} is not a regular file."
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "libcalc_rebuilt.so")
        try:
            proc = subprocess.run(
                ["gcc", "-shared", "-fPIC", LIBCALC_C, "-o", rebuilt],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Compiling the submitted libcalc.c timed out")

        assert proc.returncode == 0, (
            "The submitted libcalc.c could not be compiled.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        exercise_library(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
