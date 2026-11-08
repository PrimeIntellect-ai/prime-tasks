#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json

def test_artifacts_directory_exists():
    assert os.path.isdir("/home/user/artifacts"), "Artifacts directory does not exist at /home/user/artifacts"

def test_run_metrics_json_exists():
    assert os.path.isfile("/home/user/artifacts/run_metrics.json"), "run_metrics.json does not exist in /home/user/artifacts"

def test_run_metrics_json_content():
    json_path = "/home/user/artifacts/run_metrics.json"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not a valid JSON file"

    expected_keys = {"mean_accuracy", "ci_lower", "ci_upper"}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), f"JSON file is missing keys. Expected {expected_keys}, got {actual_keys}"
    assert actual_keys == expected_keys, f"JSON must contain exactly {expected_keys}, got {actual_keys}"

    mean_accuracy = data["mean_accuracy"]
    ci_lower = data["ci_lower"]
    ci_upper = data["ci_upper"]

    assert isinstance(mean_accuracy, (int, float)), "mean_accuracy must be a number"
    assert isinstance(ci_lower, (int, float)), "ci_lower must be a number"
    assert isinstance(ci_upper, (int, float)), "ci_upper must be a number"

    assert abs(mean_accuracy - 0.82992) < 1e-4, f"mean_accuracy {mean_accuracy} is incorrect. Expected ~0.82992"
    assert abs(ci_lower - 0.82424) < 1e-4, f"ci_lower {ci_lower} is incorrect. Expected ~0.82424"
    assert abs(ci_upper - 0.83512) < 1e-4, f"ci_upper {ci_upper} is incorrect. Expected ~0.83512"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_execution.py
import json
import os
import runpy

import numpy as np
import sklearn.model_selection
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

script = "/home/user/evaluate_model.py"
artifact = "/home/user/artifacts/run_metrics.json"
assert os.path.isfile(script), f"Missing required script: {script}"

# Fresh unpredictable scores prevent a script containing hardcoded metrics from passing.
rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
returned_scores = [rng.uniform(0.55, 0.95, size=5) for _ in range(50)]

# Sentinels let us reject scaling performed before cross-validation.
raw_X = rng.normal(size=(40, 7))
raw_y = np.array([0, 1] * 20)
calls = []

def fake_make_classification(*args, **kwargs):
    return raw_X.copy(), raw_y.copy()

def checked_cross_val_score(estimator, X, y, *args, **kwargs):
    index = len(calls)
    assert index < 50, "More than 50 cross-validation runs were performed"
    cv = kwargs.get("cv", args[0] if args else None)

    assert isinstance(estimator, Pipeline), "Cross-validation estimator must be an sklearn Pipeline"
    step_values = [step for _, step in estimator.steps]
    scaler_positions = [i for i, step in enumerate(step_values) if isinstance(step, StandardScaler)]
    assert scaler_positions, "Pipeline does not contain StandardScaler"
    assert isinstance(step_values[-1], LogisticRegression), "Pipeline must end with LogisticRegression"
    assert scaler_positions[0] < len(step_values) - 1, "StandardScaler must precede LogisticRegression"
    assert step_values[-1].random_state == 42, "LogisticRegression random_state must be 42"

    assert isinstance(cv, sklearn.model_selection.StratifiedKFold), "Each run must use StratifiedKFold"
    assert cv.n_splits == 5, "StratifiedKFold must use 5 splits"
    assert cv.shuffle is True, "StratifiedKFold must shuffle"
    assert cv.random_state == index, f"CV run {index} must use random_state={index}"

    assert np.array_equal(np.asarray(X), raw_X), "Data was transformed before cross-validation; scaling must occur inside the Pipeline"
    assert np.array_equal(np.asarray(y), raw_y), "Unexpected labels were passed to cross-validation"

    calls.append(index)
    return returned_scores[index].copy()

# Patch the imported sklearn symbols before run_path executes the submitted script.
import sklearn.datasets
sklearn.datasets.make_classification = fake_make_classification
sklearn.model_selection.cross_val_score = checked_cross_val_score

if os.path.exists(artifact):
    os.remove(artifact)
runpy.run_path(script, run_name="__main__")

assert calls == list(range(50)), f"Expected exactly 50 CV runs with seeds 0..49, got {calls}"
assert os.path.isfile(artifact), "Executing evaluate_model.py did not create run_metrics.json"
with open(artifact, "r") as f:
    data = json.load(f)
assert set(data) == {"mean_accuracy", "ci_lower", "ci_upper"}, "Metrics JSON must have exactly the required keys"

all_scores = np.concatenate(returned_scores)
assert all_scores.size == 250
expected_mean = float(np.mean(all_scores))
np.random.seed(42)
bootstrap_means = []
for _ in range(1000):
    sample = np.random.choice(all_scores, size=250, replace=True)
    bootstrap_means.append(np.mean(sample))
expected_lower, expected_upper = np.percentile(bootstrap_means, [2.5, 97.5])

for key, expected in (
    ("mean_accuracy", expected_mean),
    ("ci_lower", float(expected_lower)),
    ("ci_upper", float(expected_upper)),
):
    value = data[key]
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{key} must be numeric"
    assert abs(value - expected) < 1e-12, f"{key}={value} does not match the executed evaluation ({expected})"
DYNAMIC_EOF

rm -rf /home/user/artifacts
if timeout 180 python3 /home/user/evaluate_model.py \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short \
   && timeout 60 python3 /tmp/test_dynamic_execution.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
