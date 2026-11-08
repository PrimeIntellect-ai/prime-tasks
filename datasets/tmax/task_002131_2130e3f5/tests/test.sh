#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

OUTPUT_FILE = "/home/user/dataset_summary.jsonl"
BINARIES_DIR = "/home/user/dataset/binaries"
CSV_DATA = {
    "exp_a.bin": {"experiment_id": "EX-001", "temperature": "295K"},
    "exp_b.bin": {"experiment_id": "EX-002", "temperature": "300K"},
    "exp_c.bin": {"experiment_id": "EX-003", "temperature": "310K"}
}

def get_elf_info(filename):
    filepath = os.path.join(BINARIES_DIR, filename)
    try:
        output = subprocess.check_output(["readelf", "-h", filepath], stderr=subprocess.STDOUT).decode('utf-8')
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run readelf on {filepath}: {e.output.decode('utf-8')}")

    arch = ""
    entry = ""
    for line in output.splitlines():
        if "Machine:" in line:
            arch = line.split("Machine:")[1].strip()
        elif "Entry point address:" in line:
            entry = line.split("Entry point address:")[1].strip()

    return arch, entry

def test_jsonl_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not created."

def test_jsonl_content():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) == 3, f"Expected exactly 3 lines in {OUTPUT_FILE}, found {len(lines)}."

    parsed_files = set()

    for line_idx, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {line_idx + 1} in {OUTPUT_FILE} is not valid JSON.")

        assert isinstance(data, dict), f"Line {line_idx + 1} is not a JSON object."

        required_keys = {"filename", "experiment_id", "temperature", "architecture", "entry_point"}
        assert set(data.keys()) == required_keys, f"Line {line_idx + 1} does not have exactly the required keys."

        fname = data["filename"]
        assert fname in CSV_DATA, f"Unexpected filename '{fname}' in JSONL output."

        parsed_files.add(fname)

        expected_exp_id = CSV_DATA[fname]["experiment_id"]
        expected_temp = CSV_DATA[fname]["temperature"]

        assert data["experiment_id"] == expected_exp_id, f"Incorrect experiment_id for {fname}."
        assert data["temperature"] == expected_temp, f"Incorrect temperature for {fname}."

        expected_arch, expected_entry = get_elf_info(fname)

        assert data["architecture"] == expected_arch, f"Incorrect architecture for {fname}. Expected '{expected_arch}', got '{data['architecture']}'."
        assert data["entry_point"] == expected_entry, f"Incorrect entry_point for {fname}. Expected '{expected_entry}', got '{data['entry_point']}'."

    assert parsed_files == set(CSV_DATA.keys()), "Not all expected files were present in the JSONL output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
