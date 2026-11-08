#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import pytest

def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."

def test_cpp_processor_exists():
    cpp_path = "/home/user/processor.cpp"
    assert os.path.isfile(cpp_path), f"C++ processor file {cpp_path} is missing."

def test_output_file_exists():
    output_path = "/home/user/output/anomalies.jsonl"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

def test_anomalies_output_content():
    output_path = "/home/user/output/anomalies.jsonl"
    assert os.path.isfile(output_path), "Output file missing, cannot check content."

    # Parse the output
    actual_records = []
    with open(output_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {output_path} is not valid JSON.")

    # Derive expected records from input files
    # Read mem_metrics.json
    mem_path = "/home/user/inputs/mem_metrics.json"
    expected_records = []
    if os.path.isfile(mem_path):
        with open(mem_path, "r", encoding="utf-8") as f:
            mem_data = json.load(f)
            for row in mem_data:
                ts = int(row["ts"])
                for k, v in row.items():
                    if k != "ts" and float(v) > 90.0:
                        expected_records.append({
                            "timestamp": ts,
                            "server": k,
                            "metric": "mem",
                            "value": round(float(v), 1)
                        })

    # Read cpu_metrics.csv
    cpu_path = "/home/user/inputs/cpu_metrics.csv"
    if os.path.isfile(cpu_path):
        # The script might have converted it to utf-8 or kept it as utf-16le
        try:
            with open(cpu_path, "r", encoding="utf-8") as f:
                content = f.read()
                if "\0" in content: # likely still utf-16le
                    raise UnicodeDecodeError("utf-8", b"", 0, 1, "null byte")
        except UnicodeDecodeError:
            with open(cpu_path, "r", encoding="utf-16le") as f:
                content = f.read()

        reader = csv.DictReader(content.splitlines())
        for row in reader:
            if not row:
                continue
            ts = int(row["timestamp"])
            for k, v in row.items():
                if k != "timestamp" and float(v) > 85.0:
                    expected_records.append({
                        "timestamp": ts,
                        "server": k,
                        "metric": "cpu",
                        "value": round(float(v), 1)
                    })

    # Sort expected records
    expected_records.sort(key=lambda x: (x["timestamp"], x["server"], x["metric"]))

    # Normalize actual records for comparison
    normalized_actual = []
    for r in actual_records:
        assert "timestamp" in r, "Record missing 'timestamp' key."
        assert "server" in r, "Record missing 'server' key."
        assert "metric" in r, "Record missing 'metric' key."
        assert "value" in r, "Record missing 'value' key."
        normalized_actual.append({
            "timestamp": int(r["timestamp"]),
            "server": str(r["server"]),
            "metric": str(r["metric"]),
            "value": round(float(r["value"]), 1)
        })

    assert len(normalized_actual) == len(expected_records), f"Expected {len(expected_records)} anomalies, found {len(normalized_actual)}."

    for i, (actual, expected) in enumerate(zip(normalized_actual, expected_records)):
        assert actual == expected, f"Mismatch at sorted record index {i}. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
