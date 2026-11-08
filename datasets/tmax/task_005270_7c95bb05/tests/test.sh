#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import select
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import h5py
import numpy as np
import pytest
from dotenv import dotenv_values

SCRIPT_PATH = "/home/user/filter.py"
NGINX_CONF = "/home/user/config/nginx.conf"
ENV_FILE = "/home/user/config/.env"


def run_filter(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )


def test_filter_script_exists():
    assert os.path.exists(SCRIPT_PATH), "filter.py script is missing"
    assert os.path.isfile(SCRIPT_PATH), "filter.py is not a regular file"


def test_filter_script_classification():
    clean_dir = "/home/user/data/clean"
    evil_dir = "/home/user/data/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.h5')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.h5')]

    clean_failed = []
    evil_failed = []

    for fpath in clean_files:
        res = run_filter(fpath)
        if res.returncode != 0 or res.stdout.strip() != "ACCEPT":
            clean_failed.append(os.path.basename(fpath))

    for fpath in evil_files:
        res = run_filter(fpath)
        if res.returncode != 0 or res.stdout.strip() != "REJECT":
            evil_failed.append(os.path.basename(fpath))

    err_msgs = []
    if evil_failed:
        err_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        err_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}")
    if err_msgs:
        pytest.fail(" | ".join(err_msgs))


def test_filter_on_hidden_mixed_corpus():
    rng = np.random.default_rng(730291)
    cases = []

    # Labels are derived from the actual largest singular value. All files share
    # one neutral directory and randomized names, so their paths reveal nothing.
    for i in range(10):
        rows = int(rng.integers(24, 65))
        cols = int(rng.integers(20, 61))
        if i % 2 == 0:
            matrix = rng.normal(0.0, 0.035, size=(rows, cols))
        else:
            left = rng.normal(size=rows)
            right = rng.normal(size=cols)
            left /= np.linalg.norm(left)
            right /= np.linalg.norm(right)
            matrix = 18.0 * np.outer(left, right) + rng.normal(0.0, 0.01, size=(rows, cols))

        largest = float(np.linalg.svd(matrix, compute_uv=False)[0])
        assert largest < 10.0 or largest > 15.0
        expected = "ACCEPT" if largest < 10.0 else "REJECT"
        cases.append((matrix, expected))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="sequence-corpus-") as corpus:
        paths = []
        for matrix, expected in cases:
            path = os.path.join(corpus, f"sample-{uuid.uuid4().hex}.h5")
            with h5py.File(path, "w") as h5:
                h5.create_dataset("/quality_scores", data=matrix)
            paths.append((path, expected))

        for path, expected in paths:
            result = run_filter(path)
            assert result.returncode == 0, f"filter exited {result.returncode} for a valid HDF5 input: {result.stderr}"
            assert result.stdout.strip() == expected, f"wrong classification for neutral hidden input {os.path.basename(path)}"


def _without_comments(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def _location_block(text, route):
    text = _without_comments(text)
    pattern = re.compile(
        r"location\s+(?:(?:\^~|=|~\*?|@\w+)\s+)?" + re.escape(route) + r"(?=\s|\{)[^{]*\{",
        re.IGNORECASE,
    )
    match = pattern.search(text)
    assert match, f"nginx.conf has no location block for {route}"
    start = text.find("{", match.start())
    depth = 0
    for pos in range(start, len(text)):
        if text[pos] == "{":
            depth += 1
        elif text[pos] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:pos]
    pytest.fail(f"unterminated nginx location block for {route}")


def test_nginx_config_fixed():
    assert os.path.exists(NGINX_CONF), "nginx.conf is missing"
    with open(NGINX_CONF, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "proxy_pass http://localhost:5000" in content or "proxy_pass http://127.0.0.1:5000" in content, \
        "nginx.conf does not route /api/upload to port 5000"
    assert "proxy_pass http://localhost:5001" in content or "proxy_pass http://127.0.0.1:5001" in content, \
        "nginx.conf does not route /api/align to port 5001"

    upload_block = _location_block(content, "/api/upload")
    align_block = _location_block(content, "/api/align")
    assert re.search(r"proxy_pass\s+http://(?:localhost|127\.0\.0\.1):5000(?:/[^;\s]*)?\s*;", upload_block), \
        "/api/upload location does not proxy to the ingestion API on port 5000"
    assert re.search(r"proxy_pass\s+http://(?:localhost|127\.0\.0\.1):5001(?:/[^;\s]*)?\s*;", align_block), \
        "/api/align location does not proxy to the alignment worker on port 5001"

    checked = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True, timeout=10
    )
    assert checked.returncode == 0, f"nginx configuration is invalid: {checked.stderr}"


def test_env_config_fixed():
    assert os.path.exists(ENV_FILE), ".env is missing"
    with open(ENV_FILE, "r") as f:
        content = f.read()

    # Preserve the original assertion and also parse the effective value.
    assert "REDIS_PORT=6379" in content, ".env does not contain REDIS_PORT=6379"
    values = dotenv_values(ENV_FILE)
    assert values.get("REDIS_PORT") == "6379", "effective REDIS_PORT is not 6379"


def _request(url, data=None, method=None, headers=None):
    request = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    return urllib.request.urlopen(request, timeout=5)


def test_services_running_and_end_to_end_behavior():
    try:
        with _request("http://localhost:8080/api/align/status") as response:
            body = response.read()
            assert response.status == 200, "Align status endpoint did not return HTTP 200"
            assert json.loads(body.decode("utf-8")) == {"status": "listening"}, \
                "Align status endpoint returned the wrong JSON body"
    except (urllib.error.URLError, ValueError) as exc:
        pytest.fail(f"Failed to validate align status endpoint: {exc}")

    # Observe Redis while a real HDF5 payload is uploaded. Monitoring catches the
    # enqueue operation even if a worker immediately removes the queued item.
    monitor = subprocess.Popen(
        ["redis-cli", "-p", "6379", "MONITOR"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    try:
        ready, _, _ = select.select([monitor.stdout], [], [], 3)
        assert ready, "could not start Redis MONITOR"
        first_line = monitor.stdout.readline()
        assert "OK" in first_line, f"Redis MONITOR failed to start: {first_line}"

        with tempfile.NamedTemporaryFile(suffix=".h5") as payload_file:
            with h5py.File(payload_file.name, "w") as h5:
                h5.create_dataset("/quality_scores", data=np.eye(12, dtype=float) * 0.25)
            with open(payload_file.name, "rb") as source:
                payload = source.read()

        try:
            with _request(
                "http://localhost:8080/api/upload",
                data=payload,
                method="POST",
                headers={"Content-Type": "application/x-hdf5"},
            ) as response:
                response.read()
                assert response.status == 200, "Upload endpoint did not return HTTP 200"
        except urllib.error.URLError as exc:
            pytest.fail(f"Failed to connect to upload endpoint: {exc}")

        time.sleep(0.75)
    finally:
        monitor.terminate()
        try:
            output, errors = monitor.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            monitor.kill()
            output, errors = monitor.communicate()

    queue_commands = re.findall(r'"(LPUSH|RPUSH|XADD|SADD|ZADD)"', output, flags=re.IGNORECASE)
    assert queue_commands, \
        f"upload returned successfully but no Redis enqueue operation was observed. Monitor output: {output} {errors}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
