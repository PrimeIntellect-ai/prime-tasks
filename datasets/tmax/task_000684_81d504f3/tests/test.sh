#!/bin/bash
set -e
mkdir -p /logs/verifier

# Replace the deterministic emitter with a verifier-controlled emitter whose
# later datasets are generated only after the agent has finished.
pkill -f '/app/data_emitter.py' 2>/dev/null || true
sleep 1

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import socketserver
import threading
import time

import numpy as np
import pytest
import requests

N = 1024
DT = 0.01


def original_dataset():
    rng = random.Random(42)
    rows = []
    for i in range(N):
        t = i * DT
        value = 5.0 + 3.0 * math.sin(2 * math.pi * 15.0 * t) + rng.gauss(0, 1)
        rows.append((t, float(f"{value:.6f}")))
    return rows


def secret_dataset():
    rng = random.Random(secrets.randbits(128))
    # Exact FFT-bin frequencies avoid ambiguity from spectral leakage.
    k = rng.randint(55, 340)
    offset = rng.uniform(-8.0, 12.0)
    amplitude = rng.uniform(2.2, 4.8)
    rows = []
    for i in range(N):
        t = i * DT
        value = offset + amplitude * math.sin(2 * math.pi * k * i / N) + rng.gauss(0, 0.7)
        rows.append((t, float(f"{value:.6f}")))
    return rows


DATASETS = [original_dataset(), secret_dataset(), secret_dataset()]
SERVED = []


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class EmitterHandler(socketserver.StreamRequestHandler):
    def handle(self):
        index = min(len(SERVED), len(DATASETS) - 1)
        SERVED.append(index)
        self.wfile.write(b"time,value\n")
        for t, value in DATASETS[index]:
            self.wfile.write(f"{t:.2f},{value:.6f}\n".encode())


@pytest.fixture(scope="session", autouse=True)
def controlled_emitter():
    path = "/home/user/middleware.sh"
    assert os.path.isfile(path), f"Required middleware script does not exist: {path}"
    assert os.access(path, os.X_OK), f"Middleware script is not executable: {path}"
    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!.*(?:/|\b)bash(?:\s|$)", first_line), \
        "middleware.sh must be a Bash script with a Bash shebang"

    deadline = time.time() + 5
    while True:
        try:
            server = ReusableTCPServer(("127.0.0.1", 9001), EmitterHandler)
            break
        except OSError:
            if time.time() >= deadline:
                pytest.fail("Could not take control of TCP port 9001")
            time.sleep(0.1)

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield
    server.shutdown()
    server.server_close()


def parse_and_check_response(response):
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK on /analyze, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/json"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert "dominant_freq" in data, f"Missing 'dominant_freq' in JSON response: {data}"
    assert "ci_lower" in data, f"Missing 'ci_lower' in JSON response: {data}"
    assert "ci_upper" in data, f"Missing 'ci_upper' in JSON response: {data}"
    assert set(data) == {"dominant_freq", "ci_lower", "ci_upper"}, f"Unexpected JSON fields: {data}"

    try:
        freq = float(data["dominant_freq"])
        ci_lower = float(data["ci_lower"])
        ci_upper = float(data["ci_upper"])
    except (ValueError, TypeError):
        pytest.fail(f"JSON response values must be convertible to floats. Got: {data}")

    assert all(type(data[k]) in (int, float) and not isinstance(data[k], bool) for k in data), \
        f"JSON values must be JSON numbers, not strings: {data}"
    assert math.isfinite(freq) and math.isfinite(ci_lower) and math.isfinite(ci_upper)

    compact = re.sub(r"\s+", "", response.text)
    number = r"-?(?:0|[1-9]\d*)"
    pattern = (
        r'^\{"dominant_freq":' + number + r'\.\d,'
        r'"ci_lower":' + number + r'\.\d{2},'
        r'"ci_upper":' + number + r'\.\d{2}\}$'
    )
    assert re.match(pattern, compact), (
        "JSON must use the requested key order and rounding: dominant_freq to one "
        f"decimal and confidence bounds to two decimals. Got: {response.text!r}"
    )
    return data, freq, ci_lower, ci_upper


def reference_results(rows):
    values = np.asarray([v for _, v in rows], dtype=float)
    magnitudes = np.abs(np.fft.rfft(values))
    magnitudes[0] = -np.inf
    freq = float(np.fft.rfftfreq(values.size, d=DT)[int(np.argmax(magnitudes))])

    # A high-iteration reference percentile bootstrap. The tolerance below
    # allows normal Monte Carlo variation from the required 1000 iterations.
    rng = np.random.default_rng(0x5A17)
    means = []
    for _ in range(24):
        indices = rng.integers(0, values.size, size=(500, values.size))
        means.append(values[indices].mean(axis=1))
    means = np.concatenate(means)
    lower, upper = np.percentile(means, [2.5, 97.5])
    return round(freq, 1), round(float(lower), 2), round(float(upper), 2)


def test_middleware_analyze_endpoint():
    """Retain the original deterministic endpoint assertions."""
    url = "http://127.0.0.1:8080/analyze"
    try:
        response = requests.get(url, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the middleware service at {url}: {e}")

    data, freq, ci_lower, ci_upper = parse_and_check_response(response)
    assert abs(freq - 15.0) < 0.5, f"Dominant frequency {freq} is not close to expected 15.0 Hz"
    assert 4.5 < ci_lower < 5.0, f"ci_lower {ci_lower} is out of expected bounds (4.5, 5.0)"
    assert 5.0 < ci_upper < 5.5, f"ci_upper {ci_upper} is out of expected bounds (5.0, 5.5)"


def test_middleware_404_endpoint():
    """Retain the original unknown-route assertion."""
    url = "http://127.0.0.1:8080/unknown"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the middleware service at {url}: {e}")
    assert response.status_code == 404, (
        f"Expected HTTP 404 Not Found on /unknown, got {response.status_code}. "
        f"Response body: {response.text}"
    )


def test_analyze_uses_fresh_emitter_data_on_multiple_requests():
    url = "http://127.0.0.1:8080/analyze"
    for dataset_index in (1, 2):
        before = len(SERVED)
        try:
            response = requests.get(url, timeout=15)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed on sequential /analyze request: {e}")
        _, freq, lower, upper = parse_and_check_response(response)
        assert len(SERVED) == before + 1, \
            "Each /analyze request must make a fresh connection to 127.0.0.1:9001"

        expected_freq, expected_lower, expected_upper = reference_results(DATASETS[dataset_index])
        assert freq == expected_freq, f"Expected dominant frequency {expected_freq}, got {freq}"
        assert abs(lower - expected_lower) <= 0.06, \
            f"Expected bootstrap lower bound near {expected_lower}, got {lower}"
        assert abs(upper - expected_upper) <= 0.06, \
            f"Expected bootstrap upper bound near {expected_upper}, got {upper}"
        assert lower < upper, f"Invalid confidence interval: [{lower}, {upper}]"

    assert len(SERVED) == 3, f"Expected exactly one emitter connection per analyze request, got {len(SERVED)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
