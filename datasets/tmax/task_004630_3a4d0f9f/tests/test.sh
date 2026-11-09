#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import os
import re
import runpy
import subprocess

import numpy as np
import pytest
import sklearn.model_selection as model_selection
import sklearn.neighbors as neighbors
import sklearn.preprocessing as preprocessing
from sklearn.metrics import accuracy_score

FILE_PATH = "/home/user/experiment_fixed.py"


def test_experiment_fixed_script_exists():
    """Test that the corrected script was saved to the correct location."""
    assert os.path.isfile(FILE_PATH), f"The file {FILE_PATH} does not exist. Did you save the corrected script?"
    assert not os.path.islink(FILE_PATH), f"The file {FILE_PATH} must be a regular script, not a symbolic link."


def test_fixed_metric_file_exists_and_correct():
    """Test that the fixed_metric.txt file exists and contains the correct accuracy."""
    file_path = "/home/user/fixed_metric.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    # The expected output without data leakage is 0.5200
    assert content == "0.5200", f"Expected accuracy '0.5200', but found '{content}' in {file_path}."


def test_experiment_fixed_script_logic():
    """Test that the corrected script actually fixes the data leakage bug."""
    if not os.path.isfile(FILE_PATH):
        pytest.fail(f"Cannot check logic because {FILE_PATH} does not exist.")

    with open(FILE_PATH, "r") as f:
        content = f.read()

    # It should not do fit_transform on the whole X
    assert not re.search(r"scaler\.fit_transform\(\s*X\s*\)", content), "The script still fits the scaler on the entire dataset 'X'."

    # It should split X, not X_scaled
    assert re.search(r"train_test_split\(\s*X\s*,", content), "The script should split the original 'X', not the scaled version."

    # It should transform test data
    assert re.search(r"scaler\.transform\(", content), "The script does not appear to use scaler.transform() for the test set."


