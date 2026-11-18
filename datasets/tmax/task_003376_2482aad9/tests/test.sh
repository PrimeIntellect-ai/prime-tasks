#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import shutil
import subprocess

import pytest

SCRIPT_PATH = "/home/user/audit.sh"
RESULTS_PATH = "/home/user/audit_results.json"

CANONICAL_USERS = [
    {"id": "u1", "name": "Alice", "dept": "Engineering", "clearance": 3},
    {"id": "u2", "name": "Bob", "dept": "HR", "clearance": 1},
    {"id": "u3", "name": "Charlie", "dept": "Engineering", "clearance": 2},
    {"id": "u4", "name": "Dave", "dept": "Finance", "clearance": 2},
    {"id": "u5", "name": "Eve", "dept": "Legal", "clearance": 5},
    {"id": "u6", "name": "Frank", "dept": "Finance", "clearance": 1},
]
CANONICAL_SYSTEMS = {
    "sysA": {"req_dept": "Engineering", "req_clearance": 2},
    "sysB": {"req_dept": "Finance", "req_clearance": 3},
}
CANONICAL_MANAGERS = {"u3": "u1", "u2": "u4", "u4": "u5", "u6": "u4"}
CANONICAL_LOGS = [
    {"timestamp": 1620000000, "user_id": "u3", "system_id": "sysA"},
    {"timestamp": 1620000010, "user_id": "u2", "system_id": "sysA"},
    {"timestamp": 1620000020, "user_id": "u4", "system_id": "sysB"},
    {"timestamp": 1620000030, "user_id": "u3", "system_id": "sysB"},
    {"timestamp": 1620000040, "user_id": "u5", "system_id": "sysB"},
    {"timestamp": 1620000050, "user_id": "u6", "system_id": "sysB"},
    {"timestamp": 1620000060, "user_id": "u1", "system_id": "sysB"},
]


def compute_expected_violations(system_id, users, systems, managers, logs):
    users_by_id = {user["id"]: user for user in users}
    sys_req = systems.get(system_id)
    if not sys_req:
        return []

    violations = []
    for log in logs:
        if log["system_id"] != system_id:
            continue

        user = users_by_id.get(log["user_id"])
        if not user:
            continue

        clearance_fail = user["clearance"] < sys_req["req_clearance"]
        manager_id = managers.get(user["id"])
        manager_dept = users_by_id.get(manager_id, {}).get("dept") if manager_id else None
        dept_fail = (
            user["dept"] != sys_req["req_dept"]
            and manager_dept != sys_req["req_dept"]
        )

        if clearance_fail or dept_fail:
            if clearance_fail and dept_fail:
                reason = "Clearance and Department failed"
            elif clearance_fail:
                reason = "Clearance too low"
            else:
                reason = "Department mismatch"

            violations.append({
                "timestamp": log["timestamp"],
                "user_id": user["id"],
                "user_name": user["name"],
                "violation_reason": reason,
            })

    violations.sort(key=lambda item: item["timestamp"], reverse=True)
    return violations[:3]


