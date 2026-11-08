#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import urllib.error
import urllib.request


def mlflow_request(path, payload=None):
    url = "http://127.0.0.1:5000" + path
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"} if data is not None else {},
        method="POST" if data is not None else "GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to MLflow server at http://127.0.0.1:5000. Is it running? Error: {e}"


def expected_results():
    import pandas as pd
    from sklearn.linear_model import Ridge
    from sklearn.metrics import r2_score
    from sklearn.model_selection import GroupKFold

    sensors = pd.read_csv("/home/user/data/sensors.csv")
    labels = pd.read_json("/home/user/data/labels.json")
    joined = sensors.merge(
        labels,
        on=["machine_id", "timestamp"],
        how="inner",
        validate="one_to_one",
    )
    assert len(joined) == len(sensors) == len(labels), "The supplied datasets do not form the required perfect join."

    X = joined[["temperature", "vibration"]]
    y = joined["wear_level"]
    groups = joined["machine_id"]
    splitter = GroupKFold(n_splits=3)

    results = {}
    for alpha in [0.1, 1.0, 10.0]:
        scores = []
        for train_idx, validation_idx in splitter.split(X, y, groups):
            model = Ridge(alpha=alpha)
            model.fit(X.iloc[train_idx], y.iloc[train_idx])
            prediction = model.predict(X.iloc[validation_idx])
            scores.append(r2_score(y.iloc[validation_idx], prediction))
        results[alpha] = sum(scores) / len(scores)
    return results


def listener_processes(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            socket_inodes.add(fields[9])
        except OSError:
            pass

    commands = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_socket = any(
                os.readlink(os.path.join(fd_dir, fd)) == f"socket:[{inode}]"
                for fd in os.listdir(fd_dir)
                for inode in socket_inodes
            )
        except (OSError, PermissionError):
            continue
        if owns_socket:
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    commands.append(f.read().replace(b"\0", b" ").decode("utf-8", "replace"))
            except OSError:
                pass
    return commands


def test_mlflow_server_and_experiment():
    data = mlflow_request(
        "/api/2.0/mlflow/experiments/get-by-name?experiment_name=Wear_Prediction"
    )
    assert "experiment" in data, "Experiment 'Wear_Prediction' not found in MLflow response."
    assert data["experiment"]["name"] == "Wear_Prediction", "Experiment name does not match 'Wear_Prediction'."


def test_real_mlflow_server_is_listening():
    commands = listener_processes(5000)
    assert commands, "No process is listening on TCP port 5000."
    assert any("mlflow" in command.lower() for command in commands), (
        "Port 5000 is not owned by an MLflow server process: " + repr(commands)
    )


def test_mlflow_runs_contain_tuning_results():
    experiment = mlflow_request(
        "/api/2.0/mlflow/experiments/get-by-name?experiment_name=Wear_Prediction"
    )["experiment"]
    response = mlflow_request(
        "/api/2.0/mlflow/runs/search",
        {"experiment_ids": [experiment["experiment_id"]], "max_results": 1000},
    )
    runs = response.get("runs", [])
    expected = expected_results()

    assert len(runs) >= 3, "Wear_Prediction must contain at least one run for each of the three alpha values."
    matched_run_ids = set()
    for alpha, expected_score in expected.items():
        matches = []
        for run in runs:
            params = {item["key"]: item["value"] for item in run.get("data", {}).get("params", [])}
            metrics = {item["key"]: item["value"] for item in run.get("data", {}).get("metrics", [])}
            try:
                logged_alpha = float(params["alpha"])
                logged_score = float(metrics["cv_r2"])
            except (KeyError, TypeError, ValueError):
                continue
            if abs(logged_alpha - alpha) < 1e-12 and abs(logged_score - expected_score) < 1e-9:
                matches.append(run)

        assert matches, (
            f"No MLflow run logs alpha={alpha} with the cv_r2 derived from the supplied data "
            f"and the required 3-fold GroupKFold Ridge evaluation ({expected_score})."
        )
        run = matches[0]
        run_id = run.get("info", {}).get("run_id")
        assert run_id and run_id not in matched_run_ids, "Each alpha must be logged in a distinct MLflow run."
        matched_run_ids.add(run_id)
        assert run.get("info", {}).get("status") == "FINISHED", f"MLflow run {run_id} is not FINISHED."


def test_best_run_file_exists_and_format():
    filepath = "/home/user/best_run.json"
    assert os.path.exists(filepath), f"Missing file: {filepath}"
    assert os.path.isfile(filepath), f"Not a file: {filepath}"

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {filepath} is not valid JSON."

    assert "best_alpha" in data, f"Key 'best_alpha' missing in {filepath}"
    assert "best_cv_r2" in data, f"Key 'best_cv_r2' missing in {filepath}"
    assert set(data) == {"best_alpha", "best_cv_r2"}, f"{filepath} must contain exactly the required keys."

    assert isinstance(data["best_alpha"], (int, float)), "Value for 'best_alpha' must be a float."
    assert isinstance(data["best_cv_r2"], (int, float)), "Value for 'best_cv_r2' must be a float."


def test_best_run_values():
    filepath = "/home/user/best_run.json"
    if not os.path.exists(filepath):
        return

    with open(filepath, "r") as f:
        data = json.load(f)

    best_alpha = float(data["best_alpha"])
    best_cv_r2 = float(data["best_cv_r2"])

    # Preserve the original checks.
    expected_alpha = 0.1
    expected_cv_r2 = 0.9619
    assert best_alpha == expected_alpha, f"Expected best_alpha to be {expected_alpha}, but got {best_alpha}"
    assert abs(best_cv_r2 - expected_cv_r2) < 0.001, f"Expected best_cv_r2 to be approximately {expected_cv_r2}, but got {best_cv_r2}"

    # Also derive the answer independently from the supplied datasets.
    results = expected_results()
    derived_alpha = max(results, key=results.get)
    derived_score = round(results[derived_alpha], 4)
    assert best_alpha == float(derived_alpha), f"best_alpha does not match the best derived CV result: {derived_alpha}"
    assert best_cv_r2 == float(derived_score), f"best_cv_r2 must be the derived best score rounded to 4 decimals: {derived_score}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
