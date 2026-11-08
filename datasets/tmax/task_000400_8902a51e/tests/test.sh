#!/bin/bash
mkdir -p /logs/verifier

suffix="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
REAL_PLANNER="/app/.query_planner.real.${suffix}"
EVENT_DIR="/tmp/planner-events-${suffix}"
mkdir -p "$EVENT_DIR"

if ! mv /app/query_planner "$REAL_PLANNER"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cleanup() {
    rm -f /app/query_planner
    if [ -e "$REAL_PLANNER" ]; then
        mv "$REAL_PLANNER" /app/query_planner
    fi
    rm -rf "$EVENT_DIR"
}
trap cleanup EXIT

cat > /app/query_planner <<EOF
#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile

REAL_PLANNER = ${REAL_PLANNER@Q}
EVENT_DIR = ${EVENT_DIR@Q}

data = sys.stdin.buffer.read()
fd, event_path = tempfile.mkstemp(prefix="invocation-", dir=EVENT_DIR)
with os.fdopen(fd, "wb") as event_file:
    event_file.write(data)

result = subprocess.run([REAL_PLANNER], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
EOF
chmod 755 /app/query_planner

export REAL_PLANNER EVENT_DIR
cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/gatekeeper.sh"
REAL_PLANNER = os.environ["REAL_PLANNER"]
EVENT_DIR = os.environ["EVENT_DIR"]


def test_gatekeeper_script_exists_and_executable():
    script_path = "/home/user/gatekeeper.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_adversarial_corpus():
    script_path = "/home/user/gatekeeper.sh"
    evil_dir = "/verify/corpus/evil/"
    clean_dir = "/verify/corpus/clean/"

    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} missing."
    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} missing."

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([script_path, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = subprocess.run([script_path, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def _sum_cost(node):
    assert isinstance(node, dict), "Planner output contains a non-object operator"
    cost = node.get("est_cost", 0)
    assert isinstance(cost, int) and not isinstance(cost, bool), "est_cost is not an integer"
    inputs = node.get("inputs", [])
    assert isinstance(inputs, list), "inputs is not an array"
    return cost + sum(_sum_cost(child) for child in inputs)


def _expected_status(query_bytes):
    result = subprocess.run(
        [REAL_PLANNER], input=query_bytes, capture_output=True, timeout=10, check=True
    )
    plan = json.loads(result.stdout)
    return 1 if _sum_cost(plan) > 5000 else 0


def _clear_events():
    for name in os.listdir(EVENT_DIR):
        path = os.path.join(EVENT_DIR, name)
        if os.path.isfile(path):
            os.unlink(path)


def _recorded_inputs():
    values = []
    for name in os.listdir(EVENT_DIR):
        path = os.path.join(EVENT_DIR, name)
        if os.path.isfile(path):
            with open(path, "rb") as event_file:
                values.append(event_file.read())
    return values


def test_random_queries_are_planned_and_costed():
    random_dir = f"/tmp/gatekeeper-cases-{secrets.token_hex(12)}"
    os.mkdir(random_dir)

    cases = []
    counts = {0: 0, 1: 0}
    attempts = 0
    while min(counts.values()) < 8 and attempts < 1000:
        attempts += 1
        query = (
            f"MATCH (n) WHERE n.audit_token = '{secrets.token_hex(24)}' "
            f"RETURN n /* {attempts}-{secrets.token_hex(8)} */"
        ).encode()
        expected = _expected_status(query)
        if counts[expected] >= 8:
            continue
        path = os.path.join(random_dir, f"case-{secrets.token_hex(16)}.query")
        with open(path, "wb") as query_file:
            query_file.write(query)
        cases.append((path, query, expected))
        counts[expected] += 1

    assert counts == {0: 8, 1: 8}, f"Could not generate balanced randomized cases: {counts}"

    child_env = {
        key: value for key, value in os.environ.items()
        if key not in {"REAL_PLANNER", "EVENT_DIR"}
    }
    for path, query, expected in cases:
        _clear_events()
        result = subprocess.run(
            [SCRIPT_PATH, path], capture_output=True, timeout=10, env=child_env
        )
        assert result.returncode == expected, (
            f"Wrong decision for randomized query: expected {expected}, got {result.returncode}"
        )
        assert query in _recorded_inputs(), (
            "The gatekeeper did not pass the query file's contents to /app/query_planner via stdin"
        )
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
