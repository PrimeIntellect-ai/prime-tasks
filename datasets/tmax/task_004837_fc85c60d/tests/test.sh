#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import subprocess
import time
import pytest


def generate_test_data(num_samples=500000):
    """Generate equal-length policies with labels independent of line position."""
    lines = []
    expected = set()

    # Generate hidden, high-entropy keys and controls. Labels, key choices, and
    # marker positions cannot be inferred from line numbers.
    keys = []
    for _ in range(4096):
        key = base64.urlsafe_b64encode(os.urandom(18)).decode("ascii").rstrip("=")
        keys.append((key.encode("ascii"), key))

    controls = os.urandom(num_samples * 4)
    salt = os.urandom(32)
    positive_marker = b"escalation=granted"
    negative_marker = b"escalation=revoked"
    plaintext_len = 40
    max_marker_pos = plaintext_len - len(positive_marker)

    for i in range(num_samples):
        off = i * 4
        is_pos = controls[off] < 26
        marker_pos = controls[off + 1] % (max_marker_pos + 1)
        key_index = int.from_bytes(controls[off + 2:off + 4], "little") % len(keys)
        key_bytes, key_str = keys[key_index]

        # Both classes have exactly the same plaintext and ciphertext length.
        filler = base64.urlsafe_b64encode(
            hashlib.sha256(salt + i.to_bytes(8, "little")).digest()
        )[:plaintext_len]
        pt = bytearray(filler)
        marker = positive_marker if is_pos else negative_marker
        pt[marker_pos:marker_pos + len(marker)] = marker

        ct_bytes = bytearray(plaintext_len)
        key_len = len(key_bytes)
        for j, b in enumerate(pt):
            ct_bytes[j] = ((b ^ key_bytes[j % key_len]) + (j % 256)) & 0xFF

        hex_ct = ct_bytes.hex()
        lines.append(f"{hex_ct} {key_str}\n")
        if is_pos:
            expected.add(hex_ct)

    return "".join(lines), expected


def evaluate_f1(agent_output_file, expected_set):
    try:
        with open(agent_output_file, "r") as f:
            agent_out = set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        return 0.0

    tp = len(agent_out.intersection(expected_set))
    fp = len(agent_out - expected_set)
    fn = len(expected_set - agent_out)

    if tp == 0:
        return 0.0

    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * (precision * recall) / (precision + recall)


def test_fast_auditor_performance_and_accuracy():
    binary_path = "/home/user/fast_auditor"
    input_file = "/tmp/hidden_eval_tokens.txt"
    output_file = "/tmp/agent_output.txt"

    # 1. Check if binary exists and is executable
    assert os.path.exists(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"

    # 2. Generate test data
    num_samples = 500000
    data_str, expected_set = generate_test_data(num_samples)

    with open(input_file, "w") as f:
        f.write(data_str)

    if os.path.exists(output_file):
        os.remove(output_file)

    # 3. Execute the agent's binary and measure performance
    start_time = time.time()
    try:
        result = subprocess.run(
            [binary_path, input_file, output_file],
            capture_output=True,
            text=True,
            timeout=10.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution timed out. The C++ program took more than 10 seconds.")

    execution_time = time.time() - start_time

    assert result.returncode == 0, (
        f"Binary execution failed with return code {result.returncode}.\n"
        f"STDERR: {result.stderr}"
    )

    # 4. Evaluate Accuracy (F1-score)
    f1_score = evaluate_f1(output_file, expected_set)

    # 5. Assertions
    assert f1_score >= 1.0, f"Accuracy failed: F1-score is {f1_score:.4f}, expected >= 1.0"
    assert execution_time < 2.0, (
        f"Performance failed: Execution took {execution_time:.4f} seconds, expected < 2.0 seconds"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
