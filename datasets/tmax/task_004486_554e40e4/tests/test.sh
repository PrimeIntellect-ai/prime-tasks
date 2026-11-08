#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.util
import json
import math
import os
import secrets
import subprocess
import sys
import uuid

import pytest

OUTPUT_FILE = "/home/user/app/output.json"
DATA_DIR = "/home/user/app/data"
PROCESSOR_FILE = "/home/user/app/processor.py"
DYNAMIC_EXPECTED = {}


def stable_sigmoid(x):
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_with_unseen_inputs():
    assert os.path.isfile(PROCESSOR_FILE), f"{PROCESSOR_FILE} is missing"

    token = uuid.uuid4().hex
    utf8_path = os.path.join(DATA_DIR, f"verifier_utf8_{token}.json")
    utf16_path = os.path.join(DATA_DIR, f"verifier_utf16_{token}.json")

    utf8_data = {
        f"verify_normal_{token}": secrets.SystemRandom().uniform(-8.0, 8.0),
        f"verify_large_positive_{token}": 1000.0,
    }
    utf16_data = {
        f"verify_large_negative_{token}": -1000.0,
        f"verify_other_{token}": secrets.SystemRandom().uniform(-30.0, 30.0),
    }
    DYNAMIC_EXPECTED.update(utf8_data)
    DYNAMIC_EXPECTED.update(utf16_data)

    with open(utf8_path, "w", encoding="utf-8") as f:
        json.dump(utf8_data, f)
    with open(utf16_path, "w", encoding="utf-16") as f:
        json.dump(utf16_data, f)

    try:
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        completed = subprocess.run(
            [sys.executable, PROCESSOR_FILE],
            cwd="/home/user/app",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert completed.returncode == 0, (
            f"processor.py failed with exit code {completed.returncode}.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        yield
    finally:
        for path in (utf8_path, utf16_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not generated. Did you run the pipeline?"


def test_output_contains_all_keys():
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_FILE} is not a valid JSON file.")

    expected_keys = {f"sensor_{i}" for i in range(1, 7)}
    actual_keys = set(data.keys())

    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"Output JSON is missing expected keys: {missing_keys}"


def test_output_values_correct():
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Check specific edge cases
    assert 'sensor_4' in data, "sensor_4 is missing from output"
    assert math.isclose(data['sensor_4'], 0.0, abs_tol=1e-9), f"sensor_4 activation should be 0.0, got {data['sensor_4']}"

    assert 'sensor_3' in data, "sensor_3 is missing from output"
    assert math.isclose(data['sensor_3'], 1.0, abs_tol=1e-9), f"sensor_3 activation should be 1.0, got {data['sensor_3']}"

    # Check standard cases
    assert 'sensor_5' in data, "sensor_5 is missing from output"
    assert math.isclose(data['sensor_5'], 0.5, abs_tol=1e-9), f"sensor_5 activation (input 0.0) should be 0.5, got {data['sensor_5']}"


def test_all_original_and_unseen_output_values():
    expected_inputs = {
        "sensor_1": 1.2,
        "sensor_2": -0.5,
        "sensor_3": 850.0,
        "sensor_4": -1200.0,
        "sensor_5": 0.0,
        "sensor_6": 10.0,
    }
    expected_inputs.update(DYNAMIC_EXPECTED)

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert set(data) == set(expected_inputs), "Output keys do not match all processed input keys"
    for key, value in expected_inputs.items():
        expected = stable_sigmoid(value)
        actual = data[key]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"Incorrect activation for {key}: expected {expected}, got {actual}"
        )


def test_compute_activation_is_stable_and_equivalent():
    spec = importlib.util.spec_from_file_location("submitted_processor", PROCESSOR_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "compute_activation", None)), "compute_activation is missing"

    rng = secrets.SystemRandom()
    values = [
        -sys.float_info.max,
        -1200.0,
        -850.0,
        -100.0,
        -1.0,
        0.0,
        1.0,
        100.0,
        850.0,
        1200.0,
        sys.float_info.max,
    ]
    values.extend(rng.uniform(-1500.0, 1500.0) for _ in range(20))

    for value in values:
        try:
            actual = module.compute_activation(value)
        except OverflowError as exc:
            pytest.fail(f"compute_activation overflowed for {value}: {exc}")
        expected = stable_sigmoid(value)
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"compute_activation({value}) returned {actual}, expected {expected}"
        )


def test_data_files_unmodified():
    # Ensure the original data files haven't been modified to "fix" the encoding issue
    data_1 = os.path.join(DATA_DIR, "data_1.json")
    data_2 = os.path.join(DATA_DIR, "data_2.json")

    assert os.path.isfile(data_1), "data_1.json is missing"
    assert os.path.isfile(data_2), "data_2.json is missing"

    # Check that data_2.json is still UTF-16
    try:
        with open(data_2, 'r', encoding='utf-16') as f:
            content = f.read()
            assert "sensor_3" in content
    except UnicodeDecodeError:
        pytest.fail("data_2.json was modified and is no longer valid UTF-16. You must fix the python script, not the data files.")


def test_all_original_data_files_are_unchanged():
    expected = {
        "data_1.json": b'{"sensor_1": 1.2, "sensor_2": -0.5}\n',
        "data_2.json": '{"sensor_3": 850.0, "sensor_4": -1200.0}'.encode('utf-16'),
        "data_3.json": b'{"sensor_5": 0.0, "sensor_6": 10.0}\n',
    }
    for name, expected_bytes in expected.items():
        path = os.path.join(DATA_DIR, name)
        assert os.path.isfile(path), f"{name} is missing"
        with open(path, "rb") as f:
            assert f.read() == expected_bytes, f"{name} was modified"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
