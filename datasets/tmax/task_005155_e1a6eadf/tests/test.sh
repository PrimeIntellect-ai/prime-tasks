#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import os
import re
import subprocess
from collections import defaultdict

import pytest


@pytest.fixture(scope="session", autouse=True)
def run_etl_script():
    script_path = "/home/user/run_etl.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    # Generated artifacts must be recreated by the pipeline itself.
    for path in ("/home/user/features.csv", "/home/user/train.py", "/home/user/accuracy.txt"):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}\nOutput:\n{result.stdout}"


def test_features_csv_correctness():
    features_path = "/home/user/features.csv"
    assert os.path.isfile(features_path), f"Missing required file: {features_path}"

    logs = defaultdict(lambda: {"count": 0, "payload": 0, "resp": 0})
    with open("/home/user/raw_logs.txt", "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(" | ")
            ip = parts[1]
            resp = int(parts[2])
            payload = int(parts[3])
            logs[ip]["count"] += 1
            logs[ip]["payload"] += payload
            logs[ip]["resp"] += resp

    labels = {}
    with open("/home/user/labels.csv", "r") as f:
        for line in f:
            if not line.strip():
                continue
            ip, label = line.strip().split(",")
            labels[ip] = int(label)

    expected_rows = []
    for ip in sorted(labels.keys()):
        if ip in logs:
            count = logs[ip]["count"]
            payload = logs[ip]["payload"]
            avg_resp = logs[ip]["resp"] // count
            expected_rows.append(f"{ip},{count},{payload},{avg_resp},{labels[ip]}")

    with open(features_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_rows), f"Expected {len(expected_rows)} rows in features.csv, got {len(actual_lines)}"
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"


def test_train_script_exists():
    train_path = "/home/user/train.py"
    assert os.path.isfile(train_path), f"Python script {train_path} was not created."


def test_accuracy_file():
    acc_path = "/home/user/accuracy.txt"
    assert os.path.isfile(acc_path), f"Missing required file: {acc_path}"

    with open(acc_path, "r") as f:
        content = f.read().strip()

    try:
        acc = float(content)
    except ValueError:
        pytest.fail(f"Accuracy file does not contain a valid float: {content}")

    assert 0.0 <= acc <= 1.0, f"Accuracy {acc} is out of valid range [0, 1]"
    assert acc > 0.8, f"Accuracy {acc} is too low. Expected > 0.8 given the dataset separation."


def test_required_packages_and_install_command():
    with open("/home/user/run_etl.sh", "r") as f:
        source = f.read().lower()

    assert re.search(r"(?:pip3?|python(?:3)?\s+-m\s+pip)\s+install\b", source), \
        "run_etl.sh must use pip install."
    assert "scikit-learn" in source, "run_etl.sh must install scikit-learn."
    assert "pandas" in source, "run_etl.sh must install pandas."

    for package in ("scikit-learn", "pandas"):
        try:
            importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            pytest.fail(f"Required package {package} is not installed after running run_etl.sh")


def test_training_implementation_and_behavior():
    train_path = "/home/user/train.py"
    with open(train_path, "r") as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=train_path)
    except SyntaxError as exc:
        pytest.fail(f"train.py is not valid Python: {exc}")

    lr_calls = []
    accuracy_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            name = node.func.attr
        else:
            name = ""
        if name == "LogisticRegression":
            lr_calls.append(node)
        if name == "accuracy_score":
            accuracy_calls.append(node)

    assert lr_calls, "train.py must instantiate sklearn.linear_model.LogisticRegression."
    assert any(
        any(
            kw.arg == "random_state"
            and isinstance(kw.value, ast.Constant)
            and kw.value.value == 42
            for kw in call.keywords
        )
        for call in lr_calls
    ), "LogisticRegression must be created with random_state=42."
    assert accuracy_calls, "train.py must calculate accuracy using accuracy_score."

    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score

    datasets = []

    separable = []
    for i in range(12):
        separable.append((f"10.0.0.{i+1}", i + 1, 2 * i + 3, (3 * i) % 7 + 1, int(i >= 6)))
    datasets.append(separable)

    conflicting = []
    for i in range(8):
        features = (i + 2, 3 * i + 1, (5 * i) % 11 + 2)
        conflicting.append((f"10.0.1.{2*i+1}", *features, 0))
        conflicting.append((f"10.0.1.{2*i+2}", *features, 1))
    datasets.append(conflicting)

    features_path = "/home/user/features.csv"
    accuracy_path = "/home/user/accuracy.txt"
    with open(features_path, "rb") as f:
        original_features = f.read()
    with open(accuracy_path, "rb") as f:
        original_accuracy = f.read()

    try:
        for rows in datasets:
            with open(features_path, "w") as f:
                for row in rows:
                    f.write(",".join(map(str, row)) + "\n")

            x = [[row[1], row[2], row[3]] for row in rows]
            y = [row[4] for row in rows]
            reference = LogisticRegression(random_state=42)
            reference.fit(x, y)
            expected = accuracy_score(y, reference.predict(x))

            if os.path.exists(accuracy_path):
                os.remove(accuracy_path)
            result = subprocess.run(
                ["python3", train_path], capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, \
                f"train.py failed on a valid features.csv:\n{result.stderr}\nOutput:\n{result.stdout}"
            assert os.path.isfile(accuracy_path), "train.py did not create accuracy.txt."

            with open(accuracy_path, "r") as f:
                content = f.read().strip()
            try:
                actual = float(content)
            except ValueError:
                pytest.fail(f"train.py wrote a non-numeric accuracy: {content!r}")

            assert 0.0 <= actual <= 1.0
            assert actual == pytest.approx(float(expected), abs=1e-12), \
                f"Expected LogisticRegression training accuracy {expected}, got {actual}"
    finally:
        with open(features_path, "wb") as f:
            f.write(original_features)
        with open(accuracy_path, "wb") as f:
            f.write(original_accuracy)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
