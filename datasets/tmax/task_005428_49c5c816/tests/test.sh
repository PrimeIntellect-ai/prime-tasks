#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_prep_features"
    agent_path = "/home/user/prep_features.py"

    assert os.path.isfile(oracle_path), f"Oracle program {oracle_path} does not exist."
    assert os.path.isfile(agent_path), f"Agent program {agent_path} does not exist."

    random.seed(42)
    bases = ['A', 'C', 'G', 'T']

    for i in range(1000):
        length = random.randint(10, 50)
        seq1 = "".join(random.choices(bases, k=length))
        seq2 = "".join(random.choices(bases, k=length))

        # Run oracle
        try:
            oracle_res = subprocess.run(
                ["python3", oracle_path, seq1, seq2],
                capture_output=True,
                text=True,
                check=True
            )
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{seq1}' '{seq2}':\n{e.stderr}")

        # Run agent
        try:
            agent_res = subprocess.run(
                ["python3", agent_path, seq1, seq2],
                capture_output=True,
                text=True,
                check=True
            )
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent failed on input '{seq1}' '{seq2}':\n{e.stderr}")

        assert agent_out == oracle_out, (
            f"Mismatch on input '{seq1}' '{seq2}'.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
