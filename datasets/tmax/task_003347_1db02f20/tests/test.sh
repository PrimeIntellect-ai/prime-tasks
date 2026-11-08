#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import struct
import subprocess
import tempfile
import time

AGENT_BIN = "/home/user/workspace/build/fast_sorter"
ORACLE_BIN = "/app/legacy_sorter"


def run_capture(binary, input_path):
    return subprocess.run(
        [binary, input_path],
        stdout=subprocess.PIPE,
        check=True,
    ).stdout


def assert_outputs_equal(expected, actual):
    chunk_size = 8 * 1024 * 1024
    offset = 0
    while True:
        chunk1 = expected[offset:offset + chunk_size]
        chunk2 = actual[offset:offset + chunk_size]
        assert chunk1 == chunk2, (
            f"Agent output differs from Oracle output starting at byte offset {offset}."
        )
        if not chunk1:
            break
        offset += len(chunk1)


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def write_tie_test(path):
    records = [
        (90, 5.0, b"beta"),
        (40, 5.0, b"alpha"),
        (70, 5.0, b"alpha"),
        (10, 6.0, b"zeta"),
        (80, 5.0, b"gamma"),
        (20, 6.0, b"alpha"),
        (30, 5.0, b"alpha"),
        (60, 4.0, b"beta"),
        (50, 4.0, b"alpha"),
        (15, 6.0, b"alpha"),
        (25, 5.0, b"beta"),
        (5, 4.0, b"alpha"),
    ]
    with open(path, "wb") as f:
        for record_id, score, label in records:
            f.write(struct.pack("<Qd16s", record_id, score, label))


def generate_test_data(path, num_records):
    labels = [f"label_{i}".encode("ascii").ljust(16, b"\0") for i in range(100)]
    chunk_size = 10000
    random.seed(8675309)

    with open(path, "wb") as f:
        for chunk_idx in range(num_records // chunk_size):
            base_id = chunk_idx * chunk_size
            chunk = b"".join(
                struct.pack(
                    "<Qd16s",
                    base_id + i,
                    random.random(),
                    labels[(base_id + i) % 100],
                )
                for i in range(chunk_size)
            )
            f.write(chunk)


def test_fast_sorter_metric():
    assert os.path.exists(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.path.isfile(AGENT_BIN), f"Agent binary at {AGENT_BIN} is not a regular file"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    assert file_digest(AGENT_BIN) != file_digest(ORACLE_BIN), (
        "Agent binary must not be a byte-identical copy of the legacy oracle"
    )

    with tempfile.TemporaryDirectory(prefix="sorter_verify_") as temp_dir:
        tie_file = os.path.join(temp_dir, "ties.bin")
        test_file = os.path.join(temp_dir, "large.bin")

        # Explicitly exercise score ties, label ties, and ID tie-breaking.
        # Oracle output remains only in verifier memory and is never exposed
        # through a predictable, globally readable file.
        write_tie_test(tie_file)
        tie_expected = run_capture(ORACLE_BIN, tie_file)
        tie_actual = run_capture(AGENT_BIN, tie_file)
        assert_outputs_equal(tie_expected, tie_actual)

        # Generate the original large benchmark dataset (~96 MB).
        num_records = 3000000
        generate_test_data(test_file, num_records)

        # Run and time the oracle. Its output is retained only in this verifier
        # process, so the agent cannot copy it from /tmp/oracle.out.
        t0 = time.time()
        expected = run_capture(ORACLE_BIN, test_file)
        oracle_time = time.time() - t0

        # Run and time the agent.
        t0 = time.time()
        actual = run_capture(AGENT_BIN, test_file)
        agent_time = time.time() - t0

        # Preserve the original byte-for-byte correctness check in chunks.
        assert_outputs_equal(expected, actual)

        # Preserve the original speedup requirement.
        speedup = oracle_time / agent_time
        assert speedup >= 1.5, (
            f"Speedup is {speedup:.2f}x, which is below the threshold of 1.5x. "
            f"Oracle time: {oracle_time:.2f}s, Agent time: {agent_time:.2f}s."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