def remove_existing(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def install_fixture(users, systems, managers, logs):
    os.makedirs("/home/user", exist_ok=True)
    paths = [
        "/home/user/users.json",
        "/home/user/systems.json",
        "/home/user/org_chart.txt",
        "/home/user/access_logs.csv",
    ]
    for path in paths:
        remove_existing(path)

    with open(paths[0], "w") as f:
        json.dump(users, f)
    with open(paths[1], "w") as f:
        json.dump(systems, f)
    with open(paths[2], "w") as f:
        for employee_id, manager_id in managers.items():
            f.write(f"{manager_id} {employee_id}\n")
    with open(paths[3], "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["timestamp", "user_id", "system_id"])
        writer.writeheader()
        writer.writerows(logs)


def load_results(context):
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist {context}."
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} does not contain valid JSON {context}.")


def assert_results(actual_results, expected_results, context):
    assert isinstance(actual_results, list), f"Expected JSON array in {RESULTS_PATH} {context}."
    assert len(actual_results) == len(expected_results), (
        f"Expected {len(expected_results)} results {context}, got {len(actual_results)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert actual.get("timestamp") == expected["timestamp"], f"Mismatch in timestamp {context} at index {i}."
        assert actual.get("user_id") == expected["user_id"], f"Mismatch in user_id {context} at index {i}."
        assert actual.get("user_name") == expected["user_name"], f"Mismatch in user_name {context} at index {i}."
        assert actual.get("violation_reason") == expected["violation_reason"], f"Mismatch in violation_reason {context} at index {i}."


def run_and_check(system_id, users, systems, managers, logs, context):
    install_fixture(users, systems, managers, logs)
    expected = compute_expected_violations(system_id, users, systems, managers, logs)
    result = subprocess.run(
        [SCRIPT_PATH, system_id],
        capture_output=True,
        text=True,
        timeout=15,
        cwd="/home/user",
    )
    assert result.returncode == 0, f"Script failed {context}. Error: {result.stderr}"
    assert_results(load_results(context), expected, context)


def test_01_audit_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_02_preexisting_audit_results_for_sysB():
    expected = compute_expected_violations(
        "sysB", CANONICAL_USERS, CANONICAL_SYSTEMS, CANONICAL_MANAGERS, CANONICAL_LOGS
    )
    assert_results(load_results("for the required pre-run sysB output"), expected, "for sysB")


def test_03_execute_script_for_canonical_sysB_and_sysA():
    run_and_check(
        "sysB", CANONICAL_USERS, CANONICAL_SYSTEMS, CANONICAL_MANAGERS,
        CANONICAL_LOGS, "when running for sysB"
    )
    run_and_check(
        "sysA", CANONICAL_USERS, CANONICAL_SYSTEMS, CANONICAL_MANAGERS,
        CANONICAL_LOGS, "when running for sysA"
    )


def test_04_execute_script_with_fresh_parameterized_fixture():
    suffix = secrets.token_hex(6)
    target = f"target_{suffix}"
    other = f"other_{suffix}"
    base = 1700000000 + secrets.randbelow(1000000)

    users = [
        {"id": f"a_{suffix}", "name": f"Alfa {suffix}", "dept": "Engineering", "clearance": 1},
        {"id": f"b_{suffix}", "name": f"Bravo {suffix}", "dept": "HR", "clearance": 5},
        {"id": f"c_{suffix}", "name": f"Charlie {suffix}", "dept": "HR", "clearance": 1},
        {"id": f"d_{suffix}", "name": f"Delta {suffix}", "dept": "HR", "clearance": 5},
        {"id": f"e_{suffix}", "name": f"Echo {suffix}", "dept": "Engineering", "clearance": 5},
        {"id": f"f_{suffix}", "name": f"Foxtrot {suffix}", "dept": "Engineering", "clearance": 4},
        {"id": f"g_{suffix}", "name": f"Golf {suffix}", "dept": "Legal", "clearance": 4},
        {"id": f"m_{suffix}", "name": f"Manager {suffix}", "dept": "Finance", "clearance": 5},
    ]
    systems = {
        target: {"req_dept": "Engineering", "req_clearance": 3},
        other: {"req_dept": "Legal", "req_clearance": 5},
    }
    managers = {
        f"b_{suffix}": f"m_{suffix}",
        f"c_{suffix}": f"m_{suffix}",
        f"d_{suffix}": f"e_{suffix}",
    }
    logs = [
        {"timestamp": base + 130, "user_id": f"c_{suffix}", "system_id": target},
        {"timestamp": base + 999, "user_id": f"a_{suffix}", "system_id": other},
        {"timestamp": base + 110, "user_id": f"a_{suffix}", "system_id": target},
        {"timestamp": base + 140, "user_id": f"d_{suffix}", "system_id": target},
        {"timestamp": base + 105, "user_id": f"g_{suffix}", "system_id": target},
        {"timestamp": base + 120, "user_id": f"b_{suffix}", "system_id": target},
        {"timestamp": base + 150, "user_id": f"f_{suffix}", "system_id": target},
    ]

    run_and_check(target, users, systems, managers, logs, "with a fresh system_id and fixture")

    # Leave the canonical data and required sysB result in place.
    run_and_check(
        "sysB", CANONICAL_USERS, CANONICAL_SYSTEMS, CANONICAL_MANAGERS,
        CANONICAL_LOGS, "when restoring the canonical sysB result"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
