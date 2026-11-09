#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/app/vendored/telemetry-processor"
BINARY_PATH = os.path.join(PROJECT_DIR, "target/release/telemetry-processor")
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_binary_on_file(filepath):
    try:
        result = subprocess.run(
            [BINARY_PATH, filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution timed out for {filepath}")

    assert result.returncode == 0, (
        f"Binary exited with status {result.returncode} for {filepath}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    try:
        stdout = result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Binary emitted non-UTF-8 output for {filepath}: {exc}")

    records = []
    for line in stdout.splitlines():
        assert line.strip(), "Output contained an empty JSON-lines record"
        try:
            record = json.loads(line, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
        except (json.JSONDecodeError, ValueError) as exc:
            pytest.fail(f"Output was not valid JSON-lines: {line!r}: {exc}")
        assert isinstance(record, dict), f"Output line is not a JSON object: {line!r}"
        records.append(record)
    return records


def assert_records_equal(actual, expected):
    assert len(actual) == len(expected), f"Expected {len(expected)} records, got {len(actual)}"
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert set(got) == set(want), f"Record {index} has wrong fields: expected {want}, got {got}"
        for key, expected_value in want.items():
            actual_value = got[key]
            if key == "rolling_avg":
                assert isinstance(actual_value, (int, float)) and not isinstance(actual_value, bool)
                assert math.isfinite(float(actual_value))
                assert math.isclose(float(actual_value), float(expected_value), rel_tol=1e-9, abs_tol=1e-7), (
                    f"Record {index} has rolling_avg {actual_value}, expected {expected_value}"
                )
            else:
                assert actual_value == expected_value, (
                    f"Record {index} field {key!r}: expected {expected_value!r}, got {actual_value!r}"
                )


def contains_surrogate(value):
    if isinstance(value, str):
        return any(0xD800 <= ord(ch) <= 0xDFFF for ch in value)
    if isinstance(value, list):
        return any(contains_surrogate(item) for item in value)
    if isinstance(value, dict):
        return any(contains_surrogate(key) or contains_surrogate(item) for key, item in value.items())
    return False


def compute_expected(raw_lines):
    expected = []
    history = {}
    last_accepted = {}

    for raw_line in raw_lines:
        if not raw_line.strip():
            continue
        try:
            record = json.loads(raw_line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(record, dict) or contains_surrogate(record):
            continue

        value = record.get("value")
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        if not math.isfinite(float(value)) or not 0.0 <= float(value) <= 1000.0:
            continue

        sensor_id = record.get("sensor_id")
        message = record.get("message")
        if sensor_id in last_accepted and last_accepted[sensor_id] == message:
            continue

        last_accepted[sensor_id] = message
        history.setdefault(sensor_id, []).append(float(value))
        recent = history[sensor_id][-3:]
        out = record.copy()
        out["rolling_avg"] = sum(recent) / len(recent)
        expected.append(out)

    return expected


def test_make_build_and_binary_exists():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Makefile")), "Makefile is missing"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Cargo.toml is missing"

    if os.path.exists(BINARY_PATH):
        os.remove(BINARY_PATH)
    try:
        result = subprocess.run(
            ["make", "build"],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("`make build` timed out")

    assert result.returncode == 0, f"`make build` failed:\n{result.stdout}"
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_shipped_corpora_follow_record_level_rules():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    files = []
    for directory in (CLEAN_CORPUS_DIR, EVIL_CORPUS_DIR):
        files.extend(
            os.path.join(directory, name)
            for name in os.listdir(directory)
            if name.endswith(".jsonl")
        )
    assert files, "No JSON-lines corpus files were found"

    for filepath in files:
        with open(filepath, "rb") as corpus_file:
            expected = compute_expected(corpus_file.readlines())
        actual = run_binary_on_file(filepath)
        assert_records_equal(actual, expected)


def test_dynamic_mixed_input_filtering_deduplication_and_rolling_average():
    rng = secrets.SystemRandom()
    sensor_a = f"sensor-{secrets.token_hex(8)}"
    sensor_b = f"sensor-{secrets.token_hex(8)}"
    messages = [f"msg-{secrets.token_hex(6)}" for _ in range(7)]
    values = [float(rng.randint(1, 200)) for _ in range(5)]

    chunks = []
    expected = []
    history = {}
    last_accepted = {}

    def append_json(record):
        chunks.append((json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n").encode("utf-8"))

    def accept(record):
        append_json(record)
        sensor_id = record["sensor_id"]
        message = record["message"]
        assert last_accepted.get(sensor_id) != message
        last_accepted[sensor_id] = message
        history.setdefault(sensor_id, []).append(float(record["value"]))
        recent = history[sensor_id][-3:]
        out = record.copy()
        out["rolling_avg"] = sum(recent) / len(recent)
        expected.append(out)

    accept({"sensor_id": sensor_a, "value": values[0], "message": messages[0], "tag": "preserve-me"})
    append_json({"sensor_id": sensor_a, "value": values[1], "message": messages[0]})  # duplicate
    chunks.append((f'{{"sensor_id":{json.dumps(sensor_a)},"value":77,"message":"raw'.encode("utf-8") + b'\x01' + b'control"}\n'))
    accept({"sensor_id": sensor_a, "value": values[1], "message": messages[1]})
    append_json({"sensor_id": sensor_a, "value": -0.01, "message": messages[2]})
    chunks.append((f'{{"sensor_id":{json.dumps(sensor_a)},"value":55,"message":"bad \\uDEAD"}}\n').encode("utf-8"))

    accept({"sensor_id": sensor_b, "value": 1000.0, "message": messages[3]})
    accept({"sensor_id": sensor_b, "value": 500.0, "message": "line\nwith escaped control"})
    accept({"sensor_id": sensor_b, "value": 0.0, "message": "valid emoji 😀"})
    accept({"sensor_id": sensor_a, "value": values[2], "message": messages[2]})
    accept({"sensor_id": sensor_a, "value": values[3], "message": messages[3]})

    append_json({"sensor_id": sensor_a, "value": 1000.01, "message": messages[4]})
    append_json({"sensor_id": sensor_a, "value": "42", "message": messages[4]})
    chunks.append((f'{{"sensor_id":{json.dumps(sensor_a)},"value":42,"message":"bad \\u12G4"}}\n').encode("utf-8"))
    chunks.append(b'{not valid json}\n')

    accept({"sensor_id": sensor_a, "value": values[4], "message": messages[4]})
    append_json({"sensor_id": sensor_a, "value": 999.0, "message": messages[4]})  # duplicate of last accepted

    with tempfile.NamedTemporaryFile(prefix="telemetry-hidden-", suffix=".jsonl", delete=False) as input_file:
        filepath = input_file.name
        for chunk in chunks:
            input_file.write(chunk)

    try:
        actual = run_binary_on_file(filepath)
    finally:
        os.unlink(filepath)

    assert_records_equal(actual, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
