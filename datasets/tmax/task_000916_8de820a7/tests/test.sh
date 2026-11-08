#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import signal
import subprocess
import tempfile
import time

import pytest
import requests

HOME = "/home/user"
ENV_PYTHON = "/home/user/env/bin/python"


def resolved(node, assignments):
    if isinstance(node, ast.Name) and node.id in assignments:
        return resolved(assignments[node.id], assignments)
    try:
        return ast.literal_eval(node)
    except Exception:
        return None


def assert_training_script_uses_required_search():
    path = f"{HOME}/train.py"
    assert os.path.isfile(path), "/home/user/train.py was not found."
    source = open(path, encoding="utf-8").read()
    tree = ast.parse(source, filename=path)
    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value

    calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.id if isinstance(node.func, ast.Name) else (
            node.func.attr if isinstance(node.func, ast.Attribute) else ""
        )
        if name == "GridSearchCV":
            calls.append(node)
    assert calls, "train.py must use sklearn.model_selection.GridSearchCV."

    valid = False
    for call in calls:
        kwargs = {kw.arg: kw.value for kw in call.keywords if kw.arg}
        grid_node = kwargs.get("param_grid") or (call.args[1] if len(call.args) > 1 else None)
        scoring_node = kwargs.get("scoring") or (call.args[2] if len(call.args) > 2 else None)
        cv_node = kwargs.get("cv") or (call.args[5] if len(call.args) > 5 else None)
        grid = resolved(grid_node, assignments) if grid_node is not None else None
        scoring = resolved(scoring_node, assignments) if scoring_node is not None else None
        cv = resolved(cv_node, assignments) if cv_node is not None else None
        if not isinstance(grid, dict):
            continue
        pca_values = None
        c_values = None
        for key, values in grid.items():
            if isinstance(key, str) and key.endswith("__n_components"):
                pca_values = list(values)
            if isinstance(key, str) and key.endswith("__C"):
                c_values = list(values)
        if pca_values == [16, 32, 64] and c_values == [0.1, 1.0, 10.0] and cv == 5 and scoring == "accuracy":
            valid = True
            break
    assert valid, "GridSearchCV must use cv=5, scoring='accuracy', and exactly the required PCA/LogisticRegression grid."


def kill_port_8080():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                socket_inodes.add(fields[9])
    if not socket_inodes:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except OSError:
            pass
    time.sleep(1)


def run_env_script(source, args=(), timeout=600):
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write(source)
        path = f.name
    try:
        return subprocess.run(
            [ENV_PYTHON, path, *args], capture_output=True, text=True,
            timeout=timeout, cwd=HOME
        )
    finally:
        os.unlink(path)


