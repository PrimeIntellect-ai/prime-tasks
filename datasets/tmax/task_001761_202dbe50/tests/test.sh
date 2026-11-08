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
import json
import math
import os
import random
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

SERVER_GO = "/home/user/server.go"
COVARIANCE_FILE = "/home/user/covariance.txt"
BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer secret-token-99"}
EXPECTED_HEADER = ["CPU", "RAM", "Disk", "Network", "Failure"]
EXPECTED_ROWS = [
    [40.0, 4.0, 10.0, 50.0, 0.0],
    [90.0, 16.0, 80.0, 800.0, 1.0],
    [60.0, 8.0, 40.0, 200.0, 0.0],
    [85.0, 12.0, 60.0, 400.0, 1.0],
    [50.0, 8.0, 20.0, 100.0, 0.0],
]
EXPECTED_MATRIX = [
    [442.5000, 99.0000, 595.0000, 5875.0000],
    [99.0000, 22.4000, 134.0000, 1320.0000],
    [595.0000, 134.0000, 830.0000, 8150.0000],
    [5875.0000, 1320.0000, 8150.0000, 82500.0000],
]


def parse_expected_csv(path):
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > 100000:
            return False
        with open(path, newline="", encoding="utf-8-sig") as f:
            rows = list(csv.reader(f))
        if len(rows) != 6 or [x.strip() for x in rows[0]] != EXPECTED_HEADER:
            return False
        parsed = [[float(x.strip()) for x in row] for row in rows[1:]]
        return all(len(row) == 5 for row in parsed) and parsed == EXPECTED_ROWS
    except (OSError, UnicodeError, ValueError, csv.Error):
        return False


def find_extracted_csvs():
    matches = []
    for root in ("/home/user", "/app"):
        for directory, _, files in os.walk(root):
            for name in files:
                path = os.path.join(directory, name)
                if path in (SERVER_GO, COVARIANCE_FILE, "/app/data_table.png"):
                    continue
                if parse_expected_csv(path):
                    matches.append(path)
    return sorted(set(matches))


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            result.add(fields[9])
        except OSError:
            pass
    return result


