#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import wave
import random
import subprocess
import tempfile
import pytest

def test_requirements_fixed():
    """Verify that the dependency conflict in requirements.txt has been resolved."""
    req_path = "/app/tools/requirements.txt"
    assert os.path.isfile(req_path), f"The requirements file {req_path} is missing."

    with open(req_path, "r") as f:
        content = f.read()

    assert "numpy==1.21.0" not in content, (
        "The numpy version in requirements.txt is still 'numpy==1.21.0'. "
        "It must be updated to resolve the conflict with librosa>=0.10.0."
    )

def test_decode_fuzz_equivalence():
    """Fuzz the agent's decode.py against the oracle decoder with random WAV files and PINs."""
    agent_script = "/home/user/decode.py"
    oracle_bin = "/tests/oracle_decoder"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing: {oracle_bin}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        wav_path = os.path.join(tmpdir, "fuzz_input.wav")

        for i in range(500):
            # Generate a random 1-second 16-bit PCM Mono WAV file (44100 sample rate)
            with wave.open(wav_path, 'wb') as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(44100)
                # 44100 frames * 2 bytes per frame = 88200 bytes
                data = bytearray(random.getrandbits(8) for _ in range(44100 * 2))
                w.writeframes(data)

            # Sample a random PIN between 1000 and 9999
            pin = str(random.randint(1000, 9999))

            # Run oracle
            try:
                oracle_out = subprocess.check_output(
                    ["python3", oracle_bin, wav_path, pin],
                    text=True,
                    stderr=subprocess.STDOUT
                ).strip()
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Oracle failed unexpectedly on fuzz iteration {i}: {e.output}")

            # Run agent's script
            try:
                agent_out = subprocess.check_output(
                    ["python3", agent_script, wav_path, pin],
                    text=True,
                    stderr=subprocess.STDOUT
                ).strip()
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Agent script failed on fuzz iteration {i} with PIN {pin}:\n{e.output}")

            # Compare outputs
            assert agent_out == oracle_out, (
                f"Mismatch on fuzz iteration {i} with PIN {pin}.\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Got (Agent):       {agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
