#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import pickle
import random
import string
import subprocess
import time

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline


def read_nonempty_lines(path):
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def expected_processed_rows():
    with open("/home/user/data/dataset.csv", newline="", encoding="utf-8") as f:
        source = list(csv.DictReader(f))
    table = str.maketrans("", "", string.punctuation)
    return [(row["text"].lower().translate(table), int(row["label"])) for row in source]


def extract_components(saved):
    vectorizer = None
    classifier = None

    if isinstance(saved, Pipeline):
        for component in saved.named_steps.values():
            if isinstance(component, TfidfVectorizer):
                vectorizer = component
            if isinstance(component, LogisticRegression):
                classifier = component
    elif isinstance(saved, LogisticRegression):
        classifier = saved
    elif isinstance(saved, dict):
        for component in saved.values():
            if isinstance(component, TfidfVectorizer):
                vectorizer = component
            if isinstance(component, LogisticRegression):
                classifier = component
    elif isinstance(saved, (tuple, list)):
        for component in saved:
            if isinstance(component, TfidfVectorizer):
                vectorizer = component
            if isinstance(component, LogisticRegression):
                classifier = component

    return vectorizer, classifier


def test_pipeline_execution_and_artifacts():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    exp_csv_path = "/home/user/experiments.csv"
    before_lines = read_nonempty_lines(exp_csv_path)

    max_features = random.choice([6, 7, 8])
    c_value = random.choice([0.37, 0.61, 0.83])
    started = int(time.time())

    result = subprocess.run(
        [script_path, "--max_features", str(max_features), "--c_value", str(c_value)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    finished = int(time.time())
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )

    assert os.path.isfile(exp_csv_path), f"{exp_csv_path} was not created."
    lines = read_nonempty_lines(exp_csv_path)
    assert len(lines) >= 2, (
        f"{exp_csv_path} does not contain enough data (header + at least one row)."
    )
    assert lines[0] == "id,max_features,C,accuracy", (
        f"Header in {exp_csv_path} is incorrect. Got: {lines[0]}"
    )
    assert len(lines) == len(before_lines) + 1, "The test run must append exactly one experiment record."
    if before_lines:
        assert lines[:-1] == before_lines, "Existing experiment records were modified instead of preserved."

    last_row = lines[-1].split(",")
    assert len(last_row) == 4, (
        f"Expected 4 columns in the last row of {exp_csv_path}, got {len(last_row)}."
    )
    exp_id, logged_max_features, logged_c_value, accuracy_text = last_row
    assert logged_max_features == str(max_features), (
        f"Expected max_features to be {max_features}, got {logged_max_features}."
    )
    assert logged_c_value == str(c_value), f"Expected C to be {c_value}, got {logged_c_value}."

    try:
        logged_accuracy = float(accuracy_text)
    except ValueError:
        assert False, f"Expected accuracy to be a float, got '{accuracy_text}'."
    assert math.isfinite(logged_accuracy) and 0.0 <= logged_accuracy <= 1.0

    assert exp_id.isdigit(), f"Experiment ID must be a Unix timestamp, got {exp_id!r}."
    assert started - 2 <= int(exp_id) <= finished + 2, "Experiment ID is not the current Unix timestamp."

    artifact_dir = f"/home/user/artifacts/exp_{exp_id}"
    assert os.path.isdir(artifact_dir), f"Artifact directory {artifact_dir} does not exist."
    model_path = os.path.join(artifact_dir, "model.pkl")
    processed_path = os.path.join(artifact_dir, "processed.csv")
    assert os.path.isfile(model_path), f"model.pkl is missing in {artifact_dir}."
    assert os.path.isfile(processed_path), f"processed.csv is missing in {artifact_dir}."
    assert os.path.getsize(model_path) > 0, "model.pkl is empty."

    with open(processed_path, "r", encoding="utf-8") as f:
        processed_content = f.read()
    assert not any(c.isupper() for c in processed_content), (
        "processed.csv contains uppercase characters, which should have been lowercased."
    )
    for char in processed_content:
        if not (char.isalnum() or char in " \n\r,"):
            assert False, f"Found unexpected punctuation character '{char}' in processed.csv."

    with open(processed_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["text", "label"], "processed.csv must retain the text,label header."
        actual_rows = [(row["text"], int(row["label"])) for row in reader]
    expected_rows = expected_processed_rows()
    assert actual_rows == expected_rows, "processed.csv is not the correctly transformed dataset.csv."

    with open(model_path, "rb") as f:
        saved_model = pickle.load(f)
    vectorizer, classifier = extract_components(saved_model)
    assert classifier is not None, "model.pkl does not contain a LogisticRegression model."
    assert hasattr(classifier, "coef_") and hasattr(classifier, "classes_"), (
        "The LogisticRegression model in model.pkl is not fitted."
    )
    assert float(classifier.C) == c_value, f"The saved model used C={classifier.C}, expected {c_value}."
    assert classifier.random_state == 42, "LogisticRegression must use random_state=42."

    texts = [text for text, _ in expected_rows]
    labels = np.asarray([label for _, label in expected_rows])
    if vectorizer is None:
        vectorizer = TfidfVectorizer(max_features=max_features)
        features = vectorizer.fit_transform(texts)
        predictions = classifier.predict(features)
    else:
        assert vectorizer.max_features == max_features, (
            f"TfidfVectorizer used max_features={vectorizer.max_features}, expected {max_features}."
        )
        assert hasattr(vectorizer, "vocabulary_"), "The saved TfidfVectorizer is not fitted."
        if isinstance(saved_model, Pipeline):
            predictions = saved_model.predict(texts)
        else:
            predictions = classifier.predict(vectorizer.transform(texts))

    assert classifier.coef_.shape[1] <= max_features, "Model feature count exceeds max_features."
    recomputed_accuracy = float(np.mean(np.asarray(predictions) == labels))
    assert math.isclose(logged_accuracy, recomputed_accuracy, rel_tol=1e-9, abs_tol=1e-9), (
        f"Logged accuracy {logged_accuracy} does not match trained-model accuracy {recomputed_accuracy}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
