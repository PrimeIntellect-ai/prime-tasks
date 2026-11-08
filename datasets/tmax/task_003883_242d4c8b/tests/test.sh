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
import io
import math
import random
import secrets
from datetime import datetime, timedelta, timezone

import pytest
import requests

URL = "http://127.0.0.1:8000/process"


def calibrate(val):
    return (val * 1.045) + math.sin(val) * 2.1


def post_payload(payload):
    try:
        response = requests.post(URL, data=payload, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service or request timed out: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    assert response.headers.get("Content-Type", "").lower().startswith("application/json"), (
        f"Expected application/json Content-Type, got {response.headers.get('Content-Type')}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def assert_result(data, expected):
    assert isinstance(data, list), "Expected response to be a JSON array"
    assert len(data) == len(expected), f"Expected {len(expected)} items, got {len(data)}"

    for i, (act, exp) in enumerate(zip(data, expected)):
        assert isinstance(act, dict), f"Item {i}: expected an object"
        assert act.get("timestamp") == exp["timestamp"], (
            f"Item {i}: expected timestamp {exp['timestamp']}, got {act.get('timestamp')}"
        )
        assert act.get("sensor_id") == exp["sensor_id"], (
            f"Item {i}: expected sensor_id {exp['sensor_id']}, got {act.get('sensor_id')}"
        )
        act_val = act.get("calibrated_value")
        assert act_val is not None, f"Item {i}: missing 'calibrated_value'"
        assert isinstance(act_val, (int, float)) and not isinstance(act_val, bool), (
            f"Item {i}: 'calibrated_value' must be a number"
        )
        assert math.isfinite(act_val), f"Item {i}: calibrated_value must be finite"
        assert abs(act_val - exp["calibrated_value"]) <= 0.001, (
            f"Item {i}: expected calibrated_value ~{exp['calibrated_value']}, got {act_val}"
        )


def test_process_endpoint():
    # Preserve the original fixed regression case.
    csv_content = (
        "timestamp,sensor_id,raw_value\n"
        "2024-01-01T10:00:00Z,S1,10.0\n"
        "2024-01-01T10:00:03Z,S1,16.0\n"
        "2024-01-01T10:00:04Z,S1,\n"
        "2024-01-01T10:00:05Z,S1,20.0\n"
    )
    payload = csv_content.encode("windows-1252")
    data = post_payload(payload)

    expected = [
        {"timestamp": "2024-01-01T10:00:00Z", "sensor_id": "S1", "calibrated_value": round(calibrate(10.0), 3)},
        {"timestamp": "2024-01-01T10:00:01Z", "sensor_id": "S1", "calibrated_value": round(calibrate(11.0), 3)},
        {"timestamp": "2024-01-01T10:00:02Z", "sensor_id": "S1", "calibrated_value": round(calibrate(12.0), 3)},
        {"timestamp": "2024-01-01T10:00:03Z", "sensor_id": "S1", "calibrated_value": round(calibrate(13.0), 3)},
        {"timestamp": "2024-01-01T10:00:04Z", "sensor_id": "S1", "calibrated_value": round(calibrate(14.0), 3)},
        {"timestamp": "2024-01-01T10:00:05Z", "sensor_id": "S1", "calibrated_value": round(calibrate(16.0), 3)},
    ]
    assert_result(data, expected)


def iso_z(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def derive_expected(rows):
    grouped = {}
    for timestamp, sensor_id, raw_text in rows:
        dt = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        grouped.setdefault(sensor_id, {})[dt] = None if raw_text == "" else float(raw_text)

    result = []
    for sensor_id in sorted(grouped):
        observations = grouped[sensor_id]
        start = min(observations)
        end = max(observations)
        known = sorted((dt, value) for dt, value in observations.items() if value is not None)
        assert known and known[0][0] == start and known[-1][0] == end

        interpolated = []
        current = start
        while current <= end:
            value = observations.get(current)
            if value is None:
                before = max((item for item in known if item[0] < current), key=lambda item: item[0])
                after = min((item for item in known if item[0] > current), key=lambda item: item[0])
                fraction = (current - before[0]).total_seconds() / (after[0] - before[0]).total_seconds()
                value = before[1] + (after[1] - before[1]) * fraction
            interpolated.append((current, value))
            current += timedelta(seconds=1)

        for index, (timestamp, value) in enumerate(interpolated):
            window = [v for _, v in interpolated[max(0, index - 4):index + 1]]
            rolling_average = sum(window) / len(window)
            result.append({
                "timestamp": iso_z(timestamp),
                "sensor_id": sensor_id,
                "calibrated_value": round(calibrate(rolling_average), 3),
            })
    return result


def test_randomized_csv_processing_and_multiple_sensors():
    # Values, timestamps, and sensor IDs are generated only after the submitted
    # service is running, so a fixed response cannot satisfy this test.
    rng = random.Random(secrets.randbits(128))

    for request_number in range(2):
        base = datetime(
            2024 + rng.randrange(0, 2),
            rng.randrange(1, 13),
            rng.randrange(1, 25),
            rng.randrange(0, 20),
            rng.randrange(0, 55),
            rng.randrange(0, 10),
            tzinfo=timezone.utc,
        )
        token = f"{rng.randrange(10000, 99999)}{request_number}"
        sensor_a = f"Aé{token}"  # é is a single CP1252 byte and invalid standalone UTF-8.
        sensor_b = f"B{token}"

        a0 = round(rng.uniform(-18.0, 22.0), 3)
        a5 = round(a0 + rng.uniform(7.0, 24.0), 3)
        a8 = round(a5 + rng.uniform(-9.0, 13.0), 3)
        b1 = round(rng.uniform(25.0, 65.0), 3)
        b4 = round(b1 + rng.uniform(-16.0, 18.0), 3)
        b7 = round(b4 + rng.uniform(5.0, 20.0), 3)

        rows = [
            (iso_z(base + timedelta(seconds=0)), sensor_a, str(a0)),
            (iso_z(base + timedelta(seconds=2)), sensor_a, ""),
            (iso_z(base + timedelta(seconds=5)), sensor_a, str(a5)),
            (iso_z(base + timedelta(seconds=8)), sensor_a, str(a8)),
            (iso_z(base + timedelta(seconds=1)), sensor_b, str(b1)),
            (iso_z(base + timedelta(seconds=4)), sensor_b, str(b4)),
            (iso_z(base + timedelta(seconds=5)), sensor_b, ""),
            (iso_z(base + timedelta(seconds=7)), sensor_b, str(b7)),
        ]
        rng.shuffle(rows)

        stream = io.StringIO(newline="")
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["timestamp", "sensor_id", "raw_value"])
        writer.writerows(rows)
        payload = stream.getvalue().encode("windows-1252")

        expected = derive_expected(rows)
        actual = post_payload(payload)
        assert_result(actual, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
