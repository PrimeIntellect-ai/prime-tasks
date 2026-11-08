#!/bin/bash
mkdir -p /logs/verifier /tmp/verifier_hook

cat <<'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json

LOG = "/tmp/pipeline_events.log"

def record(event, **details):
    try:
        with open(LOG, "a") as f:
            f.write(json.dumps({"event": event, **details}) + "\n")
    except Exception:
        pass

def wrap_method(cls, name, event):
    try:
        original = getattr(cls, name)
        def wrapped(self, *args, **kwargs):
            size = None
            if args:
                try:
                    size = len(args[0])
                except Exception:
                    pass
            record(event, size=size)
            return original(self, *args, **kwargs)
        setattr(cls, name, wrapped)
    except Exception:
        pass

try:
    from sklearn.ensemble import RandomForestClassifier
    wrap_method(RandomForestClassifier, "fit", "rf_fit")
    wrap_method(RandomForestClassifier, "predict", "rf_predict")
except Exception:
    pass

try:
    from sklearn.preprocessing import OneHotEncoder
    wrap_method(OneHotEncoder, "transform", "onehot_transform")
except Exception:
    pass

try:
    from sklearn.impute import SimpleImputer
    wrap_method(SimpleImputer, "transform", "imputer_transform")
except Exception:
    pass

try:
    import pandas as pd
    original_get_dummies = pd.get_dummies
    def logged_get_dummies(*args, **kwargs):
        record("get_dummies")
        return original_get_dummies(*args, **kwargs)
    pd.get_dummies = logged_get_dummies

    for cls in (pd.DataFrame, pd.Series):
        original = cls.fillna
        def make_fillna(fn):
            def logged_fillna(self, *args, **kwargs):
                record("fillna")
                return fn(self, *args, **kwargs)
            return logged_fillna
        cls.fillna = make_fillna(original)
except Exception:
    pass

try:
    import datacleaner.schema as schema
    original_enforce = schema.enforce_age_schema
    def logged_enforce(*args, **kwargs):
        record("enforce_age_schema")
        return original_enforce(*args, **kwargs)
    schema.enforce_age_schema = logged_enforce
    try:
        import datacleaner
        datacleaner.enforce_age_schema = logged_enforce
    except Exception:
        pass
except Exception:
    pass
HOOK_EOF

# Stop whichever process currently owns port 8000, then execute the submitted
# service artifact ourselves with lightweight instrumentation.
python3 - <<'PY'
import os, signal
inodes = set()
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                if int(fields[1].rsplit(':', 1)[1], 16) == 8000 and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass
for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass
PY
sleep 1
rm -f /tmp/pipeline_events.log
nohup env PYTHONPATH="/tmp/verifier_hook${PYTHONPATH:+:$PYTHONPATH}" python3 /home/user/serve.py >/tmp/verifier_service.log 2>&1 &

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib.metadata
import json
import os
import subprocess
import sys
import threading
import time

import pandas as pd
import pytest
import requests

URL = "http://127.0.0.1:8000/predict"
HEADERS = {"Authorization": "Bearer secret-token-99X"}


def wait_for_service():
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            r = requests.post(URL, json={"data": []}, timeout=1)
            if r.status_code in (200, 400, 401, 403, 422):
                return
        except requests.RequestException as e:
            last_error = e
        time.sleep(0.25)
    pytest.fail(f"Submitted /home/user/serve.py did not start a service on port 8000: {last_error}")


def test_service_artifact_exists_and_is_running():
    assert os.path.isfile("/home/user/serve.py"), "/home/user/serve.py is missing"
    assert os.path.getsize("/home/user/serve.py") > 0, "/home/user/serve.py is empty"
    wait_for_service()

    found = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\x00", b" ").decode(errors="ignore")
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
        except OSError:
            continue
        if "serve.py" in cmdline and ("/home/user/serve.py" in cmdline or cwd == "/home/user"):
            found = True
            break
    assert found, "The listener was not started from the submitted serve.py artifact"


def test_datacleaner_bug_fixed():
    """Test that the datacleaner package drops invalid age rows."""
    sys.path.insert(0, "/app/datacleaner-1.2.0")
    try:
        from datacleaner.schema import enforce_age_schema
    except ImportError:
        pytest.fail("Could not import datacleaner.schema. Was the package installed/fixed?")

    df = pd.DataFrame({
        "age": ["25", "twenty", "30"],
        "income": [50000.0, 60000.0, 70000.0],
        "category": ["A", "B", "A"]
    })
    try:
        cleaned_df = enforce_age_schema(df)
    except Exception as e:
        pytest.fail(f"enforce_age_schema raised an exception: {e}")

    assert len(cleaned_df) == 2, "Expected rows with invalid age ('twenty') to be dropped."
    assert cleaned_df["age"].isna().sum() == 0, "Expected no NaN values in the age column."

    all_bad = enforce_age_schema(pd.DataFrame({"age": ["bad", "1.2", None]}))
    assert len(all_bad) == 0, "All non-castable integer ages must be dropped"


