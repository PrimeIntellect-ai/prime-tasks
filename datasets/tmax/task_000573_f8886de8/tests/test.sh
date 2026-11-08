#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy
import sys
import time
import secrets

import numpy as np
import pandas as pd
import pytest


def test_pipeline_end_to_end():
    script = "/home/user/run_pipeline.py"
    assert os.path.exists(script), f"Missing file: {script}"
    assert os.path.isfile(script), f"Not a regular file: {script}"
    with open(script, "rb") as f:
        compile(f.read(), script, "exec")

    feature_columns = [f"f{i}" for i in range(50)]
    train = pd.read_parquet("/home/user/train.parquet")
    test = pd.read_parquet("/home/user/test.parquet")
    expected_train_x = train[feature_columns].to_numpy()
    expected_train_y = train["label"].to_numpy()
    expected_test_x = test[feature_columns].to_numpy()
    expected_test_y = test["label"].to_numpy()

    outputs = [
        "/home/user/accuracy.txt",
        "/home/user/inference_time.txt",
        "/home/user/confusion_matrix.png",
    ]
    for path in outputs:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                pytest.fail(f"Output path is a directory: {path}")
            os.unlink(path)

    # Patch the actual sklearn class before executing the submitted artifact. This
    # records model configuration and calls while retaining sklearn's real behavior.
    import sklearn.ensemble
    original_rf = sklearn.ensemble.RandomForestClassifier
    audit = {"models": [], "test_predictions": [], "durations": []}
    injected_delay = 0.080 + secrets.randbelow(120001) / 1_000_000.0

    class AuditedRandomForest:
        def __init__(self, *args, **kwargs):
            self._model = original_rf(*args, **kwargs)
            self._random_state = self._model.get_params().get("random_state")
            self._fit_matches = False
            audit["models"].append(self)

        def fit(self, X, y, *args, **kwargs):
            xa = np.asarray(X)
            ya = np.asarray(y)
            self._fit_matches = (
                xa.shape == expected_train_x.shape
                and ya.shape == expected_train_y.shape
                and np.allclose(xa, expected_train_x)
                and np.array_equal(ya, expected_train_y)
            )
            self._model.fit(X, y, *args, **kwargs)
            return self

        def predict(self, X, *args, **kwargs):
            xa = np.asarray(X)
            is_full_test = (
                xa.shape == expected_test_x.shape
                and np.allclose(xa, expected_test_x)
            )
            start = time.perf_counter()
            result = self._model.predict(X, *args, **kwargs)
            if is_full_test:
                # A randomized CPU delay makes a prewritten timing value unable to
                # pass while remaining visible to both wall and process-time clocks.
                deadline = time.perf_counter() + injected_delay
                value = 0
                while time.perf_counter() < deadline:
                    value = (value * 33 + 17) & 0xFFFFFFFF
                duration = time.perf_counter() - start
                audit["durations"].append(duration)
                audit["test_predictions"].append(np.asarray(result).copy())
            return result

        def __getattr__(self, name):
            return getattr(self._model, name)

        def get_params(self, *args, **kwargs):
            return self._model.get_params(*args, **kwargs)

        def set_params(self, *args, **kwargs):
            self._model.set_params(*args, **kwargs)
            self._random_state = self._model.get_params().get("random_state")
            return self

        def score(self, *args, **kwargs):
            return self._model.score(*args, **kwargs)

    sklearn.ensemble.RandomForestClassifier = AuditedRandomForest

    # Capture the numerical data actually plotted when the requested PNG is saved.
    os.environ["MPLBACKEND"] = "Agg"
    import matplotlib
    matplotlib.use("Agg", force=True)
    import matplotlib.figure

    original_savefig = matplotlib.figure.Figure.savefig
    plot_audit = {"saved": False, "matrix": False}

    def audited_savefig(fig, fname, *args, **kwargs):
        if os.path.abspath(os.fspath(fname)) == "/home/user/confusion_matrix.png":
            plot_audit["saved"] = True
            if audit["test_predictions"]:
                pred = audit["test_predictions"][-1]
                labels = np.unique(np.concatenate([expected_test_y, pred]))
                cm = np.zeros((len(labels), len(labels)), dtype=float)
                index = {v: i for i, v in enumerate(labels.tolist())}
                for actual, guessed in zip(expected_test_y, pred):
                    cm[index[actual], index[guessed]] += 1
                candidates = [cm]
                row_sums = cm.sum(axis=1, keepdims=True)
                candidates.append(np.divide(cm, row_sums, out=np.zeros_like(cm), where=row_sums != 0))
                total = cm.sum()
                if total:
                    candidates.append(cm / total)
                for ax in fig.axes:
                    artists = list(ax.images) + list(ax.collections)
                    for artist in artists:
                        try:
                            arr = np.asarray(artist.get_array(), dtype=float)
                        except Exception:
                            continue
                        if arr.size == cm.size:
                            arr = arr.reshape(cm.shape)
                            if any(np.allclose(arr, candidate, rtol=1e-5, atol=1e-8) for candidate in candidates):
                                plot_audit["matrix"] = True
        return original_savefig(fig, fname, *args, **kwargs)

    matplotlib.figure.Figure.savefig = audited_savefig

    old_cwd = os.getcwd()
    old_argv = sys.argv[:]
    try:
        os.chdir("/home/user")
        sys.argv = [script]
        try:
            runpy.run_path(script, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"Pipeline exited unsuccessfully: {exc.code}"
    finally:
        os.chdir(old_cwd)
        sys.argv = old_argv
        sklearn.ensemble.RandomForestClassifier = original_rf
        matplotlib.figure.Figure.savefig = original_savefig

    valid_models = [m for m in audit["models"] if m._fit_matches]
    assert valid_models, "No RandomForestClassifier was fitted on the complete training dataset"
    assert any(m._random_state == 42 for m in valid_models), "RandomForestClassifier must use random_state=42"
    assert len(audit["test_predictions"]) >= 10, "predict was not run on the entire test set at least 10 times"

    float_pattern = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")

    # Preserve the original accuracy assertions and also derive the answer from the
    # predictions made by the submitted pipeline.
    accuracy_path = "/home/user/accuracy.txt"
    assert os.path.exists(accuracy_path), f"Missing file: {accuracy_path}"
    with open(accuracy_path, "r") as f:
        accuracy_content = f.read().strip()
    assert float_pattern.fullmatch(accuracy_content), "accuracy.txt must contain only one float"
    accuracy = float(accuracy_content)
    assert abs(accuracy - 0.923) < 0.01, f"Accuracy {accuracy} is not within 0.01 of expected 0.923"
    measured_accuracy = float(np.mean(audit["test_predictions"][-1] == expected_test_y))
    assert abs(accuracy - measured_accuracy) < 1e-12, (
        f"Reported accuracy {accuracy} does not match executed predictions {measured_accuracy}"
    )

    # Preserve positivity while checking that the value tracks an unpredictable,
    # actually measured set of full-test predictions.
    timing_path = "/home/user/inference_time.txt"
    assert os.path.exists(timing_path), f"Missing file: {timing_path}"
    with open(timing_path, "r") as f:
        timing_content = f.read().strip()
    assert float_pattern.fullmatch(timing_content), "inference_time.txt must contain only one float"
    inference_time = float(timing_content)
    assert inference_time > 0.0, f"Inference time must be strictly positive, got {inference_time}"
    observed_time = float(np.mean(audit["durations"][:10]))
    tolerance = max(0.015, observed_time * 0.15)
    assert abs(inference_time - observed_time) <= tolerance, (
        f"Reported inference time {inference_time} was not measured from the prediction runs "
        f"(observed approximately {observed_time})"
    )

    # Preserve the original file and size assertions, then decode the image and
    # require that the saved figure contained the computed confusion matrix.
    image_path = "/home/user/confusion_matrix.png"
    assert os.path.exists(image_path), f"Missing file: {image_path}"
    assert os.path.isfile(image_path), f"Not a file: {image_path}"
    size = os.path.getsize(image_path)
    assert size > 5000, f"Confusion matrix image is too small ({size} bytes). It might be blank or corrupted."

    import matplotlib.image as mpimg
    image = mpimg.imread(image_path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, "Invalid PNG dimensions"
    assert np.isfinite(image).all(), "PNG contains invalid pixel values"
    assert float(np.std(image)) > 1e-4, "Confusion matrix PNG appears blank"
    assert plot_audit["saved"], "The script did not save the requested confusion matrix figure"
    assert plot_audit["matrix"], "The saved plot does not contain the confusion matrix from test predictions"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
