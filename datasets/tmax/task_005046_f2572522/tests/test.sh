#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import statistics
import subprocess
import time

import pytest

SUMMARY_FILE = '/home/user/summary.json'
PROCESS_SCRIPT = '/home/user/process.py'
DATA_DIR = '/home/user/sensor_data'


def test_summary_file_exists():
    assert os.path.isfile(SUMMARY_FILE), f"The output file {SUMMARY_FILE} does not exist."


def test_summary_json_content():
    with open(SUMMARY_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SUMMARY_FILE} does not contain valid JSON.")

    expected_data = {
        "S01": {"max_temperature": 37.0, "mean_vibration": 14.60, "temp_spikes": 3},
        "S02": {"max_temperature": 30.0, "mean_vibration": 9.50, "temp_spikes": 4},
        "S03": {"max_temperature": 50.0, "mean_vibration": 5.50, "temp_spikes": 4}
    }

    for sensor, expected_features in expected_data.items():
        assert sensor in data, f"Sensor {sensor} is missing from the summary JSON."
        actual_features = data[sensor]
        for feature, expected_val in expected_features.items():
            assert feature in actual_features, f"Feature '{feature}' is missing for sensor {sensor}."
            actual_val = actual_features[feature]
            if isinstance(expected_val, float):
                assert math.isclose(actual_val, expected_val, rel_tol=1e-2), \
                    f"Expected {feature} for {sensor} to be {expected_val}, but got {actual_val}."
            else:
                assert actual_val == expected_val, \
                    f"Expected {feature} for {sensor} to be {expected_val}, but got {actual_val}."


def _interpolate(values):
    result = list(values)
    valid = [i for i, value in enumerate(result) if value is not None]
    assert valid
    first, last = valid[0], valid[-1]
    for i in range(first):
        result[i] = result[first]
    for left, right in zip(valid, valid[1:]):
        if right > left + 1:
            step = (result[right] - result[left]) / (right - left)
            for i in range(left + 1, right):
                result[i] = result[left] + step * (i - left)
    for i in range(last + 1, len(result)):
        result[i] = result[last]
    return result


def _make_unseen_dataset():
    os.makedirs(DATA_DIR, exist_ok=True)
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isfile(path):
            os.unlink(path)

    rng = secrets.SystemRandom()
    token = secrets.token_hex(5)
    expected = {}
    row_count = 40000

    for file_number in range(8):
        sensor_id = f"DYN_{token}_{file_number}"
        temperatures = []
        vibrations = []
        path = os.path.join(DATA_DIR, f"unseen_batch_{file_number}.csv")

        with open(path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'sensor_id', 'temperature', 'vibration'])
            for row in range(row_count):
                temp = round(18.0 + file_number * 1.7 + (row % 41) * 0.19 + rng.uniform(-0.7, 0.7), 4)
                if row % 997 == 503:
                    temp += 13.0
                vibration = round(2.0 + file_number * 0.31 + (row % 29) * 0.11 + rng.uniform(-0.35, 0.35), 4)

                missing_temp = row == 0 or row == row_count - 1 or row % 113 == 17
                missing_vibration = row % 97 == 23 or row % 389 == 7
                temperatures.append(None if missing_temp else temp)
                vibrations.append(None if missing_vibration else vibration)

                temp_cell = ('NaN' if row % 2 else '') if missing_temp else temp
                vibration_cell = ('NaN' if row % 3 else '') if missing_vibration else vibration
                writer.writerow([row + 1, sensor_id, temp_cell, vibration_cell])

        clean_temp = _interpolate(temperatures)
        present_vibration = [v for v in vibrations if v is not None]
        median_vibration = statistics.median(present_vibration)
        clean_vibration = [median_vibration if v is None else v for v in vibrations]
        mean_temp = sum(clean_temp) / len(clean_temp)
        expected[sensor_id] = {
            'max_temperature': max(clean_temp),
            'mean_vibration': round(sum(clean_vibration) / len(clean_vibration), 2),
            'temp_spikes': sum(1 for value in clean_temp if value > mean_temp + 2.0),
        }

    return expected


