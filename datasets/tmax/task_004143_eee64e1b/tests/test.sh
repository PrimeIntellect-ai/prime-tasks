#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import wave
import random
import subprocess
import pytest

def get_wav_duration(filepath):
    with wave.open(filepath, 'rb') as wav_file:
        frames = wav_file.getnframes()
        rate = wav_file.getframerate()
        return frames / float(rate)

def test_audio_duration():
    audio_file = "/app/fan_profile.wav"
    output_file = "/home/user/audio_duration.txt"

    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist."

    expected_duration = get_wav_duration(audio_file)

    with open(output_file, 'r') as f:
        content = f.read().strip()

    try:
        actual_duration = float(content)
    except ValueError:
        pytest.fail(f"Could not parse duration from {output_file}. Content: '{content}'")

    # Allow a small tolerance for rounding differences
    assert abs(actual_duration - expected_duration) < 0.05, \
        f"Audio duration mismatch. Expected ~{expected_duration}, got {actual_duration}"

def test_tv_distance_fuzz_equivalence():
    agent_script = "/home/user/tv_distance.sh"
    oracle_script = "/tests/tv_distance_oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    def generate_input(length, force_zero=False):
        if force_zero:
            return ",".join(["0"] * length)
        return ",".join(str(random.randint(0, 1000)) for _ in range(length))

    test_cases = []
    # Generate 100 test cases
    for i in range(100):
        length = random.randint(2, 10)
        # Force sum to 0 for some cases
        force_zero_1 = (i % 10 == 0)
        force_zero_2 = (i % 10 == 1)

        arg1 = generate_input(length, force_zero_1)
        arg2 = generate_input(length, force_zero_2)
        test_cases.append((arg1, arg2))

    for arg1, arg2 in test_cases:
        # Run oracle uploaded only at verification time
        oracle_proc = subprocess.run(
            ["bash", oracle_script, arg1, arg2],
            capture_output=True,
            text=True
        )

        # Run agent
        agent_proc = subprocess.run(
            [agent_script, arg1, arg2],
            capture_output=True,
            text=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, \
            f"Exit code mismatch on inputs '{arg1}' and '{arg2}'. " \
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

        assert agent_proc.stdout.strip() == oracle_proc.stdout.strip(), \
            f"Stdout mismatch on inputs '{arg1}' and '{arg2}'. " \
            f"Oracle: '{oracle_proc.stdout.strip()}', Agent: '{agent_proc.stdout.strip()}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
