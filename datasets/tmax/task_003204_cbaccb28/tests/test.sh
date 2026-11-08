#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.base import BaseEstimator
from sklearn.feature_selection import SelectKBest
from sklearn.metrics import accuracy_score
from sklearn.pipeline import Pipeline
from sklearn.utils.validation import check_is_fitted

DATASET_PATH = "/home/user/dataset.csv"
SCRIPT_PATH = "/home/user/train.py"
MODEL_PATH = "/home/user/model.joblib"
EXPECTED_COLUMNS = [f"feature_{i}" for i in range(20)] + ["target"]


def _scope_nodes(scope):
    nodes = []

    class Visitor(ast.NodeVisitor):
        def visit_FunctionDef(self, node):
            if node is scope:
                for stmt in node.body:
                    self.visit(stmt)

        def visit_AsyncFunctionDef(self, node):
            if node is scope:
                for stmt in node.body:
                    self.visit(stmt)

        def visit_ClassDef(self, node):
            return

        def visit_Lambda(self, node):
            return

        def generic_visit(self, node):
            nodes.append(node)
            super().generic_visit(node)

    visitor = Visitor()
    if isinstance(scope, ast.Module):
        for stmt in scope.body:
            if not isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                visitor.visit(stmt)
    else:
        visitor.visit(scope)
    return nodes


def _call_name(call):
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return ""


def _assigned_names(target):
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, (ast.Tuple, ast.List)):
        result = []
        for item in target.elts:
            result.extend(_assigned_names(item))
        return result
    return []


