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
import re
import math
import importlib.util
from datetime import datetime, timedelta
from collections import defaultdict
import requests
import pytest

def test_vendored_parse_fixed():
    path = "/app/vendored/parse/parse.py"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    correct_line = "match = self._search_re.search(string, pos, endpos)"
    broken_line = "match = self._search_re.match(string)"
    incomplete_line = "match = self._search_re.search(string)"

    assert correct_line in content, f"The fix '{correct_line}' was not found in {path}."
    assert broken_line not in content, f"The perturbation '{broken_line}' is still present in {path}."
    assert incomplete_line not in content, f"The search implementation in {path} ignores pos and endpos."

    spec = importlib.util.spec_from_file_location("vendored_parse_under_test", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    parser = module.Parser("key={word:w}")
    text = "key=first key=second"
    result = parser.search(text, pos=len("key=first "), endpos=len(text))
    assert result is not None, "Parser.search failed to find a match within the requested range."
    assert result.named["word"] == "second", "Parser.search did not honor its pos argument."

    bounded = parser.search("xxxx key=hidden", pos=0, endpos=4)
    assert bounded is None, "Parser.search did not honor its endpos argument."

def compute_expected_data(sensor_id):
    log_path = "/home/user/data/raw_sensors.log"
    assert os.path.exists(log_path), f"Log file {log_path} is missing."

    pattern = re.compile(r"\[(.*?)\] SYSTEM_LOG: Sensor (.*?) recorded a value of (.*?) at the edge node.")
    raw_data = defaultdict(list)

    with open(log_path, "r") as f:
        for line in f:
            match = pattern.search(line)
            if match:
                ts_str, s_id, val_str = match.groups()
                if s_id == sensor_id:
                    dt = datetime.fromisoformat(ts_str)
                    val = float(val_str)
                    dt_min = dt.replace(second=0, microsecond=0)
                    raw_data[dt_min].append(val)

    if not raw_data:
        return []

    minute_data = {dt: sum(vals) / len(vals) for dt, vals in raw_data.items()}
    sorted_minutes = sorted(minute_data.keys())
    min_time = sorted_minutes[0]
    max_time = sorted_minutes[-1]

    full_series = {}
    current = min_time
    while current <= max_time:
        full_series[current] = minute_data.get(current, None)
        current += timedelta(minutes=1)

    times = sorted(full_series.keys())
    for i, t in enumerate(times):
        if full_series[t] is None:
            prev_idx = i - 1
            while prev_idx >= 0 and full_series[times[prev_idx]] is None:
                prev_idx -= 1

            next_idx = i + 1
            while next_idx < len(times) and full_series[times[next_idx]] is None:
                next_idx += 1

            if prev_idx >= 0 and next_idx < len(times):
                prev_t = times[prev_idx]
                next_t = times[next_idx]
                prev_v = full_series[prev_t]
                next_v = full_series[next_t]
                total_diff = (next_t - prev_t).total_seconds()
                curr_diff = (t - prev_t).total_seconds()
                full_series[t] = prev_v + (next_v - prev_v) * (curr_diff / total_diff)

    sampled_data = []
    target_minutes = {0, 12, 24, 36, 48}
    for t in times:
        if t.minute in target_minutes and full_series[t] is not None:
            sampled_data.append({
                "timestamp": t.isoformat(),
                "value": round(full_series[t], 2)
            })

    return sampled_data

def test_api_unauthorized():
    url = "http://127.0.0.1:8080/api/v1/samples?sensor=TX-99"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API on 127.0.0.1:8080: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"

def test_api_authorized_tx99():
    url = "http://127.0.0.1:8080/api/v1/samples?sensor=TX-99"
    headers = {"Authorization": "Bearer secret_sensor_token_99X"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API on 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_data = compute_expected_data("TX-99")
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} samples, got {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual["timestamp"] == expected["timestamp"], f"Mismatch in timestamp at index {i}. Expected {expected['timestamp']}, got {actual['timestamp']}"
        assert math.isclose(actual["value"], expected["value"], rel_tol=1e-5, abs_tol=0.01), f"Mismatch in value at index {i}. Expected {expected['value']}, got {actual['value']}"

def test_api_authorized_rx42():
    url = "http://127.0.0.1:8080/api/v1/samples?sensor=RX-42"
    headers = {"Authorization": "Bearer secret_sensor_token_99X"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API on 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_data = compute_expected_data("RX-42")
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} samples, got {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual["timestamp"] == expected["timestamp"], f"Mismatch in timestamp at index {i}. Expected {expected['timestamp']}, got {actual['timestamp']}"
        assert math.isclose(actual["value"], expected["value"], rel_tol=1e-5, abs_tol=0.01), f"Mismatch in value at index {i}. Expected {expected['value']}, got {actual['value']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
