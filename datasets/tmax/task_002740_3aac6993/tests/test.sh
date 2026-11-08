#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_fixed_daemon.py
import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile

import pytest

SCRIPT = "/home/user/fixed_daemon.py"
FINAL_STATE = "/home/user/final_state.json"
PROVIDED_DATA = "/home/user/app/test_data.txt"


def load_module():
    spec = importlib.util.spec_from_file_location("submitted_fixed_daemon", SCRIPT)
    assert spec is not None and spec.loader is not None, "fixed_daemon.py is not importable Python"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_script(data_path):
    result = subprocess.run(
        [sys.executable, SCRIPT, data_path],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Script stdout is not valid JSON: {exc}; stdout={result.stdout!r}")


def signed8(text):
    value = int(text, 16)
    return value - 256 if value >= 128 else value


def expected_emas(rows):
    emas = {}
    for sensor_id, text in rows:
        value = signed8(text)
        if sensor_id not in emas:
            emas[sensor_id] = value
        else:
            previous = emas[sensor_id]
            candidate = 0.5 * value + 0.5 * previous
            if abs(candidate - previous) <= 50:
                emas[sensor_id] = candidate
    return emas


def test_fixed_daemon_exists():
    assert os.path.isfile(SCRIPT), f"Expected fixed script at {SCRIPT} is missing."


def test_final_state_json_exists():
    assert os.path.isfile(FINAL_STATE), f"Expected output file at {FINAL_STATE} is missing. Did you run the script and pipe the output?"


def test_final_state_values_and_actual_execution():
    with open(FINAL_STATE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{FINAL_STATE} does not contain valid JSON.")

    assert "s1" in data, "Key 's1' missing from final state JSON."
    assert "s2" in data, "Key 's2' missing from final state JSON."
    assert "s3" in data, "Key 's3' missing from final state JSON."

    expected_s1 = 1.0
    expected_s2 = -2.25
    expected_s3 = 127.0
    assert abs(data["s1"] - expected_s1) < 0.01, f"Expected s1 to be near {expected_s1}, got {data['s1']}"
    assert abs(data["s2"] - expected_s2) < 0.01, f"Expected s2 to be near {expected_s2}, got {data['s2']}"
    assert abs(data["s3"] - expected_s3) < 0.01, f"Expected s3 to be near {expected_s3}, got {data['s3']}"

    actual = run_script(PROVIDED_DATA)
    assert actual == data, "final_state.json is not the current output of fixed_daemon.py on test_data.txt"


def test_parse_hex_signed_8_bit():
    module = load_module()
    assert hasattr(module, "SensorProcessor"), "SensorProcessor is missing"
    processor = module.SensorProcessor()
    assert processor.parse_hex("00") == 0
    assert processor.parse_hex("7f") == 127
    assert processor.parse_hex("80") == -128
    assert processor.parse_hex("ff") == -1
    assert processor.parse_hex("FE") == -2


def test_script_on_derived_unseen_input():
    rng = random.SystemRandom()
    rows = []
    for sensor_number in range(6):
        sensor = f"hidden_{sensor_number}_{rng.randrange(1 << 30)}"
        for _ in range(18):
            rows.append((sensor, f"{rng.randrange(256):02x}"))
    rng.shuffle(rows)

    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        path = handle.name
        for sensor, value in rows:
            handle.write(f"{sensor},{value}\n")
    try:
        actual = run_script(path)
    finally:
        os.unlink(path)

    expected = expected_emas(rows)
    assert set(actual) == set(expected)
    for sensor, value in expected.items():
        assert actual[sensor] == pytest.approx(value), f"Wrong EMA for {sensor}"


def test_retry_queue_does_not_grow_without_bound():
    module = load_module()
    processor = module.SensorProcessor()

    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        path = handle.name
        handle.write("stress,7f\n")
        for _ in range(40000):
            handle.write("stress,80\n")
            handle.write("stress,7f\n")
    try:
        processor.process_readings(path)
        first_size = len(getattr(processor, "retry_queue", []))
        processor.process_readings(path)
        second_size = len(getattr(processor, "retry_queue", []))
    finally:
        os.unlink(path)

    assert second_size <= first_size + 100, (
        f"Retry queue continues growing with repeated failed readings: "
        f"{first_size} entries became {second_size}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_fixed_daemon.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
