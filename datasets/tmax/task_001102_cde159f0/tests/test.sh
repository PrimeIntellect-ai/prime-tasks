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
import json
import math
import os
import re
import secrets
import select
import subprocess
import time

import matplotlib.image as mpimg
import pytest
import redis
import requests

URL = "http://127.0.0.1:8080/simulate"
HEADERS = {"Authorization": "Bearer bio-secret-2024"}


def compute_peak_B(seq):
    k1 = seq.count('A') * 0.1 + 0.05
    k2 = (seq.count('B') + seq.count('C')) * 0.05 + 0.02
    A0 = 100.0

    max_B = 0.0
    for i in range(1000):
        t = 50.0 * i / 999.0
        if abs(k1 - k2) < 1e-9:
            B = k1 * A0 * t * math.exp(-k1 * t)
        else:
            B = k1 * A0 / (k2 - k1) * (math.exp(-k1 * t) - math.exp(-k2 * t))
        if B > max_B:
            max_B = B
    return max_B


def get_expected_results(sequences):
    results = []
    for seq in sequences:
        results.append({
            'sequence': seq,
            'length': len(seq),
            'peak_B': compute_peak_B(seq)
        })

    results.sort(key=lambda x: x['sequence'])

    total_peak = 0.0
    for result in results:
        total_peak += result['peak_B']

    n = len(results)
    sum_x = sum(result['length'] for result in results)
    sum_y = sum(result['peak_B'] for result in results)
    sum_x2 = sum(result['length'] ** 2 for result in results)
    sum_xy = sum(result['length'] * result['peak_B'] for result in results)

    denominator = n * sum_x2 - sum_x ** 2
    if denominator == 0:
        slope = 0.0
        intercept = sum_y / n if n else 0.0
    else:
        slope = (n * sum_xy - sum_x * sum_y) / denominator
        intercept = (sum_y - slope * sum_x) / n

    return total_peak, slope, intercept


def assert_response(response, sequences):
    assert response.status_code == 200, \
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "total_peak" in data, "Missing total_peak in response"
    assert "regression_slope" in data, "Missing regression_slope in response"
    assert "regression_intercept" in data, "Missing regression_intercept in response"

    expected_total, expected_slope, expected_intercept = get_expected_results(sequences)
    assert math.isclose(data["total_peak"], expected_total, rel_tol=1e-2, abs_tol=1e-6), \
        f"total_peak mismatch. Expected ~{expected_total}, got {data['total_peak']}"
    assert math.isclose(data["regression_slope"], expected_slope, rel_tol=1e-2, abs_tol=1e-6), \
        f"regression_slope mismatch. Expected ~{expected_slope}, got {data['regression_slope']}"
    assert math.isclose(data["regression_intercept"], expected_intercept, rel_tol=1e-2, abs_tol=1e-6), \
        f"regression_intercept mismatch. Expected ~{expected_intercept}, got {data['regression_intercept']}"


def random_sequences(lengths):
    alphabet = "ABCXYZ"
    result = []
    used = set()
    for length in lengths:
        while True:
            seq = ''.join(secrets.choice(alphabet) for _ in range(length))
            if seq not in used:
                used.add(seq)
                result.append(seq)
                break
    return result


def read_plot():
    path = "/home/user/plot.png"
    assert os.path.isfile(path), "Plot file /home/user/plot.png was not generated"
    assert os.path.getsize(path) > 0, "Plot file /home/user/plot.png is empty"
    raw = open(path, "rb").read()
    assert raw.startswith(b"\x89PNG\r\n\x1a\n"), "plot.png is not a PNG file"
    image = mpimg.imread(path)
    assert image.ndim in (2, 3), "plot.png is not a decodable image"
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "plot.png is implausibly small"
    assert float(image.max()) - float(image.min()) > 0.05, "plot.png appears blank"
    return raw


