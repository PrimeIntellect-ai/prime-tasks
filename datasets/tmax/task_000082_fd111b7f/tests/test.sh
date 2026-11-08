#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import pytest

CPP_PATH = "/home/user/fit_model.cpp"
DATASET_PATH = "/home/user/dataset.csv"
RESULTS_PATH = "/home/user/results.json"
BINARY_PATH = "/tmp/fit_model_verified"


def newton_y(x, p1, p2):
    y = 1.0
    for _ in range(50):
        f = y * y * y + p1 * y - p2 * x
        if abs(f) < 1e-6:
            break
        derivative = 3.0 * y * y + p1
        y -= f / derivative
    return y


def calculate_sse(rows, p1, p2):
    total = 0.0
    for x, observed in rows:
        predicted = newton_y(x, p1, p2)
        total += (predicted - observed) ** 2
    return total


def expected_result(rows):
    p1 = 1.0
    p2 = 1.0
    h = 1e-4
    eta = 0.005

    for _ in range(1000):
        grad_p1 = (
            calculate_sse(rows, p1 + h, p2)
            - calculate_sse(rows, p1 - h, p2)
        ) / (2.0 * h)
        grad_p2 = (
            calculate_sse(rows, p1, p2 + h)
            - calculate_sse(rows, p1, p2 - h)
        ) / (2.0 * h)
        p1 -= eta * grad_p1
        p2 -= eta * grad_p2

    sse = calculate_sse(rows, p1, p2)
    return {"p1": round(p1, 4), "p2": round(p2, 4), "sse": round(sse, 4)}


def make_synthetic_rows(true_p1, true_p2, xs, offsets):
    return [
        (x, float(f"{newton_y(x, true_p1, true_p2) + offset:.6f}"))
        for x, offset in zip(xs, offsets)
    ]


def write_dataset(rows):
    with open(DATASET_PATH, "w", encoding="utf-8") as f:
        f.write("x,y_obs\n")
        for x, y in rows:
            f.write(f"{x:.6f},{y:.6f}\n")


def parse_dataset(raw):
    lines = raw.decode("utf-8").strip().splitlines()
    assert lines[0].strip() == "x,y_obs"
    rows = []
    for line in lines[1:]:
        x, y = line.split(",")
        rows.append((float(x), float(y)))
    return rows


def run_submission():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    subprocess.run(
        [BINARY_PATH],
        cwd="/home/user",
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(RESULTS_PATH), f"The results file is missing at {RESULTS_PATH}"

    text = open(RESULTS_PATH, "r", encoding="utf-8").read()
    number = r"-?(?:0|[1-9][0-9]*)\.[0-9]{4}"
    pattern = (
        r'^\s*\{\s*"p1"\s*:\s*(' + number + r')\s*,\s*'
        r'"p2"\s*:\s*(' + number + r')\s*,\s*'
        r'"sse"\s*:\s*(' + number + r')\s*\}\s*$'
    )
    assert re.fullmatch(pattern, text), (
        "results.json must contain exactly p1, p2, and sse in that order, "
        "with every value written to four decimal places"
    )

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        pytest.fail(f"The file at {RESULTS_PATH} is not valid JSON.")
    return data


@pytest.fixture(scope="session")
def verified_original_result():
    assert os.path.isfile(CPP_PATH), f"The C++ source file is missing at {CPP_PATH}"
    assert os.path.getsize(CPP_PATH) > 0, "The C++ source file is empty"

    subprocess.run(
        ["g++", "-O3", "-std=c++17", CPP_PATH, "-o", BINARY_PATH],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)

    with open(DATASET_PATH, "rb") as f:
        original_raw = f.read()
    original_rows = parse_dataset(original_raw)

    cases = [
        make_synthetic_rows(
            0.8,
            1.6,
            [0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.2, 3.6, 4.0],
            [0.002, -0.003, 0.001, -0.002, 0.003, -0.001, 0.002, -0.002, 0.001, -0.001],
        ),
        make_synthetic_rows(
            2.5,
            3.0,
            [0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0],
            [-0.002, 0.001, 0.003, -0.001, 0.002, -0.003, 0.001, 0.002, -0.001, 0.001],
        ),
    ]

    try:
        for rows in cases:
            write_dataset(rows)
            actual = run_submission()
            expected = expected_result(rows)
            for key in ("p1", "p2", "sse"):
                assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool)
                assert math.isfinite(actual[key])
                assert abs(actual[key] - expected[key]) < 5e-5, (
                    f"Incorrect {key} on a verifier-generated dataset: "
                    f"got {actual[key]}, expected {expected[key]:.4f}"
                )

        with open(DATASET_PATH, "wb") as f:
            f.write(original_raw)
        actual = run_submission()
        expected = expected_result(original_rows)
        for key in ("p1", "p2", "sse"):
            assert abs(actual[key] - expected[key]) < 5e-5, (
                f"Incorrect {key} for the reference dataset: "
                f"got {actual[key]}, expected {expected[key]:.4f}"
            )
        yield actual
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original_raw)


def test_cpp_file_exists():
    cpp_path = "/home/user/fit_model.cpp"
    assert os.path.isfile(cpp_path), f"The C++ source file is missing at {cpp_path}"


def test_results_json_exists_and_valid(verified_original_result):
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"The results file is missing at {results_path}"

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file at {results_path} is not valid JSON.")

    assert "p1" in data, "The results.json file is missing the 'p1' key."
    assert "p2" in data, "The results.json file is missing the 'p2' key."
    assert "sse" in data, "The results.json file is missing the 'sse' key."

    p1 = data["p1"]
    p2 = data["p2"]
    sse = data["sse"]

    assert isinstance(p1, (int, float)), f"'p1' must be a number, got {type(p1)}"
    assert isinstance(p2, (int, float)), f"'p2' must be a number, got {type(p2)}"
    assert isinstance(sse, (int, float)), f"'sse' must be a number, got {type(sse)}"

    assert 1.9 <= p1 <= 2.1, f"p1 out of bounds: {p1}. Expected between 1.9000 and 2.1000."
    assert 3.9 <= p2 <= 4.1, f"p2 out of bounds: {p2}. Expected between 3.9000 and 4.1000."
    assert sse < 0.05, f"sse too high: {sse}. Expected less than 0.05."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
