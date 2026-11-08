#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

def generate_random_log_line():
    length = random.randint(20, 200)
    keywords = ["ERROR", "WARN", "TIMEOUT", "CRITICAL", "ConnectionRefused", "Timeout"]

    # Decide whether to make it match the regex occasionally
    if random.random() < 0.1:
        level = random.choice(["CRITICAL", "ERROR"])
        reason = random.choice(["ConnectionRefused", "Timeout"])
        num = random.randint(1, 9999)
        base = f"[{level}] "
        mid = "".join(random.choices(string.ascii_letters + string.digits + " ", k=random.randint(5, 50)))
        end = f" {reason} {num}"
        return base + mid + end

    chars = string.ascii_letters + string.digits + " []"
    res = "".join(random.choices(chars, k=length))

    if random.random() < 0.5:
        kw = random.choice(keywords)
        insert_pos = random.randint(0, len(res))
        res = res[:insert_pos] + kw + res[insert_pos:]

    return res

def test_fuzz_equivalence():
    oracle_path = "/app/legacy_alert_parser.bin"
    agent_script = "/home/user/new_alert_parser.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle is not executable: {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    inputs = [generate_random_log_line() for _ in range(5000)]

    for i, log_line in enumerate(inputs):
        oracle_proc = subprocess.run(
            [oracle_path, log_line],
            capture_output=True,
            text=True
        )
        agent_proc = subprocess.run(
            ["python3", agent_script, log_line],
            capture_output=True,
            text=True
        )

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        assert oracle_out == agent_out, (
            f"Mismatch on input {i}:\n"
            f"Input: {repr(log_line)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )

def test_systemd_service_dependency():
    service_path = "/home/user/.config/systemd/user/alert-watcher.service"
    assert os.path.isfile(service_path), f"Service file missing at {service_path}"

    with open(service_path, "r") as f:
        content = f.read()

    # Check for dependency on dummy-mail-relay.service
    has_dep = "dummy-mail-relay.service" in content
    assert has_dep, f"Service file {service_path} does not specify dependency on dummy-mail-relay.service"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
