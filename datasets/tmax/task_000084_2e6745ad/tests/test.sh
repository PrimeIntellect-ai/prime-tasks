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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.machinery
import json
import math
import os
import signal
import subprocess
import tempfile
import time

import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.model_selection import KFold

URL = "http://127.0.0.1:8080/evaluate"
TOKEN = {"Authorization": "Bearer ds-research-2024"}
DATA = "/home/user/data/metrics.csv"
ALPHAS = [0.1, 1.0, 10.0]


def test_fast_bayes_installed_and_vendored_setup_builds():
    """The fixed vendored setup must build a real importable extension."""
    try:
        import fast_bayes
    except ImportError as e:
        pytest.fail(f"Failed to import fast_bayes: {e}")

    origin = getattr(fast_bayes, "__file__", "") or ""
    assert any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_bayes must be an installed compiled extension, got {origin!r}"
    assert hasattr(fast_bayes, "BayesianClassifier")

    setup_dir = "/app/vendored/fast_bayes"
    setup_file = os.path.join(setup_dir, "setup.py")
    assert os.path.isfile(setup_file), "The vendored setup.py is missing"

    # Force a clean extension compilation through the submitted setup.py. This
    # fails if NumPy's headers were not added to the Extension include paths.
    with tempfile.TemporaryDirectory() as td:
        lib = os.path.join(td, "lib")
        tmp = os.path.join(td, "tmp")
        result = subprocess.run(
            ["python3", "setup.py", "build_ext", "--force",
             "--build-lib", lib, "--build-temp", tmp],
            cwd=setup_dir, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=120,
        )
        assert result.returncode == 0, f"Vendored setup.py cannot build the extension:\n{result.stdout}"
        built = []
        for root, _, files in os.walk(lib):
            built.extend(os.path.join(root, f) for f in files
                         if any(f.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES))
        assert built, f"setup.py completed without producing an extension:\n{result.stdout}"


def independently_selected_alpha():
    """Recompute the requested seeded five-fold model selection."""
    import fast_bayes

    df = pd.read_csv(DATA)
    X = df.iloc[:, :4].to_numpy(dtype=float)
    y = df.iloc[:, 4].to_numpy(dtype=int)
    folds = KFold(n_splits=5, shuffle=True, random_state=42)
    scores = []
    for alpha in ALPHAS:
        fold_scores = []
        for train, test in folds.split(X):
            model = fast_bayes.BayesianClassifier(alpha=alpha)
            model.fit(X[train], y[train])
            probability = float(model.predict_proba(X[test]))
            predictions = np.full(len(test), int(probability >= 0.5), dtype=int)
            fold_scores.append(float(np.mean(predictions == y[test])))
        scores.append(float(np.mean(fold_scores)))
    return ALPHAS[int(np.argmax(scores))]


def test_best_alpha_file_matches_recomputed_cross_validation():
    alpha_file = "/home/user/best_alpha.txt"
    assert os.path.isfile(alpha_file), f"File {alpha_file} does not exist."
    content = open(alpha_file).read().strip()
    try:
        alpha_val = float(content)
    except ValueError:
        pytest.fail(f"Content of {alpha_file} is not a valid float: {content!r}")
    assert alpha_val in ALPHAS, f"Expected one of {ALPHAS}, got {alpha_val}"
    expected = independently_selected_alpha()
    assert alpha_val == expected, f"Expected cross-validation to select {expected}, got {alpha_val}"


def test_server_unauthorized():
    payload = {"features": [0.5, -1.2, 3.4, 0.1]}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized, got {response.status_code}: {response.text}"


