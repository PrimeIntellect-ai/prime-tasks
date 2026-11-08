#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
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
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import numpy as np

ROOT = "/app/spatial_pipeline"
SOURCE = f"{ROOT}/worker/pde_worker.cpp"
WORKER = f"{ROOT}/worker/pde_worker"
API_SOURCE = f"{ROOT}/api/app.py"


def parse_vector(path):
    assert os.path.isfile(path), f"Output file not found at {path}."
    with open(path, "r") as f:
        content = f.read().strip()
    try:
        vector = np.array([float(x.strip()) for x in content.split(",") if x.strip()])
    except ValueError:
        assert False, "Output file does not contain a valid comma-separated list of floats."
    assert np.all(np.isfinite(vector)), "Output vector contains NaN or infinity."
    return vector


def post(payload, timeout=20):
    req = urllib.request.Request(
        "http://localhost:8080/analyze",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    return urllib.request.urlopen(req, timeout=timeout)


def test_required_sources_and_compiled_worker():
    assert os.path.isfile(SOURCE), "C++ worker source is missing."
    assert os.path.isfile(API_SOURCE), "Flask API source is missing."
    assert os.path.isfile(WORKER) and os.access(WORKER, os.X_OK), "Compiled worker is missing or not executable."
    with open(WORKER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pde_worker is not a compiled ELF executable."

    source = open(SOURCE, "r").read()
    compact = re.sub(r"\s+", "", source)
    assert re.search(r"#pragma\s+omp\s+parallel\s+for", source), "The spatial loop is not parallelized with OpenMP."
    assert "matrixU().col(0)" in compact, "The worker does not extract the first left singular vector."
    assert re.search(r"dx\*dx.{0,200}D", compact, re.S), "No CFL time-step calculation based on dx^2 and D was found."

    api_source = open(API_SOURCE, "r").read()
    assert "redis" in api_source.lower() and re.search(r"\.get\s*\(", api_source), "The API does not retrieve coefficients from Redis."
    assert "subprocess" in api_source and "/app/spatial_pipeline/worker/pde_worker" in api_source, "The API is not configured to invoke the worker."

    rebuilt = "/tmp/verifier_pde_worker"
    subprocess.run(
        ["g++", "-O3", "-fopenmp", SOURCE, "-o", rebuilt, "-I/usr/include/eigen3"],
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    symbols = subprocess.run(["nm", "-D", rebuilt], check=True, text=True, stdout=subprocess.PIPE).stdout
    assert "GOMP_" in symbols, "The rebuilt worker does not contain OpenMP parallel-runtime calls."

    direct_output = f"/tmp/direct_mode_{uuid.uuid4().hex}.txt"
    subprocess.run([rebuilt, "3.7", "0.002", direct_output], check=True, timeout=30)
    vector = parse_vector(direct_output)
    assert len(vector) == 100, f"Direct worker output has length {len(vector)}, expected 100."
    assert abs(np.linalg.norm(vector) - 1.0) < 1e-3, "Direct worker output is not a normalized singular vector."


def test_dynamic_redis_api_worker_path():
    ping = subprocess.run(["redis-cli", "ping"], check=True, text=True, stdout=subprocess.PIPE).stdout.strip()
    assert ping == "PONG", "Redis is not running on the expected local port."

    sequence_id = "VERIFY_" + uuid.uuid4().hex
    missing_id = "MISSING_" + uuid.uuid4().hex
    coefficient = "1.731"
    subprocess.run(["redis-cli", "set", sequence_id, coefficient], check=True, stdout=subprocess.PIPE)

    output_file = f"/home/user/output_mode_{sequence_id}.txt"
    if os.path.exists(output_file):
        os.remove(output_file)
    started = time.time()
    with post({"sequence_id": sequence_id, "time_end": 0.02}) as response:
        assert response.status == 200, f"Dynamic API request returned status {response.status}."
        body = json.loads(response.read().decode("utf-8"))
        assert body.get("status") == "success", "Dynamic API response did not report success."

    vector = parse_vector(output_file)
    assert len(vector) == 100, f"Dynamic request produced length {len(vector)}, expected 100."
    assert os.path.getmtime(output_file) >= started - 1, "Dynamic output was not freshly generated."
    assert abs(np.linalg.norm(vector) - 1.0) < 1e-3, "Dynamic output is not a normalized singular vector."

    try:
        with post({"sequence_id": missing_id, "time_end": 0.02}) as response:
            assert response.status == 404, "An ID absent from Redis was unexpectedly accepted."
    except urllib.error.HTTPError as exc:
        assert exc.code == 404, f"Unknown sequence returned {exc.code}, expected 404."


def test_pipeline_end_to_end():
    url = "http://localhost:8080/analyze"
    data = json.dumps({"sequence_id": "SEQ_99", "time_end": 10.0}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            assert response.status == 200, f"API returned status {response.status}"
    except Exception as e:
        assert False, f"Failed to trigger API at {url}: {e}"

    time.sleep(1)

    output_file = "/home/user/output_mode_SEQ_99.txt"
    assert os.path.isfile(output_file), f"Output file not found at {output_file}. Pipeline did not generate the expected file."

    with open(output_file, "r") as f:
        content = f.read().strip()

    try:
        agent_vector = np.array([float(x.strip()) for x in content.split(",") if x.strip()])
    except ValueError:
        assert False, "Output file does not contain a valid comma-separated list of floats."

    N = len(agent_vector)
    assert N > 1, f"Generated vector is too short (length {N})."
    assert N == 100, f"Generated vector has length {N}; the worker's configured grid requires 100 values."
    assert np.all(np.isfinite(agent_vector)), "Generated vector contains NaN or infinity."

    x = np.linspace(0, 1, N)
    truth_vector = np.sin(np.pi * x)
    truth_vector /= np.linalg.norm(truth_vector)

    if np.dot(agent_vector, truth_vector) < 0:
        truth_vector = -truth_vector

    mse = np.mean((agent_vector - truth_vector)**2)
    assert mse < 1e-4, f"Metric Threshold Failed: MSE {mse:.6e} is >= 1e-4. The computed spatial mode differs significantly from the analytical ground truth."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
