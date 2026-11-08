#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import math
import os
import random
import statistics
import subprocess
import sys

SCRIPT_PATH = "/home/user/calc_volatility.py"


def load_submission():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_calc_volatility", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "Could not load calc_volatility.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "calculate_volatility", None)), \
        "calc_volatility.py must define calculate_volatility(prices)"
    return module


def test_solution_file_exists_and_correct():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"File {solution_path} does not exist. The agent must save the output here."

    # Derive the expected value from the truth data
    encoded_payload = "MTAwMDAwMDAwMC4wMDAxLDEwMDAwMDAwMDAuMDAwMiwxMDAwMDAwMDAwLjAwMDM="
    decoded_payload = base64.b64decode(encoded_payload).decode('utf-8')
    prices = [float(x) for x in decoded_payload.split(',')]

    # Compute the expected standard deviation
    expected_volatility = statistics.stdev(prices)
    expected_output = f"{expected_volatility:.6f}"

    with open(solution_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_output, f"Expected solution.txt to contain '{expected_output}', but found '{content}'."


def test_calculate_volatility_is_robust_on_fresh_inputs():
    module = load_submission()
    rng = random.SystemRandom()

    cases = [[1.0, 2.0, 3.0, 4.0]]
    for _ in range(6):
        baseline = rng.randrange(100_000_000, 10_000_000_000)
        step = rng.choice([0.001, 0.0025, 0.005, 0.01])
        offsets = rng.sample(range(-30, 31), 9)
        cases.append([baseline + step * offset for offset in offsets])

    for prices in cases:
        expected = statistics.stdev(prices)
        actual = module.calculate_volatility(prices)
        assert isinstance(actual, (int, float)), "calculate_volatility must return a number"
        assert math.isfinite(actual), "calculate_volatility returned a non-finite value"
        assert math.isclose(actual, expected, rel_tol=5e-3, abs_tol=1e-10), \
            f"Incorrect volatility for {prices}: expected {expected}, got {actual}"


def test_command_line_execution_on_fresh_unstable_input():
    rng = random.SystemRandom()
    baseline = rng.randrange(100_000_000, 1_000_000_000)
    step = rng.choice([0.005, 0.01, 0.02])
    offsets = rng.sample(range(-20, 21), 7)
    prices = [baseline + step * offset for offset in offsets]
    payload = ",".join(repr(value) for value in prices)
    expected_output = f"{statistics.stdev(prices):.6f}"

    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH, payload],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert completed.returncode == 0, \
        f"calc_volatility.py failed: {completed.stderr or completed.stdout}"
    assert completed.stdout.strip() == expected_output, \
        f"Expected CLI output '{expected_output}', but found '{completed.stdout.strip()}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
