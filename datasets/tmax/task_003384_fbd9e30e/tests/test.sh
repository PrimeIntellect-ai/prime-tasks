#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_extractor"
AGENT_PATH = "/home/user/extractor/target/release/extractor"
PROJECTION_MATRIX_PATH = "/app/projection_matrix.bin"

def test_step1_sample_bin_exists():
    """Check if the user correctly converted the WAV file to sample.bin."""
    path = "/home/user/sample.bin"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    assert os.path.getsize(path) > 0, f"{path} is empty."

    # We can verify it matches ffmpeg output roughly, but checking existence and size is a good start.
    # The prompt asked for raw, 16kHz, mono, 32-bit floating-point (little-endian) PCM stream.
    # Let's just check if it's a multiple of 4 bytes (f32).
    assert os.path.getsize(path) % 4 == 0, f"{path} size is not a multiple of 4 bytes (f32)."

def test_step2_agent_binary_exists():
    """Check if the agent's Rust binary is compiled and exists."""
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}. Did you compile in release mode?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable."

def test_step3_sample_features_bin_exists():
    """Check if the user generated sample_features.bin."""
    path = "/home/user/sample_features.bin"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    assert os.path.getsize(path) > 0, f"{path} is empty."

def test_fuzz_equivalence():
    """Fuzz test the agent's binary against the oracle."""
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"

    random.seed(42)
    num_tests = 100

    with tempfile.TemporaryDirectory() as tmpdir:
        fuzz_in = os.path.join(tmpdir, "fuzz_in.bin")
        oracle_out = os.path.join(tmpdir, "oracle_out.bin")
        agent_out = os.path.join(tmpdir, "agent_out.bin")

        for i in range(num_tests):
            # Generate random file size between 1 byte and 2 MB
            # Bias towards some smaller sizes to test padding logic heavily, and some larger sizes.
            if i < 20:
                size = random.randint(1, 256) # Small sizes, unaligned
            elif i < 40:
                size = random.randint(1, 256) * 4 # Small sizes, aligned to f32
            else:
                size = random.randint(256, 2 * 1024 * 1024)

            # Generate random bytes
            random_bytes = bytearray(random.getrandbits(8) for _ in range(size))
            with open(fuzz_in, "wb") as f:
                f.write(random_bytes)

            # Run oracle
            if os.path.exists(oracle_out):
                os.remove(oracle_out)
            oracle_proc = subprocess.run([ORACLE_PATH, fuzz_in, oracle_out], capture_output=True, text=True)
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with size {size}. stderr: {oracle_proc.stderr}"

            # Run agent
            if os.path.exists(agent_out):
                os.remove(agent_out)
            agent_proc = subprocess.run([AGENT_PATH, fuzz_in, agent_out], capture_output=True, text=True)
            assert agent_proc.returncode == 0, f"Agent binary failed on iteration {i} with size {size}. stderr: {agent_proc.stderr}"

            # Compare outputs
            assert os.path.isfile(oracle_out), f"Oracle did not produce output on iteration {i}"
            assert os.path.isfile(agent_out), f"Agent did not produce output on iteration {i}"

            with open(oracle_out, "rb") as f:
                oracle_data = f.read()
            with open(agent_out, "rb") as f:
                agent_data = f.read()

            assert oracle_data == agent_data, (
                f"Mismatch on iteration {i} (input size {size} bytes).\n"
                f"Oracle output size: {len(oracle_data)}\n"
                f"Agent output size: {len(agent_data)}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
