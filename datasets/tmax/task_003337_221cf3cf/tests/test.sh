#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess
import urllib.request

import numpy as np

TRAIN = [
    {"id": 1, "text": "hello world", "label": 1},
    {"id": 2, "text": "bad text", "label": 0},
    {"id": 3, "text": "missing label", "label": None},
    {"id": 4, "text": "a " * 60, "label": 1},
]
TEST = [
    {"id": 5, "text": "hello", "label": None},
    {"id": 6, "text": "bad", "label": None},
]


def clean_text(text):
    text = ''.join(ch for ch in text.lower() if ch.isalpha() or ch == ' ')
    return [token for token in text.split(' ') if token]


def expected_predictions():
    cleaned = []
    for row in TRAIN:
        if row["label"] is None or len(row["text"].split()) > 50:
            continue
        cleaned.append((clean_text(row["text"]), row["label"]))

    vocabulary = sorted({token for tokens, _ in cleaned for token in tokens})
    counts = {0: {token: 0 for token in vocabulary}, 1: {token: 0 for token in vocabulary}}
    totals = {0: 0, 1: 0}
    documents = {0: 0, 1: 0}

    for tokens, label in cleaned:
        documents[label] += 1
        for token in tokens:
            counts[label][token] += 1
            totals[label] += 1

    result = {}
    total_documents = len(cleaned)
    for row in TEST:
        logs = {}
        for label in (0, 1):
            value = math.log(documents[label] / total_documents)
            denominator = totals[label] + len(vocabulary)
            for token in clean_text(row["text"]):
                if token in counts[label]:
                    value += math.log((counts[label][token] + 1) / denominator)
            logs[label] = value
        maximum = max(logs.values())
        p0 = math.exp(logs[0] - maximum)
        p1 = math.exp(logs[1] - maximum)
        result[row["id"]] = p1 / (p0 + p1)
    return result


def test_repaired_api_is_running_and_serves_data():
    with urllib.request.urlopen("http://127.0.0.1:5000/data/train", timeout=5) as response:
        train = json.loads(response.read().decode())
    with urllib.request.urlopen("http://127.0.0.1:5000/data/test", timeout=5) as response:
        test = json.loads(response.read().decode())
    assert train == TRAIN
    assert test == TEST


def test_c_program_builds_runs_and_predictions_match():
    c_file = "/home/user/naive_bayes.c"
    pred_path = "/home/user/predictions.csv"
    executable = "/tmp/verified_naive_bayes"

    assert os.path.exists(c_file), f"C source file not found at {c_file}"
    assert os.path.isfile(c_file), f"C source path is not a regular file: {c_file}"

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", c_file, "-lm", "-o", executable],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"C source did not compile:\n{compile_result.stderr}"

    if os.path.exists(pred_path):
        os.remove(pred_path)
    run_result = subprocess.run(
        [executable],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert run_result.returncode == 0, (
        f"Compiled C program failed with status {run_result.returncode}:\n"
        f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
    )
    assert os.path.exists(pred_path), f"Predictions file not found at {pred_path} after running C program"

    with open(pred_path, newline='') as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["id", "probability_class_1"], (
            "Predictions must contain exactly the columns id,probability_class_1"
        )
        rows = list(reader)

    expected = expected_predictions()
    assert len(rows) == len(expected), "Predictions must contain exactly one row per test item"

    actual = {}
    for row in rows:
        identifier = int(row["id"])
        probability = float(row["probability_class_1"])
        assert identifier not in actual, f"Duplicate prediction ID: {identifier}"
        assert math.isfinite(probability) and 0.0 <= probability <= 1.0
        actual[identifier] = probability

    assert set(actual) == set(expected), "Prediction IDs do not exactly match the test IDs"
    merged_errors = [(expected[i] - actual[i]) ** 2 for i in expected]
    mse = np.mean(merged_errors)
    assert mse <= 0.0001, f"MSE is {mse:.6f}, which is greater than the threshold of 0.0001"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
