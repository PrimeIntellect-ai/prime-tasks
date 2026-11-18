#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/process_logs.sh"
INPUT_PATH = "/home/user/cargo_logs.jsonl"
OUTPUT_PATH = "/home/user/dashboard_data.json"


def write_jsonl(records):
    with open(INPUT_PATH, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists_and_executable():
    script_path = "/home/user/process_logs.sh"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
    syntax = subprocess.run(
        ["/bin/bash", "-n", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert syntax.returncode == 0, f"Script is not valid Bash syntax: {syntax.stderr}"


def test_script_executes_on_baseline_input():
    write_jsonl([
        {"reason": "compiler-artifact", "message": {"code": {"code": "E0382"}, "spans": [{"file_name": "ignored.rs", "line_start": 1}]}},
        {"reason": "compiler-message", "message": {"code": {"code": "E0382"}, "spans": [{"file_name": "src/main.rs", "line_start": 5}]}},
        {"reason": "compiler-message", "message": {"code": {"code": "E0499"}, "spans": [{"file_name": "src/lib.rs", "line_start": 10}]}},
        {"reason": "compiler-message", "message": {"code": {"code": "E0382"}, "spans": [{"file_name": "src/config.rs", "line_start": 42}]}},
    ])
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_script()


def test_dashboard_data_exists():
    data_path = "/home/user/dashboard_data.json"
    assert os.path.isfile(data_path), f"Output file missing: {data_path}"


def test_dashboard_data_content():
    data_path = "/home/user/dashboard_data.json"

    with open(data_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {data_path} is not valid JSON"

    assert isinstance(data, list), f"Expected the root of {data_path} to be a JSON array, got {type(data).__name__}"

    expected_data = [
        {
            "error_code": "E0382",
            "file": "src/main.rs",
            "line": 5
        },
        {
            "error_code": "E0382",
            "file": "src/config.rs",
            "line": 42
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} elements in the JSON array, but found {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}:\nExpected: {expected}\nActual: {actual}"


def test_script_processes_changed_input_and_first_spans():
    token = secrets.token_hex(12)
    file_one = f"generated/{token}/owner.rs"
    file_two = f"generated/{token}/borrow.rs"
    line_one = 1000 + secrets.randbelow(50000)
    line_two = 60000 + secrets.randbelow(50000)

    records = [
        {"reason": "compiler-message", "message": {"code": {"code": "E0499"}, "spans": [{"file_name": f"decoy-{token}.rs", "line_start": 9}]}},
        {"reason": "compiler-message", "message": {"code": {"code": "E0382"}, "spans": [
            {"file_name": file_one, "line_start": line_one, "is_primary": False},
            {"file_name": f"wrong-second-{token}.rs", "line_start": 1, "is_primary": True}
        ]}},
        {"reason": "compiler-artifact", "message": {"code": {"code": "E0382"}, "spans": [{"file_name": f"wrong-reason-{token}.rs", "line_start": 2}]}},
        {"reason": "compiler-message", "message": {"code": None, "spans": [{"file_name": f"missing-code-{token}.rs", "line_start": 3}]}},
        {"reason": "compiler-message", "message": {"code": {"code": "E0382"}, "spans": [
            {"file_name": file_two, "line_start": line_two},
            {"file_name": f"another-wrong-second-{token}.rs", "line_start": 4}
        ]}},
    ]
    expected = [
        {"error_code": "E0382", "file": file_one, "line": line_one},
        {"error_code": "E0382", "file": file_two, "line": line_two},
    ]

    write_jsonl(records)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write("stale output that must be replaced")
    run_script()

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        actual = json.load(f)
    assert actual == expected, f"Changed-input result mismatch:\nExpected: {expected}\nActual: {actual}"

    write_jsonl([
        {"reason": "compiler-message", "message": {"code": {"code": "E0502"}, "spans": [{"file_name": f"none-{token}.rs", "line_start": 7}]}},
        {"reason": "build-script-executed"},
    ])
    run_script()
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        empty_result = json.load(f)
    assert empty_result == [], f"Expected an empty JSON array when there are no E0382 messages, got {empty_result}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
