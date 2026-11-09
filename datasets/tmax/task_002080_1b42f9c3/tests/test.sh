#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import pytest

def generate_fuzz_inputs(n):
    random.seed(42)
    inputs = []
    chars = string.ascii_letters + string.digits + string.punctuation + ' '
    for _ in range(n):
        choice = random.random()
        if choice < 0.4:
            # valid
            host = ''.join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(1, 10)))
            port = ''.join(random.choices(string.digits, k=random.randint(1, 5)))
            path = ''.join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(1, 10)))
            inputs.append(f"upstream://{host}:{port}/{path}")
        elif choice < 0.7:
            # random ascii
            length = random.randint(1, 50)
            inputs.append(''.join(random.choices(chars, k=length)))
        else:
            # edge cases
            edge_cases = [
                "upstream://host:port/",
                "upstream://:80/path",
                "upstream://host:/path",
                "upstream://host:80path",
                "upstream:/host:80/path",
                "upstream://host:80/path/extra",
                "upstream://host:80/path?query=1",
            ]
            inputs.append(random.choice(edge_cases))
    return inputs

def test_fuzz_equivalence():
    agent_bin = "/app/socket_resolver/target/release/socket_resolver"
    oracle_bin = "/tests/socket_resolver_oracle"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}. Did you build the release binary?"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable."
    assert os.path.isfile(oracle_bin), f"Verifier oracle not found at {oracle_bin}."

    inputs = generate_fuzz_inputs(1000)
    for inp in inputs:
        # Run oracle
        oracle_proc = subprocess.run([oracle_bin], input=inp.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        oracle_out = oracle_proc.stdout.decode().strip()

        # Run agent
        agent_proc = subprocess.run([agent_bin], input=inp.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        agent_out = agent_proc.stdout.decode().strip()

        assert agent_out == oracle_out, f"Mismatch on input {repr(inp)}: expected {repr(oracle_out)}, got {repr(agent_out)}"

def test_backup_exists():
    backup_path = "/home/user/backups/resolver.conf.bak"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."

def test_supervisor_config():
    conf_path = "/home/user/supervisor/conf.d/resolver.conf"
    assert os.path.isfile(conf_path), f"Supervisor config {conf_path} is missing."

    content = open(conf_path).read()
    content_no_spaces = content.replace(" ", "").replace("\t", "")

    assert "[program:resolver_daemon]" in content, "Missing [program:resolver_daemon] section in supervisor config."
    assert "command=/home/user/wrapper.sh" in content_no_spaces, "Supervisor config does not execute /home/user/wrapper.sh."
    assert "autorestart=true" in content_no_spaces or "autorestart=unexpected" in content_no_spaces, "Supervisor config is not set to auto-restart on failure."

def test_logrotate_config():
    conf_path = "/home/user/logrotate.d/resolver"
    assert os.path.isfile(conf_path), f"Logrotate config {conf_path} is missing."

    content = open(conf_path).read()

    assert "/home/user/logs/resolver.log" in content, "Logrotate config does not target /home/user/logs/resolver.log."
    assert "daily" in content, "Logrotate config is not set to rotate daily."
    assert "rotate 7" in content or "rotate=7" in content.replace(" ", ""), "Logrotate config does not keep 7 backups."
    assert "compress" in content, "Logrotate config does not compress old logs."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
