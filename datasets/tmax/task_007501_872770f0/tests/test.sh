#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import uuid
import pytest

BASE_DIR = "/home/user/data_pipeline"


def test_config_contains_recovered_secret():
    config_file = os.path.join(BASE_DIR, "config.json")
    assert os.path.isfile(config_file), f"File missing: {config_file}"
    with open(config_file, "r", encoding="utf-8") as f:
        config = json.load(f)
    assert config.get("secret_key") == "SUPER_SECRET_99X", "config.json does not contain the secret from git history."


def test_build_script_executes_successfully():
    build_script = os.path.join(BASE_DIR, "build.sh")
    assert os.path.isfile(build_script), f"File missing: {build_script}"

    result = subprocess.run([build_script], cwd=BASE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"build.sh failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_combined_json_output():
    output_file = os.path.join(BASE_DIR, "output", "combined.json")
    assert os.path.isfile(output_file), f"Output file missing: {output_file}"

    with open(output_file, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {output_file} as JSON: {e}")

    assert isinstance(data, list), "The combined.json file must contain a JSON array."
    assert len(data) == 3, f"Expected exactly 3 objects in the JSON array, but found {len(data)}."

    expected_values = {1: "A", 2: "B", 3: "C"}
    found_ids = set()
    for index, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {index} is not a dictionary."
        assert "auth" in item, f"Item at index {index} is missing the 'auth' key."
        assert item["auth"] == "SUPER_SECRET_99X", f"Item at index {index} has incorrect 'auth' value: {item['auth']}"

        assert "id" in item, f"Item at index {index} is missing the 'id' key."
        found_ids.add(item["id"])
        assert "value" in item, f"Item at index {index} is missing the source 'value' key."
        assert item.get("value") == expected_values.get(item["id"]), f"Item with ID {item['id']} has incorrect source value: {item.get('value')}"

    assert found_ids == {1, 2, 3}, f"Expected IDs 1, 2, and 3 in the combined output, but found {found_ids}."


def test_data_files_untouched():
    data_dir = os.path.join(BASE_DIR, "data")
    expected_files = {"file 1.json", "file 2.json", "file 3 spaces.json"}
    actual_files = set(os.listdir(data_dir))

    assert expected_files.issubset(actual_files), f"Some data files were missing or renamed. Expected at least {expected_files}, found {actual_files}"


def test_build_processes_additional_utf16_file_with_spaces():
    data_dir = os.path.join(BASE_DIR, "data")
    output_file = os.path.join(BASE_DIR, "output", "combined.json")
    build_script = os.path.join(BASE_DIR, "build.sh")
    token = uuid.uuid4().hex
    probe_id = 10_000_000 + (uuid.uuid4().int % 1_000_000_000)
    probe_data = {"id": probe_id, "value": f"probe-{token}"}
    probe_file = os.path.join(data_dir, f"verifier probe {token}.json")
    previous_output = open(output_file, "rb").read() if os.path.isfile(output_file) else None

    try:
        with open(probe_file, "w", encoding="utf-16le") as f:
            json.dump(probe_data, f)

        result = subprocess.run([build_script], cwd=BASE_DIR, capture_output=True, text=True)
        assert result.returncode == 0, f"build.sh failed on an additional UTF-16 file with spaces.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

        with open(output_file, "r", encoding="utf-8") as f:
            combined = json.load(f)

        assert isinstance(combined, list), "The rebuilt combined.json must contain a JSON array."
        assert len(combined) == 4, f"Expected all four input files to be processed, but found {len(combined)} objects."
        matches = [item for item in combined if isinstance(item, dict) and item.get("id") == probe_id]
        assert len(matches) == 1, "The dynamically added source object was not processed exactly once."
        assert matches[0].get("value") == probe_data["value"], "The source value from the dynamic input was not preserved."
        assert matches[0].get("auth") == "SUPER_SECRET_99X", "The recovered secret was not added to the dynamic input."
    finally:
        if os.path.exists(probe_file):
            os.unlink(probe_file)
        if previous_output is None:
            if os.path.exists(output_file):
                os.unlink(output_file)
        else:
            with open(output_file, "wb") as f:
                f.write(previous_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
