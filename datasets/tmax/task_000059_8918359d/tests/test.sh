#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import tempfile
import urllib.error
import urllib.request

import mlflow
import numpy as np
import pandas as pd
import pytest
import scipy.stats as stats
from mlflow.tracking import MlflowClient
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

PIPELINE = "/home/user/pipeline"
SUMMARY = os.path.join(PIPELINE, "fix_summary.json")
TRAIN = os.path.join(PIPELINE, "train.py")
TRACKING_URI = "http://127.0.0.1:5000"


def load_summary():
    assert os.path.isfile(SUMMARY), f"File {SUMMARY} does not exist."
    with open(SUMMARY, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("fix_summary.json is not a valid JSON file.")


def get_run_via_api(run_id):
    url = f"{TRACKING_URI}/api/2.0/mlflow/runs/get?run_id={run_id}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to MLflow server or run not found: {e}")


def all_run_ids(client):
    result = set()
    for exp in client.search_experiments():
        for run in client.search_runs([exp.experiment_id], max_results=10000):
            result.add(run.info.run_id)
    return result


def expected_results():
    df = pd.read_csv(os.path.join(PIPELINE, "data.csv"))
    X = df[["feature_1", "feature_2", "feature_3"]]
    y = df["target_engagement"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    imputer = SimpleImputer(strategy="mean")
    X_train_imputed = imputer.fit_transform(X_train)
    X_test_imputed = imputer.transform(X_test)
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train_imputed)
    X_test_scaled = scaler.transform(X_test_imputed)
    model = Ridge(alpha=1.0, random_state=42)
    model.fit(X_train_scaled, y_train)
    preds = model.predict(X_test_scaled)
    squared_errors = np.square(np.asarray(y_test) - preds)
    mse = mean_squared_error(y_test, preds)
    lower, upper = stats.t.interval(
        confidence=0.95,
        df=len(squared_errors) - 1,
        loc=np.mean(squared_errors),
        scale=stats.sem(squared_errors),
    )
    corr = pd.DataFrame(X_train_scaled).corr().to_numpy()
    return float(mse), float(lower), float(upper), corr


def mlflow_server_command():
    # Locate the process listening on 127.0.0.1:5000, then walk through its
    # parents because gunicorn workers commonly own the listening socket.
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1388" and fields[3] == "0A":
                    socket_inodes.add(fields[9])

    owners = []
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    owners.append(int(pid))
                    break
        except OSError:
            pass

    for starting_pid in owners:
        pid = starting_pid
        for _ in range(12):
            try:
                raw = open(f"/proc/{pid}/cmdline", "rb").read()
                cmd = raw.replace(b"\0", b" ").decode("utf-8", "replace").strip()
                if "mlflow" in cmd.lower() and "server" in cmd.lower():
                    return cmd
                stat = open(f"/proc/{pid}/stat").read()
                pid = int(stat[stat.rfind(")") + 2:].split()[1])
                if pid <= 1:
                    break
            except (OSError, ValueError, IndexError):
                break
    return ""


def configured_path(cmd, options):
    import shlex
    tokens = shlex.split(cmd)
    for i, token in enumerate(tokens):
        for option in options:
            if token == option and i + 1 < len(tokens):
                return tokens[i + 1]
            if token.startswith(option + "="):
                return token.split("=", 1)[1]
    return None


def path_is_under_mlruns(value):
    if not value:
        return False
    if value.startswith("sqlite:///"):
        value = value[len("sqlite:///"):]
        if not value.startswith("/"):
            value = "/" + value
    elif value.startswith("file://"):
        value = value[len("file://"):]
    elif "://" in value:
        return False
    return os.path.commonpath([os.path.abspath(value), "/home/user/mlruns"]) == "/home/user/mlruns"


def test_fix_summary_exists_and_valid():
    summary = load_summary()
    assert "run_id" in summary, "run_id missing from fix_summary.json"
    assert "mse_ci_lower" in summary, "mse_ci_lower missing from fix_summary.json"
    assert "mse_ci_upper" in summary, "mse_ci_upper missing from fix_summary.json"
    assert isinstance(summary["mse_ci_lower"], (int, float)), "mse_ci_lower must be a number"
    assert isinstance(summary["mse_ci_upper"], (int, float)), "mse_ci_upper must be a number"


def test_mlflow_server_storage_configuration():
    # First establish that the advertised HTTP service is an MLflow server.
    try:
        with urllib.request.urlopen(f"{TRACKING_URI}/api/2.0/mlflow/experiments/search", timeout=10) as response:
            assert response.status == 200
    except urllib.error.URLError as e:
        pytest.fail(f"MLflow is not running at {TRACKING_URI}: {e}")

    cmd = mlflow_server_command()
    assert cmd, "No MLflow server process is listening on port 5000."
    backend = configured_path(cmd, ["--backend-store-uri"])
    artifact = configured_path(cmd, ["--default-artifact-root", "--artifacts-destination"])
    assert path_is_under_mlruns(backend), f"MLflow backend is not stored in /home/user/mlruns: {backend!r}"
    assert path_is_under_mlruns(artifact), f"MLflow artifacts are not stored in /home/user/mlruns: {artifact!r}"


