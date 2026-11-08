#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_instrumented_pipeline.py
import inspect
import json
import math
import runpy

import pandas as pd
from sklearn.feature_extraction.text import CountVectorizer as RealCountVectorizer
from sklearn.metrics import accuracy_score as real_accuracy_score
from sklearn.model_selection import train_test_split as real_train_test_split
from sklearn.naive_bayes import MultinomialNB as RealMultinomialNB

SCRIPT = "/home/user/etl_pipeline.py"
RAW = "/home/user/raw_data.csv"
METRICS = "/home/user/metrics.json"

# Independently derive the required result before instrumenting the public APIs.
df = pd.read_csv(RAW)
clean = df.dropna(subset=["text", "label"])
X = RealCountVectorizer(lowercase=True, stop_words="english").fit_transform(clean["text"])
y = clean["label"]
X_train, X_test, y_train, y_test = real_train_test_split(
    X, y, test_size=0.3, random_state=42
)
model = RealMultinomialNB()
model.fit(X_train, y_train)
expected = float(real_accuracy_score(y_test, model.predict(X_test)))
default_nb_params = RealMultinomialNB().get_params()

events = {"vectorizer": [], "split": [], "nb": [], "accuracy": 0}

import sklearn.feature_extraction.text as text_module
import sklearn.metrics as metrics_module
import sklearn.model_selection as selection_module
import sklearn.naive_bayes as nb_module


def checked_vectorizer(*args, **kwargs):
    obj = RealCountVectorizer(*args, **kwargs)
    params = obj.get_params()
    events["vectorizer"].append(
        (params.get("lowercase"), params.get("stop_words"))
    )
    return obj


def checked_split(*args, **kwargs):
    bound = inspect.signature(real_train_test_split).bind_partial(*args, **kwargs)
    bound.apply_defaults()
    events["split"].append(
        (bound.arguments.get("test_size"), bound.arguments.get("random_state"))
    )
    return real_train_test_split(*args, **kwargs)


def checked_nb(*args, **kwargs):
    obj = RealMultinomialNB(*args, **kwargs)
    events["nb"].append(obj.get_params())
    return obj


def checked_accuracy(*args, **kwargs):
    events["accuracy"] += 1
    return real_accuracy_score(*args, **kwargs)


text_module.CountVectorizer = checked_vectorizer
selection_module.train_test_split = checked_split
nb_module.MultinomialNB = checked_nb
metrics_module.accuracy_score = checked_accuracy

runpy.run_path(SCRIPT, run_name="__main__")

assert (True, "english") in events["vectorizer"], (
    "The script did not use CountVectorizer with lowercase=True and "
    "stop_words='english'."
)
assert (0.3, 42) in events["split"], (
    "The script did not use train_test_split with test_size=0.3 and "
    "random_state=42."
)
assert any(params == default_nb_params for params in events["nb"]), (
    "The script did not construct MultinomialNB with default parameters."
)
assert events["accuracy"] > 0, "The script did not call accuracy_score."

with open(METRICS, "r") as f:
    reported = json.load(f)
assert isinstance(reported, dict) and set(reported) == {"accuracy"}, (
    "metrics.json must contain exactly the accuracy key."
)
assert isinstance(reported["accuracy"], float), (
    "metrics.json accuracy must be a float."
)
assert math.isclose(reported["accuracy"], expected, rel_tol=0.0, abs_tol=1e-12), (
    f"Reported accuracy {reported['accuracy']} does not equal the independently "
    f"computed accuracy {expected}."
)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import subprocess

import numpy as np
import pandas as pd
import pytest

SCRIPT = Path("/home/user/etl_pipeline.py")
RAW = Path("/home/user/raw_data.csv")
METRICS = Path("/home/user/metrics.json")
RUNNER = "/tmp/run_instrumented_pipeline.py"


def test_etl_pipeline_script_exists():
    """Test that the ETL pipeline script exists."""
    script_path = "/home/user/etl_pipeline.py"
    assert os.path.exists(script_path), f"The script {script_path} is missing."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."


def test_metrics_json_exists_and_format():
    """Test that metrics.json exists, is valid JSON, and contains the accuracy key."""
    metrics_path = "/home/user/metrics.json"
    assert os.path.exists(metrics_path), f"The file {metrics_path} is missing. Did the script run and produce it?"
    assert os.path.isfile(metrics_path), f"The path {metrics_path} is not a file."

    with open(metrics_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {metrics_path} does not contain valid JSON.")

    assert "accuracy" in data, f"The key 'accuracy' is missing from {metrics_path}."

    accuracy = data["accuracy"]
    assert isinstance(accuracy, (float, int)), f"The 'accuracy' value should be a number, got {type(accuracy).__name__}."
    assert 0.0 <= accuracy <= 1.0, f"The 'accuracy' value should be between 0.0 and 1.0, got {accuracy}."


def run_pipeline_with_checks():
    if METRICS.exists():
        METRICS.unlink()
    result = subprocess.run(
        ["python3", RUNNER],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        "The pipeline failed execution or did not implement the required steps.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert METRICS.is_file(), "Running the pipeline did not produce metrics.json."


def test_pipeline_executes_and_computes_original_data_accuracy():
    run_pipeline_with_checks()


def test_pipeline_generalizes_to_unseen_data():
    raw_backup = RAW.read_bytes()
    metrics_backup = METRICS.read_bytes() if METRICS.exists() else None
    vocabulary = np.array([
        "amber", "beacon", "cobalt", "delta", "ember", "forest",
        "galaxy", "harbor", "island", "jungle", "kernel", "lantern",
    ])

    try:
        # Two fresh datasets prevent a precomputed or constant metric from passing.
        for _ in range(2):
            rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
            labels = np.array(["spam"] * 25 + ["ham"] * 25)
            rng.shuffle(labels)
            texts = [
                " ".join(rng.choice(vocabulary, size=int(rng.integers(2, 7)), replace=True))
                for _ in range(50)
            ]
            frame = pd.DataFrame({
                "id": np.arange(1, 53),
                "text": texts + [None, "amber beacon"],
                "label": labels.tolist() + ["ham", None],
            })
            frame.to_csv(RAW, index=False)
            run_pipeline_with_checks()
    finally:
        RAW.write_bytes(raw_backup)
        if metrics_backup is None:
            if METRICS.exists():
                METRICS.unlink()
        else:
            METRICS.write_bytes(metrics_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
