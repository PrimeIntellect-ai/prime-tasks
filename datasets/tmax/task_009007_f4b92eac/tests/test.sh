#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

DATA_PATH = Path("/home/user/data/raw_products.jsonl")
RESULT_PATH = Path("/home/user/test_results.json")


def load_records(raw_bytes):
    return [json.loads(line) for line in raw_bytes.decode("utf-8").splitlines() if line.strip()]


def expected_result(records):
    descriptions = [row["description"] for row in records]
    categories = [row["category"] for row in records]
    vectorizer = TfidfVectorizer(stop_words="english", max_features=50)
    embeddings = vectorizer.fit_transform(descriptions)
    classifier = LogisticRegression(random_state=42)
    classifier.fit(embeddings[:80], categories[:80])
    predictions = classifier.predict(embeddings[80:]).tolist()
    accuracy = float(accuracy_score(categories[80:], predictions))
    return {
        "accuracy": accuracy,
        "passed": accuracy > 0.80,
        "predictions": predictions,
    }


def make_probe_records():
    records = []
    for i in range(100):
        amber = ((i * 7 + i // 3) % 5) < 2
        if amber:
            description = "quasar zircon processor circuitry voltage battery nebula"
            category = "AmberGoods"
        else:
            description = "velvet cotton garment tailoring fabric meadow comfort"
            category = "VioletGoods"
        records.append({"id": 1000 + i, "description": description, "category": category})
    return records


def write_records(records):
    with DATA_PATH.open("w", encoding="utf-8") as handle:
        for row in records:
            handle.write(json.dumps(row) + "\n")


def candidate_commands():
    excluded = {DATA_PATH.resolve(), RESULT_PATH.resolve()}
    commands = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".git"}]
        for filename in files:
            path = Path(root) / filename
            try:
                resolved = path.resolve()
                if resolved in excluded or not path.is_file():
                    continue
                first_line = b""
                with path.open("rb") as handle:
                    first_line = handle.readline(512)
            except (OSError, RuntimeError):
                continue

            if path.suffix == ".py":
                commands.append((str(path), ["python3", str(path)]))
            elif path.suffix == ".sh":
                commands.append((str(path), ["bash", str(path)]))
            elif os.access(path, os.X_OK):
                commands.append((str(path), [str(path)]))
            elif first_line.startswith(b"#!"):
                shebang = first_line[2:].decode("utf-8", "ignore").strip()
                parts = shlex.split(shebang)
                if parts and os.path.basename(parts[0]) == "env":
                    parts = parts[1:]
                if parts:
                    commands.append((str(path), parts + [str(path)]))
    return [command for _, command in sorted(commands, key=lambda item: item[0])]


def execute(command):
    if RESULT_PATH.exists():
        RESULT_PATH.unlink()
    completed = subprocess.run(
        command,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    if completed.returncode != 0 or not RESULT_PATH.is_file():
        return None
    try:
        with RESULT_PATH.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None


def matches_expected(actual, expected):
    return (
        isinstance(actual, dict)
        and isinstance(actual.get("accuracy"), (int, float))
        and not isinstance(actual.get("accuracy"), bool)
        and abs(float(actual["accuracy"]) - expected["accuracy"]) < 1e-12
        and isinstance(actual.get("passed"), bool)
        and actual["passed"] is expected["passed"]
        and actual.get("predictions") == expected["predictions"]
        and isinstance(actual.get("predictions"), list)
        and all(isinstance(value, str) for value in actual["predictions"])
    )


def test_pipeline_script_is_executed_and_recomputes_results():
    original_bytes = DATA_PATH.read_bytes()
    original_records = load_records(original_bytes)
    probe_records = make_probe_records()
    probe_expected = expected_result(probe_records)
    selected_command = None

    try:
        for command in candidate_commands():
            write_records(probe_records)
            actual = execute(command)
            if matches_expected(actual, probe_expected):
                selected_command = command
                break
    finally:
        DATA_PATH.write_bytes(original_bytes)

    assert selected_command is not None, "No runnable submitted script generated correct results for an independently derived probe dataset."

    actual = execute(selected_command)
    assert actual is not None, "The submitted script did not recreate /home/user/test_results.json on the original input."
    assert matches_expected(actual, expected_result(original_records)), "The script output does not match a recomputation of the required TF-IDF and LogisticRegression pipeline."


def test_test_results_file_exists():
    assert os.path.isfile("/home/user/test_results.json"), "/home/user/test_results.json file is missing. The script did not produce the expected output file."


def test_test_results_content():
    file_path = "/home/user/test_results.json"

    with open(file_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    # Check keys
    assert "accuracy" in results, "Missing 'accuracy' key in test_results.json"
    assert "passed" in results, "Missing 'passed' key in test_results.json"
    assert "predictions" in results, "Missing 'predictions' key in test_results.json"

    # Check accuracy
    assert isinstance(results["accuracy"], (int, float)), "'accuracy' must be a number."
    assert results["accuracy"] == 1.0, f"Expected accuracy to be 1.0, but got {results['accuracy']}."

    # Check passed flag
    assert isinstance(results["passed"], bool), "'passed' must be a boolean."
    assert results["passed"] is True, "Expected 'passed' to be true."

    # Check predictions
    predictions = results["predictions"]
    assert isinstance(predictions, list), "'predictions' must be a list."
    assert len(predictions) == 20, f"Expected exactly 20 predictions, but got {len(predictions)}."

    expected_predictions = [
        "Electronics" if i % 2 == 0 else "Clothing"
        for i in range(20)
    ]

    assert predictions == expected_predictions, "The predicted categories do not match the expected pattern."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
