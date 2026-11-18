#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import subprocess
import random
import string
from datetime import datetime, timedelta


def test_emitter_json_fixed():
    path = "/home/user/emitter.json"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not valid JSON")

    assert data.get("output_type") == "redis", f"output_type in {path} is not 'redis'"
    assert data.get("redis_host") == "127.0.0.1", f"redis_host in {path} is not '127.0.0.1'"
    assert data.get("redis_port") == 6379, f"redis_port in {path} is not 6379"


def test_dashboard_env_fixed():
    path = "/home/user/dashboard.env"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()

    assert "REDIS_URL=redis://127.0.0.1:6379/0" in content, f"REDIS_URL is not correctly set in {path}"


def test_normalize_sh_fuzz_equivalence():
    agent_script = "/home/user/normalize.sh"
    oracle_script = "/tests/oracle_normalize.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."

    random.seed(42)

    services = ["web_server", "db_server", "cache", "auth_svc", "api_gateway"]
    operations = ["CREATE", "MODIFY", "DELETE", "READ", "UPDATE", "SYNC"]
    secret_variants = ["SECRET", "secret", "SeCrEt"]

    start_date = datetime(2020, 1, 1)
    end_date = datetime(2025, 12, 31)
    delta = end_date - start_date
    delta_seconds = int(delta.total_seconds())

    for i in range(500):
        num_lines = random.randint(50, 500)
        lines = []
        for _ in range(num_lines):
            rand_seconds = random.randint(0, delta_seconds)
            dt = start_date + timedelta(seconds=rand_seconds)
            ts_str = dt.strftime("%Y-%m-%d %H:%M:%S")

            svc = random.choice(services)
            op = random.choice(operations)

            key_len = random.randint(5, 15)
            key = ''.join(random.choices(string.ascii_letters + string.digits, k=key_len))
            if random.random() < 0.2:
                sec = random.choice(secret_variants)
                insert_pos = random.randint(0, len(key))
                key = key[:insert_pos] + sec + key[insert_pos:]

            val_len = random.randint(0, 255)
            val = ''.join(random.choices(string.printable.replace('\n', '').replace('\r', ''), k=val_len))

            line = f"{ts_str} | {svc} | {op} | {key}={val}"
            lines.append(line)

        input_data = "\n".join(lines) + "\n"

        agent_proc = subprocess.run(["bash", agent_script], input=input_data, text=True, capture_output=True)
        oracle_proc = subprocess.run(["bash", oracle_script], input=input_data, text=True, capture_output=True)

        if agent_proc.returncode != 0 and oracle_proc.returncode == 0:
            pytest.fail(f"Agent script failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr}")

        if agent_proc.stdout != oracle_proc.stdout:
            input_snippet = "\n".join(lines[:5])
            if len(lines) > 5:
                input_snippet += "\n..."

            pytest.fail(
                f"Mismatch on iteration {i+1}.\n"
                f"--- Input snippet ---\n"
                f"{input_snippet}\n"
                f"--- Expected Output (Oracle) ---\n"
                f"{oracle_proc.stdout}\n"
                f"--- Actual Output (Agent) ---\n"
                f"{agent_proc.stdout}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