def test_execute_training_and_verify_computation():
    mlflow.set_tracking_uri(TRACKING_URI)
    client = MlflowClient(tracking_uri=TRACKING_URI)
    before = all_run_ids(client)

    result = subprocess.run(
        ["python3", TRAIN], cwd=PIPELINE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert result.returncode == 0, f"train.py failed when executed:\n{result.stdout}"

    after = all_run_ids(client)
    new_ids = after - before
    assert new_ids, "Executing train.py did not create a new MLflow run."

    summary = load_summary()
    run_id = summary.get("run_id")
    assert run_id, "run_id is empty or missing."
    assert run_id in new_ids, "fix_summary.json does not identify a run created by this execution of train.py."

    data = get_run_via_api(run_id)
    run_data = data.get("run", {}).get("data", {})
    metrics = {m["key"]: m["value"] for m in run_data.get("metrics", [])}
    assert "mse_ci_lower" in metrics, "mse_ci_lower metric not logged to MLflow."
    assert "mse_ci_upper" in metrics, "mse_ci_upper metric not logged to MLflow."
    assert "mse" in metrics, "mse metric not logged to MLflow."

    # Preserve the original JSON-to-MLflow assertions.
    assert math.isclose(summary["mse_ci_lower"], metrics["mse_ci_lower"], rel_tol=1e-3), \
        "mse_ci_lower in JSON does not match MLflow metric."
    assert math.isclose(summary["mse_ci_upper"], metrics["mse_ci_upper"], rel_tol=1e-3), \
        "mse_ci_upper in JSON does not match MLflow metric."

    expected_mse, expected_lower, expected_upper, expected_corr = expected_results()
    assert math.isclose(metrics["mse"], expected_mse, rel_tol=1e-10, abs_tol=1e-10), \
        "Logged MSE was not recomputed from the correctly preprocessed test predictions."
    assert math.isclose(metrics["mse_ci_lower"], expected_lower, rel_tol=1e-10, abs_tol=1e-10), \
        "Logged lower confidence bound is not the 95% t interval of test squared errors."
    assert math.isclose(metrics["mse_ci_upper"], expected_upper, rel_tol=1e-10, abs_tol=1e-10), \
        "Logged upper confidence bound is not the 95% t interval of test squared errors."
    assert math.isclose(summary["mse_ci_lower"], round(expected_lower, 4), abs_tol=5e-5), \
        "Summary lower bound is not the calculated value rounded to four decimals."
    assert math.isclose(summary["mse_ci_upper"], round(expected_upper, 4), abs_tol=5e-5), \
        "Summary upper bound is not the calculated value rounded to four decimals."

    with tempfile.TemporaryDirectory() as tmp:
        artifact_path = client.download_artifacts(run_id, "corr_matrix.csv", tmp)
        actual_corr = pd.read_csv(artifact_path).to_numpy()
    assert actual_corr.shape == expected_corr.shape, "Logged correlation matrix has the wrong shape."
    assert np.allclose(actual_corr, expected_corr, rtol=1e-10, atol=1e-10), \
        "Correlation matrix was not computed from the scaled training features."


def test_code_changes():
    assert os.path.isfile(TRAIN), "train.py is missing."
    with open(TRAIN, "r") as f:
        code = f.read()

    # Preserve the original assertions.
    assert "train_test_split" in code, "train_test_split is missing."
    assert "fit_transform" in code, "fit_transform is missing."
    split_idx = code.find("train_test_split")
    imputer_fit_idx = code.find("fit_transform", split_idx)
    assert imputer_fit_idx > split_idx, \
        "Data leakage not fixed: fit_transform appears to be called before train_test_split."

    tree = ast.parse(code)
    split_lines = [n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call) and
                   ((isinstance(n.func, ast.Name) and n.func.id == "train_test_split") or
                    (isinstance(n.func, ast.Attribute) and n.func.attr == "train_test_split"))]
    assert split_lines, "train_test_split call is missing."
    split_line = min(split_lines)

    preprocessors = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Name):
            if n.value.func.id in {"SimpleImputer", "StandardScaler"}:
                preprocessors.update(t.id for t in n.targets if isinstance(t, ast.Name))
    assert preprocessors, "Imputer and scaler instances are missing."

    fit_calls = []
    transform_calls = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and isinstance(n.func.value, ast.Name):
            if n.func.value.id in preprocessors and n.func.attr in {"fit", "fit_transform"}:
                fit_calls.append(n)
            if n.func.value.id in preprocessors and n.func.attr in {"transform", "fit_transform"}:
                transform_calls.append(n)
    assert len(fit_calls) >= 2, "Both the imputer and scaler must be fit on training data."
    assert all(n.lineno > split_line for n in fit_calls), "A preprocessor is fit before the train/test split."
    for call in fit_calls:
        assert call.args and isinstance(call.args[0], ast.Name), "Preprocessor fit input must be the training feature variable."
        name = call.args[0].id.lower()
        assert "train" in name and "test" not in name, "A preprocessor is not fit exclusively on training features."
    transformed_names = [call.args[0].id.lower() for call in transform_calls
                         if call.args and isinstance(call.args[0], ast.Name)]
    assert any("train" in name for name in transformed_names), "Training features are not transformed."
    assert any("test" in name for name in transformed_names), "Test features are not transformed with fitted preprocessing."

    ridge_calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "Ridge"]
    assert ridge_calls, "Ridge model is missing."
    for call in ridge_calls:
        kwargs = {kw.arg: kw.value for kw in call.keywords}
        assert "alpha" in kwargs and isinstance(kwargs["alpha"], ast.Constant) and kwargs["alpha"].value == 1.0, \
            "Ridge alpha hyperparameter was changed."
    random_assignments = [n for n in ast.walk(tree) if isinstance(n, ast.Assign) and
                          any(isinstance(t, ast.Name) and t.id == "RANDOM_STATE" for t in n.targets)]
    assert random_assignments and isinstance(random_assignments[0].value, ast.Constant) and random_assignments[0].value.value == 42, \
        "RANDOM_STATE was changed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
