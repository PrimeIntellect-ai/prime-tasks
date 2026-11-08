#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import struct
import subprocess

APP_DIR = "/home/user/app"
PROCESS_PATH = "/home/user/app/process.py"
RESULT_PATH = "/home/user/output/result.json"
BIN_PATH = "/home/user/data/batch_01.bin"


def expected_sum_from_binary(path):
    expected_sum = 0.0
    record_size = 20
    fmt = '<IIfd'

    with open(path, 'rb') as f:
        while True:
            chunk = f.read(record_size)
            if not chunk:
                break
            if len(chunk) == record_size:
                record = struct.unpack(fmt, chunk)
                expected_sum += record[3]
    return expected_sum


def run_pipeline(command):
    if os.path.exists(RESULT_PATH):
        os.unlink(RESULT_PATH)

    completed = subprocess.run(
        command,
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Command {' '.join(command)} failed with exit code "
        f"{completed.returncode}:\n{completed.stdout}"
    )
    assert os.path.isfile(RESULT_PATH), f"Expected output file {RESULT_PATH} is missing."

    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULT_PATH} does not contain valid JSON."


def assert_result_matches_binary(data):
    assert "total_sensor2" in data, f"Key 'total_sensor2' missing from {RESULT_PATH}."
    assert os.path.isfile(BIN_PATH), f"Binary file {BIN_PATH} is missing."

    expected_sum = expected_sum_from_binary(BIN_PATH)
    actual_sum = data["total_sensor2"]
    assert math.isclose(actual_sum, expected_sum, rel_tol=1e-5, abs_tol=1e-9), \
        f"Expected total_sensor2 to be approximately {expected_sum}, but got {actual_sum}."


def write_records(records):
    with open(BIN_PATH, 'wb') as f:
        for record in records:
            f.write(struct.pack('<IIfd', *record))


def test_result_json_exists_and_correct():
    # The required pipeline must actually execute successfully on the supplied batch.
    data = run_pipeline(["make", "run"])
    assert_result_matches_binary(data)


def test_makefile_fixed():
    makefile_path = "/home/user/app/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} is missing."

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert "exitt 1" not in content, "The deliberate typo 'exitt 1' is still present in the Makefile."


def test_make_pipeline_and_processor_handle_new_format():
    assert os.path.isfile(PROCESS_PATH), f"Processing script {PROCESS_PATH} is missing."
    with open(BIN_PATH, 'rb') as f:
        original_binary = f.read()

    try:
        # Exercise make run with data different from the image's original values.
        make_records = [
            (41, 1700000101, 1.25, 7.5),
            (99, 1700000202, -3.0, -2.125),
            (7, 1700000303, 8.75, 0.5),
            (1234, 1700000404, 0.0, 19.875),
        ]
        write_records(make_records)
        data = run_pipeline(["make", "run"])
        assert_result_matches_binary(data)

        # Execute the repaired processor itself on another independently derived batch.
        processor_records = [
            (3, 1800000001, 100.0, -11.25),
            (4, 1800000002, -0.5, 4.0),
            (5, 1800000003, 2.5, 3.125),
            (6, 1800000004, 9.0, 20.75),
            (7, 1800000005, 1.0, -1.5),
        ]
        write_records(processor_records)
        data = run_pipeline(["python3", PROCESS_PATH])
        assert_result_matches_binary(data)
    finally:
        with open(BIN_PATH, 'wb') as f:
            f.write(original_binary)
        # Restore the normal final pipeline output when possible.
        subprocess.run(
            ["make", "run"], cwd=APP_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=30, check=False,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
