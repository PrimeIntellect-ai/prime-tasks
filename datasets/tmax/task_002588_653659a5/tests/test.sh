#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile
import pytest

def generate_csv(filename, header, id_range, val_range, num_rows):
    with open(filename, 'w') as f:
        f.write(f"{header}\n")
        for _ in range(num_rows):
            id_val = random.randint(*id_range)
            val = random.randint(*val_range)
            f.write(f"{id_val},{val}\n")

def test_fuzz_equivalence():
    oracle_path = "/app/legacy_cleaner"
    agent_script = "/home/user/cleaner.sh"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(50):
            file1 = os.path.join(tmpdir, f"file_x_{i}.csv")
            file2 = os.path.join(tmpdir, f"file_y_{i}.csv")

            num_rows1 = random.randint(20, 100)
            generate_csv(file1, "id,value_x", (1, 200), (-50, 50), num_rows1)

            num_rows2 = random.randint(20, 100)
            generate_csv(file2, "id,value_y", (1, 200), (-50, 50), num_rows2)

            # Run oracle
            oracle_cmd = [oracle_path, file1, file2]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}. Stderr: {oracle_res.stderr}"
            oracle_out = oracle_res.stdout

            # Run agent
            agent_cmd = ["/bin/bash", agent_script, file1, file2]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert agent_res.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_res.stderr}"
            agent_out = agent_res.stdout

            if oracle_out != agent_out:
                with open(file1) as f1, open(file2) as f2:
                    f1_content = f1.read()
                    f2_content = f2.read()

                error_msg = (
                    f"Output mismatch on iteration {i}.\n"
                    f"--- File 1 ({file1}) ---\n{f1_content}\n"
                    f"--- File 2 ({file2}) ---\n{f2_content}\n"
                    f"--- Oracle Output ---\n{oracle_out}\n"
                    f"--- Agent Output ---\n{agent_out}\n"
                )
                pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
