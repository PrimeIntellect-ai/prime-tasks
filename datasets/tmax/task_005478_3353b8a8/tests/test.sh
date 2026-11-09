#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import struct
import subprocess
import tempfile


def to_float32(val):
    """Simulate IEEE 754 32-bit float casting."""
    return struct.unpack('f', struct.pack('f', float(val)))[0]


def compute_expected_failing_row():
    """Derive the exact failing row using float32 simulation."""
    count = to_float32(0.0)
    sum_val = to_float32(0.0)
    sum_sq = to_float32(0.0)

    for i in range(1, 10001):
        val = to_float32(10000.0 if i % 2 != 0 else 10000.1)
        count = to_float32(count + to_float32(1.0))
        sum_val = to_float32(sum_val + val)
        sum_sq = to_float32(sum_sq + to_float32(val * val))

        mean = to_float32(sum_val / count)
        variance = to_float32(to_float32(sum_sq / count) - to_float32(mean * mean))

        if variance < 0:
            return i
    return -1


def expected_output(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
    return f"{math.sqrt(variance):.6f}\n"


def run_processor(executable, csv_path):
    result = subprocess.run(
        [executable, csv_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def test_failing_row():
    """Verify that failing_row.txt contains the correct 1-indexed row count."""
    file_path = "/home/user/data_processor/failing_row.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_row = compute_expected_failing_row()
    assert expected_row > 0, "Failed to compute expected failing row in test."
    assert content == str(expected_row), f"Expected failing row {expected_row}, but got '{content}'."


def test_final_result():
    """Verify that final_result.txt contains the correct standard deviation."""
    file_path = "/home/user/data_processor/final_result.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = "0.050000"
    assert content == expected, f"Expected final result '{expected}', but got '{content}'."


def test_processor_executable():
    """Verify that the processor executable exists and is executable."""
    file_path = "/home/user/data_processor/processor"
    assert os.path.isfile(file_path), f"Executable {file_path} does not exist."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."


def test_processor_and_fixed_source_behavior():
    base = "/home/user/data_processor"
    source = os.path.join(base, "main.go")
    submitted = os.path.join(base, "processor")
    dataset = os.path.join(base, "dataset.csv")

    assert os.path.isfile(source), f"Source {source} does not exist."

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "processor_from_main")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, source],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"main.go does not build:\n{build.stderr}"

        with open(dataset, "r") as f:
            production_values = [float(line.strip()) for line in f if line.strip()]
        production_expected = expected_output(production_values)
        assert production_expected == "0.050000\n"

        submitted_output = run_processor(submitted, dataset)
        rebuilt_output = run_processor(rebuilt, dataset)
        assert submitted_output == production_expected
        assert rebuilt_output == production_expected

        with open(os.path.join(base, "final_result.txt"), "r") as f:
            assert f.read() == submitted_output

        probes = [
            [10000.0 + ((i % 7) - 3) * 0.03125 for i in range(733)],
            [24000.0 + (0.125 if i % 3 == 0 else -0.0625) for i in range(911)],
        ]
        for index, values in enumerate(probes):
            probe_path = os.path.join(temp_dir, f"probe_{index}.csv")
            with open(probe_path, "w") as f:
                for value in values:
                    f.write(f"{value:.10f}\n")
            expected = expected_output(values)
            assert run_processor(submitted, probe_path) == expected
            assert run_processor(rebuilt, probe_path) == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
