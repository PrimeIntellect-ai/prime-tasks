#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import wave
import random
import tempfile
import pytest

def generate_wav(filepath, num_samples):
    with wave.open(filepath, 'wb') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(1)
        wav_file.setframerate(44100)

        data = bytearray()
        for _ in range(num_samples):
            r = random.random()
            if r < 0.1:
                data.append(0)
            elif r < 0.2:
                data.append(128)
            else:
                data.append(random.randint(1, 255))
        wav_file.writeframes(data)

def test_audiostat_fixed_exists():
    agent_bin = "/home/user/audiostat_fixed"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"

def test_fuzz_equivalence():
    oracle_bin = "/tests/oracle_audiostat"
    agent_bin = "/home/user/audiostat_fixed"

    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary at {oracle_bin} is not executable"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            num_samples = random.randint(1000, 50000)
            wav_path = os.path.join(tmpdir, f"test_{i}.wav")
            generate_wav(wav_path, num_samples)

            try:
                oracle_result = subprocess.run(
                    [oracle_bin, wav_path],
                    capture_output=True,
                    timeout=5
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Oracle timed out on input {wav_path}. This indicates an issue with the test setup.")

            try:
                agent_result = subprocess.run(
                    [agent_bin, wav_path],
                    capture_output=True,
                    timeout=5
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent binary timed out on input {wav_path}. The infinite loop bug is likely not fixed.")

            assert agent_result.returncode == oracle_result.returncode, (
                f"Return code mismatch on input {wav_path}.\n"
                f"Oracle: {oracle_result.returncode}\n"
                f"Agent: {agent_result.returncode}\n"
                f"Oracle stdout: {oracle_result.stdout}\n"
                f"Agent stdout: {agent_result.stdout}"
            )

            assert agent_result.stdout == oracle_result.stdout, (
                f"Stdout mismatch on input {wav_path}.\n"
                f"Oracle stdout: {oracle_result.stdout}\n"
                f"Agent stdout: {agent_result.stdout}"
            )

            assert agent_result.stderr == oracle_result.stderr, (
                f"Stderr mismatch on input {wav_path}.\n"
                f"Oracle stderr: {oracle_result.stderr}\n"
                f"Agent stderr: {agent_result.stderr}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
