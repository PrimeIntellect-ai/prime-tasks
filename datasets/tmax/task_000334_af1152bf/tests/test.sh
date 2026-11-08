#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess

CONFIG_PATH = "/home/user/app_restore/config.ini"
JSON_PATH = "/home/user/restore_status.json"
DATA_DIR = "/home/user/app_restore/data/"

ORIGINAL_CONFIG = """[General]
AppName=BackupTester
Version=1.0.4

[Security]
AllowAutomatedRestore=false
StrictKeys=yes

[Locale]
Timezone=America/New_York
Language=en_US
"""

EXPECTED_CONFIG = """[General]
AppName=BackupTester
Version=1.0.4

[Security]
AllowAutomatedRestore=true
StrictKeys=yes

[Locale]
Timezone=UTC
Language=en_US
"""


def read_config():
    assert os.path.isfile(CONFIG_PATH), f"File {CONFIG_PATH} does not exist."
    with open(CONFIG_PATH, "r") as f:
        return f.read()


def read_and_validate_json():
    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        data = json.load(f)

    assert isinstance(data, dict), "restore_status.json must contain a JSON object."
    assert set(data) == {"status", "data_size_bytes", "timezone"}, \
        "restore_status.json must contain exactly the specified schema fields."
    assert data["status"] == "ready", f"Expected status 'ready', got {data['status']!r}."
    assert data["timezone"] == "UTC", f"Expected timezone 'UTC', got {data['timezone']!r}."
    assert type(data["data_size_bytes"]) is int, "'data_size_bytes' must be an integer."
    return data


def expected_data_size():
    cmd = f"du -sb {DATA_DIR} | awk '{{print $1}}'"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
    return int(result.stdout.strip())


def validate_outputs():
    content = read_config()
    assert "AllowAutomatedRestore=true" in content, "config.ini missing 'AllowAutomatedRestore=true'."
    assert "Timezone=UTC" in content, "config.ini missing 'Timezone=UTC'."
    assert "AllowAutomatedRestore=false" not in content, "config.ini still contains 'AllowAutomatedRestore=false'."
    assert "Timezone=America/New_York" not in content, "config.ini still contains 'Timezone=America/New_York'."
    assert content == EXPECTED_CONFIG, "config.ini did not preserve all other original lines exactly."

    data = read_and_validate_json()
    expected_size = expected_data_size()
    assert data["data_size_bytes"] == expected_size, \
        f"Expected data_size_bytes {expected_size}, got {data['data_size_bytes']}."


def script_command(path):
    if path.endswith((".sh", ".bash")):
        return ["bash", path]
    if path.endswith(".py"):
        return ["python3", path]
    if os.access(path, os.X_OK):
        return [path]
    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    if first_line.startswith("#!"):
        import shlex
        return shlex.split(first_line[2:]) + [path]
    raise AssertionError(f"Cannot determine how to execute script {path}.")


def test_initial_final_state():
    validate_outputs()


def test_saved_script_executes_and_recreates_outputs():
    candidates = sorted(
        path for path in glob.glob("/home/user/fix_restore*")
        if os.path.isfile(path) and not os.path.islink(path)
    )
    assert candidates, "No /home/user/fix_restore script exists."

    errors = []
    for path in candidates:
        challenge_path = os.path.join(DATA_DIR, f".verifier_challenge_{secrets.token_hex(12)}")
        try:
            with open(CONFIG_PATH, "w") as f:
                f.write(ORIGINAL_CONFIG)
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)

            challenge_size = 4097 + secrets.randbelow(8192)
            with open(challenge_path, "wb") as f:
                f.write(os.urandom(challenge_size))

            command = script_command(path)
            result = subprocess.run(
                ["runuser", "-u", "user", "--"] + command,
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, \
                f"Script exited with {result.returncode}: {result.stderr}"
            validate_outputs()
            return
        except Exception as exc:
            errors.append(f"{path}: {exc}")
        finally:
            if os.path.exists(challenge_path):
                os.remove(challenge_path)

    raise AssertionError("No saved fix_restore script successfully recreated the required state:\n" + "\n".join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
