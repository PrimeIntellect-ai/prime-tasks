#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/wal_extractor.sh"
ORACLE_BINARY = "/app/backup_wal_parser"

def generate_random_path():
    suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
    return f"/var/backups/file_{suffix}.dat"

def generate_fuzz_input():
    num_records = random.randint(1, 50)
    lines = []
    for _ in range(num_records):
        lines.append("BEGIN_WAL_RECORD")

        record_lines = []
        record_lines.append(f"PATH: {generate_random_path()}")
        record_lines.append(f"OP: {random.choice(['ARCHIVE', 'SKIP', 'DELETE', 'COMPRESS'])}")

        if random.random() > 0.10:
            record_lines.append(f"BYTES: {random.randint(0, 104857600)}")

        random.shuffle(record_lines)
        lines.extend(record_lines)
        lines.append("END_WAL_RECORD")

        # Interleave 0-2 empty lines
        for _ in range(random.randint(0, 2)):
            lines.append("")

    return "\n".join(lines) + "\n"

def test_script_exists_and_executable():
    """Test that the agent's script exists and is executable."""
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"Path {AGENT_SCRIPT} is not a regular file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    """Test that the agent's script behaves identically to the oracle binary on random inputs."""
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary {ORACLE_BINARY} does not exist."

    random.seed(42)
    N = 100

    for i in range(N):
        fuzz_input = generate_fuzz_input()

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_BINARY],
            input=fuzz_input,
            text=True,
            capture_output=True,
            check=False
        )
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=fuzz_input,
            text=True,
            capture_output=True,
            check=False
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch on fuzz run {i+1}/{N}.\n"
                f"--- INPUT ---\n{fuzz_input}\n"
                f"--- ORACLE OUTPUT ---\n{oracle_out}\n"
                f"--- AGENT OUTPUT ---\n{agent_out}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
