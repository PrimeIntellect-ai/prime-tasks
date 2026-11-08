#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import uuid
import pytest

BASE = "/home/user/legacy_pipeline"
DATA = os.path.join(BASE, "data")


def test_run_pipeline_success():
    """Verify run_pipeline.sh runs successfully with exit code 0."""
    script_path = "/home/user/legacy_pipeline/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} not found."

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_pipeline.sh failed with exit code {result.returncode}.\nStderr: {result.stderr}"


def test_rejected_lines():
    """Verify rejected.txt contains exactly the two corrupted lines."""
    rejected_path = "/home/user/legacy_pipeline/data/rejected.txt"
    assert os.path.isfile(rejected_path), f"File {rejected_path} not found."

    with open(rejected_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        '{"id": 3, "name": "Charlie", "target_value": 300',
        '{"id": 5, "name": "Eve", "target_val: 500}'
    ]

    assert len(lines) == 2, f"Expected 2 rejected lines, found {len(lines)}."
    assert lines[0] == expected_lines[0], f"First rejected line mismatch. Expected: {expected_lines[0]}, Got: {lines[0]}"
    assert lines[1] == expected_lines[1], f"Second rejected line mismatch. Expected: {expected_lines[1]}, Got: {lines[1]}"


def test_output_jsonl():
    """Verify output.jsonl contains 4 JSON lines and Bob has final_value of 0."""
    output_path = "/home/user/legacy_pipeline/data/output.jsonl"
    assert os.path.isfile(output_path), f"File {output_path} not found."

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 4, f"Expected 4 valid JSON lines in output.jsonl, found {len(lines)}."

    bob_found = False
    for line in lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in output.jsonl: {line}")

        if record.get("name") == "Bob":
            bob_found = True
            assert "final_value" in record, "Bob's record is missing 'final_value'."
            assert record["final_value"] == 0, f"Bob's final_value should be 0, got {record['final_value']}."

    assert bob_found, "Record for 'Bob' not found in output.jsonl."


