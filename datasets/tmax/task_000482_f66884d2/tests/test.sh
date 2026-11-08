#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import time
import random
import subprocess
import hmac
import hashlib
import pytest

def generate_requests(filepath, count):
    with open(filepath, 'w') as f:
        for _ in range(count):
            dev_id = f"{random.randint(0, 0xFFFFFFFF):08x}"
            ts = str(int(time.time()) + random.randint(0, 10000))
            f.write(f"{dev_id},{ts}\n")

def test_fast_token_gen_performance_and_accuracy():
    binary_path = "/home/user/fast_token_gen"
    requests_path = "/home/user/requests.csv"
    tokens_path = "/home/user/tokens.csv"

    assert os.path.isfile(binary_path), f"Missing executable: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Not executable: {binary_path}"

    # Generate 500,000 requests
    num_requests = 500000
    generate_requests(requests_path, num_requests)

    # Remove old output if it exists
    if os.path.exists(tokens_path):
        os.remove(tokens_path)

    # Measure execution time
    start_time = time.time()
    result = subprocess.run([binary_path], capture_output=True)
    end_time = time.time()

    assert result.returncode == 0, f"Binary failed with return code {result.returncode}. Stderr: {result.stderr.decode()}"

    execution_time = end_time - start_time

    assert os.path.isfile(tokens_path), f"Missing output file: {tokens_path}"

    with open(tokens_path, 'r') as f:
        lines = f.readlines()

    assert len(lines) == num_requests, f"Expected {num_requests} lines in output, got {len(lines)}"

    # Verify every output row corresponds to the request at the same position.
    with open(requests_path, 'r') as f:
        requests = f.readlines()

    assert len(requests) == num_requests
    for index, (request_line, output_line) in enumerate(zip(requests, lines), start=1):
        request_parts = request_line.strip().split(',')
        output_parts = output_line.strip().split(',')
        assert len(output_parts) == 3, f"Invalid line format at line {index}: {output_line.strip()}"
        assert output_parts[0] == request_parts[0] and output_parts[1] == request_parts[1], \
            f"Output does not match request at line {index}"

    # Check accuracy on a random sample
    correct = 0
    sample_size = min(1000, len(lines))
    sample_lines = random.sample(lines, sample_size)

    for line in sample_lines:
        parts = line.strip().split(',')
        assert len(parts) == 3, f"Invalid line format: {line.strip()}"
        dev_id, ts, token = parts
        msg = (dev_id + ts).encode()
        expected = hmac.new(b"IoT_Sec_Key_99!", msg, hashlib.sha256).hexdigest()[:32]
        if token == expected:
            correct += 1

    accuracy = correct / float(sample_size)
    assert accuracy == 1.0, f"Accuracy failed: {accuracy} (expected 1.0)"

    # Assert execution time threshold
    assert execution_time <= 0.5, f"Execution time failed: {execution_time:.3f}s (threshold <= 0.5s)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
