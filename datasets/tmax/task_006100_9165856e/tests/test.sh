#!/bin/bash
mkdir -p /logs/verifier

run_verify() {
cat << 'TEST_EOF' > /tmp/test_final_state.py || return 1
import os
import json
import csv
import secrets
import subprocess
import pytest

DATA_DIR = '/home/user/audit_data'
OUTPUT = '/home/user/sod_violations.json'
BINARY = '/tmp/audit_submission'
DATA_FILES = [
    'users.csv',
    'roles.csv',
    'user_roles.csv',
    'role_hierarchy.csv',
    'role_permissions.csv',
]

def get_expected_violations():
    users = {}
    with open('/home/user/audit_data/users.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[row['user_id']] = row['user_name']

    user_roles = {}
    with open('/home/user/audit_data/user_roles.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_roles.setdefault(row['user_id'], set()).add(row['role_id'])

    role_hierarchy = {}
    with open('/home/user/audit_data/role_hierarchy.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            role_hierarchy.setdefault(row['parent_role_id'], set()).add(row['child_role_id'])

    role_permissions = {}
    with open('/home/user/audit_data/role_permissions.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            role_permissions.setdefault(row['role_id'], set()).add(row['permission_name'])

    def get_all_inherited_roles(role_id, visited=None):
        if visited is None:
            visited = set()
        if role_id in visited:
            return visited
        visited.add(role_id)
        for child in role_hierarchy.get(role_id, set()):
            get_all_inherited_roles(child, visited)
        return visited

    violations = []
    for user_id in sorted(users.keys()):
        roles = user_roles.get(user_id, set())
        all_roles = set()
        for r in roles:
            all_roles.update(get_all_inherited_roles(r))

        perms = set()
        for r in all_roles:
            perms.update(role_permissions.get(r, set()))

        if 'FUNDS_INITIATE' in perms and 'FUNDS_APPROVE' in perms:
            violations.append({
                "user_id": user_id,
                "user_name": users[user_id],
                "violation": True
            })

    return violations

def write_csv(name, fields, rows):
    with open(os.path.join(DATA_DIR, name), 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

def test_go_program_exists():
    assert os.path.isfile("/home/user/audit.go"), "The Go program /home/user/audit.go was not found."

def test_json_output_exists():
    assert os.path.isfile("/home/user/sod_violations.json"), "The output file /home/user/sod_violations.json was not found."

def test_json_output_correctness():
    expected = get_expected_violations()

    with open("/home/user/sod_violations.json", "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/sod_violations.json is not valid JSON.")

    assert isinstance(actual, list), "The JSON output must be a list of objects."

    # Sort both just in case, though the spec requires actual to be sorted
    expected_sorted = sorted(expected, key=lambda x: x.get('user_id', ''))
    actual_sorted = sorted(actual, key=lambda x: x.get('user_id', ''))

    assert actual == expected_sorted, f"The JSON output does not match the expected violations. Expected: {expected_sorted}, Actual: {actual}"

def test_json_output_sorted():
    with open("/home/user/sod_violations.json", "r") as f:
        actual = json.load(f)

    user_ids = [obj.get('user_id') for obj in actual]
    assert user_ids == sorted(user_ids), "The JSON output is not sorted by user_id in ascending order."

def test_z_program_processes_randomized_csv_data():
    backups = {}
    for name in DATA_FILES:
        with open(os.path.join(DATA_DIR, name), 'rb') as f:
            backups[name] = f.read()
    with open(OUTPUT, 'rb') as f:
        output_backup = f.read()

    token = secrets.token_hex(6).upper()
    users = [
        (f'U4{token}', 'Random Direct User'),
        (f'U1{token}', 'Random Transitive User'),
        (f'U3{token}', 'Random Approval User'),
        (f'U2{token}', 'Random Initiation User'),
    ]
    roles = {name: f'R{i}{token}' for i, name in enumerate(
        ['top', 'middle', 'initiate', 'approve', 'unrelated'], start=1
    )}

    try:
        write_csv('users.csv', ['user_id', 'user_name'], [
            {'user_id': uid, 'user_name': name} for uid, name in reversed(users)
        ])
        write_csv('roles.csv', ['role_id', 'role_name'], [
            {'role_id': rid, 'role_name': name.title()}
            for name, rid in roles.items()
        ])
        write_csv('user_roles.csv', ['user_id', 'role_id'], [
            {'user_id': users[0][0], 'role_id': roles['initiate']},
            {'user_id': users[0][0], 'role_id': roles['approve']},
            {'user_id': users[1][0], 'role_id': roles['top']},
            {'user_id': users[2][0], 'role_id': roles['approve']},
            {'user_id': users[3][0], 'role_id': roles['middle']},
        ])
        write_csv('role_hierarchy.csv', ['parent_role_id', 'child_role_id'], [
            {'parent_role_id': roles['top'], 'child_role_id': roles['middle']},
            {'parent_role_id': roles['middle'], 'child_role_id': roles['initiate']},
            {'parent_role_id': roles['top'], 'child_role_id': roles['approve']},
        ])
        write_csv('role_permissions.csv', ['role_id', 'permission_name'], [
            {'role_id': roles['initiate'], 'permission_name': 'FUNDS_INITIATE'},
            {'role_id': roles['approve'], 'permission_name': 'FUNDS_APPROVE'},
            {'role_id': roles['unrelated'], 'permission_name': 'VIEW_BALANCE'},
        ])

        expected = get_expected_violations()
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        subprocess.run([BINARY], cwd='/home/user', check=True, timeout=30)
        assert os.path.isfile(OUTPUT), 'The executed Go program did not create sod_violations.json.'
        with open(OUTPUT, 'r') as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail('The executed Go program produced invalid JSON for randomized input.')
        assert actual == expected, f'Program failed randomized hierarchy and permission projection test. Expected: {expected}, Actual: {actual}'
    finally:
        for name, content in backups.items():
            with open(os.path.join(DATA_DIR, name), 'wb') as f:
                f.write(content)
        with open(OUTPUT, 'wb') as f:
            f.write(output_backup)
TEST_EOF

    go build -o /tmp/audit_submission /home/user/audit.go || return 1
    rm -f /home/user/sod_violations.json || return 1
    (cd /home/user && /tmp/audit_submission) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
}

if run_verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
