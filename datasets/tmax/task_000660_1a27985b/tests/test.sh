#!/bin/bash
set +e
mkdir -p /logs/verifier /tmp/verifier_hooks

# Stop any service left running by the agent so the artifacts are exercised
# against an instrumented implementation of the specified API.
fuser -k 5000/tcp >/dev/null 2>&1 || true

cat <<'PY' > /tmp/instrumented_service.py
import hashlib
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE_PATH = "/tmp/embedding_service_state.json"
lock = threading.Lock()
state = {}

def reset_state():
    global state
    with lock:
        state = {
            "model_alpha": {"count": 0, "active": 0, "max_active": 0, "texts": []},
            "model_beta": {"count": 0, "active": 0, "max_active": 0, "texts": []},
        }
        write_state()

def write_state():
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_PATH)

def embedding(text):
    h = hashlib.md5(text.encode()).digest()
    return [b / 255.0 for b in h[:5]]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        if self.path == "/__verifier_reset_8f31c":
            reset_state()
            self.send_response(200)
            self.end_headers()
            return

        prefix = "/embed/"
        if not self.path.startswith(prefix):
            self.send_error(404)
            return
        model = self.path[len(prefix):]
        if model not in state:
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            text = payload.get("text", "")
        except Exception:
            self.send_error(400)
            return

        with lock:
            rec = state[model]
            rec["count"] += 1
            rec["active"] += 1
            rec["max_active"] = max(rec["max_active"], rec["active"])
            rec["texts"].append(text)
            write_state()

        try:
            time.sleep(0.01 if model == "model_alpha" else 0.05)
            body = json.dumps({"embedding": embedding(text)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        finally:
            with lock:
                state[model]["active"] -= 1
                write_state()

reset_state()
server = ThreadingHTTPServer(("127.0.0.1", 5000), Handler)
server.serve_forever()
PY

python3 /tmp/instrumented_service.py >/tmp/instrumented_service.log 2>&1 &
SERVICE_PID=$!

cat <<'PY' > /tmp/verifier_hooks/sitecustomize.py
import json

LOG = "/tmp/ml_calls.jsonl"

def serial(value):
    if hasattr(value, "tolist"):
        return value.tolist()
    if hasattr(value, "to_list"):
        return value.to_list()
    return list(value)

def record(item):
    with open(LOG, "a") as f:
        f.write(json.dumps(item) + "\n")

try:
    import sklearn.model_selection as model_selection
    original_split = model_selection.train_test_split

    def checked_split(*arrays, **kwargs):
        record({
            "kind": "train_test_split",
            "test_size": kwargs.get("test_size"),
            "random_state": kwargs.get("random_state"),
            "shuffle": kwargs.get("shuffle", True),
            "arrays": [serial(a) for a in arrays],
        })
        return original_split(*arrays, **kwargs)

    model_selection.train_test_split = checked_split

    import sklearn.linear_model as linear_model
    OriginalLogisticRegression = linear_model.LogisticRegression

    def checked_logistic_regression(*args, **kwargs):
        model = OriginalLogisticRegression(*args, **kwargs)
        record({
            "kind": "LogisticRegression",
            "random_state": model.get_params().get("random_state"),
        })
        return model

    linear_model.LogisticRegression = checked_logistic_regression
except Exception as exc:
    record({"kind": "hook_error", "error": repr(exc)})
PY

cat <<'PY' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import subprocess
import time
import urllib.request
from collections import Counter

import pytest

STATE = "/tmp/embedding_service_state.json"


def reset_service():
    req = urllib.request.Request(
        "http://127.0.0.1:5000/__verifier_reset_8f31c", data=b"", method="POST"
    )
    with urllib.request.urlopen(req, timeout=3) as response:
        assert response.status == 200


def read_state():
    with open(STATE) as f:
        return json.load(f)


def deterministic_embedding(text):
    digest = hashlib.md5(text.encode()).digest()
    return [b / 255.0 for b in digest[:5]]


def test_artifacts_are_executed_and_pipeline_is_correct():
    benchmark_path = "/home/user/benchmark.sh"
    train_path = "/home/user/train.py"
    report_path = "/home/user/report.json"

    # Preserve the original artifact-existence assertions.
    assert os.path.isfile(benchmark_path), f"Expected bash script at {benchmark_path} is missing."
    assert os.path.isfile(train_path), f"Expected python script at {train_path} is missing."

    with open(benchmark_path, "rb") as f:
        assert b"\x00" not in f.read(), "benchmark.sh is not a text Bash script"

    if os.path.exists(report_path):
        os.remove(report_path)

    # Actually execute the Bash benchmark and verify its observable requests.
    reset_service()
    subprocess.run(
        ["bash", benchmark_path],
        cwd="/home/user",
        check=True,
        timeout=30,
    )
    benchmark_state = read_state()
    for model in ("model_alpha", "model_beta"):
        rec = benchmark_state[model]
        assert rec["count"] == 50, f"benchmark.sh must send exactly 50 requests to {model}"
        assert rec["max_active"] == 1, f"Requests to {model} were not sequential"

    # Execute train.py from a clean report state. The injected hooks retain the
    # real sklearn behavior while recording the requested API parameters/data.
    reset_service()
    if os.path.exists(report_path):
        os.remove(report_path)
    if os.path.exists("/tmp/ml_calls.jsonl"):
        os.remove("/tmp/ml_calls.jsonl")
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hooks" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    subprocess.run(
        ["python3", train_path],
        cwd="/home/user",
        env=env,
        check=True,
        timeout=30,
    )

    with open("/home/user/dataset.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    texts = [row["text"] for row in rows]
    labels = [int(row["label"]) for row in rows]

    train_state = read_state()
    assert train_state["model_beta"]["count"] == 0, "train.py used the slower endpoint"
    assert train_state["model_alpha"]["count"] == len(rows), (
        "train.py must fetch one embedding for every dataset row"
    )
    assert Counter(train_state["model_alpha"]["texts"]) == Counter(texts), (
        "train.py did not request embeddings for exactly the dataset texts"
    )

    with open("/tmp/ml_calls.jsonl") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert not any(c["kind"] == "hook_error" for c in calls)

    split_calls = [c for c in calls if c["kind"] == "train_test_split"]
    assert split_calls, "train.py did not call sklearn.model_selection.train_test_split"
    split = split_calls[0]
    assert split["test_size"] == 0.25
    assert split["random_state"] == 42
    assert split["shuffle"] is False
    assert len(split["arrays"]) >= 2

    expected_features = [deterministic_embedding(t) + [len(t)] for t in texts]
    actual_features = split["arrays"][0]
    actual_labels = split["arrays"][1]
    assert len(actual_features) == len(expected_features)
    for actual, expected in zip(actual_features, expected_features):
        assert len(actual) == 6, "Each feature vector must contain 5 embedding values plus text length"
        assert actual == pytest.approx(expected), "Engineered features are incorrect"
    assert actual_labels == labels

    logistic_calls = [c for c in calls if c["kind"] == "LogisticRegression"]
    assert logistic_calls, "train.py did not instantiate sklearn.linear_model.LogisticRegression"
    assert logistic_calls[0]["random_state"] == 42

    # Preserve and strengthen the original report assertions.
    assert os.path.isfile(report_path), f"Expected report file at {report_path} is missing."
    with open(report_path) as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert set(report) == {"faster_model", "test_accuracy"}, "report.json has the wrong structure"
    assert "faster_model" in report, f"Key 'faster_model' missing in {report_path}"
    assert report["faster_model"] == "model_alpha", (
        f"Expected 'faster_model' to be 'model_alpha', got '{report['faster_model']}'"
    )
    assert "test_accuracy" in report, f"Key 'test_accuracy' missing in {report_path}"
    accuracy = report["test_accuracy"]
    assert isinstance(accuracy, (int, float)), f"'test_accuracy' must be a number, got {type(accuracy)}"
    expected_accuracy = 0.4
    assert abs(accuracy - expected_accuracy) < 0.01, (
        f"Expected 'test_accuracy' to be close to {expected_accuracy}, got {accuracy}"
    )
PY

# Wait briefly for the instrumented service to accept connections.
READY=0
for _ in $(seq 1 50); do
    if curl -s -X POST http://127.0.0.1:5000/__verifier_reset_8f31c >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 0.1
done

if [ "$READY" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

kill "$SERVICE_PID" >/dev/null 2>&1 || true
exit 0
