#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import tempfile
import struct
import pytest

def test_diagnostic_token():
    token_file = "/home/user/diagnostic_token.txt"
    assert os.path.exists(token_file), f"Token file not found: {token_file}"
    with open(token_file, "r") as f:
        content = f.read().strip()
    assert content == "DIAG-7729-ALPHA", f"Token file contains incorrect content: {content}"

def test_fuzz_equivalence():
    oracle = "/tests/oracle_audio_tool"
    agent = "/home/user/audio_tool/process_audio"

    assert os.path.exists(agent), f"Agent binary not found at {agent}"
    assert os.access(agent, os.X_OK), f"Agent binary is not executable: {agent}"

    random.seed(42)

    for i in range(50):
        # Generate a random WAV file between 10KB and 5MB
        size = random.randint(10 * 1024, 5 * 1024 * 1024)
        data_size = size - 44

        # Construct a basic valid WAV header
        header = b'RIFF' + struct.pack('<I', size - 8) + b'WAVE'
        header += b'fmt ' + struct.pack('<I', 16) + struct.pack('<H', 1) + struct.pack('<H', 1)
        header += struct.pack('<I', 44100) + struct.pack('<I', 88200) + struct.pack('<H', 2) + struct.pack('<H', 16)
        header += b'data' + struct.pack('<I', data_size)

        # Generate random audio data bytes
        data = os.urandom(data_size)

        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
            tmp.write(header + data)
            tmp_path = tmp.name

        try:
            oracle_res = subprocess.run([oracle, tmp_path], capture_output=True)
            agent_res = subprocess.run([agent, tmp_path], capture_output=True)

            assert oracle_res.returncode == agent_res.returncode, (
                f"Return code mismatch on random input {i} (size: {size} bytes).\n"
                f"Oracle exit code: {oracle_res.returncode}\n"
                f"Agent exit code: {agent_res.returncode}\n"
            )
            assert oracle_res.stdout == agent_res.stdout, (
                f"Stdout mismatch on random input {i} (size: {size} bytes).\n"
                f"Oracle stdout: {oracle_res.stdout!r}\n"
                f"Agent stdout: {agent_res.stdout!r}\n"
            )
            assert oracle_res.stderr == agent_res.stderr, (
                f"Stderr mismatch on random input {i} (size: {size} bytes).\n"
                f"Oracle stderr: {oracle_res.stderr!r}\n"
                f"Agent stderr: {agent_res.stderr!r}\n"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
