#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import urllib.error
import urllib.parse
import urllib.request

import joblib
import numpy as np
import pandas as pd
import yaml
from sklearn.compose import TransformedTargetRegressor
from sklearn.decomposition import PCA
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.pipeline import Pipeline

MODEL_PATH = "/home/user/model.pkl"
COMPOSE_PATH = "/app/docker-compose.yml"
MLFLOW_URL = "http://localhost:5000"
EXPERIMENT_NAME = "Feature_Engineering_Exp"


def _environment(service):
    env = service.get("environment", {}) or {}
    if isinstance(env, dict):
        return {str(k): str(v) for k, v in env.items()}
    result = {}
    for item in env:
        key, sep, value = str(item).partition("=")
        result[key] = value if sep else ""
    return result


def _request_json(path, payload=None):
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(MLFLOW_URL + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as response:
        assert response.status == 200, f"MLflow API returned status {response.status}."
        return json.loads(response.read().decode("utf-8"))


def _load_model():
    assert os.path.isfile(MODEL_PATH), f"Model file {MODEL_PATH} was not created."
    try:
        return joblib.load(MODEL_PATH)
    except Exception as exc:
        assert False, f"Failed to load the model file at {MODEL_PATH}: {exc}"


def test_compose_configuration_is_corrected():
    assert os.path.isfile(COMPOSE_PATH), f"Compose file {COMPOSE_PATH} is missing."
    with open(COMPOSE_PATH, "r", encoding="utf-8") as handle:
        compose = yaml.safe_load(handle)

    services = compose.get("services", {})
    assert all(name in services for name in ("postgres", "minio", "mlflow")), \
        "The compose file must retain the postgres, minio, and mlflow services."

    mlflow = services["mlflow"]
    minio = services["minio"]
    mlflow_env = _environment(mlflow)
    minio_env = _environment(minio)
    command = mlflow.get("command", "")
    if isinstance(command, list):
        command = " ".join(str(part) for part in command)
    command = str(command)

    backend = mlflow_env.get("MLFLOW_BACKEND_STORE_URI", "")
    backend_configuration = backend + " " + command
    assert "postgresql://" in backend_configuration, "MLflow is not configured to use PostgreSQL."
    assert "@postgres:5432/" in backend_configuration, \
        "MLflow must connect to the postgres service on its container port 5432."
    assert "@postgres:5433/" not in backend_configuration, \
        "The incorrect postgres port 5433 is still configured."

    endpoint = mlflow_env.get("MLFLOW_S3_ENDPOINT_URL", "").rstrip("/")
    assert endpoint == "http://minio:9000", \
        "MLFLOW_S3_ENDPOINT_URL must point to http://minio:9000."

    minio_user = minio_env.get("MINIO_ROOT_USER")
    minio_password = minio_env.get("MINIO_ROOT_PASSWORD")
    assert minio_user and minio_password, "MinIO root credentials must be configured."
    assert minio_user != "wrong_user" and minio_password != "wrong_password", \
        "The placeholder MinIO credentials were not corrected."
    assert mlflow_env.get("AWS_ACCESS_KEY_ID") == minio_user, \
        "MLflow's S3 access key must match the MinIO root user."
    assert mlflow_env.get("AWS_SECRET_ACCESS_KEY") == minio_password, \
        "MLflow's S3 secret key must match the MinIO root password."
    assert "s3://" in command or mlflow_env.get("MLFLOW_DEFAULT_ARTIFACT_ROOT", "").startswith("s3://"), \
        "MLflow must use an S3/MinIO artifact root."


def test_model_exists():
    assert os.path.isfile(MODEL_PATH), f"Model file {MODEL_PATH} was not created."


def test_pipeline_structure_and_performance():
    pipeline = _load_model()
    assert type(pipeline) is Pipeline, "model.pkl must contain a scikit-learn Pipeline object."
    assert len(pipeline.steps) == 3, "The pipeline must contain exactly Imputer, PCA, and Ridge steps."

    imputer = pipeline.steps[0][1]
    pca = pipeline.steps[1][1]
    ridge = pipeline.steps[2][1]
    assert type(imputer) is SimpleImputer, "The first pipeline step must be SimpleImputer."
    assert imputer.strategy == "mean", "Missing values must be imputed using column means."
    assert type(pca) is PCA, "The second pipeline step must be PCA, with no scaler before it."
    assert pca.n_components == 10, "PCA must reduce the data to exactly 10 components."
    assert type(ridge) is Ridge, "The final pipeline step must be sklearn.linear_model.Ridge."
    assert float(ridge.alpha) == 1.0, "Ridge alpha must be 1.0."

    train_df = pd.read_csv("/home/user/train_data.csv")
    test_df = pd.read_csv("/app/test_data.csv")
    X_train = train_df.drop(columns=["target"])
    X_test = test_df.drop(columns=["target"])
    y_test = test_df["target"]

    try:
        predictions = pipeline.predict(X_test)
    except Exception as exc:
        assert False, f"Failed to generate predictions using the loaded pipeline: {exc}"

    predictions = np.asarray(predictions)
    assert predictions.shape == (len(X_test),), "The pipeline returned predictions with an invalid shape."
    assert np.isfinite(predictions).all(), "The pipeline returned non-finite predictions."
    score = r2_score(y_test, predictions)
    assert math.isfinite(score), "The pipeline produced a non-finite R2 score."

    reference = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("pca", PCA(n_components=10)),
        ("ridge", Ridge(alpha=1.0)),
    ])
    reference.fit(X_train, train_df["target"])
    reference_score = r2_score(y_test, reference.predict(X_test))
    tolerance = max(0.05, abs(reference_score) * 0.25)
    assert score >= reference_score - tolerance, \
        f"R2 score {score:.4f} is materially below the verifier-derived score {reference_score:.4f} for the required pipeline."


def test_mlflow_experiment_and_training_mse():
    pipeline = _load_model()
    train_df = pd.read_csv("/home/user/train_data.csv")
    X_train = train_df.drop(columns=["target"])
    y_train = train_df["target"]
    expected_mse = mean_squared_error(y_train, pipeline.predict(X_train))

    encoded_name = urllib.parse.quote(EXPERIMENT_NAME)
    try:
        experiment_response = _request_json(
            f"/api/2.0/mlflow/experiments/get-by-name?experiment_name={encoded_name}"
        )
    except urllib.error.URLError as exc:
        assert False, f"Could not connect to MLflow at localhost:5000. Is the service running? Error: {exc}"

    assert "experiment" in experiment_response, f"Experiment '{EXPERIMENT_NAME}' not found in MLflow."
    experiment_id = experiment_response["experiment"]["experiment_id"]
    runs_response = _request_json(
        "/api/2.0/mlflow/runs/search",
        {"experiment_ids": [experiment_id], "max_results": 100},
    )
    runs = runs_response.get("runs", [])
    assert runs, f"No runs were logged to experiment '{EXPERIMENT_NAME}'."

    logged_values = []
    for run in runs:
        metrics = run.get("data", {}).get("metrics", [])
        if isinstance(metrics, dict):
            metrics = [{"key": key, "value": value} for key, value in metrics.items()]
        for metric in metrics:
            if str(metric.get("key", "")).lower() == "mse":
                logged_values.append(float(metric["value"]))

    assert logged_values, "No MSE metric was logged in the Feature_Engineering_Exp experiment."
    tolerance = max(1e-6, abs(expected_mse) * 1e-5)
    assert any(math.isfinite(value) and abs(value - expected_mse) <= tolerance for value in logged_values), \
        f"The logged MSE does not match the pipeline's training MSE ({expected_mse:.6f})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
