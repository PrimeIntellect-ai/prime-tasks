#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import runpy
import shutil

import numpy as np
import pandas as pd
import pytest
from scipy import stats
from sklearn.decomposition import TruncatedSVD
from sklearn.ensemble import RandomForestClassifier
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.pipeline import Pipeline
import sklearn.model_selection as model_selection

WORKSPACE_DIR = "/home/user/workspace"
SCRIPT_PATH = os.path.join(WORKSPACE_DIR, "train_pipeline.py")
DATASET_PATH = os.path.join(WORKSPACE_DIR, "dataset.csv")
JSON_PATH = os.path.join(WORKSPACE_DIR, "ci_results.json")
MLRUNS_DIR = os.path.join(WORKSPACE_DIR, "mlruns")

TRACE = {
    "cv_calls": [],
    "splits": [],
    "fits": [],
    "scores": [],
    "interval_calls": [],
}
RUN_ERROR = None


def _indices(value):
    index = getattr(value, "index", None)
    if index is None:
        return None
    try:
        return tuple(int(i) for i in index.tolist())
    except Exception:
        return None


def _pipeline_description(estimator):
    if not isinstance(estimator, Pipeline):
        return None
    return tuple(type(step) for _, step in estimator.steps)


def _run_submission():
    global RUN_ERROR
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.path.isfile(DATASET_PATH), f"{DATASET_PATH} does not exist."

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    if os.path.exists(MLRUNS_DIR):
        shutil.rmtree(MLRUNS_DIR)

    os.environ["MLFLOW_TRACKING_URI"] = "file://" + MLRUNS_DIR

    original_cv_score = model_selection.cross_val_score
    original_cv_validate = model_selection.cross_validate
    original_split = model_selection.StratifiedKFold.split
    original_fit = Pipeline.fit
    original_score = Pipeline.score
    original_interval = stats.t.interval

    def traced_cv_score(estimator, X, y=None, *args, **kwargs):
        result = original_cv_score(estimator, X, y, *args, **kwargs)
        TRACE["cv_calls"].append({
            "kind": "cross_val_score",
            "pipeline": _pipeline_description(estimator),
            "scoring": kwargs.get("scoring"),
            "scores": np.asarray(result, dtype=float),
        })
        return result

    def traced_cv_validate(estimator, X, y=None, *args, **kwargs):
        result = original_cv_validate(estimator, X, y, *args, **kwargs)
        if "test_score" in result:
            TRACE["cv_calls"].append({
                "kind": "cross_validate",
                "pipeline": _pipeline_description(estimator),
                "scoring": kwargs.get("scoring"),
                "scores": np.asarray(result["test_score"], dtype=float),
            })
        return result

    def traced_split(self, X, y, groups=None):
        record = {
            "n_splits": self.n_splits,
            "shuffle": self.shuffle,
            "random_state": self.random_state,
            "x_indices": _indices(X),
            "y_indices": _indices(y),
            "folds": [],
        }
        TRACE["splits"].append(record)
        for train, test in original_split(self, X, y, groups):
            record["folds"].append((tuple(map(int, train)), tuple(map(int, test))))
            yield train, test

    def traced_fit(self, X, y=None, **params):
        TRACE["fits"].append({
            "steps": _pipeline_description(self),
            "indices": _indices(X),
        })
        return original_fit(self, X, y, **params)

    def traced_score(self, X, y=None, sample_weight=None):
        if sample_weight is None:
            value = original_score(self, X, y)
        else:
            value = original_score(self, X, y, sample_weight=sample_weight)
        TRACE["scores"].append({"indices": _indices(X), "value": float(value)})
        return value

    def traced_interval(*args, **kwargs):
        result = original_interval(*args, **kwargs)
        TRACE["interval_calls"].append((args, kwargs, result))
        return result

    model_selection.cross_val_score = traced_cv_score
    model_selection.cross_validate = traced_cv_validate
    model_selection.StratifiedKFold.split = traced_split
    Pipeline.fit = traced_fit
    Pipeline.score = traced_score
    stats.t.interval = traced_interval

    old_cwd = os.getcwd()
    try:
        os.chdir(WORKSPACE_DIR)
        runpy.run_path(SCRIPT_PATH, run_name="__main__")
    except BaseException as exc:
        RUN_ERROR = exc
    finally:
        os.chdir(old_cwd)
        model_selection.cross_val_score = original_cv_score
        model_selection.cross_validate = original_cv_validate
        model_selection.StratifiedKFold.split = original_split
        Pipeline.fit = original_fit
        Pipeline.score = original_score
        stats.t.interval = original_interval


_run_submission()


def _valid_split_record():
    df = pd.read_csv(DATASET_PATH)
    expected_indices = tuple(range(len(df)))
    for record in TRACE["splits"]:
        if (record["n_splits"] == 5 and record["shuffle"] is True
                and record["random_state"] == 42
                and record["x_indices"] == expected_indices
                and record["y_indices"] == expected_indices
                and len(record["folds"]) == 5):
            return record
    return None


def _observed_scores(split_record):
    for call in TRACE["cv_calls"]:
        if call["pipeline"] == (TfidfVectorizer, TruncatedSVD, RandomForestClassifier):
            scores = call["scores"]
            if len(scores) == 5:
                assert call["scoring"] in (None, "accuracy"), "Cross-validation must evaluate accuracy."
                return scores

    values = []
    for _, test_positions in split_record["folds"]:
        expected = tuple(test_positions)
        matches = [entry["value"] for entry in TRACE["scores"] if entry["indices"] == expected]
        if not matches:
            return None
        values.append(matches[-1])
    return np.asarray(values, dtype=float)


