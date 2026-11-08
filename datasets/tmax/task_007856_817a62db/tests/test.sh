#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile
from fractions import Fraction


def run_script(script_path, csv_path, sensor):
    result = subprocess.run(
        [script_path, csv_path, sensor],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script crashed or returned non-zero exit code. STDERR: {result.stderr}"
    )

    output = result.stdout.strip()
    assert output, "Script produced no output."
    try:
        return int(output)
    except ValueError:
        raise AssertionError(f"Script output '{output}' is not a valid integer.")


def exact_population_variance_floor(values):
    count = len(values)
    assert count > 0
    total = sum(values)
    total_sq = sum(value * value for value in values)
    variance = Fraction(count * total_sq - total * total, count * count)
    return variance.numerator // variance.denominator, variance


def test_buggy_line_identified():
    """Verify that the buggy line number was correctly identified and written to buggy_line.txt."""
    buggy_file = "/home/user/buggy_line.txt"
    assert os.path.isfile(buggy_file), f"File {buggy_file} does not exist."

    with open(buggy_file, "r") as f:
        content = f.read().strip()

    assert content == "3421", f"Expected buggy line to be 3421, but found '{content}'."


def test_calc_variance_script_output():
    """Verify correctness on the supplied daily query."""
    script_path = "/home/user/calc_variance.sh"
    csv_path = "/home/user/daily_query.csv"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    vals = []
    with open(csv_path, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) >= 3 and parts[1] == "SENSOR_X":
                try:
                    vals.append(float(parts[2]))
                except ValueError:
                    pass

    assert len(vals) > 0, "No valid sensor readings found."
    mean = sum(vals) / len(vals)
    variance = sum((x - mean) ** 2 for x in vals) / len(vals)
    expected_variance = math.floor(variance)

    student_variance = run_script(script_path, csv_path, "SENSOR_X")
    assert student_variance == expected_variance, (
        f"Incorrect variance calculated. Expected {expected_variance}, got {student_variance}."
    )


def test_arguments_malformed_values_and_large_dataset():
    """Exercise arbitrary file/sensor arguments, malformed values, and overflow-prone totals."""
    script_path = "/home/user/calc_variance.sh"
    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)
    target_sensor = f"TARGET_{token}"
    other_sensor = f"OTHER_{token}"

    # More than 1,800 readings near two million makes (sum * sum) exceed
    # signed 64-bit arithmetic, while the true variance remains modest.
    while True:
        base = rng.randint(2_000_000, 4_000_000)
        target_values = [base + rng.randint(-5000, 5000) for _ in range(1901)]
        expected_target, exact_variance = exact_population_variance_floor(target_values)
        fractional_part = exact_variance - expected_target
        if Fraction(1, 5) < fractional_part < Fraction(4, 5):
            break

    other_base = rng.randint(5_000_000, 8_000_000)
    other_values = [other_base - 1200, other_base - 200, other_base + 300,
                    other_base + 900, other_base + 1700]
    expected_other, _ = exact_population_variance_floor(other_values)

    fd, csv_path = tempfile.mkstemp(prefix="variance_case_", suffix=".csv")
    os.close(fd)
    try:
        with open(csv_path, "w") as f:
            for index, value in enumerate(target_values):
                f.write(f"2026-01-01T00:00:{index % 60:02d}Z,{target_sensor},{value}\n")
                if index == 50:
                    f.write(f"2026-01-01T01:00:00Z,{target_sensor},\n")
                    f.write(f"2026-01-01T01:00:01Z,{target_sensor},not-a-number\n")
                    f.write(f"2026-01-01T01:00:02Z,{target_sensor},123oops\n")
                    f.write(f"2026-01-01T01:00:03Z,{target_sensor},1+2\n")
                    f.write(f"2026-01-01T01:00:04Z,{target_sensor},   \n")
            for index, value in enumerate(other_values):
                f.write(f"2026-01-02T00:00:{index:02d}Z,{other_sensor},{value}\n")
            f.write(f"2026-01-02T01:00:00Z,{other_sensor},broken\n")

        actual_target = run_script(script_path, csv_path, target_sensor)
        assert actual_target == expected_target, (
            f"Incorrect variance for generated target sensor. "
            f"Expected {expected_target}, got {actual_target}."
        )

        actual_other = run_script(script_path, csv_path, other_sensor)
        assert actual_other == expected_other, (
            f"Script did not honor the sensor argument. "
            f"Expected {expected_other}, got {actual_other}."
        )
    finally:
        os.unlink(csv_path)


if __name__ == "__main__":
    raise SystemExit("Run with pytest")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
