#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

restore_decoder() {
    if [ -e /app/telemetry_decoder.real ]; then
        rm -f /app/telemetry_decoder
        mv /app/telemetry_decoder.real /app/telemetry_decoder
    fi
}
trap restore_decoder EXIT

if [ ! -x /app/telemetry_decoder ]; then
    exit 0
fi

rm -f /app/telemetry_decoder.real
if ! mv /app/telemetry_decoder /app/telemetry_decoder.real; then
    exit 0
fi

cat << 'WRAPPER_EOF' > /app/telemetry_decoder
#!/bin/bash
payload="$(cat)"
printf '%s\n' "$payload" >> /tmp/telemetry_decoder_calls.log
printf '%s' "$payload" | /app/telemetry_decoder.real
exit ${PIPESTATUS[1]}
WRAPPER_EOF
chmod 755 /app/telemetry_decoder
: > /tmp/telemetry_decoder_calls.log
chmod 666 /tmp/telemetry_decoder_calls.log

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import datetime
import json
import math
import os
import py_compile
import random

import pytest
import requests

URL = "http://127.0.0.1:8080/process"
OBSERVED_PAYLOADS = []


def encode_payload(temp, pressure, humidity):
    payload_str = json.dumps({"temp": temp, "pressure": pressure, "humidity": humidity})
    return binascii.hexlify(payload_str.encode("utf-8")).decode("utf-8")


def post_and_parse(req_data):
    OBSERVED_PAYLOADS.append(req_data["payload"])
    try:
        response = requests.post(URL, json=req_data, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the middleware service at {URL}: {exc}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def expected_bucket(timestamp):
    dt = datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
    return dt.replace(minute=(dt.minute // 5) * 5, second=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def assert_complete_result(data, timestamp, temp, pressure, humidity):
    bucket = expected_bucket(timestamp)
    distance = round(math.sqrt(
        (temp - 20.0) ** 2
        + (pressure - 1013.25) ** 2
        + (humidity - 50.0) ** 2
    ), 2)
    alert = (
        f"ALERT: Deviation of {distance} detected at {bucket}."
        if distance > 10.0 else None
    )
    assert data.get("bucket") == bucket, f"Incorrect bucket. Got: {data.get('bucket')}"
    assert data.get("distance") == distance, f"Incorrect distance. Got: {data.get('distance')}"
    assert data.get("alert") == alert, f"Incorrect alert. Got: {data.get('alert')}"


def test_middleware_artifact_exists_and_is_python():
    assert os.path.isfile("/home/user/middleware.py"), "Missing /home/user/middleware.py"
    py_compile.compile("/home/user/middleware.py", doraise=True)


def test_process_deviation_alert():
    payload = encode_payload(35.0, 1020.0, 45.0)
    req_data = {
        "timestamp": "2024-01-01T10:13:45Z",
        "payload": payload,
    }
    data = post_and_parse(req_data)
    assert data.get("bucket") == "2024-01-01T10:10:00Z", f"Incorrect bucket. Got: {data.get('bucket')}"
    assert data.get("distance") == 17.19, f"Incorrect distance. Got: {data.get('distance')}"
    expected_alert = "ALERT: Deviation of 17.19 detected at 2024-01-01T10:10:00Z."
    assert data.get("alert") == expected_alert, f"Incorrect alert. Got: {data.get('alert')}"


def test_process_no_deviation():
    payload = encode_payload(20.0, 1013.25, 50.0)
    req_data = {
        "timestamp": "2024-02-29T23:59:59Z",
        "payload": payload,
    }
    data = post_and_parse(req_data)
    assert data.get("bucket") == "2024-02-29T23:55:00Z", f"Incorrect bucket. Got: {data.get('bucket')}"
    assert data.get("distance") == 0.0, f"Incorrect distance. Got: {data.get('distance')}"
    assert data.get("alert") is None, f"Alert should be null. Got: {data.get('alert')}"


def test_process_bucketing_edge_cases():
    payload = encode_payload(22.0, 1010.0, 55.0)
    req_data = {
        "timestamp": "2023-10-01T12:00:00Z",
        "payload": payload,
    }
    data = post_and_parse(req_data)
    assert data.get("bucket") == "2023-10-01T12:00:00Z"
    assert_complete_result(data, req_data["timestamp"], 22.0, 1010.0, 55.0)

    req_data["timestamp"] = "2023-10-01T12:04:59Z"
    data = post_and_parse(req_data)
    assert data.get("bucket") == "2023-10-01T12:00:00Z"
    assert_complete_result(data, req_data["timestamp"], 22.0, 1010.0, 55.0)


def test_unpredictable_payloads_timestamps_and_threshold():
    rng = random.SystemRandom()
    start = datetime.datetime(2021, 1, 1)
    cases = []

    # Exercise the strict threshold at an unpredictable timestamp.
    threshold_time = start + datetime.timedelta(seconds=rng.randrange(0, 6 * 365 * 24 * 3600))
    cases.append((threshold_time, 30.0, 1013.25, 50.0))

    for index in range(16):
        while True:
            when = start + datetime.timedelta(seconds=rng.randrange(0, 6 * 365 * 24 * 3600))
            if index % 2 == 0:
                temp = round(20.0 + rng.uniform(-3.0, 3.0), 3)
                pressure = round(1013.25 + rng.uniform(-4.0, 4.0), 3)
                humidity = round(50.0 + rng.uniform(-4.0, 4.0), 3)
            else:
                temp = round(20.0 + rng.uniform(12.0, 30.0), 3)
                pressure = round(1013.25 + rng.uniform(-15.0, 15.0), 3)
                humidity = round(50.0 + rng.uniform(-15.0, 15.0), 3)
            raw_distance = math.sqrt(
                (temp - 20.0) ** 2
                + (pressure - 1013.25) ** 2
                + (humidity - 50.0) ** 2
            )
            # Avoid alert-string ambiguity from a trailing zero in the hundredths place.
            if int(round(raw_distance * 100)) % 10 != 0:
                break
        cases.append((when, temp, pressure, humidity))

    for when, temp, pressure, humidity in cases:
        timestamp = when.strftime("%Y-%m-%dT%H:%M:%SZ")
        payload = encode_payload(temp, pressure, humidity)
        data = post_and_parse({"timestamp": timestamp, "payload": payload})
        assert_complete_result(data, timestamp, temp, pressure, humidity)


def test_decoder_was_invoked_for_submitted_payloads():
    with open("/tmp/telemetry_decoder_calls.log", "r", encoding="utf-8") as handle:
        calls = [line.strip() for line in handle if line.strip()]
    assert OBSERVED_PAYLOADS, "No telemetry payloads were submitted"
    for payload in OBSERVED_PAYLOADS:
        assert payload in calls, f"/app/telemetry_decoder was not invoked for payload {payload}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    printf '1\n' > /logs/verifier/reward.txt
else
    printf '0\n' > /logs/verifier/reward.txt
fi
