#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /home/user/oob_accuracies.csv /home/user/experiment_results.json /tmp/pipeline_trace.json

cat <<'PY_EOF' > /tmp/run_instrumented.py
import json
import os
import runpy
import sys

import numpy as np
import pandas as pd
import scipy.sparse as sp
import sklearn.metrics
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

TRAIN = "/home/user/train_evaluate.py"
DATA = "/app/data/dataset.csv"
trace = {
    "token_inputs": [],
    "tfidf_documents": None,
    "fit_rows": [],
    "score_events": [],
    "accuracy_events": [],
}

if not os.path.isfile(TRAIN):
    raise AssertionError(f"Missing required Python script: {TRAIN}")

import fast_vocab
import fast_vocab.tokenizer as tokenizer_module
original_tokenize = tokenizer_module.tokenize

def traced_tokenize(text):
    trace["token_inputs"].append(str(text))
    return original_tokenize(text)

fast_vocab.tokenize = traced_tokenize
tokenizer_module.tokenize = traced_tokenize

full_matrix = {"value": None}
original_fit_transform = TfidfVectorizer.fit_transform

def traced_fit_transform(self, raw_documents, y=None):
    documents = list(raw_documents)
    trace["tfidf_documents"] = [str(x) for x in documents]
    result = original_fit_transform(self, documents, y)
    full_matrix["value"] = result.copy()
    return result

TfidfVectorizer.fit_transform = traced_fit_transform

original_fit = LogisticRegression.fit
original_score = LogisticRegression.score
original_predict = LogisticRegression.predict
prediction_subsets = {}

def row_key(row):
    if sp.issparse(row):
        row = row.tocsr()
        return (tuple(row.indices.tolist()), tuple(np.round(row.data, 12).tolist()))
    return tuple(np.round(np.asarray(row).ravel(), 12).tolist())

def subset_info(X):
    full = full_matrix["value"]
    if full is None or not hasattr(X, "shape") or len(X.shape) < 1:
        return {"valid": False, "size": -1, "indices": []}
    try:
        lookup = {row_key(full[i]): i for i in range(full.shape[0])}
        indices = []
        for i in range(X.shape[0]):
            key = row_key(X[i])
            if key not in lookup:
                return {"valid": False, "size": int(X.shape[0]), "indices": []}
            indices.append(int(lookup[key]))
        valid = 0 < len(indices) < full.shape[0] and len(indices) == len(set(indices))
        return {"valid": bool(valid), "size": len(indices), "indices": indices}
    except Exception:
        return {"valid": False, "size": -1, "indices": []}

def traced_fit(self, X, y, *args, **kwargs):
    trace["fit_rows"].append(int(X.shape[0]))
    return original_fit(self, X, y, *args, **kwargs)

def traced_predict(self, X, *args, **kwargs):
    result = original_predict(self, X, *args, **kwargs)
    prediction_subsets[id(result)] = subset_info(X)
    return result

def traced_score(self, X, y, *args, **kwargs):
    value = original_score(self, X, y, *args, **kwargs)
    event = subset_info(X)
    event["value"] = float(value)
    trace["score_events"].append(event)
    return value

LogisticRegression.fit = traced_fit
LogisticRegression.predict = traced_predict
LogisticRegression.score = traced_score

original_accuracy = sklearn.metrics.accuracy_score

def traced_accuracy(y_true, y_pred, *args, **kwargs):
    value = original_accuracy(y_true, y_pred, *args, **kwargs)
    info = prediction_subsets.get(id(y_pred))
    if info is not None:
        event = dict(info)
        event["value"] = float(value)
        trace["accuracy_events"].append(event)
    return value

sklearn.metrics.accuracy_score = traced_accuracy
try:
    import sklearn.metrics._classification as classification
    classification.accuracy_score = traced_accuracy
except Exception:
    pass

old_argv = sys.argv[:]
sys.argv = [TRAIN]
try:
    runpy.run_path(TRAIN, run_name="__main__")
finally:
    sys.argv = old_argv
    with open("/tmp/pipeline_trace.json", "w") as f:
        json.dump(trace, f)
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


def read_scores():
    path = "/home/user/oob_accuracies.csv"
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    return lines, [float(x) for x in lines]


def test_required_scripts_exist():
    for path in ["/home/user/train_evaluate.py", "/home/user/calculate_ci.R"]:
        assert os.path.isfile(path), f"Required script {path} is missing."
        assert os.path.getsize(path) > 0, f"Required script {path} is empty."


