#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess
import tempfile


def test_cleaned_data_correctness():
    cleaned_data_path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(cleaned_data_path), f"File not found: {cleaned_data_path}"

    with open(cleaned_data_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1.0,2.1",
        "2.0,4.0",
        "3.0,6.1",
        "4.0,8.0"
    ]

    assert len(lines) == 4, f"Expected 4 lines in cleaned_data.csv, found {len(lines)}"
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in cleaned_data.csv"

    content = "\n".join(lines)
    assert "X,Y" not in content, "Header was not removed from cleaned_data.csv"
    assert "NaN" not in content, "'NaN' rows were not removed from cleaned_data.csv"
    assert "-1.5" not in content, "Negative X values were not removed from cleaned_data.csv"
    assert "-0.5" not in content, "Negative X values were not removed from cleaned_data.csv"


def test_compiled_executable_exists():
    executable_path = "/home/user/train_model"
    assert os.path.isfile(executable_path), f"Executable not found: {executable_path}"

    st = os.stat(executable_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"File is not executable: {executable_path}"

    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "train_model is not a compiled ELF executable"


def test_model_output_correctness():
    output_path = "/home/user/model_output.txt"
    assert os.path.isfile(output_path), f"File not found: {output_path}"

    with open(output_path, 'r') as f:
        content = f.read()

    assert "Slope: 1.98" in content, "Slope value is incorrect or missing in model_output.txt"
    assert "Intercept: 0.1" in content, "Intercept value is incorrect or missing in model_output.txt"
    assert content == "Slope: 1.98\nIntercept: 0.1\n", "model_output.txt contains extra or incorrect output"

    result = subprocess.run(
        ["/home/user/train_model", "/home/user/cleaned_data.csv"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, "train_model failed on cleaned_data.csv"
    assert result.stdout == content.encode(), "model_output.txt is not the exact output of train_model on cleaned_data.csv"


def _ols(points):
    n = len(points)
    sum_x = sum(x for x, _ in points)
    sum_y = sum(y for _, y in points)
    sum_xy = sum(x * y for x, y in points)
    sum_xx = sum(x * x for x, _ in points)
    mean_x = sum_x / n
    mean_y = sum_y / n
    slope = (sum_xy - n * mean_x * mean_y) / (sum_xx - n * mean_x * mean_x)
    intercept = mean_y - slope * mean_x
    return slope, intercept


def _parse_output(output):
    number = rb"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"
    match = re.fullmatch(rb"Slope: " + number + rb"\nIntercept: " + number + rb"\n", output)
    assert match is not None, f"Unexpected model output format: {output!r}"
    return float(match.group(1)), float(match.group(2))


def test_model_executes_train_cpp_algorithm_on_unseen_inputs():
    source_path = "/home/user/train.cpp"
    assert os.path.isfile(source_path), f"File not found: {source_path}"

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as temp_dir:
        reference = os.path.join(temp_dir, "reference_model")
        build = subprocess.run(
            ["g++", source_path, "-o", reference],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert build.returncode == 0, f"train.cpp does not compile with g++: {build.stderr.decode(errors='replace')}"

        for case_number in range(4):
            count = rng.randint(5, 10)
            xs = rng.sample(range(-80, 121), count)
            points = []
            for x_raw in xs:
                x = x_raw / 4.0
                y = rng.randint(-300, 400) / 10.0
                points.append((x, y))

            data_path = os.path.join(temp_dir, f"input_{case_number}.csv")
            with open(data_path, "w") as f:
                for x, y in points:
                    f.write(f"{x},{y}\n")

            submitted = subprocess.run(
                ["/home/user/train_model", data_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=False,
            )
            trusted = subprocess.run(
                [reference, data_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=False,
            )

            assert submitted.returncode == 0, "train_model failed on a valid unseen CSV input"
            assert submitted.stderr == trusted.stderr, "train_model produced unexpected diagnostic output"
            assert submitted.stdout == trusted.stdout, "train_model behavior does not match the compiled train.cpp source"

            actual_slope, actual_intercept = _parse_output(submitted.stdout)
            expected_slope, expected_intercept = _ols(points)
            assert math.isclose(actual_slope, expected_slope, rel_tol=1e-5, abs_tol=1e-5), "Incorrect slope on unseen data"
            assert math.isclose(actual_intercept, expected_intercept, rel_tol=1e-5, abs_tol=1e-5), "Incorrect intercept on unseen data"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
