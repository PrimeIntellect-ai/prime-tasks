#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import secrets
import subprocess


def test_output_file_exists_and_correct():
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"Output file does not exist: {output_path}"

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == "154.50", f"Output file contains incorrect value: {content}. Expected: 154.50"


def test_sensor_data_unchanged():
    data_path = "/home/user/sensor_data.txt"
    assert os.path.isfile(data_path), f"Input data file missing: {data_path}"

    with open(data_path, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) == 105, f"Input data file length changed. Expected 105, got {len(lines)}"
    assert lines[0] == "1e16", "Input data file first line changed."
    assert lines[-1] == "-1e16", "Input data file last line changed."

    # Check that the mathematical sum of the file is still 154.50
    floats = [float(x) for x in lines]
    assert math.isclose(math.fsum(floats), 154.50), "Input data file contents changed."


def test_sensor_aggregator_exists():
    script_path = "/home/user/sensor_aggregator.py"
    assert os.path.isfile(script_path), f"Missing script file: {script_path}"


def test_sensor_aggregator_executes_and_handles_edge_cases():
    script_path = "/home/user/sensor_aggregator.py"
    data_path = "/home/user/sensor_data.txt"
    output_path = "/home/user/output.txt"

    with open(data_path, "rb") as f:
        original_data = f.read()

    def run_and_check(data_bytes):
        with open(data_path, "wb") as f:
            f.write(data_bytes)
        if os.path.exists(output_path):
            os.unlink(output_path)

        result = subprocess.run(
            ["python3", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"sensor_aggregator.py exited with {result.returncode}. "
            f"stderr: {result.stderr}"
        )
        assert os.path.isfile(output_path), "Executed script did not create output.txt"

        with open(data_path, "rb") as f:
            assert f.read() == data_bytes, "Executed script modified sensor_data.txt"

        values = [float(line) for line in data_bytes.decode().splitlines() if line.strip()]
        expected = f"{math.fsum(values):.2f}"
        with open(output_path, "r") as f:
            actual = f.read().strip()
        assert actual == expected, f"Executed script produced {actual!r}; expected {expected!r}"

    rng = secrets.SystemRandom()
    cases = [[1.25]]
    for length in (9, 10, 11, rng.randrange(17, 40)):
        while length % 10 == 0 and length not in (10,):
            length += 1
        small_values = [rng.randrange(1, 41) / 4.0 for _ in range(length - 2)]
        cases.append([1e16] + small_values + [-1e16])

    try:
        # Execute the submitted script against the original input first.
        run_and_check(original_data)

        # Exercise incomplete chunks and precision-sensitive cancellation using
        # verifier-generated inputs whose answers are independently derived.
        for values in cases:
            generated = ("\n".join(repr(value) for value in values) + "\n").encode()
            run_and_check(generated)
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)

    # Leave the required output corresponding to the original sensor stream.
    run_and_check(original_data)
    with open(output_path, "r") as f:
        assert f.read().strip() == "154.50"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
