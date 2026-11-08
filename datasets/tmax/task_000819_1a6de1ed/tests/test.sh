#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile


def test_fixed_processor_equivalence():
    agent_executable = "/home/user/fixed_processor"
    oracle_executable = "/tests/oracle_processor"

    assert os.path.isfile(agent_executable), f"Agent executable {agent_executable} does not exist."
    assert os.access(agent_executable, os.X_OK), f"Agent executable {agent_executable} is not executable."
    assert os.path.isfile(oracle_executable), f"Oracle executable {oracle_executable} does not exist."

    with open(agent_executable, "rb") as agent_file, open(oracle_executable, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent executable must not be byte-identical to the oracle."

    # Move the verification-only oracle out of the known path before any agent
    # process is run, then remove it completely after expected outputs are built.
    oracle_dir = tempfile.mkdtemp(prefix="verifier-oracle-")
    private_oracle = os.path.join(oracle_dir, "oracle_processor")
    shutil.copy2(oracle_executable, private_oracle)
    os.unlink(oracle_executable)

    random.seed(42)
    num_rounds = 5000
    cases = []

    try:
        for _ in range(num_rounds):
            length = random.randint(2, 50)
            sequence = [str(random.randint(0, 1000)) for _ in range(length)]
            input_str = ",".join(sequence)

            oracle_proc = subprocess.run(
                [private_oracle, input_str],
                capture_output=True,
                text=True,
                check=False
            )
            cases.append((input_str, oracle_proc.returncode, oracle_proc.stdout.strip()))
    finally:
        shutil.rmtree(oracle_dir)

    for input_str, oracle_returncode, oracle_out in cases:
        agent_proc = subprocess.run(
            [agent_executable, input_str],
            capture_output=True,
            text=True,
            check=False
        )

        assert agent_proc.returncode == oracle_returncode, \
            f"Return code mismatch on input '{input_str}'. Oracle: {oracle_returncode}, Agent: {agent_proc.returncode}"

        agent_out = agent_proc.stdout.strip()
        assert agent_out == oracle_out, \
            f"Output mismatch on input '{input_str}'.\nExpected (Oracle): {oracle_out}\nGot (Agent): {agent_out}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
