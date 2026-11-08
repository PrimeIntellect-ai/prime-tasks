#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess

def test_extracted_loads():
    """Verify that Part 1 extracted the correct loads into /home/user/extracted_loads.txt."""
    extracted_file = "/home/user/extracted_loads.txt"
    assert os.path.isfile(extracted_file), f"File {extracted_file} does not exist."

    with open(extracted_file, "r") as f:
        content = f.read().strip()

    expected = "45\n120\n60\n200\n180\n90\n50\n210\n100\n130"
    assert content == expected, f"Extracted loads do not match the expected values.\nExpected:\n{expected}\nGot:\n{content}"

def test_optimizer_script_exists_and_executable():
    """Verify that the optimizer script exists and is executable."""
    script_path = "/home/user/optimizer.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_optimizer_fuzz_equivalence():
    """Verify Part 2 by fuzzing the agent's script against the reference oracle."""
    agent_script = "/home/user/optimizer.sh"
    oracle_script = "/tests/reference_optimizer.sh"

    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."
    assert os.access(oracle_script, os.X_OK), f"Oracle script {oracle_script} is not executable."

    random.seed(42)
    num_tests = 500

    for i in range(num_tests):
        length = random.randint(3, 20)
        loads = [str(random.randint(0, 255)) for _ in range(length)]
        input_string = ",".join(loads)

        # Run agent
        agent_res = subprocess.run([agent_script, input_string], capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input: {input_string}\nStderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        # Run oracle
        oracle_res = subprocess.run([oracle_script, input_string], capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle script failed on input: {input_string}\nStderr: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Fuzz test failed on iteration {i}.\n"
            f"Input: {input_string}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
