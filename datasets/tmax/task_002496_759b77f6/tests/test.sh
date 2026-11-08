#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import math
import os
import subprocess
import sys

import pytest

APP_DIR = "/home/user/app"
INPUT_STREAM_FILE = os.path.join(APP_DIR, "input_stream.txt")
MATH_LOGIC_FILE = os.path.join(APP_DIR, "math_logic.py")
WORKER_FILE = os.path.join(APP_DIR, "worker.py")
RUN_FILE = os.path.join(APP_DIR, "run.py")
SUCCESS_FILE = os.path.join(APP_DIR, "success.txt")


def run_service(timeout=5):
    return subprocess.run(
        [sys.executable, RUN_FILE],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def read_success():
    assert os.path.isfile(SUCCESS_FILE), f"Output file {SUCCESS_FILE} does not exist. Did you run run.py?"
    with open(SUCCESS_FILE, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_00_service_executes_modified_code_and_regenerates_output():
    assert os.path.isfile(RUN_FILE), f"File {RUN_FILE} is missing."
    with open(INPUT_STREAM_FILE, "r") as f:
        original_input = f.read()

    dynamic_values = [float(i * i) for i in range(2, 63)]
    dynamic_values[7] = -2.0
    dynamic_values[31] = -3.0
    expected = [f"{math.sqrt(v):.4f}" for v in dynamic_values if v >= 0]

    try:
        with open(INPUT_STREAM_FILE, "w") as f:
            f.write("".join(f"{v}\n" for v in dynamic_values))
        if os.path.exists(SUCCESS_FILE):
            os.remove(SUCCESS_FILE)

        completed = run_service()
        assert completed.returncode == 0, completed.stderr
        assert read_success() == expected
        assert "Skipped corrupted input: -2.0" in completed.stdout
        assert "Skipped corrupted input: -3.0" in completed.stdout
    finally:
        with open(INPUT_STREAM_FILE, "w") as f:
            f.write(original_input)

    # Regenerate the required final artifact from the original stream.
    if os.path.exists(SUCCESS_FILE):
        os.remove(SUCCESS_FILE)
    completed = run_service()
    assert completed.returncode == 0, completed.stderr
    assert "Skipped corrupted input: -4.0" in completed.stdout
    assert "Skipped corrupted input: -1.0" in completed.stdout


def test_success_file_exists_and_correct():
    assert os.path.isfile(SUCCESS_FILE), f"Output file {SUCCESS_FILE} does not exist. Did you run run.py?"

    with open(SUCCESS_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # The expected output is the square roots of the positive numbers in input_stream.txt
    expected = ["3.1623", "5.0000", "4.0000", "3.0000", "6.0000", "7.0000", "8.0000", "9.0000"]

    assert len(lines) == len(expected), f"Expected {len(expected)} lines in {SUCCESS_FILE}, but got {len(lines)}."
    for i, (actual, exp) in enumerate(zip(lines, expected)):
        assert actual == exp, f"Line {i+1} in {SUCCESS_FILE} is {actual}, expected {exp}."


def test_math_logic_fixes():
    assert os.path.isfile(MATH_LOGIC_FILE), f"File {MATH_LOGIC_FILE} is missing."
    with open(MATH_LOGIC_FILE, "r") as f:
        content = f.read()

    assert "RuntimeError" in content, "math_logic.py does not raise RuntimeError on convergence failure."
    assert "100" in content, "math_logic.py does not appear to enforce the 100 iterations limit."

    sys.path.insert(0, APP_DIR)
    import math_logic

    for value in (2.0, 7.5, 121.0, 0.25):
        actual = math_logic.calculate_equilibrium(value)
        assert math.isclose(actual, math.sqrt(value), rel_tol=1e-5, abs_tol=1e-5)

    # NaN never satisfies the Newton convergence comparison, so this call must
    # terminate via the iteration bound rather than hanging indefinitely.
    code = (
        "import sys; "
        f"sys.path.insert(0, {APP_DIR!r}); "
        "from math_logic import calculate_equilibrium; "
        "\ntry:\n calculate_equilibrium(float('nan'))"
        "\nexcept RuntimeError as e:\n"
        " assert str(e) == 'Convergence failed'\n print('bounded')"
        "\nelse:\n raise AssertionError('non-convergent input did not raise RuntimeError')\n"
    )
    completed = subprocess.run(
        [sys.executable, "-c", code],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.strip() == "bounded"


def test_worker_fixes():
    assert os.path.isfile(WORKER_FILE), f"File {WORKER_FILE} is missing."
    with open(WORKER_FILE, "r") as f:
        content = f.read()

    assert "RuntimeError" in content, "worker.py does not appear to catch RuntimeError."
    assert "50" in content, "worker.py does not appear to cap the seen_records list at 50."

    sys.path.insert(0, APP_DIR)
    import worker

    if hasattr(worker.seen_records, "clear"):
        worker.seen_records.clear()

    values = [float(i * i) for i in range(1, 74)]
    for index in (5, 22, 51, 68):
        values[index] = -2.0 - index
    stream = [f"{value}\n" for value in values]

    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        results = worker.process_data(stream)

    expected_results = [math.sqrt(value) for value in values if value >= 0]
    assert len(results) == len(expected_results)
    for actual, expected in zip(results, expected_results):
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5)

    output = captured.getvalue()
    for value in values:
        if value < 0:
            assert f"Skipped corrupted input: {value}" in output

    state = worker.seen_records
    assert len(state) <= 50, f"seen_records retained {len(state)} items"
    expected_recent = values[-50:]
    if isinstance(state, dict):
        keys = list(state.keys())
        vals = list(state.values())
        assert keys == expected_recent or vals == expected_recent
    else:
        assert list(state) == expected_recent
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
