#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/etl_scorer.py"
ORACLE_BINARY = "/app/legacy_score"

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        return result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT"

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_rejects_extra_keys():
    payload = json.dumps({"f1": 1.0, "f2": 2.0, "f3": 3.0, "f4": 4.0, "f5": 5.0})
    agent_code, agent_out = run_cmd(["python3", AGENT_SCRIPT, payload])
    assert agent_code == 1, f"Agent accepted an extra key. Exit code: {agent_code}"
    assert "SCHEMA_ERROR" in agent_out, f"Agent did not output SCHEMA_ERROR for an extra key. Output: {agent_out}"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary missing at {ORACLE_BINARY}"

    random.seed(42)
    N = 5000

    for i in range(N):
        # 5% malformed inputs
        is_malformed = random.random() < 0.05
        malform_type = None

        if is_malformed:
            malform_type = random.choice(["missing_key", "extra_key", "string_val", "bad_json"])
            d = {"f1": 1.0, "f2": 2.0, "f3": 3.0, "f4": 4.0}
            if malform_type == "missing_key":
                del d["f2"]
                payload = json.dumps(d)
            elif malform_type == "extra_key":
                d["f5"] = 5.0
                payload = json.dumps(d)
            elif malform_type == "string_val":
                d["f3"] = "not_a_number"
                payload = json.dumps(d)
            else:
                payload = '{"f1": 1.0, "f2": 2.0, "f3": 3.0, "f4": 4.0' # missing brace
        else:
            d = {
                "f1": random.uniform(-50.0, 50.0),
                "f2": random.uniform(-50.0, 50.0),
                "f3": random.uniform(-50.0, 50.0),
                "f4": random.uniform(-50.0, 50.0)
            }
            payload = json.dumps(d)

        oracle_code, oracle_out = run_cmd([ORACLE_BINARY, payload])
        agent_code, agent_out = run_cmd(["python3", AGENT_SCRIPT, payload])

        if is_malformed:
            # The required schema is stricter than the legacy binary: extra keys
            # must be rejected even though the oracle accepts them.
            assert agent_code == 1, f"Agent accepted malformed input {payload}. Exit code: {agent_code}"
            assert "SCHEMA_ERROR" in agent_out, f"Agent did not output SCHEMA_ERROR on malformed input {payload}. Output: {agent_out}"
            if malform_type != "extra_key":
                assert oracle_code == agent_code, f"Exit code mismatch on input {payload}. Oracle: {oracle_code}, Agent: {agent_code}"
        else:
            assert oracle_code == agent_code, f"Exit code mismatch on input {payload}. Oracle: {oracle_code}, Agent: {agent_code}"
            # We compare the float output. The prompt says "rounded to 4 decimal places".
            # The oracle outputs %.4f, so string comparison should work.
            assert oracle_out == agent_out, f"Output mismatch on input {payload}. Oracle: {oracle_out}, Agent: {agent_out}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
