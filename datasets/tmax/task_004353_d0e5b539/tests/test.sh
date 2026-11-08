#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import random
import time
import subprocess
import pytest

def generate_test_wal(path, num_records):
    """Generates a test WAL file with the specified number of records."""
    with open(path, 'wb') as f:
        for _ in range(num_records):
            timestamp = int(time.time() * 1e6)
            tx_id = random.randint(1, 1000)
            payload_len = random.randint(10, 50)
            payload = os.urandom(payload_len)
            # <B = 1 byte magic (0xAB)
            # Q = 8 bytes uint64_t timestamp
            # I = 4 bytes uint32_t tx_id
            # H = 2 bytes uint16_t payload_len
            header = struct.pack('<BQIH', 0xAB, timestamp, tx_id, payload_len)
            f.write(header + payload)

def test_fast_scanner_speedup_and_correctness():
    fast_scanner = "/home/user/fast_scanner"
    legacy_scanner = "/app/wal_scanner"

    assert os.path.exists(fast_scanner), f"Compiled binary {fast_scanner} not found."
    assert os.access(fast_scanner, os.X_OK), f"{fast_scanner} is not executable."

    test_wal = "/tmp/test_eval.wal"
    # Generate a moderately large WAL file (e.g., ~100,000 records, ~5MB)
    # This is large enough to measure speedup but small enough to not timeout the test.
    generate_test_wal(test_wal, 100000)

    # Run legacy scanner
    start_time = time.time()
    legacy_proc = subprocess.run([legacy_scanner, test_wal], capture_output=True, text=True)
    legacy_time = time.time() - start_time
    assert legacy_proc.returncode == 0, f"Legacy scanner failed: {legacy_proc.stderr}"

    # Run fast scanner
    start_time = time.time()
    fast_proc = subprocess.run([fast_scanner, test_wal], capture_output=True, text=True)
    fast_time = time.time() - start_time
    assert fast_proc.returncode == 0, f"Fast scanner failed: {fast_proc.stderr}"

    # Check correctness
    legacy_output = legacy_proc.stdout.strip()
    fast_output = fast_proc.stdout.strip()

    assert fast_output == legacy_output, "Output of fast_scanner does not exactly match legacy wal_scanner."

    # Check speedup
    # To avoid division by zero if fast_time is extremely small
    fast_time = max(fast_time, 1e-6)
    speedup = legacy_time / fast_time

    assert speedup >= 5.0, f"Runtime speedup is {speedup:.2f}x, which is below the threshold of 5.0x (Legacy: {legacy_time:.4f}s, Fast: {fast_time:.4f}s)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
