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

def test_fuzz_equivalence():
    agent_script = "/home/user/audit_paths.sh"
    oracle_script = "/tests/audit_paths_oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)
    sources = [f"User{chr(65+i)}" for i in range(20)]
    destinations = [f"Server{i}" for i in range(1, 51)]

    for i in range(100):
        num_lines = random.randint(50, 500)
        lines = []
        for _ in range(num_lines):
            src = random.choice(sources)
            dst = random.choice(destinations)
            lines.append(f"{src} {dst}")

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
            tmp.write("\n".join(lines) + "\n")
            tmp_path = tmp.name

        try:
            oracle_res = subprocess.run(["/bin/bash", oracle_script, tmp_path], capture_output=True, text=True)
            agent_res = subprocess.run(["/bin/bash", agent_script, tmp_path], capture_output=True, text=True)

            assert agent_res.returncode == oracle_res.returncode, f"Return code mismatch on iteration {i}. Oracle: {oracle_res.returncode}, Agent: {agent_res.returncode}"
            assert agent_res.stdout == oracle_res.stdout, (
                f"Output mismatch on iteration {i}.\n"
                f"Oracle output:\n{oracle_res.stdout}\n"
                f"Agent output:\n{agent_res.stdout}\n"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
