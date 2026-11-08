#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fasta():
    header = f">seq_{random.randint(1, 10000)}"
    seq_lines = []
    # Generate 1 to 5 lines of sequence
    for _ in range(random.randint(1, 5)):
        length = random.randint(10, 100)
        seq = "".join(random.choices("ACGT", k=length))
        seq_lines.append(seq)
    return header + "\n" + "\n".join(seq_lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_bin"
    agent_script = "/home/user/decay_simulator.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)

    for i in range(100):
        fasta_input = generate_fasta()

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", oracle_path],
            input=fasta_input.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{fasta_input}\nStderr: {oracle_proc.stderr.decode()}"
        oracle_out = oracle_proc.stdout.decode('utf-8').strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=fasta_input.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        assert agent_proc.returncode == 0, f"Agent script failed on input:\n{fasta_input}\nStderr: {agent_proc.stderr.decode()}"
        agent_out = agent_proc.stdout.decode('utf-8').strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on fuzz iteration {i+1}.\n"
            f"Input:\n{fasta_input}\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output:  '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
