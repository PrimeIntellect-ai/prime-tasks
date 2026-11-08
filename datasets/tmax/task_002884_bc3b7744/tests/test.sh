#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import random
import string
import subprocess
import os
import time
import pytest

ORACLE_SCRIPT = "/tests/oracle_transform"

def generate_fuzz_input():
    msg_id = ''.join(random.choices("0123456789abcdef", k=8))
    lang = ''.join(random.choices(string.ascii_lowercase, k=2))

    num_placeholders = random.randint(0, 5)
    keys = []
    for _ in range(num_placeholders):
        keys.append(''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 5))))

    template_parts = []
    for key in keys:
        template_parts.append(''.join(random.choices(string.ascii_letters + " ", k=random.randint(5, 10))))
        template_parts.append(f"{{{key}}}")
    template_parts.append(''.join(random.choices(string.ascii_letters + " ", k=random.randint(5, 10))))
    template = "".join(template_parts)

    vars_dict = {}
    for key in keys:
        r = random.random()
        if r < 0.5:
            pass # missing
        elif r < 0.7:
            vars_dict[key] = ""
        else:
            vars_dict[key] = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 8)))

    # Add some random keys not in template
    for _ in range(random.randint(0, 3)):
        k = ''.join(random.choices(string.ascii_lowercase, k=4))
        if k not in vars_dict:
            vars_dict[k] = "randomval"

    return json.dumps({
        "msg_id": msg_id,
        "lang": lang,
        "template": template,
        "vars": vars_dict
    })

def run_oracle(payload):
    return subprocess.run(
        ["python3", ORACLE_SCRIPT],
        input=payload.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

def test_fuzz_transform():
    """Fuzz test the transform.sh script against the oracle binary."""
    agent_script = "/home/user/transform.sh"

    assert os.path.exists(agent_script), f"Missing {agent_script}"
    assert os.access(agent_script, os.X_OK), f"{agent_script} is not executable"
    assert os.path.exists(ORACLE_SCRIPT), f"Missing {ORACLE_SCRIPT}"

    random.seed(42)
    for _ in range(500):
        payload = generate_fuzz_input()

        # Run oracle
        proc_oracle = run_oracle(payload)
        oracle_out = proc_oracle.stdout.decode().strip()

        # Run agent
        proc_agent = subprocess.run([agent_script], input=payload.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        agent_out = proc_agent.stdout.decode().strip()

        assert agent_out == oracle_out, f"Mismatch on input: {payload}\nExpected: {oracle_out}\nGot: {agent_out}"

def test_end_to_end_worker():
    """Test the end-to-end orchestration flow with worker.sh and Redis."""
    # Check if redis-server is running
    try:
        subprocess.run(["redis-cli", "PING"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        pytest.fail("redis-server is not running or not accessible via redis-cli on default port")

    # Check if worker.sh is running
    pgrep_worker = subprocess.run(["pgrep", "-f", "worker.sh"], stdout=subprocess.PIPE)
    assert pgrep_worker.returncode == 0, "worker.sh is not running in the background"

    random.seed(1337)
    payloads = [generate_fuzz_input() for _ in range(10)]

    # Push jobs to Redis
    for p in payloads:
        subprocess.run(["redis-cli", "RPUSH", "loc_jobs", p], check=True, stdout=subprocess.DEVNULL)

    # Wait for the worker to process
    time.sleep(2)

    # Verify results in Redis
    for p in payloads:
        data = json.loads(p)
        msg_id = data["msg_id"]

        # Compute expected output using oracle
        proc_oracle = run_oracle(p)
        oracle_out = proc_oracle.stdout.decode().strip()
        # Oracle outputs msg_id|lang|interpolated_template
        # Worker should store lang|interpolated_template in Redis
        expected_val = "|".join(oracle_out.split("|")[1:])

        # Check Redis hash
        proc_redis = subprocess.run(["redis-cli", "HGET", "loc_results", msg_id], stdout=subprocess.PIPE)
        redis_out = proc_redis.stdout.decode().strip()

        assert redis_out == expected_val, f"Redis hash loc_results for msg_id '{msg_id}' mismatch.\nExpected: {expected_val}\nGot: {redis_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
