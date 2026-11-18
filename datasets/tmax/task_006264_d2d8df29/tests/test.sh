#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_metrics_fixed.sh"
INPUT_PATH = "/home/user/encoded_logs.txt"
OUTPUT_PATH = "/home/user/decoded_metrics.json"

ORIGINAL_INPUT = """1|base64|Q1BVX0xPQUQ9ODAl
2|hex|4d454d4f52595f55534147453d344742
3|RLE|024100000342
4|base64|RVJST1I9Ik91dCBvZiBtZW1vcnki
"""

EXPECTED_ORIGINAL = [
    {"id": "1", "metric": "CPU_LOAD=80%"},
    {"id": "2", "metric": "MEMORY_USAGE=4GB"},
    {"id": "3", "metric": "AABBB"},
    {"id": "4", "metric": "ERROR=\"Out of memory\""},
]


def run_script(input_text):
    with open(INPUT_PATH, "w") as f:
        f.write(input_text)
    try:
        os.remove(OUTPUT_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Fixed script exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    try:
        with open(OUTPUT_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON: {e}")


def test_fixed_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The fixed script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and re.search(r"(^|[/\s])bash(?:\s|$)", first_line[2:]), (
        "The corrected solution must be an executable Bash script."
    )


def test_decoded_metrics_json_is_valid_and_correct():
    data = run_script(ORIGINAL_INPUT)

    assert isinstance(data, list), "The JSON root must be a list (array)."
    assert len(data) == 4, f"Expected 4 items in the JSON array, found {len(data)}."

    for i, expected_item in enumerate(EXPECTED_ORIGINAL):
        assert data[i] == expected_item, (
            f"Item at index {i} does not match the expected output. "
            f"Expected: {expected_item}, Got: {data[i]}"
        )


def test_script_processes_derived_inputs_and_advances_past_zero_rle_counts():
    token = secrets.token_hex(10)
    quoted_metric = f'probe_{token}=\"quoted\"\\path'
    hex_metric = f"HEX_{token}_OK"
    first_char = chr(ord("A") + secrets.randbelow(13))
    second_char = chr(ord("N") + secrets.randbelow(13))
    first_count = 1 + secrets.randbelow(9)
    second_count = 1 + secrets.randbelow(9)

    rle_data = (
        f"{first_count:02x}{ord(first_char):02x}"
        f"00{ord('Z'):02x}"
        f"{second_count:02x}{ord(second_char):02x}"
    )
    derived_input = "\n".join([
        f"b-{token}|base64|{base64.b64encode(quoted_metric.encode()).decode()}",
        f"h-{token}|hex|{hex_metric.encode().hex()}",
        f"r-{token}|RLE|{rle_data}",
    ]) + "\n"
    expected = [
        {"id": f"b-{token}", "metric": quoted_metric},
        {"id": f"h-{token}", "metric": hex_metric},
        {"id": f"r-{token}", "metric": first_char * first_count + second_char * second_count},
    ]

    try:
        data = run_script(derived_input)
        assert isinstance(data, list), "The JSON root must be a list (array)."
        assert data == expected, f"Derived-input output mismatch. Expected {expected!r}, got {data!r}"
    finally:
        # Leave the required files in their canonical final state.
        run_script(ORIGINAL_INPUT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
