#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/auditor.py"
ORACLE_BINARY = "/app/audit_bin"


def generate_fuzz_input():
    nodes = [''.join(random.choices(string.ascii_uppercase, k=3)) for _ in range(10)]
    users = [''.join(random.choices(string.ascii_lowercase, k=4)) for _ in range(3)]
    ops = []

    for node in nodes:
        ops.append({"op": "add_node", "node": node, "is_sensitive": random.choice([True, False])})

    for _ in range(15):
        ops.append({"op": "add_edge", "src": random.choice(nodes), "dst": random.choice(nodes)})

    for _ in range(10):
        ops.append({"op": "grant", "user": random.choice(users), "node": random.choice(nodes)})

    random.shuffle(ops)
    return json.dumps(ops)


def expected_output(input_data):
    data = json.loads(input_data)
    nodes = {}
    edges = {}
    grants = {}

    for op in data:
        if op.get("op") == "add_node":
            nodes[op["node"]] = op.get("is_sensitive", False)
        elif op.get("op") == "add_edge":
            edges.setdefault(op["src"], []).append(op["dst"])
        elif op.get("op") == "grant":
            grants.setdefault(op["user"], []).append(op["node"])

    result = {}
    for user, starts in grants.items():
        visited = set()
        queue = list(starts)
        while queue:
            current = queue.pop(0)
            if current not in visited:
                visited.add(current)
                queue.extend(edges.get(current, []))
        result[user] = sum(1 for node in visited if nodes.get(node, False))

    return json.dumps(result, separators=(",", ":"), sort_keys=True)


def run_program(cmd, input_data):
    try:
        result = subprocess.run(
            cmd,
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as exc:
        return f"ERROR: Process exited with {exc.returncode}\nStderr: {exc.stderr}"
    except subprocess.TimeoutExpired:
        return "ERROR: Process timed out"


def test_auditor_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary missing at {ORACLE_BINARY}"
    assert os.access(ORACLE_BINARY, os.X_OK), f"Oracle binary not executable at {ORACLE_BINARY}"

    random.seed(42)
    cases = [generate_fuzz_input() for _ in range(50)]

    oracle_outputs = []
    for i, input_data in enumerate(cases):
        oracle_out = run_program([ORACLE_BINARY], input_data)
        independently_derived = expected_output(input_data)
        assert oracle_out == independently_derived, (
            f"Oracle/model disagreement on fuzz iteration {i + 1}"
        )
        oracle_outputs.append(oracle_out)

    # The oracle was available for reverse engineering during the task, but must
    # not be available when the submitted implementation is exercised.
    os.unlink(ORACLE_BINARY)

    for i, (input_data, oracle_out) in enumerate(zip(cases, oracle_outputs)):
        agent_out = run_program(["python3", AGENT_SCRIPT], input_data)
        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on fuzz iteration {i + 1}!\n"
                f"Input:\n{input_data}\n\n"
                f"Expected (Oracle):\n{oracle_out}\n\n"
                f"Actual (Agent):\n{agent_out}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
