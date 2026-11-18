#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest


def test_pipeline_script_exists_and_uses_parallelism():
    """Test that the pipeline script exists, is executable, and contains parallelism commands."""
    script_path = "/home/user/clean_pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} is missing."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    has_split = "split" in content
    has_xargs_p = "xargs -P" in content
    has_ampersand = "&" in content

    assert has_split or has_xargs_p or has_ampersand, (
        "The script does not appear to use parallel execution tools (split, xargs -P, or &)."
    )


def test_output_file_exists():
    """Test that the final output file exists."""
    output_path = "/home/user/clean_feedback.jsonl"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."


def test_output_file_content():
    """Test that the output contains the correctly cleaned, filtered, and anonymized JSON lines."""
    output_path = "/home/user/clean_feedback.jsonl"
    expected_path = "/tests/.expected_feedback.jsonl"

    assert os.path.isfile(output_path), f"Output file {output_path} is missing."
    assert os.path.isfile(expected_path), f"Expected file {expected_path} is missing."

    def load_jsonl(path):
        records = []
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON found in {path}: {line}")
        return records

    actual_records = load_jsonl(output_path)
    expected_records = load_jsonl(expected_path)

    actual_records.sort(key=lambda x: x.get("id", 0))
    expected_records.sort(key=lambda x: x.get("id", 0))

    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records, but found {len(actual_records)}."
    )

    for actual, expected in zip(actual_records, expected_records):
        assert actual == expected, f"Record mismatch. Expected: {expected}, Actual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
