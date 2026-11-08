#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import secrets
import subprocess
from collections import Counter


def test_merged_timeline_exists_and_matches_historical_logs():
    file_path = "/home/user/merged_timeline.log"
    assert os.path.isfile(file_path), f"Merged timeline log is missing: {file_path}"

    with open(file_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert lines, "Merged timeline log is empty"

    pattern = re.compile(r"^(\d+)\s+\[(SERVICE_A|SERVICE_B)\]\s+(.*)$")
    parsed = []
    previous_timestamp = -1

    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Line does not match required format '<epoch> [SERVICE_NAME] <message>': {line}"
        timestamp = int(match.group(1))
        assert timestamp >= previous_timestamp, f"Timestamps are not sorted chronologically at line: {line}"
        previous_timestamp = timestamp
        parsed.append((timestamp, match.group(2), match.group(3)))

    expected = [
        (1698228001, "SERVICE_A", "- Sending ID 1"),
        (1698228002, "SERVICE_A", "- Sending ID 2"),
        (1698228003, "SERVICE_A", "- Sending ID 3"),
        (1698228004, "SERVICE_A", "- Sending ID 4"),
        (1698228005, "SERVICE_A", "- Sending ID 5"),
        (1698228006, "SERVICE_A", "- Sending ID 6"),
        (1698228007, "SERVICE_A", "- Skipping invalid value for ID 7"),
        (1698228008, "SERVICE_A", "- Sending ID 8"),
        (1698228001, "SERVICE_B", "- Received ID 1"),
        (1698228001, "SERVICE_B", "- Processed ID 1, Current Total: 100"),
        (1698228002, "SERVICE_B", "- Received ID 2"),
        (1698228002, "SERVICE_B", "- Processed ID 2, Current Total: 300"),
        (1698228003, "SERVICE_B", "- Received ID 3"),
        (1698228003, "SERVICE_B", "- FATAL ERROR: Invalid arithmetic operation on 15.5 for ID 3"),
    ]

    assert Counter(parsed) == Counter(expected), (
        "Merged timeline must contain every entry from both historical logs exactly once"
    )
    assert any(service == "SERVICE_A" for _, service, _ in parsed), "No SERVICE_A logs found"
    assert any(service == "SERVICE_B" for _, service, _ in parsed), "No SERVICE_B logs found"


def test_corrupted_ids_correct_for_historical_crash():
    file_path = "/home/user/corrupted_ids.txt"
    assert os.path.isfile(file_path), f"Corrupted IDs file is missing: {file_path}"

    with open(file_path, "r") as f:
        ids = [line.strip() for line in f if line.strip()]

    # The historical service_b log records a crash only for ID 3.
    assert ids == ["3"], f"Expected the historical crashing ID ['3'], got {ids}"


def test_final_output_correct_for_supplied_data():
    file_path = "/home/user/app/final_output.txt"
    assert os.path.isfile(file_path), f"Final output file is missing: {file_path}. Did you run the pipeline?"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "Final Total: 1500", f"Final output is incorrect: {content!r}"


def test_service_a_fixed_and_pipeline_handles_unseen_inputs():
    service_a = "/home/user/app/service_a.sh"
    run_pipeline = "/home/user/app/run_pipeline.sh"
    raw_data = "/home/user/app/raw_data.csv"
    pipe = "/tmp/data_pipe"

    assert os.path.isfile(service_a), f"Service A script is missing: {service_a}"
    assert os.path.isfile(run_pipeline), f"Pipeline runner is missing: {run_pipeline}"

    with open(service_a, "r") as f:
        content = f.read()
    assert "== *[a-zA-Z]*" not in content, "The buggy validation logic in service_a.sh is still present."

    original_raw = open(raw_data, "rb").read()
    reader = None
    writer = None

    base = 100000 + secrets.randbelow(800000)
    valid = [
        (str(base + 1), str(100 + secrets.randbelow(900))),
        (str(base + 3), str(1000 + secrets.randbelow(8000))),
        (str(base + 8), str(10 + secrets.randbelow(80))),
    ]
    invalid = [
        (str(base + 2), "0"),
        (str(base + 4), "-7"),
        (str(base + 5), "12.5"),
        (str(base + 6), "abc"),
        (str(base + 7), "50a"),
        (str(base + 9), "+9"),
        (str(base + 10), ""),
        (str(base + 11), "4$"),
    ]
    records = [valid[0], invalid[0], valid[1], invalid[1], invalid[2],
               invalid[3], invalid[4], valid[2], invalid[5], invalid[6], invalid[7]]

    csv = "id,timestamp,value,status\n" + "".join(
        f"{record_id},2026-01-01,{value},OK\n" for record_id, value in records
    )

    try:
        with open(raw_data, "w") as f:
            f.write(csv)

        # Exercise service_a directly and verify that only strictly positive
        # integer records are emitted to its pipe.
        if os.path.lexists(pipe):
            os.remove(pipe)
        os.mkfifo(pipe)
        reader = subprocess.Popen(["cat", pipe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        writer = subprocess.Popen(["bash", service_a], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        writer_stdout, writer_stderr = writer.communicate(timeout=20)
        captured, reader_stderr = reader.communicate(timeout=20)
        assert writer.returncode == 0, f"service_a.sh failed: {writer_stdout}\n{writer_stderr}"
        assert reader.returncode == 0, f"Could not read service_a output: {reader_stderr}"

        emitted = captured.splitlines()
        expected_emitted = [f"{record_id},{value}" for record_id, value in records if (record_id, value) in valid]
        expected_emitted.append("EOF")
        assert emitted == expected_emitted, (
            f"service_a.sh emitted the wrong records. Expected {expected_emitted}, got {emitted}"
        )

        # Execute the complete pipeline on the unseen data. This prevents a
        # prewritten final_output.txt or a hardcoded total from passing.
        result = subprocess.run(
            ["bash", run_pipeline],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Pipeline failed on validatable input: {result.stdout}\n{result.stderr}"

        expected_total = sum(int(value) for _, value in valid)
        with open("/home/user/app/final_output.txt", "r") as f:
            dynamic_output = f.read().strip()
        assert dynamic_output == f"Final Total: {expected_total}", (
            f"Pipeline produced {dynamic_output!r}; expected 'Final Total: {expected_total}'"
        )
    finally:
        if writer is not None and writer.poll() is None:
            writer.kill()
        if reader is not None and reader.poll() is None:
            reader.kill()
        with open(raw_data, "wb") as f:
            f.write(original_raw)
        if os.path.lexists(pipe):
            os.remove(pipe)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
