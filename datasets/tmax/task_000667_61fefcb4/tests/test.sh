#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import subprocess
import tempfile
import shutil
import shlex
import pytest


def get_expected_crashes():
    processor_log = "/home/user/ingestion_system/logs/processor.log"
    service_a_log = "/home/user/ingestion_system/logs/service_a.log"
    raw_data_file = "/home/user/ingestion_system/raw_data/dump_20231001.jsonl"

    # 1. Find req_ids that crashed
    crash_req_ids = []
    if os.path.exists(processor_log):
        with open(processor_log, "r") as f:
            lines = f.readlines()
            for i, line in enumerate(lines):
                if "Panic: unwrap()" in line:
                    # Look back for the "Starting processing" line
                    for j in range(i - 1, -1, -1):
                        if "Starting processing for" in lines[j]:
                            req_id = lines[j].strip().split()[-1]
                            crash_req_ids.append(req_id)
                            break

    # 2. Get timestamps from service_a.log
    req_to_ts = {}
    if os.path.exists(service_a_log):
        with open(service_a_log, "r") as f:
            for line in f:
                if "Received incoming API request" in line:
                    parts = line.split("INFO: Received incoming API request ")
                    if len(parts) == 2:
                        ts_part = parts[0].strip()[1:-1]
                        req_id = parts[1].split()[0]
                        req_to_ts[req_id] = ts_part

    # 3. Get payload details from raw_data
    req_to_payload = {}
    if os.path.exists(raw_data_file):
        with open(raw_data_file, "r") as f:
            for line in f:
                try:
                    data = json.loads(line)
                    req_to_payload[data["req_id"]] = data
                except json.JSONDecodeError:
                    pass

    expected_rows = []
    for req_id in crash_req_ids:
        ts = req_to_ts.get(req_id, "")
        payload = req_to_payload.get(req_id, {})
        client_version = payload.get("client_version", "")
        duration = payload.get("metrics", {}).get("duration", "")
        expected_rows.append({
            "timestamp": ts,
            "req_id": req_id,
            "client_version": client_version,
            "duration": str(duration),
        })

    expected_rows.sort(key=lambda x: x["timestamp"])
    return expected_rows


def test_crash_timeline_csv():
    csv_path = "/home/user/crash_timeline.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    expected_rows = get_expected_crashes()
    assert len(expected_rows) > 0, "Could not determine expected crashes from logs. Environment may be broken."

    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ["timestamp", "req_id", "client_version", "duration"], \
        f"CSV header is incorrect. Expected ['timestamp', 'req_id', 'client_version', 'duration'], got {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in CSV, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual["timestamp"] == expected["timestamp"], f"Row {i+1} timestamp mismatch: expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual["req_id"] == expected["req_id"], f"Row {i+1} req_id mismatch: expected {expected['req_id']}, got {actual['req_id']}"
        assert actual["client_version"] == expected["client_version"], f"Row {i+1} client_version mismatch: expected {expected['client_version']}, got {actual['client_version']}"
        assert int(actual["duration"]) < 0, f"Row {i+1} duration must be negative, got {actual['duration']}"
        assert actual["duration"] == expected["duration"], f"Row {i+1} duration mismatch: expected {expected['duration']}, got {actual['duration']}"


def read_invocations(marker):
    assert os.path.isfile(marker), "Regression test did not invoke process.sh."
    tokens = open(marker, "rb").read().split(b"\0")
    if tokens and tokens[-1] == b"":
        tokens.pop()

    invocations = []
    pos = 0
    while pos < len(tokens):
        try:
            argc = int(tokens[pos].decode("ascii"))
        except (ValueError, UnicodeDecodeError):
            pytest.fail("Could not decode the recorded process.sh invocation.")
        pos += 1
        assert pos + argc <= len(tokens), "Incomplete process.sh invocation record."
        invocations.append([value.decode("utf-8") for value in tokens[pos:pos + argc]])
        pos += argc
    return invocations