def test_experiment_fixed_script_execution():
    """Test that running the fixed script produces the correct output."""
    if not os.path.isfile(FILE_PATH):
        pytest.fail(f"Cannot execute {FILE_PATH} because it does not exist.")

    try:
        result = subprocess.run(
            ["python3", FILE_PATH],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        output = result.stdout.strip()
        assert output == "0.5200", f"Running the fixed script produced '{output}' instead of expected '0.5200'."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running {FILE_PATH} failed with error:\n{e.stderr}")


def _make_trial(seed):
    base_x = np.random.RandomState(seed).randn(200, 5)
    y = np.random.RandomState(seed + 1000).randint(0, 2, 200)
    final_x = base_x.copy()
    final_x[150:] += 50

    x_train, x_test, y_train, y_test = ORIGINAL_SPLIT(
        final_x, y, test_size=0.25, random_state=42, shuffle=False
    )
    scaler = ORIGINAL_SCALER()
    scaled_train = scaler.fit_transform(x_train)
    scaled_test = scaler.transform(x_test)
    model = ORIGINAL_KNN(n_neighbors=3)
    model.fit(scaled_train, y_train)
    expected = f"{accuracy_score(y_test, model.predict(scaled_test)):.4f}"
    return base_x, y, final_x, x_train, x_test, y_train, scaled_train, scaled_test, expected


ORIGINAL_SPLIT = model_selection.train_test_split
ORIGINAL_SCALER = preprocessing.StandardScaler
ORIGINAL_KNN = neighbors.KNeighborsClassifier


def _run_instrumented(trial):
    base_x, supplied_y, final_x, expected_train, expected_test, expected_y_train, expected_scaled_train, expected_scaled_test, expected_output = trial
    events = {
        "randn": 0,
        "randint": 0,
        "splits": [],
        "scalers": [],
        "models": [],
    }

    original_seed = np.random.seed
    original_randn = np.random.randn
    original_randint = np.random.randint

    def fake_seed(*args, **kwargs):
        return None

    def fake_randn(*shape):
        events["randn"] += 1
        assert tuple(shape) == (200, 5), f"The script requested an unexpected feature shape: {shape}"
        return base_x.copy()

    def fake_randint(*args, **kwargs):
        events["randint"] += 1
        return supplied_y.copy()

    def tracked_split(x, y, *args, **kwargs):
        events["splits"].append((np.asarray(x).copy(), np.asarray(y).copy(), args, dict(kwargs)))
        return ORIGINAL_SPLIT(x, y, *args, **kwargs)

    class TrackedScaler:
        def __init__(self, *args, **kwargs):
            self.delegate = ORIGINAL_SCALER(*args, **kwargs)
            self.fit_inputs = []
            self.transform_inputs = []
            self.transform_outputs = []
            events["scalers"].append(self)

        def fit(self, x, y=None, **kwargs):
            self.fit_inputs.append(np.asarray(x).copy())
            self.delegate.fit(x, y, **kwargs)
            return self

        def fit_transform(self, x, y=None, **kwargs):
            self.fit_inputs.append(np.asarray(x).copy())
            self.transform_inputs.append(np.asarray(x).copy())
            result = self.delegate.fit_transform(x, y, **kwargs)
            self.transform_outputs.append(np.asarray(result).copy())
            return result

        def transform(self, x, **kwargs):
            self.transform_inputs.append(np.asarray(x).copy())
            result = self.delegate.transform(x, **kwargs)
            self.transform_outputs.append(np.asarray(result).copy())
            return result

        def __getattr__(self, name):
            return getattr(self.delegate, name)

    class TrackedKNN:
        def __init__(self, *args, **kwargs):
            self.delegate = ORIGINAL_KNN(*args, **kwargs)
            self.fit_calls = []
            self.predict_calls = []
            events["models"].append(self)

        def fit(self, x, y):
            self.fit_calls.append((np.asarray(x).copy(), np.asarray(y).copy()))
            self.delegate.fit(x, y)
            return self

        def predict(self, x):
            self.predict_calls.append(np.asarray(x).copy())
            return self.delegate.predict(x)

        def __getattr__(self, name):
            return getattr(self.delegate, name)

    np.random.seed = fake_seed
    np.random.randn = fake_randn
    np.random.randint = fake_randint
    model_selection.train_test_split = tracked_split
    preprocessing.StandardScaler = TrackedScaler
    neighbors.KNeighborsClassifier = TrackedKNN

    stdout = io.StringIO()
    try:
        with contextlib.redirect_stdout(stdout):
            runpy.run_path(FILE_PATH, run_name="__main__")
    finally:
        np.random.seed = original_seed
        np.random.randn = original_randn
        np.random.randint = original_randint
        model_selection.train_test_split = ORIGINAL_SPLIT
        preprocessing.StandardScaler = ORIGINAL_SCALER
        neighbors.KNeighborsClassifier = ORIGINAL_KNN

    assert events["randn"] == 1, "The script did not generate and use the experiment feature matrix."
    assert events["randint"] == 1, "The script did not generate and use the experiment labels."
    assert len(events["splits"]) == 1, "The original feature matrix must be split exactly once."
    split_x, split_y, split_args, split_kwargs = events["splits"][0]
    assert np.array_equal(split_x, final_x), "train_test_split was not called on the original, unscaled feature matrix."
    assert np.array_equal(split_y, supplied_y), "train_test_split was not called with the generated labels."
    assert split_kwargs.get("test_size") == 0.25
    assert split_kwargs.get("random_state") == 42
    assert split_kwargs.get("shuffle") is False

    assert len(events["scalers"]) == 1, "The experiment must use one StandardScaler fitted on the training data."
    scaler = events["scalers"][0]
    assert len(scaler.fit_inputs) == 1, "The scaler must be fitted exactly once."
    assert np.array_equal(scaler.fit_inputs[0], expected_train), "The scaler was not fitted exclusively on X_train."
    assert any(np.array_equal(x, expected_train) for x in scaler.transform_inputs), "X_train was not transformed by the training-fitted scaler."
    assert any(np.array_equal(x, expected_test) for x in scaler.transform_inputs), "X_test was not transformed by the training-fitted scaler."

    assert len(events["models"]) == 1, "The experiment must execute the k-nearest-neighbors classifier."
    model = events["models"][0]
    assert len(model.fit_calls) == 1 and len(model.predict_calls) == 1
    model_x, model_y = model.fit_calls[0]
    assert np.allclose(model_x, expected_scaled_train), "The classifier was not fitted on correctly scaled training features."
    assert np.array_equal(model_y, expected_y_train), "The classifier was not fitted on the training labels."
    assert np.allclose(model.predict_calls[0], expected_scaled_test), "Prediction did not use correctly transformed test features."
    assert stdout.getvalue().strip() == expected_output, (
        f"For verifier-supplied data, the script printed {stdout.getvalue().strip()!r}; expected {expected_output!r}."
    )


def test_pipeline_behavior_on_verifier_supplied_data():
    """Execute the submitted pipeline on multiple hidden inputs and verify its data flow and derived answers."""
    trials = []
    outputs = set()
    for seed in range(1, 100):
        trial = _make_trial(seed)
        trials.append(trial)
        outputs.add(trial[-1])
        if len(outputs) >= 2 and any(output != "0.5200" for output in outputs):
            break

    assert len(outputs) >= 2, "Internal verifier trials did not produce distinct expected metrics."
    for trial in trials[-2:]:
        _run_instrumented(trial)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
