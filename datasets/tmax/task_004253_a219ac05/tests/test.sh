#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import difflib
import os

def get_truth():
    return [
        "System boot initiated",
        "Loading kernel modules",
        "Network interface eth0 up",
        "Starting sshd service",
        "User admin logged in from 192.168.1.50",
        "Disk space warning on /dev/sda1",
        "Database service starting",
        "Database connection established",
        "Worker thread 1 spawned",
        "Worker thread 2 spawned",
        "WARN: High CPU utilization detected",
        "Rate limit exceeded for endpoint /api/v1/data",
        "ERROR: Segmentation fault in worker thread 1",
        "Attempting to restart worker thread 1",
        "FATAL: Memory corruption detected",
        "Initiating emergency shutdown",
        "Flushing disk buffers",
        "Stopping sshd service",
        "Network interface eth0 down",
        "System halted"
    ]

def test_reconstructed_logs_similarity():
    agent_file = "/home/user/reconstructed_logs.jsonl"
    assert os.path.exists(agent_file), f"Output file {agent_file} does not exist."

    agent_lines = []
    with open(agent_file, 'r') as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                agent_lines.append(json.loads(line))
            except json.JSONDecodeError as e:
                assert False, f"Line {i+1} in {agent_file} is not valid JSON: {e}"

    for i, d in enumerate(agent_lines):
        assert "message" in d, f"Line {i+1} in {agent_file} is missing the 'message' key."
        assert "timestamp" in d, f"Line {i+1} in {agent_file} is missing the 'timestamp' key."
        assert "level" in d, f"Line {i+1} in {agent_file} is missing the 'level' key."

    agent_messages = [d.get("message", "") for d in agent_lines]

    truth_concat = " | ".join(get_truth())
    agent_concat = " | ".join(agent_messages)

    ratio = difflib.SequenceMatcher(None, truth_concat, agent_concat).ratio()
    threshold = 0.85

    assert ratio >= threshold, f"Similarity Ratio: {ratio:.4f} is below the threshold of {threshold}. Agent concat: {agent_concat}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
