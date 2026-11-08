#!/bin/bash
mkdir -p /logs/verifier

# Run the provided launcher, then restart the submitted Flask artifact under a
# verifier-controlled Nginx configuration so stale or fabricated services
# cannot satisfy the live integration checks.
bash /home/user/portal/start_services.sh >/tmp/verifier_start_services.log 2>&1 || true
pkill -f 'python3 /home/user/portal/app.py' >/dev/null 2>&1 || true
pkill -x nginx >/dev/null 2>&1 || true
sleep 1
redis-server --port 6379 --daemonize yes >/dev/null 2>&1 || true
cat > /tmp/verifier_nginx.conf <<'NGINX_EOF'
pid /tmp/verifier_nginx.pid;
events {}
http {
    server {
        listen 8080;
        location /datasets/ {
            alias /home/user/portal/static/datasets/;
        }
    }
}
NGINX_EOF
nginx -c /tmp/verifier_nginx.conf >/tmp/verifier_nginx.log 2>&1 || true
nohup python3 /home/user/portal/app.py >/tmp/verifier_flask.log 2>&1 &

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import zipfile

import numpy as np
import pandas as pd
import pytest
import redis


def test_app_py_fixed():
    """Verify that the Flask app configuration has been corrected."""
    app_path = "/home/user/portal/app.py"
    assert os.path.exists(app_path), f"File missing: {app_path}"

    with open(app_path, "r") as f:
        content = f.read()

    assert "6379" in content, "app.py does not contain the corrected Redis port (6379)."
    assert "6380" not in content, "app.py still contains the incorrect Redis port (6380)."
    assert "http://127.0.0.1:8080/datasets/" in content, "app.py does not contain the corrected Nginx URL (http://127.0.0.1:8080/datasets/)."


def test_integration_log():
    """Verify that the integration test was run and produced the expected JSON output."""
    log_path = "/home/user/integration_test.log"
    assert os.path.exists(log_path), f"Integration test log missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content, "Integration test log is empty."
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"integration_test.log does not contain valid JSON. Content: {content}")

    assert data.get("returncode") == 0, f"Expected returncode 0 in integration log, got: {data.get('returncode')}"
    assert data.get("status") == "CLEAN", f"Expected status 'CLEAN' in integration log, got: {data.get('status')}"


