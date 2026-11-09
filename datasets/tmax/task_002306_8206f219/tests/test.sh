#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/health_monitor.py"
LOG_PATH = "/home/user/logs/health.json"
APP_DATA_DIR = "/home/user/app_data"
EXPECTED_KEYS = {"data_size_bytes", "worker_count", "deploy_user_exists"}


def test_health_monitor_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"

    with open(SCRIPT_PATH, "r") as f:
        first_line = f.readline().strip()
    assert first_line == "#!/usr/bin/env python3", f"Script does not have correct shebang, found: {first_line}"


def test_script_runs_from_another_directory_and_generates_correct_json():
    # Add unpredictable input so a pre-fabricated health.json cannot pass.
    fixture_dir = os.path.join(APP_DATA_DIR, "verifier_" + secrets.token_hex(8), "nested")
    os.makedirs(fixture_dir)
    fixture_path = os.path.join(fixture_dir, "capacity.bin")
    with open(fixture_path, "wb") as f:
        f.write(os.urandom(4096 + secrets.randbelow(8192)))

    if os.path.lexists(LOG_PATH):
        os.remove(LOG_PATH)

    with tempfile.TemporaryDirectory(prefix="health_monitor_cwd_") as cwd:
        os.mkdir(os.path.join(cwd, "logs"))
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Script failed when executed from {cwd}: stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert not os.path.exists(os.path.join(cwd, "logs", "health.json")), (
            "Script wrote health.json relative to its working directory"
        )

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist after running script"

    with open(LOG_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {LOG_PATH} is not valid JSON: {exc}")

    assert isinstance(data, dict), "health.json must contain a single JSON object"
    assert "data_size_bytes" in data, "Missing 'data_size_bytes' in JSON"
    assert "worker_count" in data, "Missing 'worker_count' in JSON"
    assert "deploy_user_exists" in data, "Missing 'deploy_user_exists' in JSON"
    assert set(data) == EXPECTED_KEYS, f"Unexpected JSON keys: {set(data) - EXPECTED_KEYS}"

    total_size = 0
    for root, dirs, files in os.walk(APP_DATA_DIR):
        for filename in files:
            file_path = os.path.join(root, filename)
            if not os.path.islink(file_path):
                total_size += os.path.getsize(file_path)

    assert type(data["data_size_bytes"]) is int, "data_size_bytes must be an integer"
    assert data["data_size_bytes"] == total_size, (
        f"Expected data_size_bytes to be {total_size}, but got {data['data_size_bytes']}"
    )

    try:
        ps_output = subprocess.check_output(["ps", "aux"], text=True)
        worker_count = sum(
            1 for line in ps_output.strip().split("\n")
            if "background_worker.sh" in line and "grep" not in line
        )
    except subprocess.CalledProcessError:
        worker_count = 0

    assert type(data["worker_count"]) is int, "worker_count must be an integer"
    assert data["worker_count"] == worker_count, (
        f"Expected worker_count to be {worker_count}, but got {data['worker_count']}"
    )

    try:
        pwd.getpwnam("deploy_user")
        user_exists = True
    except KeyError:
        user_exists = False

    assert type(data["deploy_user_exists"]) is bool, "deploy_user_exists must be a boolean"
    assert data["deploy_user_exists"] == user_exists, (
        f"Expected deploy_user_exists to be {user_exists}, but got {data['deploy_user_exists']}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
