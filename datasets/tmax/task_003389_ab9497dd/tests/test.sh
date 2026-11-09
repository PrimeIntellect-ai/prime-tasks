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
# test_final_state.py

import os
import json
import struct
import pytest
import requests


def expected_metrics():
    """Derive the expected values from the PCM samples the application must process."""
    with open("/app/test_signal.wav", "rb") as wav_file:
        wav_file.seek(44)
        pcm = wav_file.read()

    assert len(pcm) % 2 == 0, "PCM data has an incomplete 16-bit sample"
    samples = [sample[0] for sample in struct.iter_unpack("<h", pcm)]
    assert samples, "WAV file contains no PCM samples"

    max_amp = max(abs(sample) for sample in samples)
    zero_crossings = sum(
        (previous >= 0) != (current >= 0)
        for previous, current in zip(samples, samples[1:])
    )
    return max_amp, zero_crossings


def test_source_code_exists():
    """Verify that the C source code exists at the specified location."""
    path = "/home/user/workspace/analyzer.c"
    assert os.path.isfile(path), f"Source code file {path} is missing."


def test_binary_exists():
    """Verify that the compiled binary exists."""
    path = "/home/user/workspace/analyzer"
    assert os.path.isfile(path), f"Compiled binary {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_http_metrics_endpoint():
    """Verify the /metrics endpoint returns the correct JSON and headers."""
    url = "http://127.0.0.1:8000/metrics"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type: application/json, got {content_type}"

    assert "X-Process-Time-Us" in response.headers, "Header X-Process-Time-Us is missing"
    try:
        int(response.headers["X-Process-Time-Us"])
    except ValueError:
        pytest.fail(f"Header X-Process-Time-Us is not an integer: {response.headers['X-Process-Time-Us']}")

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse JSON response: {response.text}")

    assert "max_amp" in data, "Key 'max_amp' missing in JSON response"
    assert "zero_crossings" in data, "Key 'zero_crossings' missing in JSON response"

    expected_max_amp, expected_zero_crossings = expected_metrics()
    assert data["max_amp"] == expected_max_amp, f"Expected max_amp={expected_max_amp}, got {data['max_amp']}"
    assert data["zero_crossings"] == expected_zero_crossings, f"Expected zero_crossings={expected_zero_crossings}, got {data['zero_crossings']}"


def test_http_404_endpoint():
    """Verify that an unknown path returns 404 Not Found."""
    url = "http://127.0.0.1:8000/unknown"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 404, f"Expected status code 404, got {response.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
