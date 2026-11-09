#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_run_density.sh"
AGENT_PATH = "/home/user/run_density.sh"
CALC_PATH = "/app/bash-fasta-density-1.0/bin/calc_density.sh"
NUM_TESTS = 50

def generate_random_fasta(filepath):
    num_sequences = random.randint(1, 20)
    with open(filepath, 'w') as f:
        for _ in range(num_sequences):
            seq_id_len = random.randint(5, 15)
            seq_id = ''.join(random.choices(string.ascii_letters + string.digits, k=seq_id_len))

            seq_len = random.randint(50, 1000)
            seq_body = ''.join(random.choices(['A', 'C', 'G', 'T', 'a', 'c', 'g', 't'], k=seq_len))

            f.write(f">{seq_id}\n")
            for i in range(0, len(seq_body), 80):
                f.write(f"{seq_body[i:i+80]}\n")

def test_wrapper_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent wrapper script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent wrapper script at {AGENT_PATH} is not executable"
    assert os.path.isfile(CALC_PATH), f"Density script not found at {CALC_PATH}"
    assert os.access(CALC_PATH, os.X_OK), f"Density script at {CALC_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle script not found at {ORACLE_PATH}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as temp_dir:
        cases = []
        for i in range(NUM_TESTS):
            fasta_path = os.path.join(temp_dir, f"test_{i}.fasta")
            generate_random_fasta(fasta_path)

            oracle_proc = subprocess.run(
                [ORACLE_PATH, fasta_path],
                capture_output=True,
                text=True
            )
            cases.append((fasta_path, oracle_proc.returncode, oracle_proc.stdout))

        # The oracle is uploaded only for verification and is removed before any
        # submitted artifact is executed, so it cannot be used as the solution.
        os.unlink(ORACLE_PATH)

        for fasta_path, oracle_returncode, oracle_out in cases:
            calc_proc = subprocess.run(
                [CALC_PATH, fasta_path],
                capture_output=True,
                text=True
            )
            if calc_proc.returncode != oracle_returncode:
                pytest.fail(f"Fixed tool return code mismatch on input {fasta_path}.\nOracle: {oracle_returncode}\nTool: {calc_proc.returncode}\nTool stderr: {calc_proc.stderr}")
            if calc_proc.stdout != oracle_out:
                with open(fasta_path, 'r') as f:
                    input_content = f.read()
                pytest.fail(f"Fixed tool output mismatch on input {fasta_path}.\n\nInput FASTA:\n{input_content}\n\nOracle Output:\n{oracle_out}\n\nTool Output:\n{calc_proc.stdout}")

            agent_proc = subprocess.run(
                [AGENT_PATH, fasta_path],
                capture_output=True,
                text=True
            )
            agent_out = agent_proc.stdout

            if agent_proc.returncode != oracle_returncode:
                pytest.fail(f"Return code mismatch on input {fasta_path}.\nOracle: {oracle_returncode}\nAgent: {agent_proc.returncode}\nAgent stderr: {agent_proc.stderr}")

            if agent_out != oracle_out:
                with open(fasta_path, 'r') as f:
                    input_content = f.read()
                pytest.fail(f"Output mismatch on input {fasta_path}.\n\nInput FASTA:\n{input_content}\n\nOracle Output:\n{oracle_out}\n\nAgent Output:\n{agent_out}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