def run_sanitizer(directory):
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Sanitizer script missing at {sanitizer_path}"
    result = subprocess.run(
        [sys.executable, sanitizer_path, directory],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return result.stdout.strip(), result.returncode


def test_sanitizer_adversarial_corpus():
    """Verify the sanitizer against the original adversarial corpus."""
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.exists(sanitizer_path), f"Sanitizer script missing at {sanitizer_path}"

    clean_dirs = glob.glob("/home/user/corpora/clean/*")
    evil_dirs = glob.glob("/home/user/corpora/evil/*")

    assert len(clean_dirs) > 0, "No clean datasets found in /home/user/corpora/clean/"
    assert len(evil_dirs) > 0, "No evil datasets found in /home/user/corpora/evil/"

    clean_failures = []
    evil_failures = []
    for directory in clean_dirs:
        output, code = run_sanitizer(directory)
        if output != "CLEAN" or code != 0:
            clean_failures.append(os.path.basename(directory))
    for directory in evil_dirs:
        output, code = run_sanitizer(directory)
        if output != "LEAK_DETECTED" or code != 1:
            evil_failures.append(os.path.basename(directory))

    messages = []
    if evil_failures:
        messages.append(f"{len(evil_failures)} of {len(evil_dirs)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        messages.append(f"{len(clean_failures)} of {len(clean_dirs)} clean modified/rejected: {', '.join(clean_failures)}")
    if messages:
        pytest.fail(" | ".join(messages))


def make_frames(kind, seed):
    rng = np.random.default_rng(seed)
    n = 64

    # Regenerate ordinary data until all correlations are comfortably below
    # the specified threshold, so expected results are derived from contents.
    while True:
        f1 = rng.normal(size=n)
        f2 = rng.normal(size=n)
        target = rng.normal(size=n)
        if max(abs(np.corrcoef(f1, target)[0, 1]), abs(np.corrcoef(f2, target)[0, 1])) < 0.75:
            break

    train = pd.DataFrame({
        "id": rng.permutation(np.arange(1000, 1000 + n)),
        "f1": f1,
        "f2": f2,
        "category": [f"g{i % 5}" for i in rng.permutation(n)],
        "target": target,
    })
    test = pd.DataFrame({
        "id": np.arange(9000, 9032),
        "f1": rng.normal(loc=7.0, size=32),
        "f2": rng.normal(loc=-6.0, size=32),
        "category": [f"h{i % 4}" for i in range(32)],
    })

    if kind == "overlap":
        source = int(rng.integers(0, n))
        for column in ("f1", "f2", "category"):
            test.loc[0, column] = train.loc[source, column]
    elif kind == "correlation":
        train["derived_measure"] = train["target"] * 3.7 - 2.0
        test["derived_measure"] = rng.normal(size=len(test))
    elif kind == "missing_correlation":
        train["derived_measure"] = train["target"] * -4.0 + 1.0
        missing = rng.choice(n, size=11, replace=False)
        train.loc[missing, "derived_measure"] = np.nan
        train.loc[missing[:5], "target"] = np.nan
        test["derived_measure"] = rng.normal(size=len(test))
    elif kind == "missing_clean":
        train.loc[rng.choice(n, size=8, replace=False), "f1"] = np.nan
        train.loc[rng.choice(n, size=7, replace=False), "target"] = np.nan
        test.loc[rng.choice(len(test), size=5, replace=False), "f2"] = np.nan
    elif kind == "ignored_columns_only":
        test["target"] = rng.normal(size=len(test))
        test.loc[0, "id"] = train.loc[0, "id"]
        test.loc[0, "target"] = train.loc[0, "target"]
    elif kind != "clean":
        raise ValueError(kind)

    return train, test


def write_dataset(directory, train, test):
    os.makedirs(directory, exist_ok=True)
    train.to_csv(os.path.join(directory, "train.csv"), index=False)
    test.to_csv(os.path.join(directory, "test.csv"), index=False)


def test_sanitizer_randomized_content_cases():
    expected_by_kind = {
        "clean": ("CLEAN", 0),
        "missing_clean": ("CLEAN", 0),
        "ignored_columns_only": ("CLEAN", 0),
        "overlap": ("LEAK_DETECTED", 1),
        "correlation": ("LEAK_DETECTED", 1),
        "missing_correlation": ("LEAK_DETECTED", 1),
    }
    kinds = list(expected_by_kind)
    np.random.default_rng(secrets.randbits(64)).shuffle(kinds)

    with tempfile.TemporaryDirectory(prefix="curator-check-") as root:
        for kind in kinds:
            directory = os.path.join(root, secrets.token_hex(10))
            train, test = make_frames(kind, secrets.randbits(32))
            write_dataset(directory, train, test)
            actual = run_sanitizer(directory)
            assert actual == expected_by_kind[kind], f"Incorrect result for generated {kind} data: {actual}"


def curl_json(dataset_id):
    payload = json.dumps({"dataset_id": dataset_id})
    last_error = None
    for _ in range(40):
        result = subprocess.run(
            ["curl", "-sS", "-X", "POST", "http://127.0.0.1:5000/analyze",
             "-H", "Content-Type: application/json", "-d", payload],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError as exc:
                last_error = f"invalid JSON: {result.stdout!r} ({exc})"
        else:
            last_error = result.stderr
        time.sleep(0.25)
    pytest.fail(f"Flask API did not return valid JSON: {last_error}")


def install_zip(dataset_id, train, test):
    static_dir = "/home/user/portal/static/datasets"
    os.makedirs(static_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        write_dataset(directory, train, test)
        destination = os.path.join(static_dir, dataset_id + ".zip")
        with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.write(os.path.join(directory, "train.csv"), "train.csv")
            archive.write(os.path.join(directory, "test.csv"), "test.csv")


def test_live_end_to_end_api_and_redis():
    # Confirm the submitted app is genuinely running and reproduces the saved
    # curl result for the supplied sample.
    sample_result = curl_json("test_sample")
    assert sample_result.get("status") == "CLEAN"
    assert sample_result.get("returncode") == 0
    with open("/home/user/integration_test.log", "r") as stream:
        assert json.load(stream) == sample_result

    assignments = [("clean", ("CLEAN", 0))]
    assignments.append((secrets.choice(["overlap", "correlation"]), ("LEAK_DETECTED", 1)))
    np.random.default_rng(secrets.randbits(64)).shuffle(assignments)

    rdb = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    assert rdb.ping(), "Redis is not reachable on port 6379"

    for kind, (expected_status, expected_code) in assignments:
        dataset_id = secrets.token_hex(12)
        train, test = make_frames(kind, secrets.randbits(32))
        install_zip(dataset_id, train, test)
        result = curl_json(dataset_id)
        assert result.get("status") == expected_status, (kind, result)
        assert result.get("returncode") == expected_code, (kind, result)
        assert rdb.get(f"status:{dataset_id}") == expected_status

    missing_id = secrets.token_hex(12)
    payload = json.dumps({"dataset_id": missing_id})
    result = subprocess.run(
        ["curl", "-sS", "-o", "/tmp/verifier_missing_response", "-w", "%{http_code}",
         "-X", "POST", "http://127.0.0.1:5000/analyze",
         "-H", "Content-Type: application/json", "-d", payload],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0
    assert result.stdout == "404", f"Missing Nginx dataset should produce HTTP 404, got {result.stdout}"
    with open("/tmp/verifier_missing_response", "r") as stream:
        assert json.load(stream).get("error") == "dataset not found on nginx"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
