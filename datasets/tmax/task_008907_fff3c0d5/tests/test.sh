#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import runpy
import shutil
import uuid

import numpy as np
import pandas as pd
import pytest
from sklearn.impute import SimpleImputer as OriginalImputer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.preprocessing import StandardScaler as OriginalScaler

APP_DIR = "/home/user/app"
RECOMMEND_SCRIPT = os.path.join(APP_DIR, "recommend.py")
RECOMMENDATIONS_FILE = os.path.join(APP_DIR, "recommendations.json")
EXPERIMENT_LOG_FILE = os.path.join(APP_DIR, "experiment_log.json")
TRACK_SCRIPT = os.path.join(APP_DIR, "track_experiment.sh")
FEATURES = ["feature_1", "feature_2", "feature_3"]


def test_recommendations_file_exists_and_correct():
    assert os.path.isfile(RECOMMENDATIONS_FILE), f"The file {RECOMMENDATIONS_FILE} was not generated."

    with open(RECOMMENDATIONS_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RECOMMENDATIONS_FILE} does not contain valid JSON.")

    expected_mapping = {
        "q1": "t1",
        "q2": "t3"
    }

    assert data == expected_mapping, f"The recommendations mapping is incorrect. Expected {expected_mapping}, but got {data}."


def test_experiment_log_exists_and_logged():
    assert os.path.isfile(EXPERIMENT_LOG_FILE), f"The file {EXPERIMENT_LOG_FILE} was not generated. Did you run track_experiment.sh?"

    with open(EXPERIMENT_LOG_FILE, "r") as f:
        content = f.read()

    assert '"q1"' in content and '"t1"' in content, "The experiment log does not seem to contain the expected 'q1' -> 't1' mapping."
    assert '"q2"' in content and '"t3"' in content, "The experiment log does not seem to contain the expected 'q2' -> 't3' mapping."

    assert os.path.isfile(TRACK_SCRIPT) and os.access(TRACK_SCRIPT, os.X_OK), "track_experiment.sh is missing or not executable."
    with open(RECOMMENDATIONS_FILE, "rb") as f:
        recommendation_bytes = f.read()
    with open(EXPERIMENT_LOG_FILE, "rb") as f:
        log_bytes = f.read()
    assert log_bytes.endswith(recommendation_bytes), "The experiment log does not end with the generated recommendations as track_experiment.sh would append them."
    assert os.stat(EXPERIMENT_LOG_FILE).st_mtime_ns >= os.stat(RECOMMENDATIONS_FILE).st_mtime_ns, "The experiment log was not updated after recommendations.json was generated."


def _same_array(actual, expected):
    try:
        return np.asarray(actual).shape == np.asarray(expected).shape and np.allclose(
            np.asarray(actual, dtype=float), np.asarray(expected, dtype=float), equal_nan=True
        )
    except (TypeError, ValueError):
        return False


def test_recommend_script_executes_pipeline_without_leakage_or_outlier(tmp_path, monkeypatch):
    assert os.path.isfile(RECOMMEND_SCRIPT), "recommend.py is missing."

    suffix = uuid.uuid4().hex
    train_ids = [f"train_{suffix}_{i}" for i in range(5)]
    query_ids = [f"query_{suffix}_{i}" for i in range(3)]

    train = pd.DataFrame({
        "id": train_ids,
        "feature_1": [0.0, 2.0, 4.0, 5000.0, np.nan],
        "feature_2": [0.0, np.nan, 5.0, -9000.0, 2.0],
        "feature_3": [np.nan, 3.0, 6.0, 10000.0, 4.0],
    })
    query = pd.DataFrame({
        "id": query_ids,
        "feature_1": [100.0, np.nan, -25.0],
        "feature_2": [-100.0, 3.0, np.nan],
        "feature_3": [np.nan, 4.5, 8.0],
    })

    filtered_train = train.loc[~(train["feature_1"] > 1000)].copy()
    expected_train_raw = filtered_train[FEATURES].to_numpy()
    expected_query_raw = query[FEATURES].to_numpy()

    reference_imputer = OriginalImputer(strategy="mean")
    expected_train_imputed = reference_imputer.fit_transform(expected_train_raw)
    expected_query_imputed = reference_imputer.transform(expected_query_raw)
    reference_scaler = OriginalScaler()
    expected_train_scaled = reference_scaler.fit_transform(expected_train_imputed)
    expected_query_scaled = reference_scaler.transform(expected_query_imputed)
    similarities = cosine_similarity(expected_query_scaled, expected_train_scaled)
    expected = {
        query_ids[i]: filtered_train.iloc[int(np.argmax(similarities[i]))]["id"]
        for i in range(len(query_ids))
    }

    class SpyImputer(OriginalImputer):
        fits = []
        transforms = []

        def fit(self, X, y=None):
            self.__class__.fits.append(np.asarray(X).copy())
            return super().fit(X, y)

        def transform(self, X):
            self.__class__.transforms.append(np.asarray(X).copy())
            return super().transform(X)

    class SpyScaler(OriginalScaler):
        fits = []
        transforms = []

        def fit(self, X, y=None, sample_weight=None):
            self.__class__.fits.append(np.asarray(X).copy())
            return super().fit(X, y, sample_weight=sample_weight)

        def transform(self, X, copy=None):
            self.__class__.transforms.append(np.asarray(X).copy())
            return super().transform(X, copy=copy)

    import sklearn.impute
    import sklearn.preprocessing
    monkeypatch.setattr(sklearn.impute, "SimpleImputer", SpyImputer)
    monkeypatch.setattr(sklearn.preprocessing, "StandardScaler", SpyScaler)

    shutil.copy2(RECOMMEND_SCRIPT, tmp_path / "recommend.py")
    train.to_csv(tmp_path / "train_data.csv", index=False)
    query.to_csv(tmp_path / "query_data.csv", index=False)
    monkeypatch.chdir(tmp_path)

    runpy.run_path(str(tmp_path / "recommend.py"), run_name="__main__")

    generated = tmp_path / "recommendations.json"
    assert generated.is_file(), "Executing recommend.py did not generate recommendations.json."
    with generated.open() as f:
        actual = json.load(f)
    assert actual == expected, f"recommend.py failed on independently generated input: expected {expected}, got {actual}."

    assert SpyImputer.fits, "recommend.py did not fit a SimpleImputer."
    assert all(_same_array(x, expected_train_raw) for x in SpyImputer.fits), "SimpleImputer was fit on data other than the outlier-filtered training features."
    assert any(_same_array(x, expected_query_raw) for x in SpyImputer.transforms), "The fitted training imputer was not used to transform the query features."

    assert SpyScaler.fits, "recommend.py did not fit a StandardScaler."
    assert all(_same_array(x, expected_train_imputed) for x in SpyScaler.fits), "StandardScaler was fit on data other than the imputed, outlier-filtered training features."
    assert any(_same_array(x, expected_query_imputed) for x in SpyScaler.transforms), "The fitted training scaler was not used to transform the imputed query features."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
