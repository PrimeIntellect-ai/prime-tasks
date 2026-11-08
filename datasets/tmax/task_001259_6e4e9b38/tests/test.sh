#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_git_repo_is_bare():
    repo_dir = "/home/user/processor.git"
    assert os.path.isdir(repo_dir), f"Bare git repo directory {repo_dir} missing."
    assert os.path.isfile(os.path.join(repo_dir, "HEAD")), f"{repo_dir} does not appear to be a bare git repository."
    assert os.path.isdir(os.path.join(repo_dir, "objects")), f"{repo_dir} missing objects directory."

def test_git_hook_executable_and_compiles():
    hook_path = "/home/user/processor.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"post-receive hook missing at {hook_path}."
    assert os.access(hook_path, os.X_OK), f"post-receive hook at {hook_path} is not executable."
    with open(hook_path, "r") as f:
        content = f.read()
    assert "gcc" in content, "post-receive hook does not appear to contain compilation logic (missing 'gcc')."

def test_logrotate_conf_directives():
    conf_path = "/home/user/deploy/logrotate.conf"
    assert os.path.isfile(conf_path), f"logrotate.conf missing at {conf_path}."
    with open(conf_path, "r") as f:
        content = f.read().lower()

    assert "daily" in content, "logrotate.conf is missing the 'daily' directive."
    assert "rotate 7" in content, "logrotate.conf is missing the 'rotate 7' directive."
    assert "compress" in content, "logrotate.conf is missing the 'compress' directive."
    assert "size 5m" in content.replace(" ", "") or "size=5m" in content.replace(" ", ""), "logrotate.conf is missing the size 5M directive."

def test_fuzz_processor_equivalence():
    agent_bin = "/home/user/deploy/processor"
    oracle_bin = "/tests/oracle_processor"

    assert os.path.isfile(agent_bin), f"Agent binary {agent_bin} is missing. Was it compiled?"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."

    random.seed(42)
    chars = [chr(i) for i in range(0x20, 0x7F)]

    # Include edge cases from the task description
    test_cases = [
        "[DEBUG] test string",
        "this string has PANIC in it",
        "normal string",
        "[DEBUG]",
        "PANIC",
        ""
    ]

    # Generate 5000 random inputs
    for _ in range(5000):
        length = random.randint(1, 256)
        test_cases.append("".join(random.choices(chars, k=length)))

    for tc in test_cases:
        oracle_res = subprocess.run([oracle_bin, tc], capture_output=True, text=True)
        agent_res = subprocess.run([agent_bin, tc], capture_output=True, text=True)

        assert agent_res.returncode == oracle_res.returncode, \
            f"Return code mismatch on input {repr(tc)}. Expected {oracle_res.returncode}, got {agent_res.returncode}."

        assert agent_res.stdout == oracle_res.stdout, \
            f"Stdout mismatch on input {repr(tc)}.\nExpected:\n{repr(oracle_res.stdout)}\nGot:\n{repr(agent_res.stdout)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