def kill_port(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = set()
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
                    victims.add(int(pid))
                    break
        except OSError:
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def expected_prediction(payload):
    z = (0.05 * payload["CPU"] + 0.20 * payload["RAM"] +
         0.01 * payload["Disk"] + 0.001 * payload["Network"] - 5.0)
    probability = 1.0 / (1.0 + math.exp(-z))
    return probability, 1 if probability >= 0.5 else 0


def covariance(rows):
    features = [row[:4] for row in rows]
    n = len(features)
    means = [sum(row[j] for row in features) / n for j in range(4)]
    return [[sum((row[i] - means[i]) * (row[j] - means[j]) for row in features) / (n - 1)
             for j in range(4)] for i in range(4)]


def read_covariance():
    with open(COVARIANCE_FILE) as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 4, "Covariance matrix should have exactly 4 lines"
    matrix = []
    for i, line in enumerate(lines):
        values = line.split(",")
        assert len(values) == 4, f"Line {i + 1} does not have 4 values"
        assert all(re.fullmatch(r"[-+]?\d+\.\d{4}", value) for value in values), \
            f"Line {i + 1} contains a value not formatted to exactly 4 decimal places"
        matrix.append([float(value) for value in values])
    return matrix


class Runtime:
    def __init__(self):
        self.process = None
        self.log = open("/tmp/submission-server.log", "ab", buffering=0)

    def stop(self):
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        self.process = None
        kill_port(8080)

    def start(self):
        self.stop()
        self.process = subprocess.Popen(
            ["/tmp/submission-server"], cwd="/home/user",
            stdout=self.log, stderr=subprocess.STDOUT
        )
        deadline = time.time() + 8
        last_error = None
        while time.time() < deadline:
            if self.process.poll() is not None:
                pytest.fail(f"Compiled server exited with status {self.process.returncode}")
            try:
                response = requests.get(f"{BASE_URL}/accuracy", headers=AUTH_HEADER, timeout=0.4)
                if response.status_code == 200:
                    return
            except requests.RequestException as exc:
                last_error = exc
            time.sleep(0.1)
        pytest.fail(f"Compiled server did not listen on 127.0.0.1:8080: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def submission_runtime():
    assert os.path.isfile(SERVER_GO), f"Go source not found at {SERVER_GO}"
    assert os.path.getsize(SERVER_GO) > 0, f"Go source at {SERVER_GO} is empty"
    build = subprocess.run(
        ["go", "build", "-o", "/tmp/submission-server", SERVER_GO],
        cwd="/home/user", text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=30
    )
    assert build.returncode == 0, f"server.go does not compile:\n{build.stdout}"
    csv_paths = find_extracted_csvs()
    assert csv_paths, "No valid extracted CSV containing the OCR table was found"
    runtime = Runtime()
    runtime.start()
    yield runtime, csv_paths
    runtime.stop()
    runtime.log.close()


def test_extracted_csv(submission_runtime):
    _, paths = submission_runtime
    assert any(parse_expected_csv(path) for path in paths), "Extracted CSV is missing or invalid"


def test_covariance_matrix(submission_runtime):
    assert os.path.exists(COVARIANCE_FILE), f"Covariance file not found at {COVARIANCE_FILE}"
    matrix = read_covariance()
    for i in range(4):
        for j in range(4):
            assert math.isclose(matrix[i][j], EXPECTED_MATRIX[i][j], rel_tol=1e-4), \
                f"Mismatch at row {i + 1}, col {j + 1}: expected {EXPECTED_MATRIX[i][j]}, got {matrix[i][j]}"


def test_accuracy_endpoint(submission_runtime):
    response = requests.get(f"{BASE_URL}/accuracy", headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "accuracy" in data, "Response JSON missing 'accuracy' key"
    assert math.isclose(data["accuracy"], 0.8, rel_tol=1e-4), \
        f"Expected accuracy 0.8, got {data['accuracy']}"


def assert_prediction(payload, abs_tol=1e-6):
    response = requests.post(f"{BASE_URL}/predict", headers=AUTH_HEADER, json=payload, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "probability" in data, "Response JSON missing 'probability' key"
    assert "class" in data, "Response JSON missing 'class' key"
    expected_prob, expected_class = expected_prediction(payload)
    assert math.isclose(data["probability"], expected_prob, abs_tol=abs_tol), \
        f"Expected probability {expected_prob}, got {data['probability']} for {payload}"
    assert data["class"] == expected_class, \
        f"Expected class {expected_class}, got {data['class']} for {payload}"


def test_predict_endpoint(submission_runtime):
    payload = {"CPU": 40.0, "RAM": 4.0, "Disk": 10.0, "Network": 50.0}
    assert_prediction(payload, abs_tol=1e-3)


def test_predict_varied_inputs(submission_runtime):
    payloads = [
        {"CPU": 0.0, "RAM": 0.0, "Disk": 0.0, "Network": 0.0},
        {"CPU": 100.0, "RAM": 0.0, "Disk": 0.0, "Network": 0.0},
        {"CPU": 1.25, "RAM": 31.5, "Disk": 99.75, "Network": 999.0},
    ]
    rng = random.SystemRandom()
    for _ in range(12):
        payloads.append({
            "CPU": rng.uniform(0, 100),
            "RAM": rng.uniform(0, 32),
            "Disk": rng.uniform(0, 100),
            "Network": rng.uniform(0, 1000),
        })
    for payload in payloads:
        assert_prediction(payload)


def test_security_unauthorized_and_wrong_token(submission_runtime):
    payload = {"CPU": 40.0, "RAM": 4.0, "Disk": 10.0, "Network": 50.0}
    for headers in ({}, {"Authorization": "Bearer wrong-token"},
                    {"Authorization": "secret-token-99"}):
        responses = [
            requests.get(f"{BASE_URL}/accuracy", headers=headers, timeout=5),
            requests.post(f"{BASE_URL}/predict", headers=headers, json=payload, timeout=5),
        ]
        for response in responses:
            assert response.status_code == 401, \
                f"Expected 401 Unauthorized with headers {headers}, got {response.status_code}"


def test_server_reads_csv_and_recomputes_outputs(submission_runtime):
    runtime, csv_paths = submission_runtime
    changed_rows = [
        [0.0, 0.0, 0.0, 0.0, 1.0],
        [10.0, 20.0, 30.0, 40.0, 1.0],
        [20.0, 10.0, 50.0, 80.0, 1.0],
        [40.0, 30.0, 20.0, 10.0, 0.0],
        [100.0, 5.0, 70.0, 500.0, 0.0],
    ]
    backups = {path: open(path, "rb").read() for path in csv_paths}
    try:
        runtime.stop()
        text = ",".join(EXPECTED_HEADER) + "\n"
        text += "\n".join(",".join(str(value) for value in row) for row in changed_rows) + "\n"
        for path in csv_paths:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(text)
        try:
            os.remove(COVARIANCE_FILE)
        except FileNotFoundError:
            pass
        runtime.start()

        deadline = time.time() + 5
        while not os.path.exists(COVARIANCE_FILE) and time.time() < deadline:
            time.sleep(0.05)
        assert os.path.exists(COVARIANCE_FILE), "Server did not regenerate covariance.txt from changed CSV"
        actual_cov = read_covariance()
        expected_cov = covariance(changed_rows)
        for i in range(4):
            for j in range(4):
                assert math.isclose(actual_cov[i][j], expected_cov[i][j], abs_tol=5e-4), \
                    f"Covariance was not recomputed from CSV at row {i + 1}, col {j + 1}"

        response = requests.get(f"{BASE_URL}/accuracy", headers=AUTH_HEADER, timeout=5)
        assert response.status_code == 200
        predicted = [expected_prediction(dict(zip(EXPECTED_HEADER[:4], row[:4])))[1]
                     for row in changed_rows]
        expected_accuracy = sum(predicted[i] == int(changed_rows[i][4])
                                for i in range(len(changed_rows))) / len(changed_rows)
        assert math.isclose(response.json()["accuracy"], expected_accuracy, abs_tol=1e-9), \
            "Accuracy was not recomputed from the changed CSV"
    finally:
        runtime.stop()
        for path, content in backups.items():
            with open(path, "wb") as f:
                f.write(content)
        try:
            os.remove(COVARIANCE_FILE)
        except FileNotFoundError:
            pass
        runtime.start()

    restored = read_covariance()
    for i in range(4):
        for j in range(4):
            assert math.isclose(restored[i][j], EXPECTED_MATRIX[i][j], rel_tol=1e-4)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
