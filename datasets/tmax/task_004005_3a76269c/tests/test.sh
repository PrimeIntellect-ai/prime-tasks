#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import statistics
import subprocess
import time

import pytest

DATA_FILE = "/home/user/data.txt"
SCRIPT_FILE = "/home/user/calc_variance.py"
RESULT_FILE = "/home/user/result.txt"
PROGRESS_FILE = "/home/user/progress.log"
TRACE_FILE = "/tmp/calc_variance.strace"


def original_data_bytes():
    rng = random.Random(42)
    return "".join(f"{1000000.0 + rng.random():.6f}\n" for _ in range(10000)).encode()


def remove_outputs():
    for path in (RESULT_FILE, PROGRESS_FILE, "/home/user/error.log"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_script(timeout):
    remove_outputs()
    start = time.monotonic()
    try:
        proc = subprocess.run(
            ["python3", SCRIPT_FILE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"calc_variance.py did not finish within {timeout} second(s)")
    elapsed = time.monotonic() - start
    assert proc.returncode == 0, (
        f"calc_variance.py exited with status {proc.returncode}. "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    return elapsed


def read_result():
    assert os.path.exists(RESULT_FILE), "result.txt is missing. The script likely crashed or was not run."
    content = open(RESULT_FILE, "r").read().strip()
    try:
        return float(content)
    except ValueError:
        pytest.fail(f"result.txt does not contain a valid float: {content}")


def assert_progress(count):
    assert os.path.exists(PROGRESS_FILE), "progress.log is missing. The script did not log progress."
    with open(PROGRESS_FILE, "r") as f:
        lines = f.readlines()
    assert len(lines) == count, f"Expected exactly {count} lines in progress.log, found {len(lines)}."
    expected = [f"Processed step {i}\n" for i in range(1, count + 1)]
    assert lines == expected, "progress.log does not contain the correct ordered progress entries."


def test_00_script_and_original_dataset_are_intact():
    assert os.path.exists(SCRIPT_FILE), "calc_variance.py is missing."
    mode = os.lstat(SCRIPT_FILE).st_mode
    assert stat.S_ISREG(mode), "calc_variance.py must be a regular file."
    assert os.path.exists(DATA_FILE), "data.txt is missing. It should not have been modified or deleted."
    with open(DATA_FILE, "rb") as f:
        actual = f.read()
    assert actual == original_data_bytes(), "data.txt was modified; changing the input dataset is prohibited."


def test_01_script_computes_unseen_stable_variance():
    with open(DATA_FILE, "rb") as f:
        original = f.read()

    # Runtime-random, large-offset data prevents a hard-coded result and exposes
    # catastrophic cancellation in the naive sum-of-squares formula.
    values = [
        1000000000.0 + (secrets.randbelow(2000001) - 1000000) / 1000000.0
        for _ in range(10000)
    ]
    replacement = "".join(f"{value:.6f}\n" for value in values).encode()
    parsed_values = [float(line) for line in replacement.decode().splitlines()]
    expected = statistics.variance(parsed_values)

    try:
        with open(DATA_FILE, "wb") as f:
            f.write(replacement)
        elapsed = run_script(1.0)
        assert elapsed < 1.0, f"calc_variance.py took {elapsed:.3f}s; it must run in under one second."
        with open(DATA_FILE, "rb") as f:
            assert f.read() == replacement, "calc_variance.py modified data.txt while running."
        actual = read_result()
        assert abs(actual - expected) < 1e-5, (
            f"Expected variance near {expected:.6f}, got {actual:.6f}. "
            "The script may still use a numerically unstable formula."
        )
        assert_progress(len(parsed_values))
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original)


def test_02_runtime_and_buffered_logging_on_original_data():
    expected_data = original_data_bytes()
    elapsed = run_script(1.0)
    assert elapsed < 1.0, f"calc_variance.py took {elapsed:.3f}s; it must run in under one second."
    with open(DATA_FILE, "rb") as f:
        assert f.read() == expected_data, "calc_variance.py modified data.txt while running."

    # Trace a separate execution to ensure progress logging is not implemented by
    # opening and closing the log on every iteration.
    remove_outputs()
    try:
        os.unlink(TRACE_FILE)
    except FileNotFoundError:
        pass
    try:
        proc = subprocess.run(
            ["strace", "-f", "-e", "trace=open,openat,creat", "-o", TRACE_FILE,
             "python3", SCRIPT_FILE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("calc_variance.py did not complete while checking its file I/O behavior")
    assert proc.returncode == 0, (
        f"calc_variance.py failed under syscall tracing: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    with open(TRACE_FILE, "r", errors="replace") as f:
        progress_opens = sum("progress.log" in line for line in f)
    assert progress_opens <= 4, (
        f"progress.log was opened {progress_opens} times; open it once or use buffered logging."
    )
    with open(DATA_FILE, "rb") as f:
        assert f.read() == expected_data, "calc_variance.py modified data.txt while running."


def test_result_exists_and_correct():
    data_file = DATA_FILE
    result_file = RESULT_FILE

    assert os.path.exists(data_file), "data.txt is missing. It should not have been modified or deleted."
    assert os.path.exists(result_file), "result.txt is missing. The script likely crashed or was not run."

    with open(data_file, 'r') as f:
        data = [float(line.strip()) for line in f if line.strip()]

    expected_var = statistics.variance(data)

    with open(result_file, 'r') as f:
        content = f.read().strip()

    try:
        actual_var = float(content)
    except ValueError:
        pytest.fail(f"result.txt does not contain a valid float: {content}")

    assert abs(actual_var - expected_var) < 1e-5, (
        f"Expected variance near {expected_var:.6f}, got {actual_var:.6f}. "
        "The script may still suffer from precision loss (catastrophic cancellation) "
        "or the variance formula is incorrect."
    )


def test_progress_log_exists_and_correct():
    progress_file = PROGRESS_FILE
    assert os.path.exists(progress_file), "progress.log is missing. The script did not log progress."

    with open(progress_file, 'r') as f:
        lines = f.readlines()

    assert len(lines) == 10000, f"Expected exactly 10000 lines in progress.log, found {len(lines)}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