def test_fixed_package_was_installed():
    result = subprocess.run(
        [sys.executable, "-c", "import importlib.metadata, datacleaner; print(importlib.metadata.version('datacleaner'))"],
        cwd="/tmp", text=True, capture_output=True
    )
    assert result.returncode == 0, f"datacleaner is not installed: {result.stderr}"
    assert result.stdout.strip().endswith("1.2.0")


def test_pipeline_source_contains_required_training_steps():
    sources = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            if name.endswith(".py"):
                try:
                    sources.append(open(os.path.join(root, name), errors="ignore").read())
                except OSError:
                    pass
    combined = "\n".join(sources).lower()
    assert "raw_users.csv" in combined, "No ETL code reads the supplied raw dataset"
    assert "enforce_age_schema" in combined, "ETL code does not use the fixed datacleaner schema"
    assert "randomforestclassifier" in combined and ".fit(" in combined, "No Random Forest training code was found"
    assert "get_dummies" in combined or "onehotencoder" in combined, "No one-hot category encoding was found"
    assert "median" in combined, "No median income imputation was found"


def test_benchmark_results_exists():
    """Test that the benchmark results file was created."""
    benchmark_file = "/home/user/benchmark_results.txt"
    assert os.path.isfile(benchmark_file), f"Benchmark results file {benchmark_file} is missing."
    with open(benchmark_file, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, "Benchmark results file is empty."


def test_predict_endpoint_auth():
    """Test that the endpoint requires authorization."""
    payload = {"data": [{"age": "25", "income": 50000.0, "category": "A"}]}
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the prediction service: {e}")
    assert response.status_code in [401, 403], f"Expected 401 or 403 for missing auth, got {response.status_code}"

    wrong = requests.post(URL, json=payload, headers={"Authorization": "Bearer wrong-token"}, timeout=2)
    assert wrong.status_code in [401, 403], "An incorrect bearer token was accepted"


def test_predict_endpoint_success():
    """Test that the endpoint returns predictions with valid auth and payload."""
    payload = {
        "data": [
            {"age": "25", "income": 50000.0, "category": "A"},
            {"age": "35", "income": 80000.0, "category": "B"}
        ]
    }
    try:
        response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the prediction service: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "predictions" in data, "Response JSON is missing the 'predictions' key."
    predictions = data["predictions"]
    assert isinstance(predictions, list), "Expected 'predictions' to be a list."
    assert len(predictions) > 0, "Expected at least one prediction in the list."


def test_endpoint_applies_cleaning_and_batch_inference():
    payload = {"data": [
        {"age": "22", "income": None, "category": "A"},
        {"age": "not-an-integer", "income": 70000.0, "category": "B"},
        {"age": "51", "income": 90000.0, "category": "previously-unseen"}
    ]}
    response = requests.post(URL, json=payload, headers=HEADERS, timeout=5)
    assert response.status_code == 200, response.text
    predictions = response.json().get("predictions")
    assert isinstance(predictions, list)
    assert len(predictions) == 2, "The invalid-age record was not dropped, or batch cardinality is wrong"
    assert all(p in (0, 1, False, True) for p in predictions), "Classifier predictions must be binary"


def test_fifty_concurrent_inference_requests():
    start = threading.Event()
    payloads = [
        {"data": [{"age": str(20 + i % 40), "income": None if i % 3 == 0 else 40000 + i * 100,
                   "category": ["A", "B", "C", "new-category"][i % 4]}]}
        for i in range(50)
    ]

    def send(payload):
        start.wait()
        r = requests.post(URL, json=payload, headers=HEADERS, timeout=15)
        return r.status_code, r.json()

    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as pool:
        futures = [pool.submit(send, p) for p in payloads]
        start.set()
        results = [f.result(timeout=20) for f in futures]

    assert len(results) == 50
    for status, body in results:
        assert status == 200
        assert isinstance(body.get("predictions"), list) and len(body["predictions"]) == 1


def test_live_service_used_required_pipeline_components():
    assert os.path.isfile("/tmp/pipeline_events.log"), "No live pipeline activity was observed"
    events = []
    with open("/tmp/pipeline_events.log") as f:
        for line in f:
            try:
                events.append(json.loads(line)["event"])
            except Exception:
                pass
    assert "enforce_age_schema" in events, "The live endpoint did not call the fixed datacleaner schema"
    assert "rf_predict" in events, "The live endpoint did not run RandomForestClassifier.predict"
    assert "get_dummies" in events or "onehot_transform" in events, "The live pipeline did not run one-hot encoding"
    assert "fillna" in events or "imputer_transform" in events, "The live pipeline did not run missing-income imputation"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
