#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string

def test_recover_fuzz_equivalence():
    agent_script = "/home/user/recover.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)
    N = 500

    for _ in range(N):
        # Generate random 48-character lowercase hexadecimal string
        arg1 = "".join(random.choices(string.hexdigits.lower()[:16], k=48))
        # Generate random integer between 1 and 100000
        arg2 = str(random.randint(1, 100000))

        # Run oracle
        oracle_cmd = ["python3", oracle_script, arg1, arg2]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {arg1} {arg2}:\n{oracle_res.stderr}"
        oracle_output = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, arg1, arg2]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {arg1} {arg2}:\n{agent_res.stderr}"
        agent_output = agent_res.stdout.strip()

        # Compare
        assert agent_output == oracle_output, (
            f"Mismatch on input {arg1} {arg2}.\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent):       {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
