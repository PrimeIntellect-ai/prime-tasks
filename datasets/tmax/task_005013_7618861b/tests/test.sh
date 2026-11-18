#!/bin/bash
set -e
mkdir -p /logs/verifier

# Preserve the supplied hasher, then wrap it so the tests can verify that the
# service really uses hash output (including a controlled hash collision).
cp /app/config_hasher /tmp/config_hasher.verifier.real
chmod +x /tmp/config_hasher.verifier.real
restore_hasher() {
    cp /tmp/config_hasher.verifier.real /app/config_hasher
    chmod +x /app/config_hasher
}
trap restore_hasher EXIT

cat << 'HASH_EOF' > /app/config_hasher
#!/bin/bash
case "$1" in
    audit_collision_*)
        printf '%s\n' '00000000000000000000000000000000'
        ;;
    *)
        exec /tmp/config_hasher.verifier.real "$@"
        ;;
esac
HASH_EOF
chmod +x /app/config_hasher

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import random
import secrets
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:8080/process"


def post(payload):
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service or request timed out: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert isinstance(data, list), (
        f"Expected response to be a JSON array, got {type(data).__name__}"
    )
    return data


def config_hash(config_id):
    value = subprocess.check_output(
        ["/app/config_hasher", config_id], text=True, timeout=2
    ).strip()
    assert len(value) == 32 and all(c in "0123456789abcdef" for c in value)
    return value


def impute(records, field):
    values = [r[field] for r in records]
    known = [i for i, value in enumerate(values) if value is not None]
    assert known, f"test fixture must contain a known {field} value"

    first = known[0]
    for i in range(first):
        values[i] = float(values[first])

    for left, right in zip(known, known[1:]):
        left_value = float(values[left])
        right_value = float(values[right])
        left_time = records[left]["timestamp"]
        right_time = records[right]["timestamp"]
        for i in range(left + 1, right):
            ratio = (records[i]["timestamp"] - left_time) / (right_time - left_time)
            values[i] = left_value + ratio * (right_value - left_value)

    last = known[-1]
    for i in range(last + 1, len(values)):
        values[i] = float(values[last])
    return [float(v) for v in values]


def derive_expected(payload):
    ordered = sorted(payload, key=lambda record: record["timestamp"])
    deduplicated = []
    seen = set()
    for record in ordered:
        digest = config_hash(record["config_id"])
        if digest not in seen:
            seen.add(digest)
            deduplicated.append(record)

    if not deduplicated:
        return []

    cpu = impute(deduplicated, "cpu")
    mem = impute(deduplicated, "mem")
    expected = []
    for i, record in enumerate(deduplicated):
        start = max(0, i - 2)
        cpu_window = cpu[start:i + 1]
        mem_window = mem[start:i + 1]
        expected.append({
            "timestamp": record["timestamp"],
            "cpu_imputed": round(cpu[i], 2),
            "mem_imputed": round(mem[i], 2),
            "cpu_rolling_avg": round(sum(cpu_window) / len(cpu_window), 2),
            "mem_rolling_avg": round(sum(mem_window) / len(mem_window), 2),
        })
    return expected


def assert_result(payload, expected=None):
    if expected is None:
        expected = derive_expected(payload)
    data = post(payload)
    assert len(data) == len(expected), (
        f"Expected {len(expected)} records after deduplication, got {len(data)}"
    )

    required = {
        "timestamp", "cpu_imputed", "mem_imputed",
        "cpu_rolling_avg", "mem_rolling_avg"
    }
    for i, exp in enumerate(expected):
        actual = data[i]
        assert isinstance(actual, dict), f"Record {i} is not an object"
        assert required.issubset(actual), f"Record {i} is missing required keys"
        assert actual.get("timestamp") == exp["timestamp"], (
            f"Record {i}: expected timestamp {exp['timestamp']}, "
            f"got {actual.get('timestamp')}"
        )
        for key in ["cpu_imputed", "mem_imputed", "cpu_rolling_avg", "mem_rolling_avg"]:
            actual_val = actual.get(key)
            assert actual_val is not None, f"Record {i}: missing key '{key}'"
            assert isinstance(actual_val, (int, float)) and not isinstance(actual_val, bool), (
                f"Record {i}: '{key}' should be a number"
            )
            assert math.isfinite(actual_val), f"Record {i}: '{key}' must be finite"
            assert round(actual_val, 2) == exp[key], (
                f"Record {i}: expected {key} == {exp[key]}, got {actual_val}"
            )


