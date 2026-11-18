#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import statistics
import subprocess
import sys

import pytest

PIPELINE_DIR = "/home/user/pipeline"
SOLUTION_FILE = os.path.join(PIPELINE_DIR, "solution.txt")
ANALYZER = os.path.join(PIPELINE_DIR, "analyze.py")
EXTRACTOR = os.path.join(PIPELINE_DIR, "extractor.bin")


def expected_extractor_data(stream_id):
    seed = stream_id
    data = []
    lines = []
    for _ in range(1000):
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        rand_val = seed / 2147483647.0
        value = 100000000.0 + rand_val * 0.001
        line = f"{value:.9f}"
        lines.append(line)
        data.append(float(line))
    return lines, data


def run_analyzer(data):
    input_text = "".join(f"{value:.9f}\n" for value in data)
    result = subprocess.run(
        [sys.executable, ANALYZER],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}: {result.stderr}"
    )
    return result.stdout.strip()


def test_solution_file_exists():
    assert os.path.isfile(SOLUTION_FILE), f"Solution file {SOLUTION_FILE} does not exist. Did you save the output to the correct path?"


def test_solution_content():
    # Preserve the original exact final-result assertion.
    seed = 4004
    data = []
    for i in range(1000):
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        rand_val = seed / 2147483647.0
        data.append(100000000.0 + rand_val * 0.001)

    ans = statistics.pstdev(data)
    expected_content = f"StreamID: 4004, StdDev: {ans:.6f}"

    with open(SOLUTION_FILE, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {SOLUTION_FILE} is incorrect. Expected '{expected_content}', but got '{actual_content}'."


def test_analyzer_uses_stable_population_standard_deviation():
    assert os.path.isfile(ANALYZER), f"Missing analyzer: {ANALYZER}"

    # Generate fresh large-offset, low-variance inputs so a hardcoded answer or
    # the original cancellation-prone sum-of-squares formula cannot pass.
    rng = random.SystemRandom()
    for _ in range(3):
        baseline = rng.choice([100000000.0, 175000000.0, 250000000.0])
        data = [baseline + rng.randint(-50, 50) * 0.0001 for _ in range(401)]
        expected = f"StdDev: {statistics.pstdev(data):.6f}"
        assert run_analyzer(data) == expected


def test_authorized_extractor_and_fixed_pipeline_execute():
    assert os.path.isfile(EXTRACTOR), f"Missing extractor: {EXTRACTOR}"
    assert os.access(EXTRACTOR, os.X_OK), f"Extractor is not executable: {EXTRACTOR}"

    invalid_env = os.environ.copy()
    invalid_env["STREAM_AUTH"] = "invalid-token"
    denied = subprocess.run(
        [EXTRACTOR, "4004"],
        env=invalid_env,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert denied.returncode != 0, "extractor.bin accepted an invalid authorization token"

    authorized_env = os.environ.copy()
    authorized_env["STREAM_AUTH"] = "auth_v2_99x"
    extracted = subprocess.run(
        [EXTRACTOR, "4004"],
        env=authorized_env,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert extracted.returncode == 0, (
        f"Authorized extractor execution failed: {extracted.stderr}"
    )

    expected_lines, expected_data = expected_extractor_data(4004)
    actual_lines = extracted.stdout.splitlines()
    assert actual_lines == expected_lines, "extractor.bin produced incorrect stream data"

    analyzed = subprocess.run(
        [sys.executable, ANALYZER],
        input=extracted.stdout,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert analyzed.returncode == 0, (
        f"The authorized extractor-to-analyzer pipeline failed: {analyzed.stderr}"
    )
    expected_analysis = f"StdDev: {statistics.pstdev(expected_data):.6f}"
    assert analyzed.stdout.strip() == expected_analysis

    with open(SOLUTION_FILE, "r") as f:
        solution = f.read().strip()
    assert solution == f"StreamID: 4004, {expected_analysis}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