def test_fast_vocab_installed():
    """Check if the fast_vocab package was successfully installed and fixed."""
    try:
        import fast_vocab
        from fast_vocab.tokenizer import tokenize
    except ImportError as e:
        pytest.fail(f"Failed to import fast_vocab: {e}. The package was not installed correctly.")
    except SyntaxError as e:
        pytest.fail(f"SyntaxError when importing fast_vocab: {e}. The syntax error was not fixed.")

    try:
        result = tokenize("hello world")
        assert isinstance(result, str), "tokenize should return a string"
    except Exception as e:
        pytest.fail(f"fast_vocab.tokenize failed to execute: {e}")

    assert tokenize("Hello, WORLD! 123") == "hello world 123"
    assert tokenize("") == ""
    assert importlib.metadata.version("fast_vocab") == "1.2.3"

    setup_text = Path("/app/vendored/fast_vocab-1.2.3/setup.py").read_text()
    assert "fast_voab" not in setup_text, "The setup.py package-name typo was not fixed."


def test_pipeline_was_executed_with_required_components():
    with open("/tmp/pipeline_trace.json") as f:
        trace = json.load(f)

    frame = pd.read_csv("/app/data/dataset.csv")
    expected_inputs = frame["text"].astype(str).tolist()
    assert trace["token_inputs"] == expected_inputs, "Every dataset text must be tokenized with fast_vocab.tokenize."

    from fast_vocab import tokenize
    expected_documents = [tokenize(text) for text in expected_inputs]
    assert trace["tfidf_documents"] == expected_documents, "TF-IDF was not fit on the fast_vocab-tokenized texts."
    assert len(frame) in trace["fit_rows"], "LogisticRegression was not fit on the entire dataset."

    valid_scores = [e for e in trace["score_events"] if e.get("valid")]
    if len(valid_scores) < 200:
        valid_scores = [e for e in trace["accuracy_events"] if e.get("valid")]
    assert len(valid_scores) >= 200, "The trained model was not evaluated on 200 nonempty, duplicate-free OOB subsets."
    valid_scores = valid_scores[-200:]
    assert len({tuple(e["indices"]) for e in valid_scores}) > 1, "Bootstrap evaluation reused only one OOB subset."

    _, written = read_scores()
    observed = [float(e["value"]) for e in valid_scores]
    assert np.allclose(written, observed, rtol=0, atol=1e-12), "Saved scores do not match the model's 200 observed OOB evaluations."


def test_oob_accuracies_file():
    """Check if the OOB accuracies file exists and has 200 lines."""
    path = "/home/user/oob_accuracies.csv"
    assert os.path.isfile(path), f"File {path} is missing."
    lines, scores = read_scores()
    assert len(lines) == 200, f"Expected 200 OOB accuracy scores, found {len(lines)}."
    for line in lines:
        try:
            float(line)
        except ValueError:
            pytest.fail(f"Invalid float in {path}: {line}")
    assert all(math.isfinite(x) and 0.0 <= x <= 1.0 for x in scores), "OOB accuracies must be finite values in [0, 1]."


def test_experiment_results_json():
    """Check if the experiment results JSON exists and contains the required keys."""
    path = "/home/user/experiment_results.json"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Invalid JSON in {path}: {e}")

    required_keys = ["mean", "ci_lower", "ci_upper"]
    for key in required_keys:
        assert key in data, f"Key '{key}' is missing from {path}."
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"Value for '{key}' must be a number."
        assert math.isfinite(data[key]), f"Value for '{key}' must be finite."

    _, scores = read_scores()
    expected = {
        "mean": float(np.mean(scores)),
        "ci_lower": float(np.quantile(scores, 0.025, method="linear")),
        "ci_upper": float(np.quantile(scores, 0.975, method="linear")),
    }
    for key, value in expected.items():
        assert data[key] == pytest.approx(value, abs=1e-4), f"{key} was not computed from oob_accuracies.csv."


def test_metric_threshold():
    """Verify that the mean OOB accuracy is >= 0.70."""
    with open("/home/user/experiment_results.json") as f:
        data = json.load(f)
    mean_acc = data.get("mean", 0.0)
    assert mean_acc >= 0.70, f"Failed: Mean accuracy {mean_acc} is below 0.70 threshold."
TEST_EOF

if python3 /tmp/run_instrumented.py \
   && test -f /home/user/oob_accuracies.csv \
   && rm -f /home/user/experiment_results.json \
   && Rscript /home/user/calculate_ci.R \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
