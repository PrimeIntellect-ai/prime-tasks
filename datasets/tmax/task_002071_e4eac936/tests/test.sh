#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /app/data/historical_metrics.csv /tmp/historical_metrics.csv.verifier-backup
cp /app/audio/eval_sample.wav /tmp/eval_sample.wav.verifier-backup
restore_inputs() {
    cp /tmp/historical_metrics.csv.verifier-backup /app/data/historical_metrics.csv
    cp /tmp/eval_sample.wav.verifier-backup /app/audio/eval_sample.wav
}
trap restore_inputs EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import signal
import subprocess
import time

import pytest
import requests

CSV_PATH = "/app/data/historical_metrics.csv"
AUDIO_PATH = "/app/audio/eval_sample.wav"
SERVER_PATH = "/home/user/server"
URL = "http://127.0.0.1:8080/metrics"


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    if inodes:
        for name in os.listdir("/proc"):
            if not name.isdigit() or int(name) == os.getpid():
                continue
            fd_dir = f"/proc/{name}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                    except OSError:
                        continue
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        pids.add(int(name))
                        break
            except OSError:
                continue

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.2)


def expected_metrics():
    xs, ys = [], []
    with open(CSV_PATH, newline="") as f:
        for row in csv.DictReader(f):
            xs.append(float(row["inference_time_ms"]))
            ys.append(float(row["accuracy"]))

    assert len(xs) >= 2, "CSV must contain at least two data rows"
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    denominator = math.sqrt(
        sum((x - mean_x) ** 2 for x in xs)
        * sum((y - mean_y) ** 2 for y in ys)
    )
    assert denominator != 0, "CSV has zero variance"
    correlation = numerator / denominator

    size = os.path.getsize(AUDIO_PATH)
    if size > 1_000_000:
        posterior = (0.6 * 0.8) / (0.6 * 0.8 + 0.4 * 0.3)
    else:
        posterior = (0.6 * 0.2) / (0.6 * 0.2 + 0.4 * 0.7)
    return correlation, posterior, size


def start_and_query():
    kill_port_8080()
    proc = subprocess.Popen(
        [SERVER_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    response = None
    last_error = None
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                response = requests.get(URL, timeout=1)
                break
            except requests.exceptions.RequestException as exc:
                last_error = exc
                time.sleep(0.1)
        if response is None:
            pytest.fail(f"Failed to connect to the server started from {SERVER_PATH}: {last_error}")
        return response
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)
        kill_port_8080()


def check_response(response, expected):
    correlation, posterior, size = expected
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type: application/json, got {content_type}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Body: {response.text}")

    assert "correlation" in data, "Missing 'correlation' in JSON response"
    assert "posterior" in data, "Missing 'posterior' in JSON response"
    assert "file_size" in data, "Missing 'file_size' in JSON response"

    assert abs(data["correlation"] - correlation) < 0.0001, (
        f"Expected correlation approx {correlation:.4f}, got {data['correlation']}"
    )
    assert abs(data["posterior"] - posterior) < 0.0001, (
        f"Expected posterior approx {posterior:.4f}, got {data['posterior']}"
    )
    assert data["file_size"] == size, f"Expected file_size {size}, got {data['file_size']}"

    text = response.text.strip()
    correlation_token = re.search(r'"correlation"\s*:\s*(-?\d+\.\d{4})(?=\s*[,}])', text)
    posterior_token = re.search(r'"posterior"\s*:\s*(-?\d+\.\d{4})(?=\s*[,}])', text)
    assert correlation_token, "Correlation value is not formatted to exactly 4 decimal places"
    assert posterior_token, "Posterior value is not formatted to exactly 4 decimal places"
    assert correlation_token.group(1) == f"{correlation:.4f}", "Incorrect formatted correlation"
    assert posterior_token.group(1) == f"{posterior:.4f}", "Incorrect formatted posterior"


def test_source_and_binary_exist():
    assert os.path.isfile("/home/user/metric_server.c"), "C source code /home/user/metric_server.c is missing"
    assert os.path.isfile(SERVER_PATH), "Compiled binary /home/user/server is missing"
    assert os.access(SERVER_PATH, os.X_OK), "Compiled binary is not executable"
    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/server is not a compiled ELF executable"


def test_http_server_response_and_input_processing():
    # First execute the submitted binary against the supplied artifacts.
    check_response(start_and_query(), expected_metrics())

    # Replace both inputs with verifier-generated values, then restart the same
    # executable. This prevents a server with the setup constants hardcoded from passing.
    while True:
        xs = [70 + i * 31 + secrets.randbelow(17) for i in range(7)]
        ys = [0.55 + secrets.randbelow(4400) / 10000.0 for _ in range(7)]
        mx = sum(xs) / len(xs)
        my = sum(ys) / len(ys)
        den = math.sqrt(sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys))
        if den:
            corr = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den
            if abs(corr - (-0.9956)) > 0.01:
                break

    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["run_id", "inference_time_ms", "accuracy"])
        for i, (x, y) in enumerate(zip(xs, ys), 1):
            writer.writerow([i, x, f"{y:.4f}"])

    dynamic_size = 100_000 + secrets.randbelow(800_001)
    with open(AUDIO_PATH, "wb") as f:
        f.truncate(dynamic_size)

    check_response(start_and_query(), expected_metrics())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