def test_server_authorized_matches_real_model():
    import fast_bayes

    features = [0.5, -1.2, 3.4, 0.1]
    response = requests.post(URL, json={"features": features}, headers=TOKEN, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert set(data) == {"quality_score", "inference_time_ms"}, f"Unexpected response structure: {data}"
    assert isinstance(data["quality_score"], (int, float))
    assert isinstance(data["inference_time_ms"], (int, float))
    assert 0.0 <= float(data["quality_score"]) <= 1.0
    assert float(data["inference_time_ms"]) >= 0.0

    df = pd.read_csv(DATA)
    X = df.iloc[:, :4].to_numpy(dtype=float)
    y = df.iloc[:, 4].to_numpy(dtype=int)
    alpha = float(open("/home/user/best_alpha.txt").read().strip())
    model = fast_bayes.BayesianClassifier(alpha=alpha)
    model.fit(X, y)
    expected = float(model.predict_proba(np.asarray([features], dtype=float)))
    assert float(data["quality_score"]) == pytest.approx(expected, abs=1e-12), \
        f"Server returned {data['quality_score']}, but the fitted fast_bayes model returned {expected}"


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.append(int(pid))
                    break
        except OSError:
            pass
    return sorted(set(found))


def wait_for_server(proc):
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Instrumented server exited with status {proc.returncode}")
        try:
            requests.post(URL, json={"features": [0, 0, 0, 0]}, timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.1)
    pytest.fail("Server did not restart on 127.0.0.1:8080")


def test_server_really_fits_and_times_predict_proba():
    """Relaunch the submitted server with an instrumented fast_bayes module."""
    pids = listener_pids()
    assert pids, "No process is listening on port 8080"
    pid = pids[0]
    raw = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
    command = [part.decode() for part in raw if part]
    assert command, "Could not determine the submitted server command"
    cwd = os.readlink(f"/proc/{pid}/cwd")

    with tempfile.TemporaryDirectory() as hook_dir:
        log_file = os.path.join(hook_dir, "calls.jsonl")
        hook = r'''
import hashlib, json, math, os, sys, time, types
import numpy as np
LOG = os.environ["FAST_BAYES_AUDIT_LOG"]
def emit(value):
    with open(LOG, "a") as f:
        f.write(json.dumps(value) + "\\n")
class BayesianClassifier:
    def __init__(self, alpha=1.0):
        self.alpha = float(alpha)
        emit({"event": "init", "alpha": self.alpha})
    def fit(self, X, y):
        xa = np.ascontiguousarray(np.asarray(X, dtype=np.float64))
        ya = np.ascontiguousarray(np.asarray(y, dtype=np.float64))
        emit({"event": "fit", "xshape": list(xa.shape), "yshape": list(ya.shape),
              "xhash": hashlib.sha256(xa.tobytes()).hexdigest(),
              "yhash": hashlib.sha256(ya.tobytes()).hexdigest()})
        return self
    def predict_proba(self, X):
        xa = np.asarray(X, dtype=np.float64)
        start = time.perf_counter()
        delay = 0.09 + (abs(float(xa.sum())) % 5.0) / 1000.0
        time.sleep(delay)
        value = 1.0 / (1.0 + math.exp(-(float(xa.sum()) * 0.17 + self.alpha * 0.013)))
        elapsed = (time.perf_counter() - start) * 1000.0
        emit({"event": "predict", "values": xa.reshape(-1).tolist(),
              "result": value, "elapsed_ms": elapsed})
        return value
module = types.ModuleType("fast_bayes")
module.BayesianClassifier = BayesianClassifier
sys.modules["fast_bayes"] = module
'''
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(hook)

        for old_pid in pids:
            try:
                os.kill(old_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.time() + 5
        while listener_pids() and time.time() < deadline:
            time.sleep(0.1)
        for old_pid in listener_pids():
            try:
                os.kill(old_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

        env = os.environ.copy()
        env["FAST_BAYES_AUDIT_LOG"] = log_file
        env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
        output = open(os.path.join(hook_dir, "server.log"), "w")
        proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, start_new_session=True)
        try:
            wait_for_server(proc)
            bad = requests.post(URL, json={"features": [1, 2, 3, 4]}, timeout=5)
            assert bad.status_code == 401

            feature_sets = [[1.25, -0.5, 2.0, 0.75], [-2.0, 0.25, -1.5, 0.1]]
            replies = []
            for features in feature_sets:
                reply = requests.post(URL, json={"features": features}, headers=TOKEN, timeout=5)
                assert reply.status_code == 200, reply.text
                body = reply.json()
                assert set(body) == {"quality_score", "inference_time_ms"}
                replies.append(body)

            events = [json.loads(line) for line in open(log_file) if line.strip()]
            alpha = float(open("/home/user/best_alpha.txt").read().strip())
            assert any(e.get("event") == "init" and e.get("alpha") == alpha for e in events), \
                "Server did not initialize BayesianClassifier with best_alpha.txt"

            df = pd.read_csv(DATA)
            expected_x = np.ascontiguousarray(df.iloc[:, :4].to_numpy(dtype=np.float64))
            expected_y = np.ascontiguousarray(df.iloc[:, 4].to_numpy(dtype=np.float64))
            xhash = hashlib.sha256(expected_x.tobytes()).hexdigest()
            yhash = hashlib.sha256(expected_y.tobytes()).hexdigest()
            assert any(e.get("event") == "fit" and e.get("xshape") == [100, 4]
                       and e.get("yshape") == [100] and e.get("xhash") == xhash
                       and e.get("yhash") == yhash for e in events), \
                "Server did not fit BayesianClassifier on the complete metrics.csv dataset"

            predictions = [e for e in events if e.get("event") == "predict"]
            for features, body in zip(feature_sets, replies):
                matches = [e for e in predictions if e.get("values") == features]
                assert matches, f"predict_proba was not called with request features {features}"
                event = matches[-1]
                assert float(body["quality_score"]) == pytest.approx(event["result"], abs=1e-12)
                reported = float(body["inference_time_ms"])
                assert reported >= 50.0, "Reported timing did not include the predict_proba call"
                assert abs(reported - float(event["elapsed_ms"])) <= 75.0, \
                    f"Reported {reported} ms, predict_proba took {event['elapsed_ms']} ms"
        finally:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            output.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
