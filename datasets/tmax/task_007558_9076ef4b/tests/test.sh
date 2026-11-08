#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import pytest

OUTPUT_PATH = "/home/user/structured_runs.jsonl"
SCRIPT_PATH = "/home/user/process_logs.py"
INPUT_PATH = "/home/user/experiments.log"


def read_jsonl(output_path):
    actual_data = []
    with open(output_path, "r") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_data.append(record)
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {line_num} in {output_path} is not valid JSON: {e}")
    return actual_data


def test_structured_runs_jsonl_exists_and_content():
    output_path = OUTPUT_PATH

    assert os.path.exists(output_path), f"Expected output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

    expected_data = [
        {
            "Timestamp": "2023-10-01T12:00:00Z",
            "RunID": "1042",
            "User": "USER_ANONYMIZED",
            "Parameters": "alpha=0.5\nbeta=1.2\ngamma=3.0",
            "Results": "SUCCESS"
        },
        {
            "Timestamp": "2023-10-02T14:30:00Z",
            "RunID": "1043",
            "User": "USER_ANONYMIZED",
            "Parameters": "model=transformer\nlayers=12",
            "Results": "FAILURE"
        },
        {
            "Timestamp": "2023-10-03T09:15:00Z",
            "RunID": "1044",
            "User": "USER_ANONYMIZED",
            "Parameters": "",
            "Results": "SUCCESS"
        }
    ]

    actual_data = read_jsonl(output_path)
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(actual_data)} in {output_path}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Record at index {i} does not match expected output.\nExpected: {expected}\nActual: {actual}"


def test_script_exists_and_processes_unseen_input():
    assert os.path.exists(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."

    token = secrets.token_hex(8)
    base_id = 200000 + secrets.randbelow(700000)
    records = [
        {
            "Timestamp": "2041-04-05T06:07:08Z",
            "RunID": str(base_id),
            "User": f"user_{token}",
            "parameter_lines": [
                f"   alpha={token}   ",
                "\tbeta=two words\t",
                "      gamma=9"
            ],
            "Results": f"RESULT_{token}"
        },
        {
            "Timestamp": "2042-05-06T07:08:09+00:00",
            "RunID": str(base_id + 1),
            "User": f"another_{token}",
            "parameter_lines": [" model=dynamic ", "  note=left  right  "],
            "Results": "FAILURE_WITH_DETAIL"
        },
        {
            "Timestamp": "2043-06-07T08:09:10Z",
            "RunID": str(base_id + 2),
            "User": f"empty_{token}",
            "parameter_lines": [],
            "Results": "EMPTY_PARAMETERS_OK"
        }
    ]

    log_lines = []
    expected = []
    for record in records:
        log_lines.extend([
            "--- BEGIN RUN ---",
            f"Timestamp: {record['Timestamp']}",
            f"RunID: {record['RunID']}",
            f"User: {record['User']}",
            "Parameters:"
        ])
        log_lines.extend(record["parameter_lines"])
        log_lines.extend([
            f"Results: {record['Results']}",
            "--- END RUN ---"
        ])
        expected.append({
            "Timestamp": record["Timestamp"],
            "RunID": record["RunID"],
            "User": "USER_ANONYMIZED",
            "Parameters": "\n".join(line.strip() for line in record["parameter_lines"]),
            "Results": record["Results"]
        })

    with open(INPUT_PATH, "w") as f:
        f.write("\n".join(log_lines) + "\n")

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=20
    )
    assert completed.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), f"Script did not create {OUTPUT_PATH}."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."

    actual = read_jsonl(OUTPUT_PATH)
    assert len(actual) == len(expected), f"Expected {len(expected)} generated records, but found {len(actual)}."
    for i, (actual_record, expected_record) in enumerate(zip(actual, expected)):
        assert actual_record == expected_record, (
            f"Generated record at index {i} is incorrect.\n"
            f"Expected: {expected_record}\nActual: {actual_record}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