def _descendants(pid):
    found = set()
    pending = [pid]
    while pending:
        parent = pending.pop()
        children_file = f'/proc/{parent}/task/{parent}/children'
        try:
            with open(children_file) as f:
                children = [int(value) for value in f.read().split()]
        except (FileNotFoundError, ProcessLookupError, ValueError):
            continue
        for child in children:
            if child not in found:
                found.add(child)
                pending.append(child)
    return found


def _cpu_ticks(pid):
    try:
        with open(f'/proc/{pid}/stat') as f:
            stat = f.read()
        fields = stat[stat.rfind(')') + 2:].split()
        return int(fields[11]) + int(fields[12])
    except (FileNotFoundError, ProcessLookupError, ValueError, IndexError):
        return None


def test_parallel_processing_used_and_pipeline_handles_unseen_inputs():
    assert os.path.isfile(PROCESS_SCRIPT), f"The script {PROCESS_SCRIPT} does not exist."
    with open(PROCESS_SCRIPT, 'r') as f:
        script_content = f.read()
    has_multiprocessing = ('multiprocessing' in script_content or
                           'ProcessPoolExecutor' in script_content or
                           'concurrent.futures' in script_content)
    assert has_multiprocessing, \
        f"The script {PROCESS_SCRIPT} does not appear to use multiprocessing or concurrent.futures as required."

    expected = _make_unseen_dataset()
    if os.path.exists(SUMMARY_FILE):
        os.unlink(SUMMARY_FILE)

    log_path = '/tmp/process_execution.log'
    previous_ticks = {}
    cpu_active_children = set()
    maximum_simultaneous_children = 0

    with open(log_path, 'w+') as log:
        process = subprocess.Popen(
            ['python3', PROCESS_SCRIPT],
            cwd='/home/user',
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        deadline = time.time() + 120
        while process.poll() is None:
            children = _descendants(process.pid)
            maximum_simultaneous_children = max(maximum_simultaneous_children, len(children))
            for child in children:
                ticks = _cpu_ticks(child)
                if ticks is not None:
                    if child in previous_ticks and ticks > previous_ticks[child]:
                        cpu_active_children.add(child)
                    previous_ticks[child] = ticks
            if time.time() > deadline:
                process.kill()
                process.wait()
                pytest.fail('process.py did not finish within 120 seconds.')
            time.sleep(0.003)
        return_code = process.returncode
        log.seek(0)
        output = log.read()

    assert return_code == 0, f"Executing process.py failed with exit code {return_code}:\n{output}"
    assert maximum_simultaneous_children >= 2, \
        "process.py did not run at least two worker processes concurrently."
    assert len(cpu_active_children) >= 2, \
        "At least two multiprocessing workers were not observed executing work."
    assert os.path.isfile(SUMMARY_FILE), \
        f"Executing {PROCESS_SCRIPT} did not create {SUMMARY_FILE}."

    try:
        with open(SUMMARY_FILE) as f:
            actual = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        pytest.fail(f"The generated summary is not valid JSON: {exc}")

    assert set(actual) == set(expected), \
        f"Expected exactly the dynamically supplied sensor IDs, got {set(actual)}."
    for sensor_id, expected_features in expected.items():
        assert isinstance(actual[sensor_id], dict)
        assert set(actual[sensor_id]) == set(expected_features)
        for feature, expected_value in expected_features.items():
            actual_value = actual[sensor_id][feature]
            if feature == 'temp_spikes':
                assert isinstance(actual_value, int) and not isinstance(actual_value, bool)
                assert actual_value == expected_value
            else:
                assert isinstance(actual_value, (int, float)) and not isinstance(actual_value, bool)
                assert math.isclose(float(actual_value), expected_value, rel_tol=1e-9, abs_tol=1e-7), \
                    f"Wrong {feature} for {sensor_id}: expected {expected_value}, got {actual_value}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
