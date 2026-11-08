#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets
import requests
import pytest

BASE_URL = "http://127.0.0.1:8080"
TOKEN = "blue sunrise"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def post(payload, headers=HEADERS):
    try:
        return requests.post(f"{BASE_URL}/ingest", json=payload, headers=headers, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL}/ingest: {exc}")


def get_config():
    try:
        response = requests.get(f"{BASE_URL}/config", headers=HEADERS, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL}/config: {exc}")
    assert response.status_code == 200, f"Expected 200 OK from /config, got {response.status_code}: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /config is not valid JSON.")
    assert isinstance(data, list), "Expected response to be a JSON array."
    return data


def mutate(value, count):
    chars = list(value)
    for index in range(count):
        chars[index] = "x" if chars[index] != "x" else "y"
    return "".join(chars)


def assert_record(data, sequence, metric, config_hash=None):
    matches = [item for item in data if item.get("sequence") == sequence]
    assert len(matches) == 1, f"Expected exactly one record for sequence {sequence}, got {matches}"
    item = matches[0]
    assert math.isclose(float(item.get("metric")), metric, rel_tol=0, abs_tol=1e-9), (
        f"Expected metric {metric} for sequence {sequence}, got {item.get('metric')}"
    )
    if config_hash is not None:
        assert item.get("config_hash") == config_hash, (
            f"Expected hash {config_hash} for sequence {sequence}, got {item.get('config_hash')}"
        )


def assert_absent(data, sequence):
    assert not any(item.get("sequence") == sequence for item in data), (
        f"Sequence {sequence} should have been discarded as a duplicate."
    )


def test_unauthorized_access():
    try:
        resp = requests.get(f"{BASE_URL}/config", timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}: {exc}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for missing token, got {resp.status_code}"

    resp = requests.get(f"{BASE_URL}/config", headers={"Authorization": "Bearer wrong token"}, timeout=5)
    assert resp.status_code == 401, f"Expected 401 Unauthorized for incorrect token, got {resp.status_code}"

    resp = post([], headers={})
    assert resp.status_code == 401, f"Expected 401 for unauthenticated POST /ingest, got {resp.status_code}"
    resp = post([], headers={"Authorization": "Bearer wrong token"})
    assert resp.status_code == 401, f"Expected 401 for incorrectly authenticated POST /ingest, got {resp.status_code}"


def test_original_ingest_and_data_cleaning():
    payload = [
        {"sequence": 1, "metric": 10.0, "config_hash": "abcde"},
        {"sequence": 2, "metric": None, "config_hash": "abXde"},
        {"sequence": 3, "metric": None, "config_hash": "vwxyz"},
        {"sequence": 4, "metric": 30.0, "config_hash": "vwxyA"},
        {"sequence": 5, "metric": 30.0, "config_hash": "pqrst"},
    ]
    response = post(payload)
    assert response.status_code == 200, f"Expected 200 OK from /ingest, got {response.status_code}: {response.text}"
    data = get_config()

    seq_1 = next((item for item in data if item.get("sequence") == 1), None)
    seq_3 = next((item for item in data if item.get("sequence") == 3), None)
    seq_5 = next((item for item in data if item.get("sequence") == 5), None)
    assert seq_1 is not None, "Sequence 1 is missing from the cleaned data."
    assert seq_3 is not None, "Sequence 3 is missing from the cleaned data."
    assert seq_5 is not None, "Sequence 5 is missing from the cleaned data."
    assert next((item for item in data if item.get("sequence") == 2), None) is None, "Sequence 2 should have been discarded as a duplicate."
    assert next((item for item in data if item.get("sequence") == 4), None) is None, "Sequence 4 should have been discarded as a duplicate."
    assert seq_1["metric"] == 10.0, f"Expected metric 10.0 for sequence 1, got {seq_1.get('metric')}"
    assert seq_3["metric"] == 20.0, f"Expected interpolated metric 20.0 for sequence 3, got {seq_3.get('metric')}"
    assert seq_5["metric"] == 30.0, f"Expected metric 30.0 for sequence 5, got {seq_5.get('metric')}"


def test_randomized_cleaning_and_accumulated_state():
    base_sequence = secrets.randbelow(500_000_000) + 100_000_000
    hashes = [secrets.token_hex(16) for _ in range(9)]
    lead, left, middle, right, distance_base, trailing, second_left, second_middle, second_tail = hashes

    first_payload = [
        {"sequence": base_sequence, "metric": None, "config_hash": lead},
        {"sequence": base_sequence + 1, "metric": None, "config_hash": mutate(lead, 2)},
        {"sequence": base_sequence + 10, "metric": 8.0, "config_hash": left},
        {"sequence": base_sequence + 20, "metric": None, "config_hash": middle},
        {"sequence": base_sequence + 30, "metric": 20.0, "config_hash": right},
        {"sequence": base_sequence + 31, "metric": 20.0, "config_hash": mutate(right, 1)},
        {"sequence": base_sequence + 40, "metric": 25.0, "config_hash": distance_base},
        {"sequence": base_sequence + 41, "metric": 25.0, "config_hash": mutate(distance_base, 3)},
        {"sequence": base_sequence + 50, "metric": None, "config_hash": trailing},
    ]
    response = post(first_payload)
    assert response.status_code == 200, f"Randomized first ingest failed: {response.status_code}: {response.text}"
    data = get_config()

    expected_first = {
        base_sequence: (8.0, lead),
        base_sequence + 10: (8.0, left),
        base_sequence + 20: (14.0, middle),
        base_sequence + 30: (20.0, right),
        base_sequence + 40: (25.0, distance_base),
        base_sequence + 41: (25.0, mutate(distance_base, 3)),
        base_sequence + 50: (25.0, trailing),
    }
    for sequence, (metric, config_hash) in expected_first.items():
        assert_record(data, sequence, metric, config_hash)
    assert_absent(data, base_sequence + 1)
    assert_absent(data, base_sequence + 31)

    second_base = base_sequence + 1000
    second_payload = [
        {"sequence": second_base, "metric": 4.0, "config_hash": second_left},
        {"sequence": second_base + 10, "metric": None, "config_hash": second_middle},
        {"sequence": second_base + 20, "metric": 16.0, "config_hash": second_tail},
        {"sequence": second_base + 30, "metric": 16.0, "config_hash": mutate(left, 1)},
        {"sequence": second_base + 40, "metric": None, "config_hash": secrets.token_hex(16)},
    ]
    response = post(second_payload)
    assert response.status_code == 200, f"Randomized second ingest failed: {response.status_code}: {response.text}"
    accumulated = get_config()

    for sequence, (metric, config_hash) in expected_first.items():
        assert_record(accumulated, sequence, metric, config_hash)
    assert_record(accumulated, second_base, 4.0, second_left)
    assert_record(accumulated, second_base + 10, 10.0, second_middle)
    assert_record(accumulated, second_base + 20, 16.0, second_tail)
    assert_absent(accumulated, second_base + 30)
    assert_record(accumulated, second_base + 40, 16.0, second_payload[-1]["config_hash"])
TEST_EOF

if test -f /home/user/etl_tracker/Cargo.toml \
   && test -f /home/user/etl_tracker/src/main.rs \
   && cargo build --manifest-path /home/user/etl_tracker/Cargo.toml >/tmp/verifier-cargo.log 2>&1 \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
