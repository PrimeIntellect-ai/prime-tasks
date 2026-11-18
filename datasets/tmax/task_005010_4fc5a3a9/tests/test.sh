#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import sys

import pytest

CRASH_INPUT_PATH = "/home/user/crash_input.txt"
FIXED_STATS_PATH = "/home/user/fixed_stats.py"
RUN_TRACE_PATH = "/home/user/run_trace.py"
FIXED_OUTPUT_PATH = "/home/user/fixed_output.txt"


def two_pass_truth(data):
    n = len(data)
    mean = sum(data) / n
    variance = sum((x - mean) ** 2 for x in data) / n
    return mean, math.sqrt(variance)


def read_crash_data():
    with open(CRASH_INPUT_PATH, "r") as f:
        content = f.read().strip()
    assert content, "crash_input.txt is empty."
    try:
        return [float(x.strip()) for x in content.split(",")]
    except ValueError:
        pytest.fail("crash_input.txt does not contain valid comma-separated floats.")


def read_output():
    with open(FIXED_OUTPUT_PATH, "r") as f:
        output_str = f.read().strip()
    try:
        return float(output_str)
    except ValueError:
        pytest.fail(f"fixed_output.txt does not contain a valid float: {output_str}")


def execute_runner():
    if os.path.exists(FIXED_OUTPUT_PATH):
        os.unlink(FIXED_OUTPUT_PATH)
    subprocess.run(
        [sys.executable, RUN_TRACE_PATH],
        cwd="/home/user",
        check=True,
        timeout=10,
    )
    assert os.path.isfile(FIXED_OUTPUT_PATH), "run_trace.py did not create fixed_output.txt."
    return read_output()


def test_files_exist():
    for path in [CRASH_INPUT_PATH, FIXED_STATS_PATH, RUN_TRACE_PATH, FIXED_OUTPUT_PATH]:
        assert os.path.isfile(path), f"Required file {path} is missing."


def test_crash_input_triggers_value_error():
    sys.path.insert(0, "/home/user")
    import legacy_stats

    data = read_crash_data()
    with pytest.raises(ValueError) as excinfo:
        legacy_stats.calculate_metrics(data)

    assert (
        "math domain error" in str(excinfo.value)
        or "math domain error" in repr(excinfo.value)
        or excinfo.type is ValueError
    ), "Expected legacy_stats to raise ValueError due to math domain error."


def test_fixed_stats_implementation():
    sys.path.insert(0, "/home/user")
    import fixed_stats

    with open(FIXED_STATS_PATH, "r") as f:
        source = f.read()
    assert "import statistics" not in source, "Do not use the statistics module."
    assert "from statistics" not in source, "Do not use the statistics module."

    # Preserve the original functional check.
    test_data = [1e9 + 1, 1e9 + 2, 1e9 + 3]
    result = fixed_stats.calculate_metrics(test_data)
    assert isinstance(result, tuple) and len(result) == 2
    mean, std_dev = result
    assert math.isclose(mean, 1e9 + 2), f"Expected mean 1000000002.0, got {mean}"
    expected_std_dev = math.sqrt(2 / 3)
    assert math.isclose(std_dev, expected_std_dev), f"Expected std_dev {expected_std_dev}, got {std_dev}"

    # Exercise unpredictable datasets, including large bases with small variation,
    # so a return value hardcoded for the original fixed dataset cannot pass.
    rng = secrets.SystemRandom()
    datasets = [
        [rng.uniform(-10000.0, 10000.0) for _ in range(rng.randrange(5, 30))],
        [
            float(rng.randrange(10**11, 10**12)) + rng.randrange(-40, 41) * 0.25
            for _ in range(rng.randrange(8, 35))
        ],
        [float(rng.randrange(-1000, 1001)) for _ in range(rng.randrange(4, 25))],
    ]

    for data in datasets:
        expected_mean, expected_std = two_pass_truth(data)
        result = fixed_stats.calculate_metrics(data)
        assert isinstance(result, tuple) and len(result) == 2, "calculate_metrics must return a 2-tuple."
        actual_mean, actual_std = result
        assert math.isclose(actual_mean, expected_mean, rel_tol=1e-12, abs_tol=1e-12), (
            f"Incorrect mean for generated input: expected {expected_mean}, got {actual_mean}"
        )
        assert math.isclose(actual_std, expected_std, rel_tol=1e-9, abs_tol=1e-12), (
            f"Incorrect population standard deviation for generated input: expected {expected_std}, got {actual_std}"
        )


def test_run_trace_executes_and_reads_input():
    with open(CRASH_INPUT_PATH, "rb") as f:
        original_input = f.read()

    rng = secrets.SystemRandom()
    base = float(rng.randrange(10**7, 10**8))
    generated = [base + rng.randrange(-100, 101) * 0.125 for _ in range(17)]
    generated_expected = two_pass_truth(generated)[1]

    try:
        with open(CRASH_INPUT_PATH, "w") as f:
            f.write(",".join(repr(x) for x in generated) + "\n")
        generated_output = execute_runner()
        assert math.isclose(generated_output, generated_expected, rel_tol=1e-9, abs_tol=1e-12), (
            f"run_trace.py produced {generated_output}, expected {generated_expected} for generated input"
        )
    finally:
        with open(CRASH_INPUT_PATH, "wb") as f:
            f.write(original_input)

    # Run once more on the submitted crash witness, leaving the required final
    # output in place for the original output assertion below.
    original_data = read_crash_data()
    original_expected = two_pass_truth(original_data)[1]
    original_output = execute_runner()
    assert math.isclose(original_output, original_expected, rel_tol=1e-5), (
        f"run_trace.py produced {original_output}, expected {original_expected} for crash_input.txt"
    )


def test_fixed_output_correctness():
    data = read_crash_data()
    expected_std_dev = two_pass_truth(data)[1]
    output_val = read_output()
    assert math.isclose(output_val, expected_std_dev, rel_tol=1e-5), (
        f"fixed_output.txt contains {output_val}, expected {expected_std_dev}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
