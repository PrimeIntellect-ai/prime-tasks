#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import re
import subprocess

import pytest
import requests

URL = "http://localhost:8080/predict"
AUTH = {"Authorization": "Bearer chem-sim-2024"}
EXPECTED_ROWS = [(0.0, 100.00), (1.0, 60.65), (2.0, 36.79), (3.0, 22.31)]


def read_structured_csv():
    csv_path = "/home/user/extracted_data.csv"
    assert os.path.isfile(csv_path), f"Extracted CSV not found at {csv_path}"

    with open(csv_path, "r", encoding="utf-8") as f:
        rows = [row for row in csv.reader(f) if any(field.strip() for field in row)]

    # Preserve the original checks.
    assert len(rows) >= 4, "CSV should contain at least 4 rows of data"
    text_content = " ".join(" ".join(row) for row in rows).replace(",", " ").split()
    expected_values = ["0.0", "100.00", "1.0", "60.65", "2.0", "36.79", "3.0", "22.31"]
    for val in expected_values:
        val_float = float(val)
        found = False
        for token in text_content:
            try:
                if abs(float(token) - val_float) < 0.1:
                    found = True
                    break
            except ValueError:
                continue
        assert found, f"Expected value {val} not found in the extracted CSV data"

    # Require an actual two-column reshaping, not a bag of copied numeric tokens.
    assert all(len(row) == 2 for row in rows), "Every nonempty CSV row must have exactly two columns"
    data_rows = rows
    try:
        float(rows[0][0].strip())
        float(rows[0][1].strip())
    except ValueError:
        header = [cell.strip().lower() for cell in rows[0]]
        assert "time" in header[0] and "concentration" in header[1], "CSV header must be Time,Concentration"
        data_rows = rows[1:]

    assert len(data_rows) == 4, "CSV must contain exactly the four observed records"
    parsed = []
    for row in data_rows:
        try:
            parsed.append((float(row[0].strip()), float(row[1].strip())))
        except ValueError as exc:
            pytest.fail(f"CSV contains a nonnumeric observation: {row}: {exc}")
    for got, expected in zip(parsed, EXPECTED_ROWS):
        assert got[0] == pytest.approx(expected[0], abs=0.05)
        assert got[1] == pytest.approx(expected[1], abs=0.05)
    return parsed


def post_prediction(t):
    r = requests.post(URL, json={"time": t}, headers=AUTH, timeout=15)
    assert r.status_code == 200, f"Expected status code 200, got {r.status_code}. Response: {r.text}"
    try:
        data = r.json()
    except ValueError:
        pytest.fail(f"Response was not valid JSON: {r.text}")
    assert "expected_concentration" in data, "Response JSON missing 'expected_concentration' key"
    val = data["expected_concentration"]
    assert isinstance(val, (int, float)) and not isinstance(val, bool), "Expected concentration must be a number"
    assert math.isfinite(val), "Expected concentration must be finite"
    return float(val)


def posterior_euler_expectation(observations, steps):
    # Independently derive the posterior predictive answer from the submitted
    # structured observations. The likelihood uses the exact solution during
    # parameter fitting and Euler's method only for the requested projection.
    c0 = observations[0][1]
    grid_n = 20001
    total_weight = 0.0
    total_prediction = 0.0
    for i in range(grid_n):
        k = i / (grid_n - 1)
        log_likelihood = 0.0
        for t, observed in observations:
            residual = observed - c0 * math.exp(-k * t)
            log_likelihood -= 0.5 * residual * residual  # sigma = 1.0
        weight = math.exp(log_likelihood)
        prediction = c0 * ((1.0 - 0.1 * k) ** steps)
        total_weight += weight
        total_prediction += weight * prediction
    return total_prediction / total_weight


def go_source_without_comments():
    paths = glob.glob("/home/user/sim/**/*.go", recursive=True)
    assert paths, "No Go source files found under /home/user/sim"
    source = "\n".join(open(path, "r", encoding="utf-8").read() for path in paths)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    return source


