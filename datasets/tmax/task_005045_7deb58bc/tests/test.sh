#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import socket
import pytest
import requests
import numpy as np
from scipy import stats

NGINX_URL = "http://127.0.0.1:8080/api/stats"
AUTH_HEADER = {"Authorization": "Bearer secret-ml-token-99"}


def get_redis_lrange(key: str) -> list:
    """Fetch a list from Redis using a raw socket."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(("127.0.0.1", 6379))
        cmd = f"*4\r\n$6\r\nLRANGE\r\n${len(key)}\r\n{key}\r\n$1\r\n0\r\n$2\r\n-1\r\n"
        s.sendall(cmd.encode("utf-8"))
        fp = s.makefile("rb")
        line = fp.readline()
        if not line.startswith(b"*"):
            raise ValueError(f"Unexpected Redis response: {line}")
        count = int(line[1:].strip())
        if count == -1:
            return []
        result = []
        for _ in range(count):
            length_line = fp.readline()
            if not length_line.startswith(b"$"):
                raise ValueError(f"Unexpected Redis bulk response: {length_line}")
            length = int(length_line[1:].strip())
            data = fp.read(length)
            result.append(data.decode("utf-8"))
            fp.read(2)
        return result
    finally:
        s.close()


def redis_integer_command(*args) -> int:
    encoded = []
    for arg in args:
        if isinstance(arg, bytes):
            encoded.append(arg)
        else:
            encoded.append(str(arg).encode("utf-8"))
    payload = b"*" + str(len(encoded)).encode() + b"\r\n"
    for arg in encoded:
        payload += b"$" + str(len(arg)).encode() + b"\r\n" + arg + b"\r\n"

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(("127.0.0.1", 6379))
        s.sendall(payload)
        line = s.makefile("rb").readline()
        if not line.startswith(b":"):
            raise ValueError(f"Unexpected Redis response: {line}")
        return int(line[1:].strip())
    finally:
        s.close()


def replace_redis_list(items: list) -> None:
    redis_integer_command("DEL", "raw_telemetry")
    if items:
        redis_integer_command("RPUSH", "raw_telemetry", *items)


def expected_seeded_records() -> list:
    rng = np.random.RandomState(42)
    records = []
    for i in range(500):
        records.append({
            "user_id": f"uA_{i}",
            "group": "A",
            "score": float(rng.normal(80, 10)),
        })
    for i in range(500):
        records.append({
            "user_id": f"uB_{i}",
            "group": "B",
            "score": float(rng.normal(82, 12)),
        })
    return records


def compute_expected_stats(raw_data: list) -> dict:
    group_a = []
    group_b = []

    for item in raw_data:
        obj = json.loads(item)
        if obj.get("group") == "A":
            group_a.append(obj["score"])
        elif obj.get("group") == "B":
            group_b.append(obj["score"])

    n_a = len(group_a)
    n_b = len(group_b)
    mean_a = sum(group_a) / n_a
    mean_b = sum(group_b) / n_b
    var_a = sum((x - mean_a) ** 2 for x in group_a) / (n_a - 1)
    var_b = sum((x - mean_b) ** 2 for x in group_b) / (n_b - 1)
    diff = mean_b - mean_a
    se = math.sqrt(var_b / n_b + var_a / n_a)
    p_value = float(stats.ttest_ind(group_a, group_b, equal_var=False).pvalue)

    return {
        "mean_A": mean_a,
        "mean_B": mean_b,
        "p_value": p_value,
        "ci_lower": diff - 1.96 * se,
        "ci_upper": diff + 1.96 * se,
    }


def assert_response_stats(data: dict, expected: dict) -> None:
    required_keys = {"mean_A", "mean_B", "p_value", "ci_lower", "ci_upper"}
    assert required_keys.issubset(data.keys()), \
        f"Response JSON missing required keys. Found: {list(data.keys())}"

    assert math.isclose(data["mean_A"], expected["mean_A"], abs_tol=1e-4), \
        f"mean_A mismatch: expected {expected['mean_A']}, got {data['mean_A']}"
    assert math.isclose(data["mean_B"], expected["mean_B"], abs_tol=1e-4), \
        f"mean_B mismatch: expected {expected['mean_B']}, got {data['mean_B']}"
    assert math.isclose(data["ci_lower"], expected["ci_lower"], abs_tol=1e-4), \
        f"ci_lower mismatch: expected {expected['ci_lower']}, got {data['ci_lower']}"
    assert math.isclose(data["ci_upper"], expected["ci_upper"], abs_tol=1e-4), \
        f"ci_upper mismatch: expected {expected['ci_upper']}, got {data['ci_upper']}"

    assert isinstance(data["p_value"], float), "p_value must be a float"
    assert 0.0 <= data["p_value"] <= 1.0, \
        f"p_value must be between 0 and 1, got {data['p_value']}"
    assert math.isclose(data["p_value"], expected["p_value"], rel_tol=1e-8, abs_tol=1e-10), \
        f"p_value mismatch: expected {expected['p_value']}, got {data['p_value']}"


def authorized_json() -> dict:
    try:
        response = requests.get(NGINX_URL, headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to Nginx reverse proxy at {NGINX_URL}: {exc}")
    assert response.status_code == 200, \
        f"Expected 200 OK with correct token, got {response.status_code}. Response: {response.text}"
    try:
        return response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Expected JSON response, got invalid JSON: {response.text}")


def test_unauthorized_access():
    try:
        response = requests.get(NGINX_URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to Nginx reverse proxy at {NGINX_URL}: {exc}")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized without token, got {response.status_code}"


def test_authorized_access_and_stats():
    data = authorized_json()

    try:
        raw_telemetry = get_redis_lrange("raw_telemetry")
    except Exception as exc:
        pytest.fail(f"Failed to fetch data from Redis: {exc}")

    assert len(raw_telemetry) > 0, \
        "Redis list 'raw_telemetry' is empty. Was populate_redis.py run?"
    assert len(raw_telemetry) == 1000, \
        f"Expected exactly 1000 seeded telemetry records, found {len(raw_telemetry)}"

    actual_records = [json.loads(item) for item in raw_telemetry]
    seeded_records = expected_seeded_records()
    assert actual_records == seeded_records, \
        "Redis telemetry does not match the specified NumPy seed-42 population"

    expected_stats = compute_expected_stats(raw_telemetry)
    assert_response_stats(data, expected_stats)

    # Exercise the endpoint on verifier-controlled data to ensure it reads Redis
    # and computes every statistic rather than returning fixed seeded constants.
    probe_records = [
        {"user_id": "probe_a0", "group": "A", "score": 3.5},
        {"user_id": "probe_a1", "group": "A", "score": 7.0},
        {"user_id": "probe_a2", "group": "A", "score": 11.25},
        {"user_id": "probe_a3", "group": "A", "score": 19.0},
        {"user_id": "probe_b0", "group": "B", "score": 4.25},
        {"user_id": "probe_b1", "group": "B", "score": 8.5},
        {"user_id": "probe_b2", "group": "B", "score": 15.0},
        {"user_id": "probe_b3", "group": "B", "score": 23.75},
        {"user_id": "probe_b4", "group": "B", "score": 31.0},
    ]
    probe_raw = [json.dumps(record) for record in probe_records]

    try:
        replace_redis_list(probe_raw)
        probe_data = authorized_json()
        assert_response_stats(probe_data, compute_expected_stats(probe_raw))
    finally:
        replace_redis_list(raw_telemetry)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
