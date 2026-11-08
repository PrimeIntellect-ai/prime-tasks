#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile

def test_bad_commit():
    txt_path = "/home/user/bad_commit.txt"
    assert os.path.isfile(txt_path), f"{txt_path} is missing"
    with open(txt_path, "r") as f:
        student_commit = f.read().strip()

    repo_dir = "/app/uptime-monitor"
    try:
        commits = subprocess.check_output(["git", "log", "--reverse", "--format=%H"], cwd=repo_dir, text=True).strip().split('\n')
    except subprocess.CalledProcessError:
        assert False, "Failed to read git history from /app/uptime-monitor"

    assert len(commits) >= 3, "Git repository does not have enough commits to determine the bad commit"

    # According to the setup sequence:
    # Commit 1 (Good), Commit 2 (Good), Commit 3 (Bad), Commit 4 (Bad), Commit 5 (Bad)
    # The first bad commit is the 3rd commit chronologically.
    expected_commit = commits[2]

    assert student_commit == expected_commit, f"Expected bad commit {expected_commit}, but got {student_commit}"

def test_fuzz_equivalence():
    agent_script = "/home/user/fixed_uptime_calc.sh"
    oracle_binary = "/app/oracle_uptime_calc"

    assert os.path.isfile(agent_script), f"{agent_script} is missing"
    assert os.access(agent_script, os.X_OK), f"{agent_script} is not executable"

    random.seed(1337)

    for i in range(200):
        num_lines = random.randint(10, 1000)
        lines = [str(random.randint(0, 86400)) for _ in range(num_lines)]

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
            tmp.write('\n'.join(lines) + '\n')
            tmp_path = tmp.name

        try:
            oracle_out = subprocess.check_output([oracle_binary, tmp_path], text=True).strip()
        except subprocess.CalledProcessError as e:
            os.remove(tmp_path)
            assert False, f"Oracle binary failed on fuzz input {i} with error: {e}"

        try:
            agent_out = subprocess.check_output([agent_script, tmp_path], text=True).strip()
        except subprocess.CalledProcessError as e:
            assert False, f"Agent script failed on fuzz input {i} with error: {e}"

        if oracle_out != agent_out:
            assert False, f"Mismatch on fuzz input {i}:\nOracle: {oracle_out}\nAgent: {agent_out}\nInput file: {tmp_path} (saved for debugging)"

        os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