def _metric_value(path):
    with open(path, "r") as handle:
        lines = [line.strip() for line in handle if line.strip()]
    assert lines, f"MLflow metric file {path} is empty."
    parts = lines[-1].split()
    assert len(parts) >= 2, f"Invalid MLflow metric data in {path}."
    return float(parts[1])


def test_script_executes_and_uses_leak_free_cross_validation():
    assert RUN_ERROR is None, f"train_pipeline.py failed when executed: {RUN_ERROR!r}"

    split_record = _valid_split_record()
    assert split_record is not None, (
        "The executed script must use StratifiedKFold(n_splits=5, shuffle=True, random_state=42) "
        "on the complete dataset."
    )

    required_steps = (TfidfVectorizer, TruncatedSVD, RandomForestClassifier)
    expected_train_sets = {tuple(train) for train, _ in split_record["folds"]}
    fitted_train_sets = {
        entry["indices"] for entry in TRACE["fits"]
        if entry["steps"] == required_steps and entry["indices"] is not None
    }
    assert expected_train_sets.issubset(fitted_train_sets), (
        "Each fold must fit a Pipeline containing, in order, TfidfVectorizer, "
        "TruncatedSVD, and RandomForestClassifier on only that fold's training rows."
    )

    scores = _observed_scores(split_record)
    assert scores is not None and len(scores) == 5, "Could not observe five pipeline accuracy scores."
    assert np.all(np.isfinite(scores)), "Cross-validation scores must be finite."


def test_json_results_exist_and_format():
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} does not exist. Did you save the JSON file?"
    with open(JSON_PATH, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("ci_results.json is not a valid JSON file.")

    assert "ci_lower" in data, "JSON missing 'ci_lower' key."
    assert "ci_upper" in data, "JSON missing 'ci_upper' key."
    assert isinstance(data["ci_lower"], (int, float)), "'ci_lower' must be a number."
    assert isinstance(data["ci_upper"], (int, float)), "'ci_upper' must be a number."
    assert set(data) == {"ci_lower", "ci_upper"}, "ci_results.json must have exactly the required keys."

    split_record = _valid_split_record()
    scores = _observed_scores(split_record)
    expected_mean = float(np.mean(scores))
    expected_sem = float(stats.sem(scores))
    expected_lower, expected_upper = stats.t.interval(
        0.95, df=len(scores) - 1, loc=expected_mean, scale=expected_sem
    )
    assert data == {
        "ci_lower": round(float(expected_lower), 4),
        "ci_upper": round(float(expected_upper), 4),
    }, "JSON confidence bounds must be the executed fold scores' Student-t CI rounded to 4 decimals."

    assert TRACE["interval_calls"], "The script must calculate the confidence interval with scipy.stats.t.interval."
    matching_call = False
    for args, kwargs, _ in TRACE["interval_calls"]:
        confidence = kwargs.get("confidence", args[0] if args else None)
        df = kwargs.get("df", args[1] if len(args) > 1 else None)
        loc = kwargs.get("loc", args[2] if len(args) > 2 else None)
        scale = kwargs.get("scale", args[3] if len(args) > 3 else None)
        if (confidence is not None and math.isclose(float(confidence), 0.95)
                and df is not None and int(df) == 4
                and loc is not None and math.isclose(float(loc), expected_mean, abs_tol=1e-12)
                and scale is not None and math.isclose(float(scale), expected_sem, abs_tol=1e-12)):
            matching_call = True
            break
    assert matching_call, "t.interval must use confidence=0.95, df=4, the CV mean, and scipy.stats.sem(scores)."


def test_mlflow_experiment_exists():
    assert os.path.isdir(MLRUNS_DIR), "mlruns directory not found. Did you run MLflow tracking?"
    experiment_found = False
    for root, dirs, files in os.walk(MLRUNS_DIR):
        if "meta.yaml" in files:
            with open(os.path.join(root, "meta.yaml"), "r") as handle:
                if "name: text_classification_fixed" in handle.read():
                    experiment_found = True
                    break
    assert experiment_found, "Could not find MLflow experiment named 'text_classification_fixed' in mlruns."


def test_mlflow_metrics_logged_and_correct():
    exp_id = None
    for root, dirs, files in os.walk(MLRUNS_DIR):
        if "meta.yaml" in files:
            with open(os.path.join(root, "meta.yaml"), "r") as handle:
                if "name: text_classification_fixed" in handle.read():
                    exp_id = os.path.basename(root)
                    break
    if not exp_id:
        pytest.fail("Experiment 'text_classification_fixed' not found.")

    exp_dir = os.path.join(MLRUNS_DIR, exp_id)
    runs = [d for d in os.listdir(exp_dir) if os.path.isdir(os.path.join(exp_dir, d)) and d != "tags"]
    assert len(runs) > 0, "No runs found for the experiment 'text_classification_fixed'."

    valid_run = None
    for run in runs:
        metrics_dir = os.path.join(exp_dir, run, "metrics")
        if os.path.isdir(metrics_dir) and {"cv_mean", "ci_lower", "ci_upper"}.issubset(os.listdir(metrics_dir)):
            valid_run = metrics_dir
            break
    assert valid_run is not None, "A run must log cv_mean, ci_lower, and ci_upper metrics."

    split_record = _valid_split_record()
    scores = _observed_scores(split_record)
    mean = float(np.mean(scores))
    lower, upper = stats.t.interval(0.95, df=4, loc=mean, scale=stats.sem(scores))
    expected = {"cv_mean": mean, "ci_lower": float(lower), "ci_upper": float(upper)}
    for name, value in expected.items():
        actual = _metric_value(os.path.join(valid_run, name))
        assert math.isclose(actual, value, rel_tol=0, abs_tol=1e-10), (
            f"MLflow metric {name} does not match the value calculated from the executed CV scores."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