def assert_required_payload(invocations, anomalous_client_version):
    assert invocations, "Regression test did not invoke process.sh."
    valid = False
    errors = []
    for args in invocations:
        if len(args) != 1:
            errors.append(f"process.sh received {len(args)} arguments instead of one")
            continue
        try:
            payload = json.loads(args[0])
        except json.JSONDecodeError as exc:
            errors.append(f"argument was not valid JSON: {exc}")
            continue

        duration = payload.get("metrics", {}).get("duration") if isinstance(payload, dict) else None
        if payload.get("req_id") != "req-test-999":
            errors.append("payload req_id was not req-test-999")
            continue
        if payload.get("client_version") != anomalous_client_version:
            errors.append("payload did not use the anomalous client_version")
            continue
        if isinstance(duration, bool) or not isinstance(duration, (int, float)) or duration >= 0:
            errors.append("payload metrics.duration was not negative")
            continue
        valid = True

    assert valid, "No process.sh invocation supplied the required anomalous payload: " + "; ".join(errors)


def install_wrapper(process_path, delegate, marker, forced_exit=None):
    if forced_exit is None:
        ending = f"exec {shlex.quote(delegate)} \"$@\""
    else:
        ending = f"exit {forced_exit}"

    wrapper = f'''#!/bin/bash
{{
  printf '%s\\0' "$#"
  for arg in "$@"; do
    printf '%s\\0' "$arg"
  done
}} >> {shlex.quote(marker)}
{ending}
'''
    with open(process_path, "w") as f:
        f.write(wrapper)
    os.chmod(process_path, 0o755)


def test_regression_test_script():
    script_path = "/home/user/regression_test.sh"
    process_path = "/home/user/ingestion_system/process.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        script_content = f.read()

    assert "req-test-999" in script_content, "Regression test script does not contain the synthetic req_id 'req-test-999'."
    assert "/home/user/ingestion_system/process.sh" in script_content, "Regression test script does not call the process.sh script."

    expected_rows = get_expected_crashes()
    versions = {row["client_version"] for row in expected_rows}
    assert len(versions) == 1, "Could not determine a unique anomalous client_version."
    anomalous_client_version = next(iter(versions))

    workdir = tempfile.mkdtemp(prefix="regression_verify_")
    real_process = os.path.join(workdir, "process.real.sh")
    crash_marker = os.path.join(workdir, "crash_invocations")
    success_marker = os.path.join(workdir, "success_invocations")
    os.replace(process_path, real_process)

    try:
        # First exercise the real processor and verify the actual argument supplied.
        install_wrapper(process_path, real_process, crash_marker)
        result = subprocess.run([script_path], capture_output=True, text=True)

        assert result.returncode == 0, f"Regression test script failed with exit code {result.returncode}. Output: {result.stdout}\n{result.stderr}"
        assert "Test Passed: Crash Reproduced" in result.stdout or "Test Passed" in result.stdout, \
            f"Regression test did not output the expected success message. Output: {result.stdout}"
        assert_required_payload(read_invocations(crash_marker), anomalous_client_version)

        # Force process.sh to succeed and ensure the regression script handles that exit code.
        install_wrapper(process_path, real_process, success_marker, forced_exit=0)
        result = subprocess.run([script_path], capture_output=True, text=True)
        assert_required_payload(read_invocations(success_marker), anomalous_client_version)
        assert result.returncode == 1, \
            f"Regression test must exit 1 when process.sh succeeds, but exited {result.returncode}. Output: {result.stdout}\n{result.stderr}"
        assert "Test Failed: No Crash" in result.stdout, \
            f"Regression test did not report the non-crash failure. Output: {result.stdout}"
    finally:
        if os.path.lexists(process_path):
            if os.path.isdir(process_path) and not os.path.islink(process_path):
                shutil.rmtree(process_path)
            else:
                os.unlink(process_path)
        os.replace(real_process, process_path)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
