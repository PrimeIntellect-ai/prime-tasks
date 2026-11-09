#!/bin/bash
set -e
mkdir -p /logs/verifier

if [ ! -f /home/user/process_logs.py ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Regenerate the required output by actually running the submitted script.
if ! python3 /home/user/process_logs.py /home/user/access.log /home/user/output.jsonl; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess
import tempfile


def test_buggy_line_file():
    buggy_file = "/home/user/buggy_line.txt"
    assert os.path.exists(buggy_file), f"File {buggy_file} does not exist."

    with open(buggy_file, "r") as f:
        content = f.read().strip()

    expected = "192.168.1.100 - [2023-10-12T10:00:00Z] - GET - /api/status"
    assert content == expected, f"Contents of {buggy_file} do not match the expected malformed line."


def test_output_jsonl_file():
    output_file = "/home/user/output.jsonl"
    assert os.path.exists(output_file), f"File {output_file} does not exist."

    with open(output_file, "r") as f:
        lines = f.readlines()

    assert len(lines) == 4999, f"Expected exactly 4999 lines in {output_file}, but found {len(lines)}."

    for i, line in enumerate(lines):
        assert "192.168.1.100" not in line, f"Malformed line IP '192.168.1.100' found in {output_file} at line {i+1}."

        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {output_file} is not valid JSON."

        assert "ip" in record, f"Missing 'ip' field in JSON record at line {i+1}."
        assert "timestamp" in record, f"Missing 'timestamp' field in JSON record at line {i+1}."
        assert "method" in record, f"Missing 'method' field in JSON record at line {i+1}."
        assert "path" in record, f"Missing 'path' field in JSON record at line {i+1}."
        assert "status" in record, f"Missing 'status' field in JSON record at line {i+1}."


def test_output_exactly_matches_access_log():
    expected = []
    with open("/home/user/access.log", "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            parts = line.split(" - ")
            if len(parts) != 5:
                continue
            expected.append({
                "ip": parts[0],
                "timestamp": parts[1].strip("[]"),
                "method": parts[2],
                "path": parts[3],
                "status": int(parts[4]),
            })

    with open("/home/user/output.jsonl", "r") as f:
        actual = [json.loads(line) for line in f]

    assert actual == expected, "output.jsonl does not exactly match the valid records in access.log."


def test_script_skips_wrong_component_counts_silently():
    source = (
        "10.1.1.1 - [2024-01-01T00:00:00Z] - GET - /ok - 200\n"
        "malformed - [2024-01-01T00:01:00Z] - POST - /missing-status\n"
        "too - many - split - components - here - 500\n"
        "10.1.1.2 - [2024-01-01T00:02:00Z] - DELETE - /item - 404\n"
    )
    expected = [
        {"ip": "10.1.1.1", "timestamp": "2024-01-01T00:00:00Z", "method": "GET", "path": "/ok", "status": 200},
        {"ip": "10.1.1.2", "timestamp": "2024-01-01T00:02:00Z", "method": "DELETE", "path": "/item", "status": 404},
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "input.log")
        output_path = os.path.join(tmpdir, "output.jsonl")
        with open(input_path, "w") as f:
            f.write(source)

        result = subprocess.run(
            ["python3", "/home/user/process_logs.py", input_path, output_path],
            text=True,
            capture_output=True,
        )
        assert result.returncode == 0, f"process_logs.py failed on malformed input: {result.stderr}"
        assert result.stdout == "", "Malformed lines must be skipped silently (unexpected stdout)."
        assert result.stderr == "", "Malformed lines must be skipped silently (unexpected stderr)."

        with open(output_path, "r") as f:
            actual = [json.loads(line) for line in f]
        assert actual == expected, "The script did not skip only the lines with the wrong component count."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
