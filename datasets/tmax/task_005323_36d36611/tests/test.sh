#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "audit.go")
RESULTS = os.path.join(HOME, "audit_results.json")
PLAN = os.path.join(HOME, "query_plan.json")


def mongo_eval(script):
    candidates = glob.glob("/home/user/mongodb-linux-*/bin/mongosh")
    assert candidates, "mongosh was not installed by setup_env.sh"
    proc = subprocess.run(
        [candidates[0], "--quiet", "--port", "27017", "--eval", script],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, f"MongoDB command failed: {proc.stderr or proc.stdout}"
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    return lines[-1] if lines else ""


def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def prepare_and_run():
    assert os.path.exists(SOURCE), f"Go program {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    assert os.path.getsize(SOURCE) > 0, f"Go program {SOURCE} is empty."

    mongo_eval('db = db.getSiblingDB("admin"); print(JSON.stringify(db.runCommand({ping: 1})))')

    token = secrets.token_hex(10)
    high_user = "verify_high_" + token
    threshold_user = "verify_threshold_" + token
    low_user = "verify_low_" + token
    wrong_role_user = "verify_admin_" + token
    high_count = 4 + secrets.randbelow(3)

    docs = []
    for i in range(high_count):
        docs.append({"user_id": high_user, "role": "guest", "endpoint": f"/api/admin/dynamic-{i}"})
    for i in range(3):
        docs.append({"user_id": threshold_user, "role": "guest", "endpoint": f"/api/admin/threshold-{i}"})
    for i in range(2):
        docs.append({"user_id": low_user, "role": "guest", "endpoint": f"/api/admin/low-{i}"})
    for i in range(4):
        docs.append({"user_id": wrong_role_user, "role": "admin", "endpoint": f"/api/admin/wrong-role-{i}"})
    docs.extend([
        {"user_id": high_user, "role": "guest", "endpoint": "/api/public/not-admin"},
        {"user_id": high_user, "role": "guest", "endpoint": "/api/adminish/not-a-match"},
    ])

    mongo_eval(
        'db = db.getSiblingDB("compliance"); '
        'db.access_logs.insertMany(' + json.dumps(docs) + '); print("inserted")'
    )

    expected_text = mongo_eval(r'''
db = db.getSiblingDB("compliance");
const rows = db.access_logs.aggregate([
  {$match: {role: "guest", endpoint: {$regex: "^/api/admin/"}}},
  {$group: {_id: "$user_id", total_accesses: {$sum: 1}}},
  {$match: {total_accesses: {$gte: 3}}},
  {$sort: {_id: 1}}
]).toArray().map(x => ({user_id: x._id, total_accesses: x.total_accesses}));
print(JSON.stringify(rows));
''')
    expected = json.loads(expected_text)

    for path in (RESULTS, PLAN):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = subprocess.run(
        ["go", "run", SOURCE],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, f"go run audit.go failed:\n{proc.stdout}\n{proc.stderr}"

    indexes = json.loads(mongo_eval(
        'db = db.getSiblingDB("compliance"); '
        'print(JSON.stringify(db.access_logs.getIndexes().map(x => x.key)))'
    ))

    return expected, indexes, high_user, high_count, threshold_user


EXPECTED, INDEXES, HIGH_USER, HIGH_COUNT, THRESHOLD_USER = prepare_and_run()


def test_go_program_exists():
    assert os.path.exists(SOURCE), f"Go program {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_audit_results_json():
    assert os.path.exists(RESULTS), f"Expected results file {RESULTS} does not exist."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a file."

    try:
        with open(RESULTS, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected a JSON list in {RESULTS}."
    for record in data:
        assert isinstance(record, dict), "Every result must be a JSON object."
        assert set(record) == {"user_id", "total_accesses"}, \
            "Each result must strictly contain only user_id and total_accesses."
        assert isinstance(record["user_id"], str), "user_id must be a string."
        assert isinstance(record["total_accesses"], int) and not isinstance(record["total_accesses"], bool), \
            "total_accesses must be an integer."

    actual_sorted = sorted(data, key=lambda x: x["user_id"])
    expected_sorted = sorted(EXPECTED, key=lambda x: x["user_id"])
    assert actual_sorted == expected_sorted, \
        f"Aggregation output does not match the current MongoDB data: {actual_sorted!r} != {expected_sorted!r}"

    by_user = {row["user_id"]: row["total_accesses"] for row in data}
    assert by_user.get(HIGH_USER) == HIGH_COUNT
    assert by_user.get(THRESHOLD_USER) == 3


def test_compound_index_created():
    valid = False
    for key in INDEXES:
        if not isinstance(key, dict):
            continue
        fields = list(key.keys())
        if fields == ["role", "endpoint"] and all(
            isinstance(key[field], (int, float)) and key[field] != 0
            for field in fields
        ):
            valid = True
            break
    assert valid, "No compound index on exactly the role and endpoint fields was created."


def test_query_plan_json():
    assert os.path.exists(PLAN), f"Expected query plan file {PLAN} does not exist."
    assert os.path.isfile(PLAN), f"{PLAN} is not a file."

    with open(PLAN, "r", encoding="utf-8") as f:
        content = f.read()
    try:
        plan = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"File {PLAN} does not contain valid JSON.")

    assert isinstance(plan, dict), "The query plan must be a raw MongoDB explain document."
    content_lower = content.lower()
    assert "ixscan" in content_lower or "index" in content_lower, \
        "Query plan does not appear to use an index (missing 'IXSCAN' or 'index')."
    assert any(isinstance(node, dict) and str(node.get("stage", "")).upper() == "IXSCAN" for node in walk(plan)), \
        "MongoDB explain output does not contain an IXSCAN stage."
    assert "serverInfo" in plan and ("queryPlanner" in plan or "stages" in plan), \
        "The file does not have the structure of raw MongoDB explain output."

    command = plan.get("command")
    assert isinstance(command, dict), "Explain output is missing its aggregate command."
    assert command.get("aggregate") == "access_logs", "Explain was not run for access_logs."
    pipeline = command.get("pipeline")
    assert isinstance(pipeline, list), "Explain command is missing the aggregation pipeline."
    pipeline_text = json.dumps(pipeline, sort_keys=True)
    assert '"role": "guest"' in pipeline_text
    assert "/api/admin/" in pipeline_text
    assert '"$group"' in pipeline_text and '"$sum": 1' in pipeline_text
    assert '"total_accesses"' in pipeline_text and '"$gte": 3' in pipeline_text
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
