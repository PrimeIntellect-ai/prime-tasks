#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_pipeline.sh"
INPUT_PATH = "/home/user/raw_logs.jsonl"
OUTPUT_PATH = "/home/user/clean_logs.jsonl"

ORIGINAL_INPUT = "\n".join([
    r'{"id": 1, "update_text": "Set timeout=60 and retries=3 for the database connection."}',
    r'{"id": 2, "update_text": "Update DB_PASSWORD=db_pass_123 \u005Z error in auth module"}',
    r'{"id": 3, "update_text": "Changed api_key=XYZ890 and port=8080"}',
    r'{"id": 4, "update_text": "Valid unicode \u2713 auth_token=abc123"}',
    r'{"id": 5, "update_text": "No configs here, just a status update \uG123"}',
]) + "\n"


def write_input(text):
    with open(INPUT_PATH, "w", encoding="utf-8") as f:
        f.write(text)


def read_output():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."
    records = []
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {line_num} in {OUTPUT_PATH} is not valid JSON: {e}")
    return records


def execute_pipeline():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, cwd="/home/user")
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_pipeline_execution_and_output():
    write_input(ORIGINAL_INPUT)
    execute_pipeline()

    expected_records = [
        {"id": 1, "configs": {"timeout": "60", "retries": "3"}},
        {"id": 2, "configs": {"DB_PASSWORD": "***"}},
        {"id": 3, "configs": {"api_key": "***", "port": "8080"}},
        {"id": 4, "configs": {"auth_token": "***"}},
        {"id": 5, "configs": {}}
    ]

    actual_records = read_output()
    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records, but found {len(actual_records)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records), 1):
        assert "id" in actual, f"Record {i} is missing the 'id' key."
        assert "configs" in actual, f"Record {i} is missing the 'configs' key."
        assert actual["id"] == expected["id"], (
            f"Record {i} id mismatch: expected {expected['id']}, got {actual['id']}."
        )
        assert actual["configs"] == expected["configs"], (
            f"Record {i} configs mismatch: expected {expected['configs']}, got {actual['configs']}."
        )


def derive_expected(raw_lines):
    expected = []
    malformed_unicode = re.compile(r"\\u(?![0-9A-Fa-f]{4})")
    assignment = re.compile(r"([A-Za-z0-9_-]+)=([A-Za-z0-9_-]+)")
    sensitive = ("password", "token", "key", "secret")

    for raw_line in raw_lines:
        repaired = malformed_unicode.sub("", raw_line)
        try:
            obj = json.loads(repaired)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        configs = {}
        for key, value in assignment.findall(obj["update_text"]):
            configs[key] = "***" if any(word in key.lower() for word in sensitive) else value
        expected.append({"id": obj["id"], "configs": configs})
    return expected


def make_dynamic_case():
    base = secrets.randbelow(800000) + 100000
    a = secrets.token_hex(5)
    b = secrets.token_hex(5)
    c = secrets.token_hex(5)
    objects = [
        {"id": base, "update_text": f"fresh setting_{a}={b} retry-count=7"},
        {"id": base + 1, "update_text": f"broken MALFORMED_A then region={c}"},
        {"id": base + 2, "update_text": f"valid VALID_UNICODE apiToken_{a}={b} ordinary={c}"},
        {"id": base + 3, "update_text": f"DB_PASSWORD={a} client-secret={b} monkey={c}"},
        {"id": base + 4, "update_text": "nothing to extract MALFORMED_B"},
        {"id": base + 5, "update_text": f"hyphen-key={a} under_score={b} plain={c}"},
    ]

    lines = []
    for obj in objects:
        line = json.dumps(obj, ensure_ascii=True)
        line = line.replace("MALFORMED_A", "\\u12Q4")
        line = line.replace("MALFORMED_B", "\\uZ123")
        line = line.replace("VALID_UNICODE", "\\u2713")
        lines.append(line)

    # This line remains invalid after malformed-unicode repair and must be skipped.
    lines.insert(3, '{"id": ' + str(base + 99) + ', "update_text": "broken",}')
    return lines


def run_dynamic_case(lines):
    expected = derive_expected(lines)
    write_input("\n".join(lines) + "\n")
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    execute_pipeline()
    actual = read_output()
    assert actual == expected, f"Dynamic output mismatch. Expected {expected}, got {actual}"
    for i, record in enumerate(actual, 1):
        assert set(record.keys()) == {"id", "configs"}, (
            f"Dynamic record {i} must contain exactly 'id' and 'configs': {record}"
        )
        assert isinstance(record["id"], int), f"Dynamic record {i} id is not an integer."
        assert isinstance(record["configs"], dict), f"Dynamic record {i} configs is not a dictionary."


def test_pipeline_processes_changing_inputs_instead_of_fixed_output():
    try:
        # Running two independently generated fixtures also verifies that each run
        # rereads the source and replaces, rather than reuses, prior output.
        run_dynamic_case(make_dynamic_case())
        run_dynamic_case(make_dynamic_case())
    finally:
        write_input(ORIGINAL_INPUT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
