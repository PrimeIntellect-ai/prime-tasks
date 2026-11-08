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
import csv
import os
import random
import secrets
import signal
import subprocess
import time
import uuid

import pytest
import redis
import requests

API_URL = "http://127.0.0.1:5000/ingest"
OUTPUT_DIR = "/home/user/output"
WORKER_SOURCE = "/home/user/worker/main.go"
WORKER_BINARY = "/home/user/worker_bin"


def running_worker_pids():
    pids = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{name}/exe")
            if exe == os.path.realpath(WORKER_BINARY):
                pids.append(int(name))
        except OSError:
            pass
    return pids


def post_file(filepath):
    try:
        response = requests.post(API_URL, json={"filepath": filepath}, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(
            f"API request failed for {filepath}. Is the Flask API running and correctly configured? Error: {exc}"
        )
    assert response.status_code == 200, f"Failed to POST {filepath}, status {response.status_code}"


def read_labeled_points():
    with open("/app/labeled_sensor_data.csv", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["v1", "v2", "v3", "label"]
        rows = list(reader)
    clean = [[float(row[k]) for k in ("v1", "v2", "v3")] for row in rows if int(row["label"]) == 0]
    evil = [[float(row[k]) for k in ("v1", "v2", "v3")] for row in rows if int(row["label"]) == 1]
    assert clean and evil
    return clean, evil


def convex_rows(points, count, rng):
    # Convex combinations of same-label examples retain their label under the
    # linear classifier described by the task, while producing unseen values.
    result = []
    for _ in range(count):
        weights = [rng.random() + 0.01 for _ in points]
        total = sum(weights)
        row = []
        for column in range(3):
            row.append(sum(w * p[column] for w, p in zip(weights, points)) / total)
        result.append(row)
    rng.shuffle(result)
    return result


def write_csv(path, rows):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["v1", "v2", "v3"])
        for row in rows:
            writer.writerow([format(value, ".12g") for value in row])


def test_pipeline_adversarial_corpus():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} not found."
    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} not found."
    assert os.path.exists(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} not found."

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]

    # Verify the required worker artifact is a compiled Go executable and that
    # this exact executable is currently running.
    assert os.path.isfile(WORKER_SOURCE), f"Worker source {WORKER_SOURCE} not found"
    with open(WORKER_SOURCE, errors="replace") as handle:
        source = handle.read()
    assert "package main" in source, "Worker source is not a Go main package"
    assert os.path.isfile(WORKER_BINARY), f"Worker binary {WORKER_BINARY} not found"
    assert os.access(WORKER_BINARY, os.X_OK), "Worker binary is not executable"
    with open(WORKER_BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Worker binary is not an ELF executable"
    version = subprocess.run(
        ["go", "version", "-m", WORKER_BINARY], capture_output=True, text=True, timeout=5
    )
    assert version.returncode == 0, "worker_bin is not a compiled Go executable"
    worker_pids = running_worker_pids()
    assert worker_pids, "The compiled Go worker is not running"

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=2)
    assert client.ping(), "Redis is not running on the default port 6379"

    # Build unpredictable, verifier-time inputs. Expected labels are derived
    # from the supplied labeled data: convex combinations cannot cross a linear
    # separating boundary.
    clean_points, evil_points = read_labeled_points()
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    dynamic_dir = f"/tmp/pipeline-verifier-{uuid.uuid4().hex}"
    os.makedirs(dynamic_dir)
    dynamic_clean_name = f"clean-{uuid.uuid4().hex}.csv"
    dynamic_evil_name = f"evil-{uuid.uuid4().hex}.csv"
    dynamic_clean = os.path.join(dynamic_dir, dynamic_clean_name)
    dynamic_evil = os.path.join(dynamic_dir, dynamic_evil_name)
    write_csv(dynamic_clean, convex_rows(clean_points, 17, rng))
    write_csv(dynamic_evil, convex_rows(evil_points, 17, rng))

    evil_inputs = [os.path.join(evil_dir, f) for f in evil_files] + [dynamic_evil]
    clean_inputs = [os.path.join(clean_dir, f) for f in clean_files] + [dynamic_clean]
    all_inputs = evil_inputs + clean_inputs

    # Remove any pre-created outputs. Pause the actual worker and prove that the
    # API places the submitted path into Redis rather than merely returning 200.
    for pid in worker_pids:
        os.kill(pid, signal.SIGSTOP)
    try:
        client.delete("processing_queue")
        for path in all_inputs:
            out_path = os.path.join(OUTPUT_DIR, os.path.basename(path))
            try:
                os.remove(out_path)
            except FileNotFoundError:
                pass

        post_file(dynamic_clean)
        deadline = time.time() + 2
        queued = []
        while time.time() < deadline:
            queued = [value.decode() for value in client.lrange("processing_queue", 0, -1)]
            if dynamic_clean in queued:
                break
            time.sleep(0.05)
        assert dynamic_clean in queued, "The Flask API did not push the filepath to processing_queue"
    finally:
        for pid in worker_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass

    # Send the original fixed corpora as before, plus the unpredictable evil
    # input. The dynamic clean input was already submitted during the queue test.
    for path in evil_inputs:
        post_file(path)
    for path in clean_inputs:
        if path != dynamic_clean:
            post_file(path)

    expected_names = {os.path.basename(path) for path in all_inputs}
    timeout = 10
    start_time = time.time()
    while time.time() - start_time < timeout:
        output_files = set(os.listdir(OUTPUT_DIR))
        if expected_names.issubset(output_files):
            break
        time.sleep(0.5)

    # Verify evil files are rejected (only the original header remains).
    evil_bypassed = []
    for in_path in evil_inputs:
        name = os.path.basename(in_path)
        out_path = os.path.join(OUTPUT_DIR, name)
        if not os.path.exists(out_path):
            evil_bypassed.append(f"{name} (missing output)")
            continue
        with open(in_path, newline="") as fin, open(out_path, newline="") as fout:
            input_rows = list(csv.reader(fin))
            output_rows = list(csv.reader(fout))
        if not output_rows or output_rows[0] != input_rows[0] or len(output_rows) != 1:
            evil_bypassed.append(name)

    # Verify clean files are perfectly preserved.
    clean_modified = []
    for in_path in clean_inputs:
        name = os.path.basename(in_path)
        out_path = os.path.join(OUTPUT_DIR, name)
        if not os.path.exists(out_path):
            clean_modified.append(f"{name} (missing output)")
            continue
        with open(in_path, newline="") as fin, open(out_path, newline="") as fout:
            in_rows = list(csv.reader(fin))
            out_rows = list(csv.reader(fout))
        if in_rows != out_rows:
            clean_modified.append(name)

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_inputs)} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_inputs)} clean modified: {', '.join(clean_modified)}"
        )
    if errors:
        pytest.fail(" | ".join(errors))

    assert running_worker_pids(), "The compiled Go worker stopped running during verification"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
