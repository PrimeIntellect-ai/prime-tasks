#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import itertools
import json
import os
import subprocess
import sys
import tempfile

MINIMAL_CRASH_PATH = "/home/user/minimal_crash.ndjson"
PROCESSOR_PATH = "/home/user/processor.py"
FIXED_PROCESSOR_PATH = "/home/user/fixed_processor.py"
SENSOR_LOGS_PATH = "/home/user/sensor_logs.ndjson"

ORIGINAL_PROCESSOR = '''import json
import sys

def process_logs(file_path):
    temps = []
    processed_count = 0
    with open(file_path, 'r') as f:
        for line in f:
            if not line.strip(): continue
            data = json.loads(line)
            temp = float(data['temperature'])
            temps.append(temp)
            if len(temps) > 5:
                temps.pop(0)

            if len(temps) == 5:
                avg_temp = sum(temps) / 5
                if avg_temp > 100:
                    # High temperature compensation logic triggers
                    humidity = int(data['humidity']) # Crashes if humidity is "N/A"
                    pass # further processing

            processed_count += 1
    return processed_count

if __name__ == '__main__':
    try:
        process_logs(sys.argv[1])
        print("Success")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
'''

ORIGINAL_LINES = [
    '{"temperature": 45.0, "humidity": "40"}',
    '{"temperature": 50.0, "humidity": "45"}',
    '{"temperature": 55.0, "humidity": "50"}',
    '{"temperature": 60.0, "humidity": "55"}',
    '{"temperature": 65.0, "humidity": "60"}',
    '{"temperature": 105.0, "humidity": "10"}',
    '{"temperature": 110.0, "humidity": "15"}',
    '{"temperature": 102.0, "humidity": "12"}',
    '{"temperature": 108.0, "humidity": "14"}',
    '{"temperature": 101.0, "humidity": "N/A"}',
    '{"temperature": 40.0, "humidity": "30"}',
]
ORIGINAL_SENSOR_LOGS = "\n".join(ORIGINAL_LINES) + "\n"


def assert_original_inputs_unchanged():
    assert os.path.isfile(PROCESSOR_PATH)
    assert os.path.isfile(SENSOR_LOGS_PATH)
    with open(PROCESSOR_PATH, "r") as f:
        assert f.read() == ORIGINAL_PROCESSOR, "The original processor.py must not be modified."
    with open(SENSOR_LOGS_PATH, "r") as f:
        assert f.read() == ORIGINAL_SENSOR_LOGS, "The original sensor dataset must not be modified."


def model_error(lines):
    temps = []
    try:
        for line in lines:
            data = json.loads(line)
            temps.append(float(data['temperature']))
            if len(temps) > 5:
                temps.pop(0)
            if len(temps) == 5 and sum(temps) / 5 > 100:
                int(data['humidity'])
    except Exception as exc:
        return type(exc), str(exc)
    return None


def derive_minimal_crash_sequences():
    target = (ValueError, str(ValueError("invalid literal for int() with base 10: 'N/A'")))
    # Delta debugging removes records without reordering the remaining records.
    for size in range(len(ORIGINAL_LINES) + 1):
        matches = []
        for indexes in itertools.combinations(range(len(ORIGINAL_LINES)), size):
            candidate = [ORIGINAL_LINES[i] for i in indexes]
            if model_error(candidate) == target:
                matches.append(candidate)
        if matches:
            return matches
    raise AssertionError("The supplied dataset has no reproducer")


def test_original_inputs_are_unchanged():
    assert_original_inputs_unchanged()


def test_minimal_crash_exists_and_length():
    assert_original_inputs_unchanged()
    assert os.path.isfile(MINIMAL_CRASH_PATH), f"Expected file {MINIMAL_CRASH_PATH} to exist."
    with open(MINIMAL_CRASH_PATH, 'r') as f:
        lines = [line for line in f.read().splitlines() if line.strip()]

    # Preserve the original length and JSON assertions.
    assert len(lines) == 5, f"Expected {MINIMAL_CRASH_PATH} to contain exactly 5 lines, found {len(lines)}."
    for line in lines:
        json.loads(line)

    minimal_sequences = derive_minimal_crash_sequences()
    assert all(len(sequence) == 5 for sequence in minimal_sequences)
    assert lines in minimal_sequences, (
        "minimal_crash.ndjson must be an order-preserving minimal sequence of actual lines "
        "from sensor_logs.ndjson that triggers the target ValueError."
    )


