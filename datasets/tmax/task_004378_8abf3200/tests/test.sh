#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import time
import pytest

RECORD_SIZE = 12
THRESHOLD = 42.0


def validate_output(input_data, output_path, label):
    assert os.path.exists(output_path), f"{label} not found at {output_path}"
    file_size = os.path.getsize(output_path)
    assert file_size > 0, f"{label} is empty"
    assert file_size % 12 == 0 or file_size % 16 == 0, (
        f"{label} size {file_size} is not a multiple of expected struct size (12 or 16 bytes)."
    )
    assert len(input_data) % RECORD_SIZE == 0, "Input dataset has an invalid size"

    input_count = len(input_data) // RECORD_SIZE
    expected_count = 0
    for index in range(input_count):
        source_id, value, _ = struct.unpack_from("=if4s", input_data, index * RECORD_SIZE)
        assert source_id == index, "Input dataset IDs are not in the expected schema"
        if value >= THRESHOLD:
            expected_count += 1

    with open(output_path, "rb") as f:
        actual_data = f.read()

    errors = []
    candidate_sizes = []
    if file_size % 16 == 0:
        candidate_sizes.append(16)
    if file_size % 12 == 0:
        candidate_sizes.append(12)

    for record_size in candidate_sizes:
        try:
            actual_count = file_size // record_size
            assert actual_count == expected_count, (
                f"{label} has {actual_count} records, expected {expected_count} based on threshold 42.0."
            )

            seen = bytearray(input_count)
            previous_value = float("inf")

            for offset in range(0, file_size, record_size):
                chunk = actual_data[offset:offset + record_size]
                record_id, value, _ = struct.unpack_from("=if4s", chunk, 0)

                assert value >= THRESHOLD, (
                    f"Found record with value {value} < 42.0. Threshold filter not applied correctly."
                )
                assert previous_value >= value, (
                    "Output records are not sorted in descending order by value."
                )
                previous_value = value

                assert 0 <= record_id < input_count, (
                    f"{label} contains source ID {record_id}, which is not present in the input."
                )
                assert not seen[record_id], f"{label} contains duplicate source ID {record_id}."

                source_chunk = input_data[record_id * RECORD_SIZE:(record_id + 1) * RECORD_SIZE]
                assert chunk[:RECORD_SIZE] == source_chunk, (
                    f"{label} record ID {record_id} does not match its source record."
                )
                seen[record_id] = 1

            return
        except AssertionError as exc:
            errors.append(f"{record_size}-byte layout: {exc}")

    pytest.fail(f"{label} is invalid under every supported layout: {'; '.join(errors)}")


def test_execution_time_and_correctness():
    binary_path = "/home/user/audio_processor/build/audio_processor"
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Compiled binary is not executable: {binary_path}"

    with open("/app/dataset.bin", "rb") as f:
        dataset_data = f.read()

    output_path = "/home/user/output.bin"
    validate_output(dataset_data, output_path, "Output file")

    test_output_path = "/home/user/test_output.bin"
    if os.path.lexists(test_output_path):
        os.remove(test_output_path)

    start_time = time.time()
    result = subprocess.run(
        [binary_path, "/app/dataset.bin", test_output_path],
        capture_output=True
    )
    execution_time = time.time() - start_time

    assert result.returncode == 0, (
        f"Binary execution failed with error: {result.stderr.decode(errors='replace')}"
    )
    assert execution_time <= 0.15, (
        f"Execution time {execution_time:.4f}s exceeds the required threshold of 0.15s"
    )
    validate_output(dataset_data, test_output_path, "Timed output file")

    # Exercise the submitted executable on an unpredictable input so a stub that
    # merely exits or relies on a pre-created output cannot pass.
    challenge_input = tempfile.NamedTemporaryFile(prefix="audio_input_", suffix=".bin", delete=False)
    challenge_output = challenge_input.name + ".out"
    try:
        challenge_records = bytearray()
        for record_id in range(8192):
            value = (secrets.randbelow(100000) + 0.25) / 1000.0
            challenge_records.extend(struct.pack("=if4s", record_id, value, b"tst\0"))
        challenge_input.write(challenge_records)
        challenge_input.close()

        challenge_result = subprocess.run(
            [binary_path, challenge_input.name, challenge_output],
            capture_output=True,
            timeout=10
        )
        assert challenge_result.returncode == 0, (
            "Binary failed on generated input: "
            + challenge_result.stderr.decode(errors="replace")
        )
        validate_output(bytes(challenge_records), challenge_output, "Generated-input output file")
    finally:
        challenge_input.close()
        if os.path.exists(challenge_input.name):
            os.remove(challenge_input.name)
        if os.path.lexists(challenge_output):
            os.remove(challenge_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
