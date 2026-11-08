#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import re
import stat
import subprocess
import random
import string
import sys
import pytest


def test_run_ci_script():
    path = "/home/user/run_ci.sh"
    resolver_path = "/app/proxy-resolver/resolver.py"
    backup_path = "/app/proxy-resolver/.resolver.py.verifier-backup"
    log_path = "/tmp/resolver-ci-probe.jsonl"

    assert os.path.isfile(path), f"File {path} does not exist."

    # Check if executable
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    assert "/app/proxy-resolver/resolver.py" in content or "resolver.py" in content, \
        f"{path} does not seem to call the resolver.py script."

    with open(resolver_path, "rb") as f:
        original = f.read()
    original_mode = os.stat(resolver_path).st_mode

    with open(backup_path, "wb") as f:
        f.write(original)
    os.chmod(backup_path, original_mode)

    def install_probe(bad_output):
        probe = f'''#!/usr/bin/env python3
import json
import subprocess
import sys

data = sys.stdin.read()
with open({log_path!r}, "a") as log:
    log.write(json.dumps(data) + "\\n")

if {bad_output!r}:
    lines = [line for line in data.splitlines() if line.strip()]
    for line in lines:
        if len(line.split()) == 2:
            print("/definitely/not/a/valid/upstream.sock")
    sys.exit(0)

proc = subprocess.run(
    [sys.executable, {backup_path!r}],
    input=data,
    text=True,
    capture_output=True
)
sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
sys.exit(proc.returncode)
'''
        with open(resolver_path, "w") as f:
            f.write(probe)
        os.chmod(resolver_path, original_mode | stat.S_IXUSR)

    def read_probe_inputs():
        assert os.path.isfile(log_path), "run_ci.sh did not execute resolver.py."
        with open(log_path, "r") as f:
            return [json.loads(line) for line in f if line.strip()]

    try:
        if os.path.exists(log_path):
            os.unlink(log_path)
        install_probe(False)
        good_proc = subprocess.run(
            [path], text=True, capture_output=True, timeout=20
        )
        assert good_proc.returncode == 0, \
            f"run_ci.sh failed against the working resolver: {good_proc.stderr}"

        invocations = read_probe_inputs()
        supplied_lines = []
        for invocation in invocations:
            supplied_lines.extend(invocation.splitlines())
        assert len(supplied_lines) == 3, \
            f"run_ci.sh must feed exactly 3 lines to resolver.py, but fed {len(supplied_lines)}."
        assert all(len(line.split()) == 2 for line in supplied_lines), \
            "Each CI test line must use the '<src_ip> <dst_domain>' input format."

        os.unlink(log_path)
        install_probe(True)
        bad_proc = subprocess.run(
            [path], text=True, capture_output=True, timeout=20
        )
        read_probe_inputs()
        assert bad_proc.returncode != 0, \
            "run_ci.sh exited successfully even when resolver.py returned incorrect output."
    finally:
        with open(resolver_path, "wb") as f:
            f.write(original)
        os.chmod(resolver_path, original_mode)
        if os.path.exists(backup_path):
            os.unlink(backup_path)
        if os.path.exists(log_path):
            os.unlink(log_path)


def test_resolver_cron():
    path = "/home/user/resolver.cron"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original textual checks.
    assert "*/5 * * * *" in content, f"{path} does not contain the correct cron schedule (*/5 * * * *)."
    assert "/home/user/run_ci.sh" in content, f"{path} does not contain the command to run run_ci.sh."

    # Require an active cron entry; matching text in comments is not sufficient.
    active_lines = [
        line for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    cron_entry = re.compile(
        r"^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_ci\.sh(?:\s.*)?$"
    )
    assert any(cron_entry.fullmatch(line) for line in active_lines), \
        f"{path} does not contain an active valid entry running /home/user/run_ci.sh every 5 minutes."


def test_fuzz_equivalence():
    oracle_path = "/opt/oracle/resolver_oracle.py"
    agent_path = "/app/proxy-resolver/resolver.py"

    assert os.path.isfile(oracle_path), f"Oracle script missing at {oracle_path}."
    assert os.path.isfile(agent_path), f"Agent script missing at {agent_path}."

    # Check if agent script is executable
    st = os.stat(agent_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {agent_path} is not executable."

    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, \
        "The submitted resolver.py must not be byte-identical to the reference implementation."

    random.seed(42)

    def generate_ip():
        return ".".join(str(random.randint(0, 255)) for _ in range(4))

    def generate_domain():
        name = "".join(random.choices(string.ascii_lowercase, k=random.randint(5, 10)))
        tld = random.choice(["com", "net", "org", "io"])
        return f"{name}.{tld}"

    inputs = []
    for _ in range(1000):
        inputs.append(f"{generate_ip()} {generate_domain()}")

    input_data = "\n".join(inputs) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [sys.executable, oracle_path],
        input=input_data,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout.strip().split("\n")

    # Run agent
    agent_proc = subprocess.run(
        [sys.executable, agent_path],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"

    agent_output = agent_proc.stdout.strip().split("\n")

    assert len(oracle_output) == len(inputs), "Oracle output length mismatch."
    assert len(agent_output) == len(inputs), f"Agent output length mismatch. Expected {len(inputs)}, got {len(agent_output)}."

    for i, (inp, oracle_res, agent_res) in enumerate(zip(inputs, oracle_output, agent_output)):
        assert oracle_res == agent_res, \
            f"Mismatch on input '{inp}'. Oracle produced '{oracle_res}', but agent produced '{agent_res}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