def test_required_artifacts_contain_implementations():
    for path in ("/app/api.js", "/app/worker.py", "/app/plot.py"):
        assert os.path.isfile(path), f"Missing required artifact {path}"
        assert os.path.getsize(path) > 0, f"Required artifact {path} is empty"

    worker = open("/app/worker.py", encoding="utf-8").read().lower()
    assert "scipy" in worker, "worker.py does not use SciPy"
    assert re.search(r"\b(solve_ivp|odeint)\s*\(", worker), \
        "worker.py does not call solve_ivp or odeint"

    api = open("/app/api.js", encoding="utf-8").read().lower()
    assert ".sort(" in api and "sequence" in api, \
        "api.js does not sort collected results by sequence"
    assert "plot.py" in api, "api.js does not invoke plot.py"

    plot = open("/app/plot.py", encoding="utf-8").read().lower()
    assert "matplotlib" in plot, "plot.py does not use matplotlib"
    assert re.search(r"\.scatter\s*\(", plot), "plot.py does not draw a scatter plot"
    assert re.search(r"\.plot\s*\(", plot), "plot.py does not draw a regression line"
    assert "savefig" in plot and "plot.png" in plot, \
        "plot.py does not save the required plot.png"


def test_api_unauthorized():
    payload = {"sequences": ["A"]}
    try:
        response = requests.post(URL, json=payload, timeout=5)
        assert response.status_code in [401, 403], \
            f"Expected 401 or 403 for unauthorized request, got {response.status_code}"
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")


@pytest.mark.parametrize("authorization", [
    "Bearer wrong-secret",
    "bearer bio-secret-2024",
    "Bearer bio-secret-2024-extra",
])
def test_api_rejects_non_exact_authorization(authorization):
    response = requests.post(
        URL,
        json={"sequences": ["A"]},
        headers={"Authorization": authorization},
        timeout=5,
    )
    assert response.status_code in [401, 403], \
        f"Expected rejection for non-exact Authorization header, got {response.status_code}"


def test_worker_processes_random_redis_job():
    client = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    client.ping()
    client.delete("jobs", "results")
    seq = "A" + secrets.token_hex(4).upper() + "BBCCAA"
    client.lpush("jobs", seq)

    deadline = time.time() + 10
    raw = None
    while time.time() < deadline:
        raw = client.rpop("results")
        if raw is not None:
            break
        time.sleep(0.1)
    assert raw is not None, "Python worker did not process a Redis job"
    result = json.loads(raw)
    assert result["sequence"] == seq
    assert result["length"] == len(seq)
    assert math.isclose(float(result["peak_B"]), compute_peak_B(seq), rel_tol=1e-2, abs_tol=1e-6)


def test_api_authorized_and_correctness():
    sequences = ["A", "AB", "ABC", "BCA", "AABBCC", "AAABBBCCC", "ACACAC"]
    try:
        response = requests.post(URL, json={"sequences": sequences}, headers=HEADERS, timeout=15)
        assert_response(response, sequences)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API or request timed out: {exc}")


def test_randomized_end_to_end_redis_and_plot():
    first = random_sequences([2, 4, 5, 7, 9, 12, 15])
    second = random_sequences([1, 3, 6, 8, 10, 13, 17, 20])

    monitor = subprocess.Popen(
        ["redis-cli", "--raw", "MONITOR"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    ready, _, _ = select.select([monitor.stdout], [], [], 3)
    assert ready, "Could not start Redis command monitor"
    assert "OK" in monitor.stdout.readline().upper()

    try:
        response = requests.post(URL, json={"sequences": first}, headers=HEADERS, timeout=25)
        assert_response(response, first)
    finally:
        time.sleep(0.2)
        monitor.terminate()
        try:
            monitored, _ = monitor.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            monitor.kill()
            monitored, _ = monitor.communicate()

    command_log = monitored.upper()
    assert re.search(r'"LPUSH"\s+"JOBS"', command_log), \
        "API request did not enqueue sequences in the Redis jobs list"
    assert re.search(r'"(LPOP|RPOP|BLPOP|BRPOP|LRANGE)"\s+"RESULTS"', command_log), \
        "API request did not retrieve worker output from the Redis results list"

    plot_one = read_plot()
    first_hash = hashlib.sha256(plot_one).digest()

    response = requests.post(URL, json={"sequences": second}, headers=HEADERS, timeout=25)
    assert_response(response, second)
    plot_two = read_plot()
    assert hashlib.sha256(plot_two).digest() != first_hash, \
        "plot.png was not regenerated for different simulation data"


def test_plot_generated():
    assert os.path.isfile("/home/user/plot.png"), "Plot file /home/user/plot.png was not generated"
    assert os.path.getsize("/home/user/plot.png") > 0, "Plot file /home/user/plot.png is empty"
    read_plot()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
