#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest


def test_transcription():
    """Verify the audio transcription is correct."""
    transcription_path = "/home/user/transcription.txt"
    assert os.path.isfile(transcription_path), f"Transcription file missing: {transcription_path}"

    with open(transcription_path, "r") as f:
        content = f.read().strip()

    assert content == "19 45 88", f"Transcription incorrect. Expected '19 45 88', got '{content}'"


def test_normalize_fuzz_equivalence():
    """Verify that the agent's normalize.sh behaves identically to the oracle script."""
    agent_script = "/home/user/normalize.sh"
    oracle_script = "/tests/oracle_normalize.sh"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)

    num_tests = 50
    for i in range(num_tests):
        N = random.randint(5, 15)
        num_rows = random.randint(20, 100)

        csv_lines = ["col1,col2,col3,col4"]
        for _ in range(num_rows):
            row = [f"{random.uniform(-100.0, 100.0):.4f}" for _ in range(4)]
            csv_lines.append(",".join(row))

        csv_input = "\n".join(csv_lines) + "\n"

        oracle_proc = subprocess.run(
            ["/bin/bash", oracle_script, str(N)],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i} with error: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            ["/bin/bash", agent_script, str(N)],
            input=csv_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed on test {i} with error: {agent_proc.stderr}"
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch on test {i} (N={N}, {num_rows} rows).\n"
                f"--- Input CSV (first 5 rows) ---\n"
                f"{chr(10).join(csv_lines[:6])}\n"
                f"--- Oracle Output (first 5 rows) ---\n"
                f"{chr(10).join(oracle_out.splitlines()[:6])}\n"
                f"--- Agent Output (first 5 rows) ---\n"
                f"{chr(10).join(agent_out.splitlines()[:6])}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
