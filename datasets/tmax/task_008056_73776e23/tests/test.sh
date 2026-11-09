#!/bin/bash
set -e
mkdir -p /logs/verifier

if ! pgrep -x mongod >/dev/null 2>&1; then
    mongod --fork --logpath /var/log/mongodb.log --bind_ip_all >/dev/null 2>&1 || true
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import time
import uuid

import pytest
from pymongo import MongoClient

SCRIPT = "/home/user/audit.py"
RESULTS = "/home/user/audit_results.json"


def run_script(*args):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        ["python3", SCRIPT, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, (
        f"audit.py failed with arguments {args}:\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    assert os.path.isfile(RESULTS), "audit.py did not create audit_results.json"
    with open(RESULTS, "r") as f:
        return json.load(f)


def contains_equality(value, field, expected):
    if isinstance(value, dict):
        if field in value:
            candidate = value[field]
            if candidate == expected:
                return True
            if isinstance(candidate, dict) and candidate.get("$eq") == expected:
                return True
        return any(contains_equality(v, field, expected) for v in value.values())
    if isinstance(value, list):
        return any(contains_equality(v, field, expected) for v in value)
    return False


@pytest.fixture(scope="session", autouse=True)
def exercise_submission():
    client = MongoClient("localhost", 27017, serverSelectionTimeoutMS=5000)
    for _ in range(20):
        try:
            client.admin.command("ping")
            break
        except Exception:
            time.sleep(0.25)
    else:
        pytest.fail("MongoDB is not available")

    # Both options must be real, required argparse options.
    for incomplete in ([], ["--resource", "x"], ["--source-user", "x"]):
        proc = subprocess.run(
            ["python3", SCRIPT, *incomplete],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode != 0, f"Missing required CLI argument was accepted: {incomplete}"

    db = client.compliance
    collection = db.access_logs
    token = uuid.uuid4().hex
    resource = f"verify_resource_{token}"
    other_resource = f"verify_other_{token}"
    source = f"verify_source_{token}"
    user_a = f"verify_a_{token}"
    user_b = f"verify_b_{token}"
    user_c = f"verify_c_{token}"
    disconnected_1 = f"verify_disconnected_1_{token}"
    disconnected_2 = f"verify_disconnected_2_{token}"
    revoked = f"verify_revoked_{token}"
    wrong_resource = f"verify_wrong_resource_{token}"

    documents = [
        {"event_id": str(uuid.uuid4()), "action": "GRANT", "actor": source, "target": user_b, "resource": resource},
        {"event_id": str(uuid.uuid4()), "action": "GRANT", "actor": user_b, "target": user_a, "resource": resource},
        {"event_id": str(uuid.uuid4()), "action": "GRANT", "actor": source, "target": user_c, "resource": resource},
        {"event_id": str(uuid.uuid4()), "action": "GRANT", "actor": user_a, "target": source, "resource": resource},
        {"event_id": str(uuid.uuid4()), "action": "GRANT", "actor": disconnected_1, "target": disconnected_2, "resource": resource},
        {"event_id": str(uuid.uuid4()), "action": "REVOKE", "actor": source, "target": revoked, "resource": resource},
        {"event_id": str(uuid.uuid4()), "action": "GRANT", "actor": source, "target": wrong_resource, "resource": other_resource},
    ]
    collection.insert_many(documents)

    try:
        db.command("profile", 0)
        try:
            db.system.profile.drop()
        except Exception:
            pass
        db.command("profile", 2)

        data = run_script("--resource", resource, "--source-user", source)
        expected = sorted([user_a, user_b, user_c])
        assert isinstance(data, list), "Output JSON should be a list of strings."
        assert data == expected, f"Expected alternate-input result {expected}, but got {data}."

        db.command("profile", 0)
        profiles = list(db.system.profile.find({
            "op": "command",
            "command.aggregate": "access_logs",
        }))
        assert profiles, "audit.py did not execute an aggregation on compliance.access_logs"

        valid_pipeline = False
        for profile in profiles:
            pipeline = profile.get("command", {}).get("pipeline", [])
            match_stages = [stage["$match"] for stage in pipeline if isinstance(stage, dict) and "$match" in stage]
            project_stages = [stage["$project"] for stage in pipeline if isinstance(stage, dict) and "$project" in stage]
            has_action = any(contains_equality(stage, "action", "GRANT") for stage in match_stages)
            has_resource = any(contains_equality(stage, "resource", resource) for stage in match_stages)
            for projection in project_stages:
                if not isinstance(projection, dict):
                    continue
                included = {k for k, v in projection.items() if k != "_id" and v not in (0, False)}
                excludes_id = projection.get("_id") in (0, False)
                if has_action and has_resource and included == {"actor", "target"} and excludes_id:
                    valid_pipeline = True
                    break
            if valid_pipeline:
                break
        assert valid_pipeline, (
            "Aggregation must match the requested resource and GRANT actions, then project only actor and target"
        )
    finally:
        try:
            db.command("profile", 0)
        except Exception:
            pass
        collection.delete_many({"event_id": {"$in": [d["event_id"] for d in documents]}})

    # Preserve and verify the originally requested execution and final output.
    original = run_script("--resource", "vault_prod", "--source-user", "contractor_01")
    expected_original = ["admin_01", "emp_02", "emp_03", "emp_05"]
    assert original == expected_original, f"Expected {expected_original}, but got {original}."


def test_audit_py_exists():
    """Verify that the audit script was created."""
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} does not exist."
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "pymongo" in content, "Script does not seem to import or use pymongo."
    assert "networkx" in content, "Script does not seem to import or use networkx."
    assert "argparse" in content, "Script does not seem to use argparse."
    ast.parse(content)


def test_audit_results_json():
    """Verify that the audit results JSON was generated and contains the correct output."""
    assert os.path.isfile(RESULTS), f"Expected output file {RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON.")

    expected_users = ["admin_01", "emp_02", "emp_03", "emp_05"]
    assert isinstance(data, list), "Output JSON should be a list of strings."
    assert data == expected_users, f"Expected {expected_users}, but got {data}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