def test_minimal_crash_reproduces_exact_bug():
    assert_original_inputs_unchanged()
    result = subprocess.run(
        ["python3", PROCESSOR_PATH, MINIMAL_CRASH_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )
    expected_message = str(ValueError("invalid literal for int() with base 10: 'N/A'"))
    assert result.returncode != 0, "Expected the original processor to crash."
    assert result.returncode == 1
    assert result.stdout.strip() == f"Error: {expected_message}", (
        "The reproducer must trigger the same humidity-parsing ValueError, not merely any failure."
    )
    assert result.stderr == ""


def test_fixed_processor_exists_and_works():
    assert_original_inputs_unchanged()
    assert os.path.isfile(FIXED_PROCESSOR_PATH), f"Expected file {FIXED_PROCESSOR_PATH} to exist."
    assert os.path.isfile(SENSOR_LOGS_PATH)
    with open(FIXED_PROCESSOR_PATH, "rb") as fixed, open(PROCESSOR_PATH, "rb") as original:
        assert fixed.read() != original.read(), "fixed_processor.py must be a repaired implementation."

    result = subprocess.run(
        ["python3", FIXED_PROCESSOR_PATH, SENSOR_LOGS_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Expected fixed_processor.py to succeed, got {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert "Success" in result.stdout
    assert_original_inputs_unchanged()


PROBE = r'''
import importlib.util, json, os, sys
path, data_path = sys.argv[1], sys.argv[2]
saw_minus_one = False

def tracer(frame, event, arg):
    global saw_minus_one
    if (frame.f_code.co_name == "process_logs" and
            os.path.abspath(frame.f_code.co_filename) == os.path.abspath(path)):
        if frame.f_locals.get("humidity", object()) == -1:
            saw_minus_one = True
    return tracer

try:
    spec = importlib.util.spec_from_file_location("submitted_fixed_processor", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "process_logs") or not callable(module.process_logs):
        raise AssertionError("fixed processor must retain the process_logs function")
    sys.settrace(tracer)
    try:
        value = module.process_logs(data_path)
    finally:
        sys.settrace(None)
    result = {"ok": True, "value": value, "saw_minus_one": saw_minus_one}
except BaseException as exc:
    sys.settrace(None)
    result = {"ok": False, "type": type(exc).__name__, "message": str(exc),
              "saw_minus_one": saw_minus_one}
print("__PROBE__" + json.dumps(result, sort_keys=True))
'''


def probe(lines):
    fd, path = tempfile.mkstemp(prefix="processor-case-", suffix=".ndjson")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")
        result = subprocess.run(
            [sys.executable, "-c", PROBE, FIXED_PROCESSOR_PATH, path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Probe failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        records = [line for line in result.stdout.splitlines() if line.startswith("__PROBE__")]
        assert len(records) == 1, f"Could not read probe result from stdout: {result.stdout!r}"
        return json.loads(records[0][len("__PROBE__"):])
    finally:
        os.unlink(path)


def encoded(records):
    return [json.dumps(record, separators=(",", ":")) for record in records]


def test_fixed_processor_preserves_processing_and_uses_minus_one_fallback():
    assert_original_inputs_unchanged()

    anomalous_invalid = encoded([
        {"temperature": 120, "humidity": "1"},
        {"temperature": 121, "humidity": "2"},
        {"temperature": 122, "humidity": "3"},
        {"temperature": 123, "humidity": "4"},
        {"temperature": 124, "humidity": "not-an-integer"},
        {"temperature": 20, "humidity": "5"},
    ])
    outcome = probe(anomalous_invalid)
    assert outcome == {"ok": True, "value": 6, "saw_minus_one": True}, (
        "An invalid humidity in a high-temperature window must be assigned -1 and processing must continue."
    )

    low_temperature_invalid = encoded([
        {"temperature": 10, "humidity": "1"},
        {"temperature": 11, "humidity": "2"},
        {"temperature": 12, "humidity": "3"},
        {"temperature": 13, "humidity": "4"},
        {"temperature": 14, "humidity": "not-an-integer"},
    ])
    outcome = probe(low_temperature_invalid)
    assert outcome["ok"] is True and outcome["value"] == 5
    assert outcome["saw_minus_one"] is False, "Humidity parsing must remain conditional on the anomaly."

    valid_anomaly = encoded([
        {"temperature": 150, "humidity": "10"},
        {"temperature": 151, "humidity": "11"},
        {"temperature": 152, "humidity": "12"},
        {"temperature": 153, "humidity": "13"},
        {"temperature": 154, "humidity": "14"},
    ])
    outcome = probe(valid_anomaly)
    assert outcome["ok"] is True and outcome["value"] == 5
    assert outcome["saw_minus_one"] is False


def test_fixed_processor_does_not_hide_unrelated_input_errors():
    assert_original_inputs_unchanged()

    bad_temperature = encoded([{"temperature": "bad", "humidity": "10"}])
    outcome = probe(bad_temperature)
    assert outcome["ok"] is False and outcome["type"] == "ValueError"

    malformed_json = ['{"temperature": 10,']
    outcome = probe(malformed_json)
    assert outcome["ok"] is False and outcome["type"] == "JSONDecodeError"

    missing_humidity = encoded([
        {"temperature": 130, "humidity": "1"},
        {"temperature": 131, "humidity": "2"},
        {"temperature": 132, "humidity": "3"},
        {"temperature": 133, "humidity": "4"},
        {"temperature": 134},
    ])
    outcome = probe(missing_humidity)
    assert outcome["ok"] is False and outcome["type"] == "KeyError"
    assert_original_inputs_unchanged()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
