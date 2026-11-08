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
import json
import os
import random
import stat
import subprocess
import time

import pytest
import requests

PAYLOAD = """100,A,5,ok
102,B,10,"this is
a broken
row"
105,C,15,ok
101,A,2,ok
106,B,20,"another
broken"
108,C,10,ok"""


def test_pipeline_processing():
    # Retain the original end-to-end service assertions.
    try:
        requests.post("http://127.0.0.1:8080/", data=PAYLOAD, timeout=2)
    except requests.exceptions.RequestException:
        pass

    time.sleep(2)

    try:
        response = requests.get("http://127.0.0.1:8081/stats", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API service on port 8081 or request timed out: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API did not return valid JSON. Response text:\n{response.text}")

    assert "valid_rows" in data, "JSON response missing 'valid_rows' key"
    assert "rolling_sums" in data, "JSON response missing 'rolling_sums' key"
    assert data["valid_rows"] == 4, f"Expected 4 valid rows, got {data['valid_rows']}"
    assert data["rolling_sums"] == [5, 7, 22, 27], f"Expected rolling sums [5, 7, 22, 27], got {data['rolling_sums']}"


def expected_stats(rows):
    ordered = sorted(rows, key=lambda row: row[0])
    values = [row[2] for row in ordered]
    sums = [sum(values[max(0, i - 2):i + 1]) for i in range(len(values))]
    return {"valid_rows": len(rows), "rolling_sums": sums}


def run_process(payload):
    path = "/app/pipeline/process.sh"
    assert os.path.exists(path), "process.sh does not exist"
    mode = os.stat(path).st_mode
    assert stat.S_ISREG(mode), "process.sh is not a regular file"
    assert os.access(path, os.X_OK), "process.sh is not executable"

    try:
        os.unlink("/tmp/stats.json")
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [path],
        input=payload,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
        cwd="/app/pipeline",
    )
    assert result.returncode == 0, f"process.sh failed: {result.stderr}"
    assert os.path.isfile("/tmp/stats.json"), "process.sh did not create /tmp/stats.json"

    try:
        with open("/tmp/stats.json", "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as exc:
        pytest.fail(f"process.sh produced invalid JSON: {exc}")


def test_process_handles_derived_inputs_and_api_serves_current_file():
    # Runtime-generated values prevent a fixed response from satisfying the test.
    rng = random.SystemRandom()
    last_expected = None

    for case in range(4):
        timestamps = rng.sample(range(1000 + case * 1000, 1900 + case * 1000), 8)
        values = [rng.randint(1, 70) for _ in timestamps]
        rows = [(ts, chr(65 + (i % 3)), value) for i, (ts, value) in enumerate(zip(timestamps, values))]

        lines = []
        for i, (ts, category, value) in enumerate(rows):
            note = '"balanced note"' if i % 3 == 0 else "ok"
            lines.append(f"{ts},{category},{value},{note}")

        # Every line from the opening odd quote through its closing odd quote
        # belongs to one malformed logical row and must be discarded.
        insertion = rng.randrange(1, len(lines))
        bad_ts = rng.randint(8000, 9000)
        bad_value = rng.randint(200, 500)
        malformed = [
            f'{bad_ts},X,{bad_value},"broken note',
            f'{bad_ts + 1},Y,{bad_value + 1},looks like a row',
            'end of broken note"',
        ]
        lines[insertion:insertion] = malformed

        # Also verify that an unterminated logical row at EOF is discarded.
        lines.extend([
            f'{bad_ts + 10},Z,{bad_value + 2},"unterminated',
            f'{bad_ts + 11},Z,{bad_value + 3},still malformed',
        ])

        payload = "\n".join(lines) + "\n"
        last_expected = expected_stats(rows)
        actual = run_process(payload)
        assert actual.get("valid_rows") == last_expected["valid_rows"], (
            f"Expected {last_expected['valid_rows']} valid rows, got {actual.get('valid_rows')}"
        )
        assert actual.get("rolling_sums") == last_expected["rolling_sums"], (
            f"Expected rolling sums {last_expected['rolling_sums']}, got {actual.get('rolling_sums')}"
        )

    # The API must serve the newly generated file, rather than a fixed response.
    observed = None
    for _ in range(5):
        try:
            response = requests.get("http://127.0.0.1:8081/stats", timeout=2)
            assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
            observed = response.json()
            if observed == last_expected:
                break
        except (requests.exceptions.RequestException, ValueError):
            pass
        time.sleep(0.3)

    assert observed == last_expected, f"API did not serve current stats: expected {last_expected}, got {observed}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