def test_complete_workflow():
    assert os.path.isfile(ENV_PYTHON), f"Student's python environment not found at {ENV_PYTHON}"
    assert os.path.isfile(f"{HOME}/embeddings.csv"), "/home/user/embeddings.csv was not found."
    assert os.path.isfile(f"{HOME}/server.py"), "/home/user/server.py was not found."

    # Verify that embeddings are exactly the headerless 1024-D output of the legacy binary.
    with open(f"{HOME}/logs.json") as f:
        logs = json.load(f)
    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as f:
        expected_csv = f.name
    try:
        result = subprocess.run(
            ["/app/log_embedder", "-i", f"{HOME}/logs.json", "-o", expected_csv],
            capture_output=True, text=True, timeout=120
        )
        assert result.returncode == 0, f"Legacy embedder failed: {result.stdout}\n{result.stderr}"
        assert open(f"{HOME}/embeddings.csv", "rb").read() == open(expected_csv, "rb").read(), \
            "embeddings.csv is not the output produced by /app/log_embedder for logs.json."
    finally:
        os.unlink(expected_csv)

    rows = open(f"{HOME}/embeddings.csv").read().splitlines()
    assert len(rows) == len(logs), "Embedding row count does not match logs.json."
    assert rows and all(len(row.split(",")) == 1024 for row in rows), \
        "embeddings.csv must contain 1024 columns per row and no header."

    assert_training_script_uses_required_search()

    # Actually execute the submitted trainer and require it to create a fresh artifact.
    model_path = f"{HOME}/best_pipeline.pkl"
    if os.path.lexists(model_path):
        os.unlink(model_path)
    trained = subprocess.run(
        [ENV_PYTHON, f"{HOME}/train.py"], cwd=HOME,
        capture_output=True, text=True, timeout=600
    )
    assert trained.returncode == 0, f"train.py failed: {trained.stdout}\n{trained.stderr}"
    assert os.path.exists(model_path), "The best_pipeline.pkl file was not found."
    assert os.path.isfile(model_path), "/home/user/best_pipeline.pkl is not a file."

    # Validate structure, fitted state, full-data fitting, and optimality over the required grid.
    validation = r'''
import json, pickle, sys, warnings
import numpy as np
from sklearn.base import clone
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score
from sklearn.pipeline import Pipeline
warnings.filterwarnings("ignore")
X = np.loadtxt('/home/user/embeddings.csv', delimiter=',')
y = np.asarray(json.load(open('/home/user/labels.json')))
assert X.ndim == 2 and X.shape[1] == 1024
assert len(y) == len(X) and set(np.unique(y)).issubset({0, 1})
model = pickle.load(open('/home/user/best_pipeline.pkl', 'rb'))
assert type(model) is Pipeline, 'Saved object is not a sklearn Pipeline'
assert len(model.steps) == 2, 'Pipeline must contain exactly PCA then LogisticRegression'
pca_name, pca = model.steps[0]
lr_name, lr = model.steps[1]
assert type(pca) is PCA, 'First pipeline step is not PCA'
assert type(lr) is LogisticRegression, 'Second pipeline step is not LogisticRegression'
assert pca.n_components in (16, 32, 64)
assert float(lr.C) in (0.1, 1.0, 10.0)
assert hasattr(pca, 'components_') and pca.components_.shape == (pca.n_components, 1024)
assert hasattr(pca, 'mean_') and np.allclose(pca.mean_, X.mean(axis=0), rtol=1e-7, atol=1e-9)
assert getattr(pca, 'n_samples_', len(X)) == len(X)
assert hasattr(lr, 'classes_') and set(lr.classes_) == {0, 1}
assert lr.coef_.shape[1] == pca.n_components
pred = model.predict(X)
assert np.mean(pred == y) >= 0.90, 'Fitted pipeline does not learn the provided labels'
base = clone(model)
if hasattr(base.named_steps[pca_name], 'random_state'):
    base.named_steps[pca_name].random_state = 12345
if hasattr(base.named_steps[lr_name], 'random_state'):
    base.named_steps[lr_name].random_state = 12345
scores = {}
for n in (16, 32, 64):
    for c in (0.1, 1.0, 10.0):
        candidate = clone(base).set_params(**{pca_name + '__n_components': n, lr_name + '__C': c})
        scores[(n, c)] = float(cross_val_score(candidate, X, y, cv=5, scoring='accuracy').mean())
chosen = scores[(int(pca.n_components), float(lr.C))]
assert chosen >= max(scores.values()) - 1e-12, 'Saved hyperparameters do not maximize 5-fold accuracy over the required grid'
print(json.dumps({'ok': True, 'train_accuracy': float(np.mean(pred == y))}))
'''
    checked = run_env_script(validation)
    assert checked.returncode == 0, f"Saved pipeline validation failed: {checked.stdout}\n{checked.stderr}"

    # Start the submitted server against the freshly generated model.
    kill_port_8080()
    subprocess.Popen(
        [ENV_PYTHON, f"{HOME}/server.py"], cwd=HOME,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    url = "http://127.0.0.1:8080/score"
    for _ in range(40):
        try:
            if requests.post(url, json={"raw_embedding": [0.0] * 1024}, timeout=1).status_code == 200:
                break
        except requests.RequestException:
            pass
        time.sleep(0.5)
    else:
        pytest.fail("Failed to connect to the API at http://127.0.0.1:8080/score")

    # Retain the original deterministic check and add several independently derived inputs.
    random.seed(42)
    vectors = [[random.uniform(-1.0, 1.0) for _ in range(1024)]]
    random.seed(9173)
    vectors.extend([[random.uniform(-1.0, 1.0) for _ in range(1024)] for _ in range(4)])
    vectors.append([float(x) for x in rows[0].split(",")])

    prediction_script = r'''
import json, pickle, sys
model = pickle.load(open('/home/user/best_pipeline.pkl', 'rb'))
vectors = json.loads(sys.argv[1])
print(json.dumps([int(x) for x in model.predict(vectors)]))
'''
    predicted = run_env_script(prediction_script, (json.dumps(vectors),), timeout=60)
    assert predicted.returncode == 0, f"Failed to run saved model: {predicted.stdout}\n{predicted.stderr}"
    model_classes = json.loads(predicted.stdout.strip())

    for vector, model_class in zip(vectors, model_classes):
        try:
            response = requests.post(url, json={"raw_embedding": vector}, timeout=5)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to the API at {url}: {e}")
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"API did not return valid JSON. Response: {response.text}")
        assert "class" in data, "Response JSON is missing 'class' key."
        assert "inference_time_ms" in data, "Response JSON is missing 'inference_time_ms' key."
        api_class = data["class"]
        assert api_class in [0, 1], f"Expected 'class' to be 0 or 1, got {api_class}"
        inference_time = data["inference_time_ms"]
        assert isinstance(inference_time, (int, float)) and inference_time > 0, \
            f"Expected 'inference_time_ms' to be a positive number, got {inference_time}"
        assert api_class == model_class, \
            f"API returned class {api_class}, but the saved pipeline predicted {model_class}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
