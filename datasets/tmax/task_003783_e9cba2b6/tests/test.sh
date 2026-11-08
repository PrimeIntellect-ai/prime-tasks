#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import string
import subprocess
import time
import urllib.request

import pytest


def test_config_updated():
    config_path = "/app/config/settings.json"
    assert os.path.isfile(config_path), f"{config_path} is missing."

    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {config_path} as JSON.")

    assert config.get("api_secret") == "Secr3t_HMAC_v2_991", (
        "The 'api_secret' in settings.json was not updated to the correct value."
    )


def redis_exists(key):
    result = subprocess.run(
        ["redis-cli", "exists", key],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def test_redis_session_revoked():
    ping = subprocess.run(
        ["redis-cli", "ping"], capture_output=True, text=True, check=True
    )
    assert ping.stdout.strip() == "PONG", "Redis is not running."

    assert redis_exists("session:tok_compromised_a") == "0", (
        "Compromised Redis key 'session:tok_compromised_a' was not deleted."
    )
    assert redis_exists("session:tok_compromised_b") == "0", (
        "Compromised Redis key 'session:tok_compromised_b' was not deleted."
    )
    assert redis_exists("session:tok_valid_1") == "1", (
        "Uncompromised session 'tok_valid_1' was incorrectly removed."
    )
    assert redis_exists("session:tok_valid_2") == "1", (
        "Uncompromised session 'tok_valid_2' was incorrectly removed."
    )


def test_flask_restarted_with_rotated_configuration():
    with open("/app/.initial_flask_pid", "r") as f:
        initial_pid = int(f.read().strip())

    state = None
    last_error = None
    for _ in range(30):
        try:
            with urllib.request.urlopen(
                "http://127.0.0.1:5000/_loaded_config", timeout=1
            ) as response:
                state = json.loads(response.read().decode("utf-8"))
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)

    assert state is not None, f"The Flask API is not running: {last_error}"
    assert state.get("api_secret") == "Secr3t_HMAC_v2_991", (
        "The running Flask API has not loaded the rotated secret."
    )
    assert state.get("pid") != initial_pid, (
        "The original Flask API process is still serving; the API was not restarted."
    )


def test_fuzz_equivalence():
    agent_script = "/home/user/generate_token.py"
    oracle_script = "/tests/reference_token_gen"

    assert os.path.isfile(agent_script), f"The script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"The oracle {oracle_script} does not exist."
    assert stat.S_ISREG(os.stat(agent_script).st_mode), "Token generator is not a regular file."
    assert os.access(agent_script, os.X_OK), f"The script {agent_script} is not executable."

    with open(agent_script, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_script, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submission must not be a byte-identical copy of the oracle."

    random.seed(42)
    charset = string.ascii_letters + string.digits

    for i in range(500):
        user_len = random.randint(4, 20)
        fuzz_user = "".join(random.choices(charset, k=user_len))
        fuzz_time = str(random.randint(1600000000, 1800000000))

        cmd_oracle = [oracle_script, "--user", fuzz_user, "--time", fuzz_time]
        cmd_agent = [agent_script, "--user", fuzz_user, "--time", fuzz_time]

        res_oracle = subprocess.run(cmd_oracle, capture_output=True)
        assert res_oracle.returncode == 0, (
            f"Oracle failed unexpectedly on input --user {fuzz_user} --time {fuzz_time}"
        )

        res_agent = subprocess.run(cmd_agent, capture_output=True)
        assert res_agent.returncode == 0, (
            f"Agent script failed on input --user {fuzz_user} --time {fuzz_time}.\n"
            f"Stderr: {res_agent.stderr.decode('utf-8', errors='replace')}"
        )
        assert res_agent.stderr == b"", (
            f"Agent script wrote unexpected stderr on fuzz iteration {i + 1}."
        )
        assert res_agent.stdout == res_oracle.stdout, (
            f"Output mismatch on fuzz iteration {i + 1}.\n"
            f"Input: --user {fuzz_user} --time {fuzz_time}\n"
            f"Expected bytes: {res_oracle.stdout!r}\n"
            f"Got bytes: {res_agent.stdout!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