def _validate_training_source(source):
    assert source.strip(), "The training script is empty."
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"The training script is not valid Python: {exc}")

    assert DATASET_PATH in source, "train.py must read /home/user/dataset.csv."
    all_calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    assert any(_call_name(c) == "read_csv" for c in all_calls), "train.py must read the CSV dataset."

    correlation_strategy = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and node.id in {"f_classif", "r_regression"}:
            correlation_strategy = True
        if isinstance(node, ast.Attribute) and node.attr in {"corr", "corrwith", "corrcoef"}:
            correlation_strategy = True
    assert correlation_strategy, "train.py must implement correlation-based feature selection."

    scopes = [tree] + [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    valid_scope = False
    leakage_messages = []

    for scope in scopes:
        nodes = _scope_nodes(scope)
        calls = [n for n in nodes if isinstance(n, ast.Call)]
        split_calls = [c for c in calls if _call_name(c) == "train_test_split"]
        if not split_calls:
            continue

        split = min(split_calls, key=lambda n: n.lineno)
        split_line = split.lineno
        train_feature_names = set()

        for node in nodes:
            if not isinstance(node, (ast.Assign, ast.AnnAssign)):
                continue
            value = node.value
            if value is None or split not in ast.walk(value):
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            names = []
            for target in targets:
                names.extend(_assigned_names(target))
            if len(names) >= 4:
                train_feature_names.add(names[0])

        unsafe = []
        for call in calls:
            name = _call_name(call)
            if call.lineno < split_line and name in {"fit", "fit_transform", "corr", "corrwith", "corrcoef"}:
                unsafe.append((call.lineno, name))
        if unsafe:
            leakage_messages.append(str(unsafe))
            continue

        proper_fit = False
        for call in calls:
            if call.lineno <= split_line or _call_name(call) != "fit" or not call.args:
                continue
            first_arg = call.args[0]
            if isinstance(first_arg, ast.Name) and first_arg.id in train_feature_names:
                proper_fit = True
                break

        if proper_fit:
            valid_scope = True
            break

    assert valid_scope, (
        "train.py must split the raw data before fitting and fit the pipeline on the training partition; "
        f"possible preprocessing before the split: {leakage_messages}"
    )


def _validate_dataset():
    assert os.path.exists(DATASET_PATH), f"The dataset {DATASET_PATH} does not exist."
    assert os.path.isfile(DATASET_PATH), f"The path {DATASET_PATH} is not a file."

    try:
        df = pd.read_csv(DATASET_PATH)
    except Exception as exc:
        pytest.fail(f"Failed to read the training dataset: {exc}")

    assert df.shape == (10000, 21), "dataset.csv must contain exactly 10,000 samples and 21 columns."
    assert list(df.columns) == EXPECTED_COLUMNS, "dataset.csv has incorrect columns or column order."
    assert not df.isna().any().any(), "dataset.csv contains missing values."
    assert set(df["target"].unique()) == {0, 1}, "target must contain both binary classes 0 and 1."

    features = df[EXPECTED_COLUMNS[:-1]]
    assert all(pd.api.types.is_numeric_dtype(features[c]) for c in features), "All features must be numeric."
    values = features.to_numpy(dtype=float)
    assert np.isfinite(values).all(), "Features must all be finite."

    y = df["target"].to_numpy()
    informative = values[:, :5]
    noise = values[:, 5:]
    assert np.all((noise >= -0.0001) & (noise <= 10.0001)), "dataset.csv does not match generator output."
    assert np.all((informative[y == 0] >= -3.0001) & (informative[y == 0] <= 7.0001)), "dataset.csv does not match generator output."
    assert np.all((informative[y == 1] >= 2.9999) & (informative[y == 1] <= 13.0001)), "dataset.csv does not match generator output."
    assert np.allclose(values * 10000, np.round(values * 10000), atol=1e-5), "Generator values must have four-decimal precision."
    return df


def _run_training_script():
    assert os.path.exists(SCRIPT_PATH), f"The training script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()
    _validate_training_source(source)

    if os.path.lexists(MODEL_PATH):
        os.remove(MODEL_PATH)

    user = pwd.getpwnam("user")

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=300,
            preexec_fn=demote,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("train.py did not finish within 300 seconds.")
    assert result.returncode == 0, f"train.py failed:\n{result.stdout[-4000:]}"
    assert os.path.exists(MODEL_PATH), f"The model file {MODEL_PATH} does not exist."
    assert os.path.isfile(MODEL_PATH), f"The path {MODEL_PATH} is not a file."


def _walk_estimators(value, seen=None):
    if seen is None:
        seen = set()
    if id(value) in seen:
        return []
    seen.add(id(value))

    found = []
    if isinstance(value, BaseEstimator):
        found.append(value)
        try:
            params = value.get_params(deep=False).values()
        except Exception:
            params = []
        for param in params:
            found.extend(_walk_estimators(param, seen))
    elif isinstance(value, (list, tuple)):
        for item in value:
            if isinstance(item, tuple) and len(item) >= 2:
                found.extend(_walk_estimators(item[1], seen))
            else:
                found.extend(_walk_estimators(item, seen))
    elif isinstance(value, dict):
        for item in value.values():
            found.extend(_walk_estimators(item, seen))
    return found


def _as_array(value):
    if hasattr(value, "toarray"):
        value = value.toarray()
    if isinstance(value, (pd.DataFrame, pd.Series)):
        value = value.to_numpy()
    return np.asarray(value)


def test_training_workflow_and_artifacts():
    _validate_dataset()
    _run_training_script()


def test_pipeline_structure_and_selection():
    df = pd.read_csv(DATASET_PATH)
    try:
        model = joblib.load(MODEL_PATH)
    except Exception as exc:
        pytest.fail(f"Failed to load model from {MODEL_PATH}: {exc}")

    assert isinstance(model, Pipeline), "model.joblib must contain a fitted scikit-learn Pipeline."
    assert len(model.steps) >= 3, "The pipeline must include preprocessing, feature selection, and a classifier."

    preprocessing = model[:-1]
    estimators = _walk_estimators(preprocessing)
    scaler_names = {
        "standardscaler", "minmaxscaler", "maxabsscaler", "robustscaler",
        "normalizer", "powertransformer", "quantiletransformer"
    }
    scalers = [e for e in estimators if e.__class__.__name__.lower() in scaler_names or "scaler" in e.__class__.__name__.lower()]
    assert scalers, "The preprocessing portion of the pipeline must contain feature scaling."
    for scaler in scalers:
        check_is_fitted(scaler)

    selectors = []
    for estimator in estimators:
        cls_name = estimator.__class__.__name__.lower()
        if isinstance(estimator, SelectKBest):
            score_name = getattr(getattr(estimator, "score_func", None), "__name__", "")
            if score_name in {"f_classif", "r_regression"}:
                selectors.append(estimator)
        elif "corr" in cls_name or "correlation" in cls_name:
            selectors.append(estimator)
    assert selectors, "The pipeline must contain a fitted correlation-based feature selector."
    for selector in selectors:
        check_is_fitted(selector)
        if hasattr(selector, "k"):
            assert selector.k == 5, "The correlation selector must keep exactly 5 features."

    X = df.drop(columns=["target"])
    transformed = _as_array(preprocessing.transform(X.iloc[:64]))
    assert transformed.ndim == 2 and transformed.shape[1] == 5, "Pipeline preprocessing must output exactly 5 selected features."

    baseline_X = X.iloc[:64].copy()
    baseline = _as_array(preprocessing.transform(baseline_X))
    dependencies = []
    for column in X.columns:
        changed_X = baseline_X.copy()
        changed_X[column] = changed_X[column].to_numpy()[::-1]
        changed = _as_array(preprocessing.transform(changed_X))
        if not np.allclose(changed, baseline, rtol=1e-8, atol=1e-10):
            dependencies.append(column)

    correlations = X.corrwith(df["target"]).abs().sort_values(ascending=False)
    expected = set(correlations.head(5).index)
    assert set(dependencies) == expected, (
        f"The fitted preprocessing must select the five most target-correlated training features; "
        f"expected {sorted(expected)}, observed {sorted(dependencies)}"
    )


def test_model_accuracy():
    """Verify that the saved model achieves at least 0.80 accuracy on a holdout set."""
    assert os.path.exists(MODEL_PATH), f"The model file {MODEL_PATH} does not exist."
    assert os.path.isfile(MODEL_PATH), f"The path {MODEL_PATH} is not a file."

    test_data_path = "/tmp/test_data.csv"
    generator_path = "/app/data_generator"
    try:
        with open(test_data_path, "w") as handle:
            subprocess.run([generator_path, "5000"], stdout=handle, check=True)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to generate test data using {generator_path}: {exc}")
    except Exception as exc:
        pytest.fail(f"Unexpected error generating test data: {exc}")

    assert os.path.exists(test_data_path), "Test data was not generated."
    try:
        df = pd.read_csv(test_data_path)
    except Exception as exc:
        pytest.fail(f"Failed to read generated test data: {exc}")
    assert "target" in df.columns, "Generated data is missing the 'target' column."

    X_test = df.drop(columns=["target"])
    y_test = df["target"]
    try:
        model = joblib.load(MODEL_PATH)
    except Exception as exc:
        pytest.fail(f"Failed to load model from {MODEL_PATH}: {exc}")
    try:
        preds = model.predict(X_test)
    except Exception as exc:
        pytest.fail(f"Model prediction failed: {exc}")

    acc = accuracy_score(y_test, preds)
    assert acc >= 0.80, f"Model accuracy {acc:.4f} is below the required threshold of 0.80"


def test_train_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The training script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."


def test_dataset_exists():
    assert os.path.exists(DATASET_PATH), f"The dataset {DATASET_PATH} does not exist."
    assert os.path.isfile(DATASET_PATH), f"The path {DATASET_PATH} is not a file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
