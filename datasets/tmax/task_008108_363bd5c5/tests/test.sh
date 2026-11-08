#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from collections import defaultdict

def test_invalid_schemas_log():
    log_file = "/home/user/invalid_schemas.log"
    assert os.path.isfile(log_file), f"File {log_file} does not exist."

    expected_headers = {
        "users.csv": "user_id,username",
        "user_roles.csv": "user_id,role_id",
        "roles.csv": "role_id,role_name",
        "role_access.csv": "role_id,system_id,permission_level"
    }

    audit_dir = "/home/user/audit_data"
    expected_invalid = []

    if os.path.isdir(audit_dir):
        for fname in os.listdir(audit_dir):
            if not fname.endswith(".csv"):
                continue
            filepath = os.path.join(audit_dir, fname)
            with open(filepath, "r") as f:
                first_line = f.readline().strip()

            if fname in expected_headers:
                if first_line != expected_headers[fname]:
                    expected_invalid.append(fname)
            else:
                expected_invalid.append(fname)

    with open(log_file, "r") as f:
        actual_invalid = [line.strip() for line in f if line.strip()]

    assert sorted(actual_invalid) == sorted(expected_invalid), (
        f"Expected invalid schemas to contain {expected_invalid}, but got {actual_invalid}."
    )

def test_most_accessible_system():
    result_file = "/home/user/most_accessible_system.txt"
    assert os.path.isfile(result_file), f"File {result_file} does not exist."

    # Recompute the expected system
    users = {}
    with open("/home/user/audit_data/users.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("user_id") and row.get("username"):
                users[row["user_id"]] = row["username"]

    user_roles = defaultdict(list)
    with open("/home/user/audit_data/user_roles.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("user_id") and row.get("role_id"):
                user_roles[row["user_id"]].append(row["role_id"])

    role_access = defaultdict(list)
    with open("/home/user/audit_data/role_access.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("role_id") and row.get("system_id"):
                role_access[row["role_id"]].append(row["system_id"])

    system_users = defaultdict(set)
    for uid, uname in users.items():
        for rid in user_roles.get(uid, []):
            for sid in role_access.get(rid, []):
                system_users[sid].add(uname)

    if not system_users:
        expected_sys = ""
    else:
        # Find max distinct users
        max_users = max(len(unames) for unames in system_users.values())
        # The prompt says "find the system_id...". If tie, we just check if the actual is among the max.
        best_systems = [sid for sid, unames in system_users.items() if len(unames) == max_users]

    with open(result_file, "r") as f:
        actual_sys = f.read().strip()

    assert actual_sys in best_systems, (
        f"Expected most accessible system to be one of {best_systems}, but got '{actual_sys}'."
    )

def test_admin_summary():
    result_file = "/home/user/admin_summary.txt"
    assert os.path.isfile(result_file), f"File {result_file} does not exist."

    users = {}
    with open("/home/user/audit_data/users.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("user_id") and row.get("username"):
                users[row["user_id"]] = row["username"]

    user_roles = defaultdict(list)
    with open("/home/user/audit_data/user_roles.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("user_id") and row.get("role_id"):
                user_roles[row["user_id"]].append(row["role_id"])

    role_admin_access = defaultdict(list)
    with open("/home/user/audit_data/role_access.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("role_id") and row.get("system_id") and row.get("permission_level") == "admin":
                role_admin_access[row["role_id"]].append(row["system_id"])

    user_admin_systems = defaultdict(set)
    for uid, uname in users.items():
        for rid in user_roles.get(uid, []):
            for sid in role_admin_access.get(rid, []):
                user_admin_systems[uname].add(sid)

    expected_summary = []
    for uname, sids in user_admin_systems.items():
        if len(sids) > 0:
            expected_summary.append((uname, len(sids)))

    # Sort descending by count, then alphabetically by username
    expected_summary.sort(key=lambda x: (-x[1], x[0]))
    expected_lines = [f"{uname}:{count}" for uname, count in expected_summary]

    with open(result_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Expected admin summary:\n{expected_lines}\nBut got:\n{actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
