#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import subprocess

HOME = "/home/user"
LOG = f"{HOME}/server_metrics.log"
SOURCE = f"{HOME}/anomaly_detector.cpp"
SCRIPT = f"{HOME}/run_pipeline.sh"
DETECTOR = f"{HOME}/detector"
CSV = f"{HOME}/anomalies.csv"
COUNT = f"{HOME}/anomaly_count.txt"


def write_log(values, start):
    with open(LOG, "w") as f:
        for i, cpu in enumerate(values):
            timestamp = (start + datetime.timedelta(seconds=i)).strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"[{timestamp}] INFO - CPU: {cpu:.1f}% RAM: 2048MB STATUS: OK\n")


def expected_lines(values, start):
    result = []
    window = []
    rolling_sum = 0.0
    for i, cpu in enumerate(values):
        if len(window) == 50:
            sma = rolling_sum / 50.0
            if cpu > 2.0 * sma:
                timestamp = (start + datetime.timedelta(seconds=i)).strftime("%Y-%m-%d %H:%M:%S")
                result.append(f"{timestamp},{cpu:.1f},{sma:.1f}")
            rolling_sum -= window.pop(0)
        window.append(cpu)
        rolling_sum += cpu
    return result


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def remove_generated_files():
    for path in (DETECTOR, CSV, COUNT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_pipeline():
    completed = subprocess.run(
        ["bash", SCRIPT],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert completed.returncode == 0, (
        f"run_pipeline.sh failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def assert_real_detector():
    assert os.path.isfile(DETECTOR), f"Required file is missing: {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), "detector is not executable"
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "detector is not a compiled ELF executable"


def make_random_case():
    rng = random.SystemRandom()
    values = [10.0] * 50
    values.extend([20.0, 25.0])  # Strict equality is not anomalous; next value is.
    values.extend(float(rng.randint(15, 25)) for _ in range(168))
    for index in rng.sample(range(110, 220), 3):
        values[index] = float(rng.randint(75, 95))
    start = datetime.datetime(2024, rng.randint(1, 9), rng.randint(1, 20), 6, 0, 0)
    return values, start


def test_complete_pipeline_and_detector_behavior():
    assert os.path.isfile(SOURCE), f"Required file is missing: {SOURCE}"
    assert os.path.isfile(SCRIPT), f"Required file is missing: {SCRIPT}"

    with open(SCRIPT, "r") as f:
        script_text = f.read()
    assert "g++" in script_text, "run_pipeline.sh does not invoke g++"
    assert "-O3" in script_text, "run_pipeline.sh does not compile with -O3"

    # Recreate the original fixture, force the script to compile and execute, and
    # retain the original verifier's exact output assertions.
    original_start = datetime.datetime(2023, 10, 1, 10, 0, 0)
    original_values = [float([20, 21, 22, 23, 24][i % 5]) for i in range(10000)]
    original_values[1000] = 55.5
    original_values[5000] = 88.8
    original_values[9000] = 99.9
    write_log(original_values, original_start)
    remove_generated_files()
    run_pipeline()

    expected_files = [SOURCE, SCRIPT, DETECTOR, CSV, COUNT]
    for path in expected_files:
        assert os.path.exists(path), f"Required file is missing: {path}"
        assert os.path.isfile(path), f"Expected {path} to be a file."

    assert_real_detector()

    expected_original = [
        "2023-10-01 10:16:40,55.5,22.0",
        "2023-10-01 11:23:20,88.8,22.0",
        "2023-10-01 12:30:00,99.9,22.0",
    ]
    actual_original = read_nonempty_lines(CSV)
    assert len(actual_original) == len(expected_original), (
        f"Expected {len(expected_original)} lines in {CSV}, found {len(actual_original)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_original, expected_original)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} in {CSV}. Expected: '{expected}', Got: '{actual}'"
        )
    with open(COUNT, "r") as f:
        content = f.read().strip()
    assert content == "3", f"Expected '3' in {COUNT}, but got '{content}'."

    # Exercise the compiled artifact directly on an unpredictable input and
    # derive the expected SMA results independently.
    values, start = make_random_case()
    write_log(values, start)
    if os.path.exists(CSV):
        os.remove(CSV)
    completed = subprocess.run(
        [DETECTOR], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert completed.returncode == 0, (
        f"detector failed with exit code {completed.returncode}: {completed.stderr}"
    )
    expected = expected_lines(values, start)
    assert read_nonempty_lines(CSV) == expected

    # Force the shell workflow to recompile and process another unpredictable
    # log, then verify both its CSV and line count.
    values, start = make_random_case()
    write_log(values, start)
    remove_generated_files()
    run_pipeline()
    assert_real_detector()
    expected = expected_lines(values, start)
    assert read_nonempty_lines(CSV) == expected
    with open(COUNT, "r") as f:
        count_text = f.read().strip()
    assert count_text == str(len(expected)), (
        f"Expected anomaly count {len(expected)}, got {count_text!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
