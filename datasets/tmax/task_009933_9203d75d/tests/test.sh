#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "predictor.go")
BINARY = "/tmp/predictor_under_test"
HISTORICAL = os.path.join(HOME, "historical_jobs.csv")
QUERIES = os.path.join(HOME, "queries.csv")
PREDICTIONS = os.path.join(HOME, "predictions.csv")
BENCHMARK = os.path.join(HOME, "benchmark.txt")


def run_predictor(timeout=30):
    for path in (PREDICTIONS, BENCHMARK):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run([BINARY], cwd=HOME, check=True, timeout=timeout)
    assert os.path.isfile(PREDICTIONS), "Running predictor.go did not create predictions.csv"
    assert os.path.isfile(BENCHMARK), "Running predictor.go did not create benchmark.txt"


def read_benchmark():
    with open(BENCHMARK, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[0-9]+", content), f"benchmark.txt must contain one non-negative integer, got {content!r}"
    return int(content)


def read_predictions():
    with open(PREDICTIONS, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "predictions.csv is empty"
    assert rows[0] == ["QueryID", "Predicted_Duration"]
    result = {}
    for row in rows[1:]:
        assert len(row) == 2, f"Invalid prediction row: {row}"
        assert row[0] not in result, f"Duplicate QueryID in predictions.csv: {row[0]}"
        assert re.fullmatch(r"-?[0-9]+\.[0-9]{2}", row[1]), f"Prediction is not formatted to exactly two decimals: {row[1]!r}"
        result[row[0]] = row[1]
    return result


def expected_predictions(history, queries):
    mins = [min(row[i] for row in history) for i in range(3)]
    maxs = [max(row[i] for row in history) for i in range(3)]

    def scaled(features):
        return tuple(0.0 if maxs[i] == mins[i] else (features[i] - mins[i]) / (maxs[i] - mins[i]) for i in range(3))

    scaled_history = [(scaled(row[:3]), row[3]) for row in history]
    expected = {}
    for query_id, features in queries:
        sq = scaled(features)
        ranked = []
        for index, (sh, duration) in enumerate(scaled_history):
            distance = math.sqrt(sum((sq[i] - sh[i]) ** 2 for i in range(3)))
            ranked.append((distance, index, duration))
        ranked.sort()
        prediction = sum(item[2] for item in ranked[:3]) / 3.0
        expected[query_id] = f"{prediction:.2f}"
    return expected


def write_case(history, queries):
    with open(HISTORICAL, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["JobID", "CPU_Cores", "RAM_GB", "Disk_IOps", "Job_Duration"])
        for i, row in enumerate(history, 1):
            writer.writerow([f"J{i}", *row])
    with open(QUERIES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["QueryID", "CPU_Cores", "RAM_GB", "Disk_IOps"])
        for query_id, features in queries:
            writer.writerow([query_id, *features])


@pytest.fixture(scope="session", autouse=True)
def build_execute_and_restore():
    with open(HISTORICAL, "rb") as f:
        original_history = f.read()
    with open(QUERIES, "rb") as f:
        original_queries = f.read()

    subprocess.run(["go", "build", "-o", BINARY, SOURCE], cwd=HOME, check=True, timeout=30)
    run_predictor()
    yield

    with open(HISTORICAL, "wb") as f:
        f.write(original_history)
    with open(QUERIES, "wb") as f:
        f.write(original_queries)
    try:
        run_predictor()
    except Exception:
        pass


def test_predictor_go_exists():
    path = "/home/user/predictor.go"
    assert os.path.isfile(path), f"Expected Go source file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content.startswith("package main") or "func main()" in content, f"File {path} does not appear to be a valid Go program."


def test_predictions_csv_correct():
    path = "/home/user/predictions.csv"
    assert os.path.isfile(path), f"Expected predictions file {path} does not exist."

    expected_rows = {
        "Q1": "90.00",
        "Q2": "25.17",
        "Q3": "105.17",
        "Q4": "25.17"
    }

    with open(path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["QueryID", "Predicted_Duration"], f"Incorrect header in {path}. Expected ['QueryID', 'Predicted_Duration'], got {header}."

        actual_rows = {}
        for row in reader:
            assert len(row) == 2, f"Invalid row length in {path}: {row}"
            actual_rows[row[0]] = row[1]

    assert actual_rows == expected_rows, f"Predictions in {path} do not match expected values. Expected {expected_rows}, got {actual_rows}."


def test_benchmark_txt_valid():
    path = "/home/user/benchmark.txt"
    assert os.path.isfile(path), f"Expected benchmark file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."

    try:
        val = int(content)
    except ValueError:
        pytest.fail(f"File {path} does not contain a valid integer. Content: '{content}'")

    assert val >= 0, f"Benchmark time in {path} should be a non-negative integer."


def test_predictor_functionally_on_unseen_inputs_and_benchmark():
    rng = random.Random(918273)

    # This case has a constant historical CPU feature, exercising Max == Min,
    # and query IDs and values not present in the image's fixed data.
    history = []
    for i in range(19):
        ram = float(f"{rng.uniform(2.0, 90.0):.8f}")
        disk = float(f"{rng.uniform(20.0, 2400.0):.8f}")
        history.append((5.0, ram, disk, float(31 + i * 7)))
    queries = []
    for i in range(11):
        features = (
            float(f"{rng.uniform(-10.0, 20.0):.8f}"),
            float(f"{rng.uniform(-15.0, 115.0):.8f}"),
            float(f"{rng.uniform(-300.0, 2900.0):.8f}"),
        )
        queries.append((f"unseen-{i}-x", features))

    write_case(history, queries)
    run_predictor()
    assert read_predictions() == expected_predictions(history, queries)
    small_benchmark = read_benchmark()

    # A substantially larger independently generated workload checks all output
    # rows and ensures the reported inference duration is real and workload-sensitive.
    history = []
    for i in range(700):
        history.append((
            float(f"{rng.uniform(-50.0, 180.0):.8f}"),
            float(f"{rng.uniform(0.1, 1024.0):.8f}"),
            float(f"{rng.uniform(-500.0, 50000.0):.8f}"),
            float(20 + (i * 37) % 997),
        ))
    queries = []
    for i in range(1000):
        queries.append((f"load-{i:04d}", (
            float(f"{rng.uniform(-90.0, 220.0):.8f}"),
            float(f"{rng.uniform(-100.0, 1200.0):.8f}"),
            float(f"{rng.uniform(-9000.0, 62000.0):.8f}"),
        )))

    write_case(history, queries)
    run_predictor(timeout=60)
    assert read_predictions() == expected_predictions(history, queries)
    large_benchmark = read_benchmark()
    assert large_benchmark > 0, "A nontrivial KNN workload must have a positive microsecond inference duration"
    assert large_benchmark > small_benchmark, (
        f"Reported inference duration did not increase for a much larger KNN workload: "
        f"small={small_benchmark}, large={large_benchmark}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
