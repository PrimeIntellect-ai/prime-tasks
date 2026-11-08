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

def test_seqstats_installed():
    """Verify that the vendored package was fixed and successfully installed."""
    try:
        import seqstats
        counts = seqstats.count_bases("ACGTacgtN")
        assert counts == (2, 2, 2, 2), f"Expected count_bases('ACGTacgtN') to return (2, 2, 2, 2), got {counts}"
    except ImportError as e:
        pytest.fail(f"The 'seqstats' package is not installed or cannot be imported: {e}")

def test_agent_script_exists():
    """Verify the agent's script exists."""
    assert os.path.isfile("/home/user/process_seq.py"), "/home/user/process_seq.py does not exist."

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the oracle on 50 random FASTA files."""
    oracle_path = "/tests/reference_process_seq.py"
    agent_path = "/home/user/process_seq.py"

    assert os.path.isfile(oracle_path), f"Oracle script missing at {oracle_path}"

    random.seed(42)
    chars = ['A', 'C', 'G', 'T', 'a', 'c', 'g', 't', 'N']

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(50):
            length = random.randint(50, 5000)
            seq = "".join(random.choices(chars, k=length))
            fasta_path = os.path.join(tmpdir, f"test_{i}.fasta")

            with open(fasta_path, "w") as f:
                f.write(f">test_seq_{i}\n")
                for j in range(0, length, 80):
                    f.write(seq[j:j+80] + "\n")

            oracle_proc = subprocess.run(
                ["python3", oracle_path, fasta_path],
                capture_output=True, text=True
            )

            agent_proc = subprocess.run(
                ["python3", agent_path, fasta_path],
                capture_output=True, text=True
            )

            assert agent_proc.returncode == 0, (
                f"Agent script failed on input {i} (length {length}).\n"
                f"STDERR:\n{agent_proc.stderr}"
            )

            assert oracle_proc.returncode == 0, (
                f"Oracle script failed on input {i} (length {length}).\n"
                f"STDERR:\n{oracle_proc.stderr}"
            )

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()

            assert agent_out == oracle_out, (
                f"Output mismatch on random FASTA {i} (length {length}).\n"
                f"Sequence preview: {seq[:50]}...\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Got (Agent):       {agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
