#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import stat
import subprocess
import sys
import uuid

import pytest


def test_app_worker_service_dependency_fixed():
    """Verify that app_worker.service has the correct After dependency."""
    service_file = "/home/user/services/app_worker.service"
    assert os.path.exists(service_file), f"Service file {service_file} is missing."

    config = configparser.ConfigParser()
    config.read(service_file)

    assert config.has_section("Unit"), f"Missing [Unit] section in {service_file}."
    assert config.has_option("Unit", "After"), f"Missing 'After' directive in {service_file}."

    after_value = config.get("Unit", "After")
    assert after_value == "auth_server.service", f"Expected After=auth_server.service, got After={after_value}"


def test_startup_success_log():
    """Verify that the startup log exists and indicates success."""
    log_file = "/home/user/startup_success.log"
    assert os.path.exists(log_file), f"Log file {log_file} was not generated."

    with open(log_file, "r") as f:
        content = f.read()

    assert "All services started successfully." in content, "The startup log does not indicate successful startup. Did the services run correctly?"


def test_sync_script_exists():
    """Verify that the sync_auth_users.py script was created."""
    script_file = "/home/user/sync_auth_users.py"
    assert os.path.exists(script_file), f"Script {script_file} was not created."
    assert stat.S_ISREG(os.stat(script_file).st_mode), f"{script_file} is not a regular file."
    assert os.path.getsize(script_file) > 0, f"{script_file} is empty."


def test_auth_db_json_content():
    """Verify that auth_db.json is correctly derived from raw_users.txt."""
    raw_file = "/home/user/raw_users.txt"
    db_file = "/home/user/auth_db.json"

    assert os.path.exists(raw_file), f"Raw users file {raw_file} is missing."
    assert os.path.exists(db_file), f"Database file {db_file} was not generated."

    expected_db = {}
    with open(raw_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) == 3:
                username, role, uid_str = parts
                try:
                    uid = int(uid_str)
                    expected_db[username] = {"role": role, "uid": uid}
                except ValueError:
                    pass

    try:
        with open(db_file, "r") as f:
            actual_db = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {db_file} does not contain valid JSON.")

    assert actual_db == expected_db, f"Content of {db_file} does not match the expected derived state from {raw_file}."


def test_services_really_start_and_generate_log():
    """Run the requested startup command from a clean state and verify its effects."""
    status_file = "/home/user/auth_status.json"
    log_file = "/home/user/startup_success.log"

    if os.path.lexists(status_file):
        os.remove(status_file)

    with open(log_file, "w") as log:
        result = subprocess.run(
            [sys.executable, "/home/user/mini_init.py", "start"],
            stdout=log,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )

    assert result.returncode == 0, f"mini_init failed to start the services: {result.stderr}"
    assert os.path.exists(status_file), "Starting the services did not initialize auth_server."
    with open(status_file, "r") as f:
        assert json.load(f) == {"status": "running"}, "auth_server did not create the expected running status."

    with open(log_file, "r") as f:
        content = f.read()
    auth_pos = content.find("Starting auth_server.service...")
    worker_pos = content.find("Starting app_worker.service...")
    assert auth_pos >= 0, "The startup log does not show auth_server.service being started."
    assert worker_pos >= 0, "The startup log does not show app_worker.service being started."
    assert auth_pos < worker_pos, "app_worker.service was not started after auth_server.service."
    assert "All services started successfully." in content, "The actual startup run did not report success."


def test_sync_script_behavior_and_idempotence_on_altered_input():
    """Execute the submitted script against unpredictable valid and malformed data."""
    script_file = "/home/user/sync_auth_users.py"
    raw_file = "/home/user/raw_users.txt"
    db_file = "/home/user/auth_db.json"

    raw_original = open(raw_file, "rb").read()
    db_existed = os.path.exists(db_file)
    db_original = open(db_file, "rb").read() if db_existed else None

    token = uuid.uuid4().hex
    user1 = "alpha_" + token
    user2 = "beta_" + token
    user3 = "gamma_" + token
    uid1 = 200000 + (uuid.uuid4().int % 100000)
    uid2 = 400000 + (uuid.uuid4().int % 100000)
    uid1_replacement = 600000 + (uuid.uuid4().int % 100000)

    altered_input = "\n".join([
        f"{user1}:admin:{uid1}",
        "missing_fields",
        f"{user2}:user:{uid2}",
        "too:few",
        "too:many:123:extra",
        "baduid:guest:not_an_integer",
        ":admin:123",
        "missingrole::124",
        f"{user1}:auditor:{uid1_replacement}",
        "",
    ])
    expected = {
        user1: {"role": "auditor", "uid": uid1_replacement},
        user2: {"role": "user", "uid": uid2},
    }

    def run_script():
        result = subprocess.run(
            [sys.executable, script_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"sync_auth_users.py failed: {result.stderr}"
        assert os.path.exists(db_file), "sync_auth_users.py did not create auth_db.json."
        try:
            with open(db_file, "r") as f:
                return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"sync_auth_users.py produced invalid JSON: {exc}")

    try:
        with open(raw_file, "w") as f:
            f.write(altered_input)
        with open(db_file, "w") as f:
            json.dump({"stale_user": {"role": "stale", "uid": -1}}, f)

        first_state = run_script()
        assert first_state == expected, "The script did not exactly synchronize altered input or safely skip malformed lines."

        second_state = run_script()
        assert second_state == expected, "Running the script a second time changed or corrupted the synchronized state."

        with open(raw_file, "w") as f:
            f.write(f"{user3}:guest:{uid1}\ninvalid:uid:value\n")
        with open(db_file, "w") as f:
            f.write("not valid json")

        recovered_state = run_script()
        assert recovered_state == {user3: {"role": "guest", "uid": uid1}}, \
            "The script did not recreate the exact database from new input when the old database was malformed."
    finally:
        with open(raw_file, "wb") as f:
            f.write(raw_original)
        if db_existed:
            with open(db_file, "wb") as f:
                f.write(db_original)
        elif os.path.lexists(db_file):
            os.remove(db_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