def test_go_artifact_and_required_algorithm_structure():
    assert os.path.isfile("/tmp/sim-verifier"), "The Go service did not compile"
    source = go_source_without_comments()
    compact = source.replace("_", "")

    assert re.search(r"\b100000\b", compact), "MCMC implementation must specify 100,000 steps"
    assert re.search(r"\b10000\b", compact), "MCMC implementation must specify a 10,000-step burn-in"
    assert re.search(r"\b1000\b", compact), "Projection must use the last 1,000 samples"
    assert re.search(r"\bfor\b", source), "MCMC/Euler iteration loops are missing"
    assert re.search(r"(?:0\.1|1e-1)", compact, re.I), "Euler step size dt=0.1 is missing"
    assert re.search(r"encoding/csv", source) and re.search(r"\.NewReader\s*\(", source), "Go program must read the extracted CSV"
    assert re.search(r"/predict", source), "POST /predict handler is missing"

    # Require a real ascending sort operation and accumulation after that sort.
    float_sort = re.search(r"sort\s*\.\s*Float64s\s*\(\s*([A-Za-z_]\w*)\s*\)", source)
    slice_sort = re.search(r"sort\s*\.\s*Slice(?:Stable)?\s*\(\s*([A-Za-z_]\w*)\s*,", source)
    match = float_sort or slice_sort
    assert match, "Predictions must be sorted in ascending order before summation"
    predictions_name = match.group(1)
    following = source[match.end():match.end() + 2500]
    if slice_sort and match is slice_sort:
        assert "<" in following[:800], "sort.Slice comparator must sort predictions ascending"
    assert re.search(r"for\s+[^\n\{]*\brange\s+" + re.escape(predictions_name) + r"\b", following), \
        "The sorted predictions must be iterated for the final sum"


def test_extracted_csv_exists_and_correct():
    read_structured_csv()


def test_web_service_auth():
    payload = {"time": 5.0}
    try:
        r_no_auth = requests.post(URL, json=payload, timeout=5)
        assert r_no_auth.status_code in [401, 403], f"Service did not enforce auth, got status code {r_no_auth.status_code}"
        r_wrong_auth = requests.post(URL, json=payload, headers={"Authorization": "Bearer chem-sim-2024-x"}, timeout=5)
        assert r_wrong_auth.status_code in [401, 403], "Service accepted an inexact bearer token"
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the web service at localhost:8080. Is it running?")


def test_web_service_prediction():
    # Preserve the original fixed-input assertion.
    try:
        val = post_prediction(5.0)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the web service at localhost:8080. Is it running?")
    assert 7.0 < val < 9.5, f"Concentration out of bounds: {val}. Expected between 7.0 and 9.5"


def test_predictions_follow_mcmc_posterior_and_euler_projection():
    observations = read_structured_csv()

    # T=0 is independent of the sampled k values and must reproduce C(0).
    assert post_prediction(0.0) == pytest.approx(observations[0][1], abs=1e-6)

    # Exercise previously unknown inputs selected at verification time. Times are
    # exact multiples of dt, so the independently derived Euler step count is clear.
    rng = random.SystemRandom()
    step_counts = [rng.choice(range(6, 16)), rng.choice(range(20, 35)), rng.choice(range(40, 58))]
    values = []
    for steps in step_counts:
        expected = posterior_euler_expectation(observations, steps)
        actual = post_prediction(steps / 10.0)
        tolerance = max(0.15, 0.04 * expected)
        assert actual == pytest.approx(expected, abs=tolerance), \
            f"Prediction at T={steps / 10.0} is inconsistent with posterior sampling and dt=0.1 Euler integration"
        values.append(actual)
    assert values[0] > values[1] > values[2], "Predictions must decrease with increasing future time"
TEST_EOF

BUILD_OK=1
(cd /home/user/sim && go build -o /tmp/sim-verifier .) >/tmp/go-build.log 2>&1 || BUILD_OK=0
SERVER_PID=""
READY=0

if [ "$BUILD_OK" -eq 1 ]; then
    # Stop any stale service and execute the artifact compiled from the submitted source.
    python3 << 'KILL_EOF'
import os, signal, time
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        for line in open(table).read().splitlines()[1:]:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    except OSError:
        pass
for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except (OSError, ProcessLookupError, PermissionError):
        pass
time.sleep(0.5)
KILL_EOF

    cd /home/user/sim
    /tmp/sim-verifier >/tmp/sim-verifier.log 2>&1 &
    SERVER_PID=$!
    cd - >/dev/null

    for _ in $(seq 1 30); do
        python3 - << 'READY_EOF' >/dev/null 2>&1
import requests
try:
    requests.post("http://localhost:8080/predict", json={"time": 0}, timeout=1)
except Exception:
    raise SystemExit(1)
READY_EOF
        if [ $? -eq 0 ]; then READY=1; break; fi
        sleep 1
    done
fi

if [ "$BUILD_OK" -eq 1 ] && [ "$READY" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    [ -f /tmp/go-build.log ] && cat /tmp/go-build.log
    [ -f /tmp/sim-verifier.log ] && cat /tmp/sim-verifier.log
    echo "0" > /logs/verifier/reward.txt
fi

if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
exit 0
