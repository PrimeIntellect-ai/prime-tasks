#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import inspect
import json
import math
import os
import runpy
import secrets
import subprocess

import numpy as np
import sklearn.datasets as datasets
import sklearn.model_selection as model_selection
import sklearn.preprocessing as preprocessing
import sklearn.decomposition as decomposition
import sklearn.linear_model as linear_model
from sklearn.metrics import accuracy_score, roc_auc_score

PIPELINE = "/home/user/model_pipeline.py"
RESULTS = "/home/user/results.json"

OrigMakeClassification = datasets.make_classification
OrigTrainTestSplit = model_selection.train_test_split
OrigStandardScaler = preprocessing.StandardScaler
OrigPCA = decomposition.PCA
OrigLogisticRegression = linear_model.LogisticRegression


def read_results():
    assert os.path.exists(RESULTS), f"File {RESULTS} does not exist. The script must create this file."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a file."
    try:
        with open(RESULTS, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{RESULTS} is not a valid JSON file.") from exc

    assert isinstance(results, dict), "results.json must contain a JSON object."
    assert "accuracy" in results, "Key 'accuracy' is missing from results.json."
    assert "roc_auc" in results, "Key 'roc_auc' is missing from results.json."
    assert set(results) == {"accuracy", "roc_auc"}, "results.json must have exactly the required keys."

    acc = results["accuracy"]
    roc = results["roc_auc"]
    assert isinstance(acc, (int, float)), "'accuracy' must be a float."
    assert isinstance(roc, (int, float)), "'roc_auc' must be a float."
    assert not isinstance(acc, bool) and math.isfinite(acc), "'accuracy' must be a finite number."
    assert not isinstance(roc, bool) and math.isfinite(roc), "'roc_auc' must be a finite number."
    return results


def run_normally_and_check_fixed_result():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        ["python3", PIPELINE], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert completed.returncode == 0, (
        f"model_pipeline.py failed when executed:\n{completed.stdout}\n{completed.stderr}"
    )
    results = read_results()
    expected_acc = 0.805
    expected_roc = 0.90225135
    assert math.isclose(results["accuracy"], expected_acc, rel_tol=1e-3, abs_tol=1e-3), (
        f"Expected accuracy to be close to {expected_acc}, but got {results['accuracy']}. "
        "Did you fix the data leakage correctly?"
    )
    assert math.isclose(results["roc_auc"], expected_roc, rel_tol=1e-3, abs_tol=1e-4), (
        f"Expected roc_auc to be close to {expected_roc}, but got {results['roc_auc']}. "
        "Did you fix the data leakage correctly?"
    )


def bound_arguments(function, *args, **kwargs):
    bound = inspect.signature(function).bind(*args, **kwargs)
    bound.apply_defaults()
    return bound.arguments


def check_source_assertions():
    assert os.path.exists(PIPELINE), f"File {PIPELINE} is missing."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a file."
    with open(PIPELINE, "r") as f:
        content = f.read()

    # Retain the original source assertions; runtime checks below ensure comments cannot satisfy them.
    assert "scaler.fit_transform(X_test)" not in content, (
        "Data leakage bug still exists: scaler.fit_transform() is called on X_test."
    )
    assert "pca.fit_transform(X_test_scaled)" not in content, (
        "Data leakage bug still exists: pca.fit_transform() is called on X_test_scaled."
    )
    assert "scaler.transform(X_test)" in content, (
        "Expected scaler.transform(X_test) to be used for the test set."
    )
    assert "pca.transform(X_test_scaled)" in content, (
        "Expected pca.transform(X_test_scaled) to be used for the test set."
    )


def dynamic_run(secret_seed):
    # The submitted script still requests the prescribed dataset, but receives a fresh
    # verifier-selected dataset. Thus hard-coded metrics cannot pass.
    X, y = OrigMakeClassification(
        n_samples=1000, n_features=20, n_informative=15,
        random_state=secret_seed
    )
    X_train, X_test, y_train, y_test = OrigTrainTestSplit(
        X, y, test_size=0.2, random_state=42
    )

    reference_scaler = OrigStandardScaler()
    X_train_scaled = reference_scaler.fit_transform(X_train)
    X_test_scaled = reference_scaler.transform(X_test)
    reference_pca = OrigPCA(n_components=10, random_state=42)
    X_train_pca = reference_pca.fit_transform(X_train_scaled)
    X_test_pca = reference_pca.transform(X_test_scaled)
    reference_clf = OrigLogisticRegression(random_state=42)
    reference_clf.fit(X_train_pca, y_train)
    expected_acc = accuracy_score(y_test, reference_clf.predict(X_test_pca))
    expected_roc = roc_auc_score(y_test, reference_clf.predict_proba(X_test_pca)[:, 1])

    records = {
        "make": 0, "split": 0, "scalers": [], "pcas": [], "classifiers": []
    }

    expected_make_args = bound_arguments(
        OrigMakeClassification,
        n_samples=1000, n_features=20, n_informative=15, random_state=42
    )

    def fake_make_classification(*args, **kwargs):
        actual = bound_arguments(OrigMakeClassification, *args, **kwargs)
        assert actual == expected_make_args, "Dataset parameters or random seed were changed."
        records["make"] += 1
        return X.copy(), y.copy()

    expected_split_options = bound_arguments(
        OrigTrainTestSplit, X, y, test_size=0.2, random_state=42
    )
    expected_split_options.pop("arrays")

    def fake_train_test_split(*arrays, **kwargs):
        actual = bound_arguments(OrigTrainTestSplit, *arrays, **kwargs)
        actual_arrays = actual.pop("arrays")
        assert len(actual_arrays) == 2, "The train/test split inputs were changed."
        assert np.array_equal(actual_arrays[0], X) and np.array_equal(actual_arrays[1], y), (
            "The generated data must be split without substitution."
        )
        assert actual == expected_split_options, "The train/test split ratio or random seed was changed."
        records["split"] += 1
        return OrigTrainTestSplit(*arrays, **kwargs)

    expected_scaler_args = bound_arguments(OrigStandardScaler)
    expected_pca_args = bound_arguments(OrigPCA, n_components=10, random_state=42)
    expected_lr_args = bound_arguments(OrigLogisticRegression, random_state=42)

    class TransformProxy:
        def __init__(self, inner, record):
            self.inner = inner
            self.record = record

        def fit(self, X_arg, *args, **kwargs):
            self.record["fits"].append(("fit", np.asarray(X_arg).shape[0]))
            self.inner.fit(X_arg, *args, **kwargs)
            return self

        def fit_transform(self, X_arg, *args, **kwargs):
            self.record["fits"].append(("fit_transform", np.asarray(X_arg).shape[0]))
            return self.inner.fit_transform(X_arg, *args, **kwargs)

        def transform(self, X_arg, *args, **kwargs):
            self.record["transforms"].append(np.asarray(X_arg).shape[0])
            return self.inner.transform(X_arg, *args, **kwargs)

        def __getattr__(self, name):
            return getattr(self.inner, name)

    class ClassifierProxy:
        def __init__(self, inner, record):
            self.inner = inner
            self.record = record

        def fit(self, X_arg, y_arg, *args, **kwargs):
            self.record["fits"].append(np.asarray(X_arg).shape[0])
            self.inner.fit(X_arg, y_arg, *args, **kwargs)
            return self

        def predict(self, X_arg, *args, **kwargs):
            self.record["predicts"].append(np.asarray(X_arg).shape[0])
            return self.inner.predict(X_arg, *args, **kwargs)

        def predict_proba(self, X_arg, *args, **kwargs):
            self.record["predict_probas"].append(np.asarray(X_arg).shape[0])
            return self.inner.predict_proba(X_arg, *args, **kwargs)

        def __getattr__(self, name):
            return getattr(self.inner, name)

    def fake_scaler(*args, **kwargs):
        assert bound_arguments(OrigStandardScaler, *args, **kwargs) == expected_scaler_args, (
            "StandardScaler hyperparameters were changed."
        )
        record = {"fits": [], "transforms": []}
        records["scalers"].append(record)
        return TransformProxy(OrigStandardScaler(*args, **kwargs), record)

    def fake_pca(*args, **kwargs):
        assert bound_arguments(OrigPCA, *args, **kwargs) == expected_pca_args, (
            "PCA hyperparameters or random seed were changed."
        )
        record = {"fits": [], "transforms": []}
        records["pcas"].append(record)
        return TransformProxy(OrigPCA(*args, **kwargs), record)

    def fake_logistic_regression(*args, **kwargs):
        assert bound_arguments(OrigLogisticRegression, *args, **kwargs) == expected_lr_args, (
            "LogisticRegression hyperparameters or random seed were changed."
        )
        record = {"fits": [], "predicts": [], "predict_probas": []}
        records["classifiers"].append(record)
        return ClassifierProxy(OrigLogisticRegression(*args, **kwargs), record)

    datasets.make_classification = fake_make_classification
    model_selection.train_test_split = fake_train_test_split
    preprocessing.StandardScaler = fake_scaler
    decomposition.PCA = fake_pca
    linear_model.LogisticRegression = fake_logistic_regression
    try:
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        runpy.run_path(PIPELINE, run_name="__main__")
    finally:
        datasets.make_classification = OrigMakeClassification
        model_selection.train_test_split = OrigTrainTestSplit
        preprocessing.StandardScaler = OrigStandardScaler
        decomposition.PCA = OrigPCA
        linear_model.LogisticRegression = OrigLogisticRegression

    assert records["make"] == 1 and records["split"] == 1, (
        "The submitted pipeline did not generate and split the prescribed data once."
    )
    assert len(records["scalers"]) == 1, "The pipeline must use one StandardScaler."
    assert len(records["pcas"]) == 1, "The pipeline must use one PCA transformer."
    assert len(records["classifiers"]) == 1, "The pipeline must use one LogisticRegression model."

    scaler_record = records["scalers"][0]
    pca_record = records["pcas"][0]
    classifier_record = records["classifiers"][0]

    assert scaler_record["fits"] and all(rows == 800 for _, rows in scaler_record["fits"]), (
        "StandardScaler must be fitted only on the 800-row training set."
    )
    assert 200 in scaler_record["transforms"], (
        "StandardScaler.transform must be applied to the 200-row test set."
    )
    assert pca_record["fits"] and all(rows == 800 for _, rows in pca_record["fits"]), (
        "PCA must be fitted only on the transformed training set."
    )
    assert 200 in pca_record["transforms"], (
        "PCA.transform must be applied to the transformed test set."
    )
    assert classifier_record["fits"] == [800], "The classifier must be fitted on the training set."
    assert 200 in classifier_record["predicts"] and 200 in classifier_record["predict_probas"], (
        "The classifier must evaluate the test set."
    )

    results = read_results()
    assert math.isclose(results["accuracy"], float(expected_acc), rel_tol=1e-12, abs_tol=1e-12), (
        f"Executed pipeline produced accuracy {results['accuracy']}, expected {expected_acc}."
    )
    assert math.isclose(results["roc_auc"], float(expected_roc), rel_tol=1e-12, abs_tol=1e-12), (
        f"Executed pipeline produced roc_auc {results['roc_auc']}, expected {expected_roc}."
    )


check_source_assertions()
run_normally_and_check_fixed_result()
for _ in range(2):
    dynamic_run(secrets.randbelow(2**31 - 1) + 1)
# Restore the required ordinary final artifact after dynamic verification.
run_normally_and_check_fixed_result()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
