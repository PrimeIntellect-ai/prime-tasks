#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import runpy
import subprocess

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import sklearn.pipeline as pipeline_module

SCRIPT = "/home/user/build_recs.py"
DATA = "/home/user/item_features.csv"
CORR_OUT = "/home/user/test_corr_mean.txt"
RECS_OUT = "/home/user/recommendations.txt"


def test_00_execute_script():
    assert os.path.isfile(SCRIPT), f"Missing script: {SCRIPT}"
    for path in (CORR_OUT, RECS_OUT):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_test_corr_mean_file():
    """Test that the test_corr_mean.txt file exists and contains the correct value."""
    import math

    file_path = CORR_OUT
    assert os.path.exists(file_path), f"Missing output file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, f"File {file_path} is empty."

    try:
        val = float(content)
    except ValueError:
        raise AssertionError(f"Content of {file_path} is not a valid float: '{content}'")

    expected_val = 0.063063
    assert math.isclose(val, expected_val, abs_tol=1e-5), \
        f"Expected correlation mean to be close to {expected_val}, but got {val}"


def test_recommendations_file():
    """Test that the recommendations.txt file exists and contains the correct indices."""
    file_path = RECS_OUT
    assert os.path.exists(file_path), f"Missing output file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, f"File {file_path} is empty."

    expected_recs = "750,230,123"
    actual_recs = content.replace(" ", "")

    assert actual_recs == expected_recs, \
        f"Expected recommendations to be '{expected_recs}', but got '{content}'"


def test_script_uses_fitted_pipeline_and_generalizes():
    with open(DATA, "rb") as f:
        original_data = f.read()
    with open(CORR_OUT, "rb") as f:
        original_corr = f.read()
    with open(RECS_OUT, "rb") as f:
        original_recs = f.read()

    real_pipeline = pipeline_module.Pipeline

    class RecordingPipeline(real_pipeline):
        instances = []

        def __init__(self, steps, *, memory=None, verbose=False):
            super().__init__(steps, memory=memory, verbose=verbose)
            self.fit_inputs = []
            self.fit_transform_inputs = []
            self.transform_inputs = []
            RecordingPipeline.instances.append(self)

        def fit(self, X, y=None, **params):
            self.fit_inputs.append(np.asarray(X).copy())
            return super().fit(X, y, **params)

        def fit_transform(self, X, y=None, **params):
            self.fit_transform_inputs.append(np.asarray(X).copy())
            return super().fit_transform(X, y, **params)

        def transform(self, X, **params):
            self.transform_inputs.append(np.asarray(X).copy())
            return super().transform(X, **params)

    try:
        rng = np.random.RandomState(9173)
        values = rng.normal(size=(137, 11))
        values[:, 3] += 0.4 * values[:, 0]
        values[:, 7] -= 0.25 * values[:, 2]
        pd.DataFrame(values, columns=[f"feature_{i}" for i in range(11)]).to_csv(DATA, index=False)

        raw = pd.read_csv(DATA)
        expected_train, expected_test = train_test_split(
            raw, test_size=0.2, random_state=42, shuffle=True
        )
        reference = pipeline_module.Pipeline([
            ("scaler", StandardScaler()),
            ("pca", PCA(n_components=5, random_state=42)),
        ])
        transformed_train = reference.fit_transform(expected_train)
        transformed_test = reference.transform(expected_test)

        corr = np.corrcoef(transformed_test, rowvar=False)
        expected_corr = round(float(np.mean(np.abs(corr[np.tril_indices(5, k=-1)]))), 6)
        expected_recs = np.argsort(
            cosine_similarity(transformed_test[[0]], transformed_train)[0]
        )[::-1][:3]

        for path in (CORR_OUT, RECS_OUT):
            if os.path.exists(path):
                os.remove(path)

        pipeline_module.Pipeline = RecordingPipeline
        runpy.run_path(SCRIPT, run_name="__main__")

        assert os.path.exists(CORR_OUT), "Script did not create test_corr_mean.txt"
        assert os.path.exists(RECS_OUT), "Script did not create recommendations.txt"

        with open(CORR_OUT) as f:
            corr_text = f.read().strip()
        with open(RECS_OUT) as f:
            recs_text = f.read().strip().replace(" ", "")

        assert float(corr_text) == expected_corr, (
            f"On an independently generated dataset, expected correlation mean "
            f"{expected_corr:.6f}, got {corr_text}"
        )
        assert recs_text == ",".join(map(str, expected_recs)), (
            "Recommendations were not derived from the correctly fitted pipeline"
        )

        def same_array(actual, expected):
            return actual.shape == expected.shape and np.allclose(
                actual, np.asarray(expected), rtol=0, atol=1e-12
            )

        valid_instances = []
        for instance in RecordingPipeline.instances:
            steps = [step for _, step in instance.steps]
            if len(steps) != 2:
                continue
            if not isinstance(steps[0], StandardScaler) or not isinstance(steps[1], PCA):
                continue
            if steps[1].n_components != 5 or steps[1].random_state != 42:
                continue

            fitted_on_train = any(
                same_array(x, expected_train) for x in
                instance.fit_inputs + instance.fit_transform_inputs
            )
            transformed_train_ok = any(
                same_array(x, expected_train) for x in
                instance.transform_inputs + instance.fit_transform_inputs
            )
            transformed_test_ok = any(
                same_array(x, expected_test) for x in instance.transform_inputs
            )
            if fitted_on_train and transformed_train_ok and transformed_test_ok:
                valid_instances.append(instance)

        assert valid_instances, (
            "The script must use a Pipeline containing StandardScaler then PCA("
            "n_components=5, random_state=42), fit it only on the raw training split, "
            "and use it to transform both train and test splits"
        )
    finally:
        pipeline_module.Pipeline = real_pipeline
        with open(DATA, "wb") as f:
            f.write(original_data)
        with open(CORR_OUT, "wb") as f:
            f.write(original_corr)
        with open(RECS_OUT, "wb") as f:
            f.write(original_recs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
