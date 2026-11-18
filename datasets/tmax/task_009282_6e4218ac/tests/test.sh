#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request

import numpy as np
import pandas as pd
import pytest

MLFLOW_URL = "http://127.0.0.1:5000"
EXPERIMENT_NAME = "Server_Failure_Predictor"
EXPECTED_PIPELINES = {"baseline", "interactions", "log_transform"}


def request_json(path, method="GET", payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"} if data is not None else {}
    req = urllib.request.Request(MLFLOW_URL + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=15) as response:
        assert response.status == 200
        body = response.read()
        return json.loads(body.decode("utf-8")) if body else {}


def get_experiment(required=True):
    query = urllib.parse.urlencode({"experiment_name": EXPERIMENT_NAME})
    try:
        return request_json("/api/2.0/mlflow/experiments/get-by-name?" + query).get("experiment")
    except urllib.error.HTTPError as exc:
        if not required and exc.code == 404:
            return None
        raise


def search_runs(experiment_id):
    runs = []
    token = None
    while True:
        payload = {
            "experiment_ids": [str(experiment_id)],
            "run_view_type": "ACTIVE_ONLY",
            "max_results": 1000,
        }
        if token:
            payload["page_token"] = token
        result = request_json("/api/2.0/mlflow/runs/search", "POST", payload)
        runs.extend(result.get("runs", []))
        token = result.get("next_page_token")
        if not token:
            return runs


def delete_existing_active_runs():
    experiment = get_experiment(required=False)
    if not experiment:
        return
    for run in search_runs(experiment["experiment_id"]):
        request_json(
            "/api/2.0/mlflow/runs/delete",
            "POST",
            {"run_id": run["info"]["run_id"]},
        )


def run_params(run):
    return {item["key"]: item["value"] for item in run.get("data", {}).get("params", [])}


def run_metrics(run):
    return {item["key"]: item["value"] for item in run.get("data", {}).get("metrics", [])}


@pytest.fixture(scope="module")
def verified_state():
    # Preserve the server requirement and make sure the submitted script is tested
    # against a clean set of active runs rather than trusting pre-created records.
    try:
        response = request_json("/api/2.0/mlflow/experiments/list")
        assert isinstance(response, dict)
    except (urllib.error.URLError, TimeoutError) as exc:
        pytest.fail(f"Could not connect to MLflow server at {MLFLOW_URL}: {exc}")

    script_path = "/home/user/experiment.py"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    assert not os.path.islink(script_path), f"File {script_path} must be a regular script."

    delete_existing_active_runs()

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    try:
        completed = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=240,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"experiment.py timed out: {exc}")
    assert completed.returncode == 0, "experiment.py failed:\n" + completed.stdout[-5000:]

    experiment = get_experiment(required=True)
    assert experiment and experiment.get("experiment_id") is not None, (
        "Experiment 'Server_Failure_Predictor' not found."
    )
    runs = search_runs(experiment["experiment_id"])
    return experiment, runs


def expected_results():
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import PolynomialFeatures

    frame = pd.read_csv("/home/user/telemetry.csv")
    assert {"cpu", "mem", "io", "failure"}.issubset(frame.columns)
    X = frame[["cpu", "mem", "io"]]
    y = frame["failure"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42
    )

    poly = PolynomialFeatures(degree=2, interaction_only=True, include_bias=False)
    transformed = {
        "baseline": (X_train, X_test),
        "interactions": (poly.fit_transform(X_train), poly.transform(X_test)),
        "log_transform": (np.log1p(X_train), np.log1p(X_test)),
    }

    result = {}
    for name, (train_features, test_features) in transformed.items():
        model = RandomForestClassifier(random_state=42)
        model.fit(train_features, y_train)
        predictions = model.predict(test_features)
        result[name] = {
            "test_features": test_features,
            "predictions": predictions,
            "accuracy": float(accuracy_score(y_test, predictions)),
            "feature_count": int(np.asarray(train_features).shape[1]),
        }
    return result


