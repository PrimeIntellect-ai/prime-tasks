#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import pytest

AGENT_PATH = "/home/user/math_service/process.sh"
PROTO_PATH = "/home/user/math_service/proto/service.proto"


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script not executable at {AGENT_PATH}"

    with open(AGENT_PATH, "r", encoding="utf-8") as f:
        first_line = f.readline().strip()
    assert re.match(r"^#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)", first_line), \
        "process.sh must be a Bash script"

    random.seed(42)
    for i in range(500):
        data_len = random.randint(1, 100)
        data = [random.randint(0, 1000) for _ in range(data_len)]
        multiplier = random.randint(1, 50)
        shift = random.randint(0, 100)

        request = {
            "data": data,
            "multiplier": multiplier,
            "shift": shift,
        }
        input_json = json.dumps(request)
        expected = {
            "result": [((x + shift) * multiplier) % 256 for x in data]
        }

        try:
            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=input_json,
                text=True,
                capture_output=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {input_json}")

        assert agent_proc.returncode == 0, \
            f"Agent script failed on input: {input_json}\nStderr: {agent_proc.stderr}"

        try:
            agent_out = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(
                f"Agent produced invalid JSON: {agent_proc.stdout}\n"
                f"Stderr: {agent_proc.stderr}"
            )

        assert agent_out == expected, \
            f"Mismatch on input {input_json}.\nExpected: {expected}\nAgent: {agent_out}"


def _message_body(content, name):
    matches = re.findall(r"\bmessage\s+" + re.escape(name) + r"\s*\{([^{}]*)\}", content, re.DOTALL)
    assert len(matches) == 1, f"Expected exactly one valid {name} message definition."
    return matches[0]


def _fields(body):
    field_pattern = re.compile(
        r"^\s*(repeated\s+)?([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+"
        r"([A-Za-z_]\w*)\s*=\s*(\d+)(?:\s*\[[^\]]*\])?\s*;\s*$",
        re.MULTILINE,
    )
    return [
        (bool(repeated), field_type, name, int(number))
        for repeated, field_type, name, number in field_pattern.findall(body)
    ]


def test_proto_updated():
    assert os.path.isfile(PROTO_PATH), f"Proto file missing at {PROTO_PATH}"
    with open(PROTO_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert "multiplier" in content, "Proto file does not define the 'multiplier' field."
    assert "shift" in content, "Proto file does not define the 'shift' field."
    assert "result" in content, "Proto file does not define the 'result' field in ProcessResponse."

    uncommented = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)
    uncommented = re.sub(r"//[^\n]*", "", uncommented)

    request_fields = _fields(_message_body(uncommented, "ProcessRequest"))
    response_fields = _fields(_message_body(uncommented, "ProcessResponse"))

    assert request_fields == [
        (True, "int32", "data", 1),
        (False, "int32", "multiplier", 2),
        (False, "int32", "shift", 3),
    ], f"Incorrect ProcessRequest schema: {request_fields}"

    assert response_fields == [
        (True, "int32", "result", 1),
    ], f"Incorrect ProcessResponse schema: {response_fields}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
