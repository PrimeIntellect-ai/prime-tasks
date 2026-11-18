#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import resource
import secrets
import subprocess

PROJECT_DIR = "/home/user/stats_service"
DATA_PATH = "/home/user/data.csv"
RESULT_PATH = "/home/user/result.txt"
BINARY_PATH = "/home/user/stats_service/target/debug/stats_service"
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


def compute_stats(path=DATA_PATH):
    with open(path, "r") as f:
        reader = csv.reader(f)
        data = [int(row[0]) for row in reader if row]

    if not data:
        return 0.0, 0.0

    mean = sum(data) / len(data)
    variance = sum((x - mean) ** 2 for x in data) / len(data)
    return mean, variance


def compute_expected_variance():
    if not os.path.exists(DATA_PATH):
        return None
    return compute_stats()[1]


def parse_output(output):
    mean_match = re.search(rf"(?im)^\s*Mean\s*:\s*({NUMBER})\s*$", output)
    variance_match = re.search(rf"(?im)^\s*Variance\s*:\s*({NUMBER})\s*$", output)
    assert mean_match, f"Service did not print a parseable Mean line. Output:\n{output}"
    assert variance_match, f"Service did not print a parseable Variance line. Output:\n{output}"
    return float(mean_match.group(1)), float(variance_match.group(1))


def run_service(memory_limit=None, timeout=60):
    preexec_fn = None
    if memory_limit is not None:
        def set_limit():
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))
        preexec_fn = set_limit

    result = subprocess.run(
        [BINARY_PATH],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=timeout,
        preexec_fn=preexec_fn,
    )
    assert result.returncode == 0, (
        f"Service exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return parse_output(result.stdout)


def assert_stats(actual, expected):
    actual_mean, actual_variance = actual
    expected_mean, expected_variance = expected
    assert math.isfinite(actual_mean), f"Mean is not finite: {actual_mean}"
    assert math.isfinite(actual_variance), f"Variance is not finite: {actual_variance}"
    assert math.isclose(actual_mean, expected_mean, rel_tol=1e-12, abs_tol=0.02), (
        f"Expected mean {expected_mean}, got {actual_mean}"
    )
    assert math.isclose(actual_variance, expected_variance, rel_tol=1e-12, abs_tol=0.02), (
        f"Expected population variance {expected_variance}, got {actual_variance}"
    )


def test_result_txt_exists_and_correct():
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} does not exist."

    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()

    expected_variance = compute_expected_variance()
    assert expected_variance is not None, "data.csv is missing, cannot compute expected variance."
    expected_str = f"{expected_variance:.2f}"
    assert content == expected_str, (
        f"Expected variance {expected_str} in result.txt, but got {content}."
    )


def test_main_rs_streaming():
    main_rs_path = "/home/user/stats_service/src/main.rs"
    assert os.path.isfile(main_rs_path), f"File {main_rs_path} does not exist."

    with open(main_rs_path, "r") as f:
        content = f.read()

    assert ".push(" not in content, "The code still contains '.push(', indicating it might not be fully streaming."
    assert "Vec::new()" not in content or "numbers" not in content, "The code still appears to allocate a Vec for all numbers."


def test_cargo_build_succeeds():
    assert os.path.isdir(PROJECT_DIR), f"Directory {PROJECT_DIR} does not exist."

    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"cargo build failed with error:\n{result.stderr}"
    assert os.path.isfile(BINARY_PATH), f"cargo build did not produce {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Built service {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built service is not an ELF executable"


def test_service_computes_statistics_and_streams():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_result = None
    if os.path.exists(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            original_result = f.read()

    try:
        # First execute the built service on the dataset named in the task.
        assert_stats(run_service(), compute_stats())

        # Use verifier-generated values so a precomputed result cannot pass.
        rng = secrets.SystemRandom()
        values = [rng.randint(-1_000_000, 1_000_000) for _ in range(2001)]
        with open(DATA_PATH, "w") as f:
            for value in values:
                f.write(f"{value}\n")
        expected_mean = sum(values) / len(values)
        expected_variance = sum((x - expected_mean) ** 2 for x in values) / len(values)
        assert_stats(run_service(), (expected_mean, expected_variance))

        # A constant-memory implementation fits this limit; retaining all ten
        # million parsed integers does not.
        with open(DATA_PATH, "w") as f:
            chunk = "10000\n" * 100000
            for _ in range(100):
                f.write(chunk)
        assert_stats(run_service(memory_limit=48 * 1024 * 1024, timeout=90), (10000.0, 0.0))
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