def test_process_endpoint_original_case():
    # Keep the original verifier's fixed assertions.
    payload = [
        {"timestamp": 50, "cpu": None, "mem": None, "config_id": "D"},
        {"timestamp": 10, "cpu": 2.0, "mem": 100.0, "config_id": "A"},
        {"timestamp": 20, "cpu": None, "mem": None, "config_id": "B"},
        {"timestamp": 30, "cpu": 99.0, "mem": 999.0, "config_id": "A"},
        {"timestamp": 40, "cpu": 8.0, "mem": 200.0, "config_id": "C"}
    ]
    expected = [
        {"timestamp": 10, "cpu_imputed": 2.0, "mem_imputed": 100.0,
         "cpu_rolling_avg": 2.0, "mem_rolling_avg": 100.0},
        {"timestamp": 20, "cpu_imputed": 4.0, "mem_imputed": 133.33,
         "cpu_rolling_avg": 3.0, "mem_rolling_avg": 116.67},
        {"timestamp": 40, "cpu_imputed": 8.0, "mem_imputed": 200.0,
         "cpu_rolling_avg": 4.67, "mem_rolling_avg": 144.44},
        {"timestamp": 50, "cpu_imputed": 8.0, "mem_imputed": 200.0,
         "cpu_rolling_avg": 6.67, "mem_rolling_avg": 177.78}
    ]
    assert_result(payload, expected)


def test_generated_sort_dedup_imputation_and_rolling():
    token = secrets.token_hex(10)
    ids = [f"cfg_{token}_{i}" for i in range(6)]
    payload = [
        {"timestamp": 101, "cpu": None, "mem": 10.0, "config_id": ids[0]},
        {"timestamp": 109, "cpu": 1.25, "mem": None, "config_id": ids[1]},
        {"timestamp": 130, "cpu": None, "mem": None, "config_id": ids[2]},
        {"timestamp": 171, "cpu": 7.75, "mem": 40.0, "config_id": ids[3]},
        {"timestamp": 220, "cpu": None, "mem": None, "config_id": ids[4]},
        {"timestamp": 260, "cpu": None, "mem": 70.0, "config_id": ids[5]},
        # Later occurrences of existing IDs must be discarded chronologically.
        {"timestamp": 145, "cpu": 999.0, "mem": 9999.0, "config_id": ids[1]},
        {"timestamp": 280, "cpu": -500.0, "mem": -500.0, "config_id": ids[3]},
    ]
    random.SystemRandom().shuffle(payload)
    assert_result(payload)


def test_deduplication_uses_hasher_output():
    token = secrets.token_hex(10)
    # The verifier's temporary hasher wrapper deliberately gives these two
    # distinct IDs the same valid hash. Only the chronological first may remain.
    payload = [
        {"timestamp": 35, "cpu": 9.0, "mem": 90.0,
         "config_id": f"ordinary_{token}_2"},
        {"timestamp": 25, "cpu": 500.0, "mem": 5000.0,
         "config_id": f"audit_collision_second_{token}"},
        {"timestamp": 5, "cpu": 2.0, "mem": 20.0,
         "config_id": f"audit_collision_first_{token}"},
        {"timestamp": 15, "cpu": None, "mem": None,
         "config_id": f"ordinary_{token}_1"},
    ]
    assert_result(payload)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
