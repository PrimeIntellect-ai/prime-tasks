#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest


def test_report_exists():
    """Check if the report file was created."""
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."


def test_report_contents():
    """Check if the report file contains the correct results sorted alphabetically."""
    report_path = "/home/user/report.txt"

    if not os.path.isfile(report_path):
        pytest.fail(f"Report file {report_path} does not exist.")

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "exp1.csv: PASS",
        "exp2.csv: FAIL",
        "exp3.csv: FAIL"
    ]

    assert lines == expected_lines, (
        f"Report file contents do not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(lines)}"
    )


def test_go_program_updated():
    """Check if the Go program was modified to remove the TODOs."""
    go_path = "/home/user/check_accuracy.go"

    if not os.path.isfile(go_path):
        pytest.fail(f"Go program {go_path} does not exist.")

    with open(go_path, "r") as f:
        content = f.read()

    assert "TODO:" not in content, "Go program still contains 'TODO:' comments."


@pytest.fixture(scope="module")
def executable(tmp_path_factory):
    """Compile the submitted Go source and return the resulting executable."""
    output = tmp_path_factory.mktemp("bin") / "check_accuracy"
    result = subprocess.run(
        ["go", "build", "-o", str(output), "/home/user/check_accuracy.go"],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "check_accuracy.go did not compile successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert output.is_file(), "Go build did not produce an executable."
    return output


def expected_result(values):
    n = len(values)
    mean = sum(values) / n
    variance = sum((value - mean) ** 2 for value in values) / (n - 1)
    std_dev = math.sqrt(variance)
    lower = mean - 1.96 * (std_dev / math.sqrt(n))
    upper = mean + 1.96 * (std_dev / math.sqrt(n))
    return "PASS" if lower < 10.0 < upper else "FAIL"


def run_submission(executable, dataset):
    result = subprocess.run(
        [str(executable), str(dataset)],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program failed on {dataset}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result.stdout.strip()


def test_program_on_supplied_datasets(executable):
    """Run the compiled submission on every supplied dataset."""
    for name in ("exp1.csv", "exp2.csv", "exp3.csv"):
        path = os.path.join("/home/user/datasets", name)
        with open(path, "r") as f:
            values = [float(line.strip()) for line in f if line.strip()]
        actual = run_submission(executable, path)
        expected = expected_result(values)
        assert actual == expected, f"Incorrect output for {name}: expected {expected}, got {actual!r}"


def test_confidence_interval_calculation(executable, tmp_path):
    """Exercise the submitted calculation on fresh, verifier-derived cases."""
    rng = secrets.SystemRandom()
    cases = []

    # A zero-width interval at the target must fail because containment is strict.
    cases.append([10.0] * 6)

    # Generate cases immediately inside and outside both sides of the correct CI.
    # Small sample sizes also distinguish sample from population standard deviation.
    for n, side, margin_factor in (
        (5, 1.0, 0.95),
        (6, -1.0, 0.70),
        (7, 1.0, 1.05),
        (8, -1.0, 1.30),
    ):
        residuals = [rng.uniform(-3.0, 3.0) for _ in range(n)]
        residual_mean = sum(residuals) / n
        residuals = [value - residual_mean for value in residuals]
        sample_sd = math.sqrt(sum(value * value for value in residuals) / (n - 1))
        correct_margin = 1.96 * sample_sd / math.sqrt(n)
        desired_mean = 10.0 + side * margin_factor * correct_margin
        cases.append([desired_mean + value for value in residuals])

    for index, values in enumerate(cases):
        path = tmp_path / f"case_{secrets.token_hex(8)}_{index}.csv"
        path.write_text("".join(f"{value:.17g}\n" for value in values))

        # Derive the answer from the exact values serialized to the test file.
        serialized_values = [float(line) for line in path.read_text().splitlines()]
        expected = expected_result(serialized_values)
        actual = run_submission(executable, path)
        assert actual == expected, (
            f"Incorrect confidence-interval result for generated case {index}: "
            f"expected {expected}, got {actual!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
