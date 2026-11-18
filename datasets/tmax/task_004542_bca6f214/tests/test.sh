#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import re

def test_test_runner_recovered():
    assert os.path.isfile("/home/user/test_runner.py"), "test_runner.py was not recovered to /home/user/test_runner.py"
    with open("/home/user/test_runner.py", "r") as f:
        content = f.read()
    assert "compute_state" in content, "Recovered test_runner.py does not contain expected content."

def test_bad_commit_txt():
    assert os.path.isfile("/home/user/bad_commit.txt"), "/home/user/bad_commit.txt is missing."
    with open("/home/user/bad_commit.txt", "r") as f:
        student_commit = f.read().strip()

    assert len(student_commit) == 40, "Commit hash in bad_commit.txt must be 40 characters."

    # Find the actual bad commit dynamically
    repo_dir = "/home/user/sim_repo"
    # The bad commit replaced math.fsum with a standard for loop.
    # We can find the commit that removed math.fsum
    cmd = ["git", "log", "-S", "math.fsum", "--format=%H"]
    result = subprocess.run(cmd, cwd=repo_dir, capture_output=True, text=True, check=True)
    commits = result.stdout.strip().split()

    # The commit that introduced the bug is the one that removed math.fsum.
    # git log -S finds commits that added or removed the string.
    # Let's check which one removed it.
    actual_bad_commit = None
    for commit in commits:
        show_cmd = ["git", "show", commit, "--", "sim.py"]
        show_result = subprocess.run(show_cmd, cwd=repo_dir, capture_output=True, text=True, check=True)
        if "-    res = math.fsum" in show_result.stdout or "-    return math.fsum" in show_result.stdout or "-        math.fsum" in show_result.stdout:
            actual_bad_commit = commit
            break
        # Sometimes the diff might look slightly different, just check if it removes math.fsum
        if re.search(r'^-\s*.*math\.fsum', show_result.stdout, re.MULTILINE):
            actual_bad_commit = commit
            break

    if actual_bad_commit:
        assert student_commit == actual_bad_commit, f"Incorrect bad commit hash. Expected {actual_bad_commit}, got {student_commit}."

def test_fixed_algo_fuzz_equivalence():
    assert os.path.isfile("/home/user/fixed_algo.py"), "/home/user/fixed_algo.py is missing."
    assert os.path.isfile("/tests/oracle.py"), "Oracle missing."

    random.seed(42)
    for i in range(50):
        num_floats = random.randint(1000, 10000)
        floats = [random.uniform(-10000.0, 10000.0) for _ in range(num_floats)]
        input_data = " ".join(map(str, floats))

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", "/tests/oracle.py"],
            input=input_data,
            capture_output=True,
            text=True,
            check=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run student script
        student_proc = subprocess.run(
            ["python3", "/home/user/fixed_algo.py"],
            input=input_data,
            capture_output=True,
            text=True
        )
        assert student_proc.returncode == 0, f"fixed_algo.py failed on fuzz test {i+1}:\n{student_proc.stderr}"
        student_out = student_proc.stdout.strip()

        assert student_out == oracle_out, (
            f"Fuzz test {i+1} failed!\n"
            f"Input size: {num_floats} floats\n"
            f"Oracle output: {oracle_out}\n"
            f"Student output: {student_out}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