def test_merged_timeline():
    """Verify merged_timeline.txt contains the exact chronological merged logs."""
    timeline_path = "/home/user/legacy_pipeline/logs/merged_timeline.txt"
    assert os.path.isfile(timeline_path), f"File {timeline_path} not found."

    expected_lines = [
        "2023-01-16T08:00:00Z Extracting batch 1",
        "2023-01-16T08:00:02Z Transformed batch 1",
        "2023-01-16T08:00:04Z Loaded batch 1",
        "2023-01-16T08:00:05Z Extracting batch 2",
        "2023-01-16T08:00:07Z Transformed batch 2",
        "2023-01-16T08:00:09Z Loaded batch 2"
    ]

    with open(timeline_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in timeline, found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Timeline line {i+1} mismatch.\nExpected: {expected}\nGot: {actual}"


def _read_jsonl(path):
    assert os.path.isfile(path), f"Expected file was not produced: {path}"
    records = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def test_scripts_and_pipeline_on_generated_input():
    """Exercise the repaired Python scripts and the pipeline on unpredictable data."""
    paths = [
        os.path.join(DATA, "input.jsonl"),
        os.path.join(DATA, "extracted.jsonl"),
        os.path.join(DATA, "transformed.jsonl"),
        os.path.join(DATA, "output.jsonl"),
        os.path.join(DATA, "rejected.txt"),
    ]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.isfile(path) else None

    def remove_artifacts():
        for name in ("extracted.jsonl", "transformed.jsonl", "output.jsonl", "rejected.txt"):
            path = os.path.join(DATA, name)
            if os.path.lexists(path):
                os.remove(path)

    try:
        token = uuid.uuid4().hex
        direct_valid = [
            {"id": token + "-a", "name": "Generated Alpha", "target_value": 17},
            {"id": token + "-b", "name": "Generated Missing"},
            {"id": token + "-c", "name": "Generated Negative", "target_value": -6},
        ]
        direct_bad = [
            '{"id":"' + token + '-bad","name":"Broken","target_value":99',
            'not-json-' + token,
        ]
        direct_lines = [
            json.dumps(direct_valid[0]),
            direct_bad[0],
            json.dumps(direct_valid[1]),
            direct_bad[1],
            json.dumps(direct_valid[2]),
        ]

        remove_artifacts()
        with open(os.path.join(DATA, "extracted.jsonl"), "w", encoding="utf-8") as f:
            f.write("\n".join(direct_lines) + "\n")

        transformer = os.path.join(BASE, "transformer.py")
        assert os.path.isfile(transformer), f"Script {transformer} not found."
        result = subprocess.run(["python3", transformer], capture_output=True, text=True)
        assert result.returncode == 0, f"transformer.py failed on generated input.\nStderr: {result.stderr}"

        transformed_expected = [dict(record, transformed=True) for record in direct_valid]
        assert _read_jsonl(os.path.join(DATA, "transformed.jsonl")) == transformed_expected
        with open(os.path.join(DATA, "rejected.txt"), "r", encoding="utf-8") as f:
            assert f.read().splitlines() == direct_bad, "transformer.py did not preserve the generated rejected lines exactly."

        loader = os.path.join(BASE, "loader.py")
        assert os.path.isfile(loader), f"Script {loader} not found."
        result = subprocess.run(["python3", loader], capture_output=True, text=True)
        assert result.returncode == 0, f"loader.py failed on generated input.\nStderr: {result.stderr}"

        output_expected = []
        for record in transformed_expected:
            expected = dict(record)
            expected["final_value"] = expected.get("target_value", 0) * 2
            output_expected.append(expected)
        assert _read_jsonl(os.path.join(DATA, "output.jsonl")) == output_expected

        pipeline_token = uuid.uuid4().hex
        pipeline_valid = [
            {"id": pipeline_token + "-1", "name": "Pipeline One", "target_value": 31},
            {"id": pipeline_token + "-2", "name": "Pipeline Default"},
            {"id": pipeline_token + "-3", "name": "Pipeline Three", "target_value": 4},
        ]
        pipeline_bad = [
            '{"id":"' + pipeline_token + '-broken","target_value":8',
            '{bad-' + pipeline_token + '}',
        ]
        pipeline_lines = [
            json.dumps(pipeline_valid[0]),
            pipeline_bad[0],
            json.dumps(pipeline_valid[1]),
            json.dumps(pipeline_valid[2]),
            pipeline_bad[1],
        ]
        input_bytes = ("\n".join(pipeline_lines) + "\n").encode("utf-8")
        with open(os.path.join(DATA, "input.jsonl"), "wb") as f:
            f.write(input_bytes)
        remove_artifacts()

        result = subprocess.run([os.path.join(BASE, "run_pipeline.sh")], capture_output=True, text=True)
        assert result.returncode == 0, f"run_pipeline.sh failed on generated input.\nStderr: {result.stderr}"

        extracted_path = os.path.join(DATA, "extracted.jsonl")
        assert os.path.isfile(extracted_path), "run_pipeline.sh did not run the extractor."
        with open(extracted_path, "rb") as f:
            assert f.read() == input_bytes, "The pipeline's extracted data does not match its generated input."

        pipeline_transformed = [dict(record, transformed=True) for record in pipeline_valid]
        assert _read_jsonl(os.path.join(DATA, "transformed.jsonl")) == pipeline_transformed
        with open(os.path.join(DATA, "rejected.txt"), "r", encoding="utf-8") as f:
            assert f.read().splitlines() == pipeline_bad

        pipeline_output = []
        for record in pipeline_transformed:
            expected = dict(record)
            expected["final_value"] = expected.get("target_value", 0) * 2
            pipeline_output.append(expected)
        assert _read_jsonl(os.path.join(DATA, "output.jsonl")) == pipeline_output
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.lexists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
