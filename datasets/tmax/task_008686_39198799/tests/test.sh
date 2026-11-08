#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import stat
import subprocess
import uuid

import pytest

CSV_PATH = "/home/user/legacy_users.csv"
SCRIPT_PATH = "/home/user/migrate_pipeline.py"
ENVS = ["staging", "prod"]


@pytest.fixture(scope="session", autouse=True)
def exercise_submission():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist or is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a real file, not a symlink."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    token = uuid.uuid4().hex[:12]
    rows = [
        [f"zara_{token}", f"finance_{token}", "admin"],
        [f"alice_{token}", f"engineering_{token}", "admin"],
        [f"mike_{token}", f"engineering_{token}", "developer"],
        [f"bob_{token}", f"hr_{token}", "viewer"],
        [f"carol_{token}", f"finance_{token}", "viewer"],
        [f"dave_{token}", f"operations_{token}", "manager"],
        [f"amy_{token}", f"operations_{token}", "developer"],
    ]

    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["username", "department", "role"])
        writer.writerows(rows)

    try:
        for bad_args in (["--env"], ["--env", "invalid"], ["--env", "staging", "extra"]):
            result = subprocess.run(
                ["python3", SCRIPT_PATH, *bad_args],
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode != 0, f"Script incorrectly accepted arguments: {bad_args}"

        # Run each required command twice. Before every run, place stale content in
        # the target so successful cleanup/recreation and idempotency are required.
        for _ in range(2):
            for env in ENVS:
                base_dir = f"/home/user/cloud_deployment/{env}"
                stale_dir = os.path.join(base_dir, f"stale_department_{token}")
                stale_file = os.path.join(base_dir, f"stale_file_{token}")
                os.makedirs(stale_dir, exist_ok=True)
                with open(os.path.join(stale_dir, "old.txt"), "w") as f:
                    f.write("stale")
                with open(stale_file, "w") as f:
                    f.write("stale")

                result = subprocess.run(
                    ["python3", SCRIPT_PATH, "--env", env],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                assert result.returncode == 0, (
                    f"Script failed for --env {env}. stdout: {result.stdout!r}; "
                    f"stderr: {result.stderr!r}"
                )
                assert not os.path.exists(stale_dir), f"Stale directory was not cleared for {env}."
                assert not os.path.exists(stale_file), f"Stale file was not cleared for {env}."

        yield
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)


def get_expected_data():
    assert os.path.exists(CSV_PATH), f"{CSV_PATH} does not exist."
    users = []
    departments = set()
    roles = {}

    with open(CSV_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            users.append(row["username"])
            departments.add(row["department"])
            role = row["role"]
            if role not in roles:
                roles[role] = []
            roles[role].append(row["username"])

    for role in roles:
        roles[role].sort()

    return {
        "num_users": len(users),
        "num_departments": len(departments),
        "departments": list(departments),
        "roles": roles,
    }


def test_directories_and_files():
    data = get_expected_data()
    departments = data["departments"]

    for env in ENVS:
        base_dir = f"/home/user/cloud_deployment/{env}"
        assert os.path.isdir(base_dir), f"Base directory {base_dir} is missing."
        assert set(os.listdir(base_dir)) == set(departments) | {"rbac.json"}, (
            f"Base directory {base_dir} contains missing or unexpected entries."
        )

        for dept in departments:
            dept_dir = os.path.join(base_dir, dept)
            assert os.path.isdir(dept_dir), f"Department directory {dept_dir} is missing."

            st = os.stat(dept_dir)
            mode = stat.S_IMODE(st.st_mode)
            assert mode == 0o755, f"Permissions for {dept_dir} are {oct(mode)}, expected 0o755."

            assert set(os.listdir(dept_dir)) == {"__init__.py", "settings.conf"}, (
                f"Department directory {dept_dir} contains missing or unexpected entries."
            )
            for file_name in ["__init__.py", "settings.conf"]:
                file_path = os.path.join(dept_dir, file_name)
                assert os.path.isfile(file_path), f"File {file_path} is missing."
                st_file = os.stat(file_path)
                file_mode = stat.S_IMODE(st_file.st_mode)
                assert file_mode == 0o644, f"Permissions for {file_path} are {oct(file_mode)}, expected 0o644."
                assert st_file.st_size == 0, f"File {file_path} must be empty."


def test_rbac_json():
    data = get_expected_data()
    expected_roles = data["roles"]

    for env in ENVS:
        rbac_path = f"/home/user/cloud_deployment/{env}/rbac.json"
        assert os.path.isfile(rbac_path), f"RBAC file {rbac_path} is missing."

        with open(rbac_path, "r") as f:
            raw_content = f.read()

        try:
            rbac_data = json.loads(raw_content)
        except json.JSONDecodeError:
            pytest.fail(f"File {rbac_path} is not valid JSON.")

        assert rbac_data == expected_roles, f"Content of {rbac_path} does not match expected RBAC configuration."
        formatted = json.dumps(rbac_data, indent=4)
        assert raw_content in (formatted, formatted + "\n"), (
            f"File {rbac_path} is not pretty-printed with four-space indentation."
        )


def test_log_files():
    data = get_expected_data()
    num_users = data["num_users"]
    num_depts = data["num_departments"]

    for env in ENVS:
        log_path = f"/home/user/migration_summary_{env}.log"
        assert os.path.isfile(log_path), f"Log file {log_path} is missing."

        expected_log = f"[{env}] Deployment ready. Migrated {num_users} users across {num_depts} departments."

        with open(log_path, "r") as f:
            raw_log = f.read()

        log_content = raw_log.strip()
        assert log_content == expected_log, f"Log content in {log_path} is incorrect. Expected: '{expected_log}', Got: '{log_content}'"
        assert raw_log in (expected_log, expected_log + "\n"), (
            f"Log file {log_path} must contain exactly one line and no extra whitespace."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