def test_mlflow_runs_logged_and_recomputed(verified_state):
    from sklearn.ensemble import RandomForestClassifier
    import mlflow
    import mlflow.sklearn

    _, runs = verified_state
    assert len(runs) >= 3, f"Expected at least 3 runs, found {len(runs)}."

    pipelines_found = set()
    runs_by_pipeline = {}
    for run in runs:
        params = run_params(run)
        metrics = run_metrics(run)
        run_id = run["info"]["run_id"]
        if "pipeline_name" in params:
            pipelines_found.add(params["pipeline_name"])
            if params["pipeline_name"] in EXPECTED_PIPELINES:
                runs_by_pipeline.setdefault(params["pipeline_name"], []).append(run)
        assert "accuracy" in metrics, f"Run {run_id} is missing the 'accuracy' metric."

    assert EXPECTED_PIPELINES.issubset(pipelines_found), (
        f"Missing pipelines in MLflow runs. Expected {EXPECTED_PIPELINES}, found {pipelines_found}."
    )
    # The submitted script was run after all old active runs were removed. It must
    # create one genuine run for each of the three requested pipelines.
    assert len(runs) == 3, f"experiment.py should create exactly 3 active runs, found {len(runs)}."
    assert all(len(runs_by_pipeline.get(name, [])) == 1 for name in EXPECTED_PIPELINES)

    expected = expected_results()
    mlflow.set_tracking_uri(MLFLOW_URL)
    client = mlflow.tracking.MlflowClient(tracking_uri=MLFLOW_URL)

    for pipeline_name in EXPECTED_PIPELINES:
        run = runs_by_pipeline[pipeline_name][0]
        run_id = run["info"]["run_id"]
        logged_accuracy = float(run_metrics(run)["accuracy"])
        assert abs(logged_accuracy - expected[pipeline_name]["accuracy"]) <= 1e-12, (
            f"Run {run_id} has incorrect accuracy for {pipeline_name}: "
            f"expected {expected[pipeline_name]['accuracy']}, got {logged_accuracy}."
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            try:
                artifact_path = client.download_artifacts(run_id, "rf_model", temp_dir)
            except Exception as exc:
                pytest.fail(f"Run {run_id} is missing a usable rf_model artifact: {exc}")
            assert os.path.exists(artifact_path), f"Run {run_id} is missing rf_model."
            assert os.path.isdir(artifact_path), f"Run {run_id} rf_model must be a logged model."
            assert os.path.isfile(os.path.join(artifact_path, "MLmodel")), (
                f"Run {run_id} rf_model is missing MLmodel metadata."
            )
            try:
                model = mlflow.sklearn.load_model(artifact_path)
            except Exception as exc:
                pytest.fail(f"Run {run_id} rf_model is not a loadable sklearn model: {exc}")

            assert isinstance(model, RandomForestClassifier), (
                f"Run {run_id} did not log a RandomForestClassifier."
            )
            assert model.random_state == 42, f"Run {run_id} model must use random_state=42."
            assert model.n_features_in_ == expected[pipeline_name]["feature_count"], (
                f"Run {run_id} model has the wrong feature shape for {pipeline_name}."
            )
            actual_predictions = model.predict(expected[pipeline_name]["test_features"])
            np.testing.assert_array_equal(
                actual_predictions,
                expected[pipeline_name]["predictions"],
                err_msg=f"Run {run_id} model does not reproduce the required {pipeline_name} pipeline",
            )


def test_best_run_json(verified_state):
    _, runs = verified_state
    json_path = "/home/user/best_run.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."
    try:
        with open(json_path, "r", encoding="utf-8") as handle:
            best_run_data = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f"File {json_path} is not valid JSON.")

    assert "best_run_id" in best_run_data, "Missing 'best_run_id' in JSON."
    assert "best_pipeline" in best_run_data, "Missing 'best_pipeline' in JSON."

    best_run = None
    best_accuracy = -1.0
    for run in runs:
        accuracy = run_metrics(run).get("accuracy", -1.0)
        if accuracy > best_accuracy:
            best_accuracy = accuracy
            best_run = run
    assert best_run is not None, "No runs with accuracy found."

    expected_run_id = best_run["info"]["run_id"]
    expected_pipeline = run_params(best_run).get("pipeline_name")
    assert best_run_data["best_run_id"] == expected_run_id, (
        f"Incorrect best_run_id in JSON. Expected {expected_run_id}, "
        f"got {best_run_data['best_run_id']}."
    )
    assert best_run_data["best_pipeline"] == expected_pipeline, (
        f"Incorrect best_pipeline in JSON. Expected {expected_pipeline}, "
        f"got {best_run_data['best_pipeline']}."
    )


def test_mlflow_server_still_running(verified_state):
    response = request_json("/api/2.0/mlflow/experiments/list")
    assert isinstance(response, dict)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
