#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/app/legacy_auditor"
AGENT_PATH = "/home/user/py_auditor.py"
NUM_TESTS = 1000

def base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')

def generate_input(seed: int) -> str:
    random.seed(seed)
    if random.random() < 0.05:
        # Malformed inputs
        choices = [
            "".join(random.choices(string.ascii_letters, k=20)),
            "a.b",
            "a.b.c.d",
            "invalid_base64!.b.c",
            base64url_encode(b'{"alg":"none"}') + "." + base64url_encode(b'not json') + ".sig",
            "eyJhbGciOiJub25lIn0.invalid_payload_!@#.sig"
        ]
        return random.choice(choices)

    alg = random.choice(["HS256", "none", "RS256"])
    header = {"alg": alg}

    user = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(5, 10)))
    admin = random.choice([True, False])
    payload = {"user": user, "admin": admin}

    if random.random() < 0.5:
        extra_choices = ["<script>", "UNION SELECT", "1=1", "admin'--", "' OR 1=1", "normal text", "some random data"]
        payload["extra"] = random.choice(extra_choices)

    header_b64 = base64url_encode(json.dumps(header).encode('utf-8'))
    payload_b64 = base64url_encode(json.dumps(payload).encode('utf-8'))
    sig_b64 = base64url_encode(os.urandom(random.randint(0, 16))) if random.random() < 0.8 else ""

    return f"{header_b64}.{payload_b64}.{sig_b64}"

def run_cmd(cmd: list, arg: str) -> str:
    try:
        result = subprocess.run(
            cmd + [arg],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return "<TIMEOUT>"
    except Exception as e:
        return f"<ERROR: {e}>"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"

    oracle_cmd = [ORACLE_PATH]
    agent_cmd = ["/usr/bin/python3", AGENT_PATH]

    mismatches = []

    for i in range(NUM_TESTS):
        token = generate_input(seed=42 + i)

        oracle_out = run_cmd(oracle_cmd, token)
        agent_out = run_cmd(agent_cmd, token)

        if oracle_out != agent_out:
            mismatches.append({
                "input": token,
                "oracle": oracle_out,
                "agent": agent_out
            })

            # Stop early to avoid massive output
            if len(mismatches) >= 5:
                break

    if mismatches:
        err_msg = f"Found mismatches between {ORACLE_PATH} and {AGENT_PATH}:\n"
        for m in mismatches:
            err_msg += f"Input:  {m['input']}\n"
            err_msg += f"Oracle: {repr(m['oracle'])}\n"
            err_msg += f"Agent:  {repr(m['agent'])}\n"
            err_msg += "-" * 40 + "\n"
        pytest.fail(err_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
