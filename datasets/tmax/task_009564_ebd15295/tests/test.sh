#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import pytest

CONFIG_PATH = "/home/user/monitor_config.json"
BACKUP_PATH = "/home/user/monitor_config.json.bak"
SCRIPT_PATH = "/home/user/update_config.py"

ORIGINAL = {
    "global_timeout": 30,
    "endpoints": [
        {
            "name": "db_service",
            "url": "http://localhost:5432/ping"
        }
    ]
}

EXPECTED_UPDATED = {
    "global_timeout": 30,
    "endpoints": [
        {
            "name": "db_service",
            "url": "http://localhost:5432/ping"
        },
        {
            "name": "cache_service",
            "url": "http://localhost:8081/health"
        }
    ]
}

def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")

def run_script():
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} failed with error: {result.stderr}"

def load_json(path):
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")

def assert_four_space_indentation(path):
    with open(path, "r") as f:
        raw = f.read()
    data = json.loads(raw)
    expected_text = json.dumps(data, indent=4)
    assert raw.rstrip("\n") == expected_text, f"{path} was not written using four-space JSON indentation."

def test_script_exists():
    """Test that the update_config.py script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

def test_backup_exists_and_correct():
    """Test that the backup file exists and contains the original configuration."""
    assert os.path.exists(BACKUP_PATH), f"Backup file {BACKUP_PATH} does not exist."
    data = load_json(BACKUP_PATH)
    assert data == ORIGINAL, f"Backup file {BACKUP_PATH} does not match the original configuration."

def test_config_updated_correctly():
    """Test that the configuration file was updated correctly."""
    assert os.path.exists(CONFIG_PATH), f"Configuration file {CONFIG_PATH} does not exist."
    data = load_json(CONFIG_PATH)
    assert data == EXPECTED_UPDATED, f"Configuration file {CONFIG_PATH} does not contain the expected updated state."

def test_script_performs_transformation_and_preserves_backup():
    """Restore inputs and exercise creation, formatting, and backup non-overwrite behavior."""
    write_json(CONFIG_PATH, ORIGINAL)
    if os.path.exists(BACKUP_PATH):
        os.remove(BACKUP_PATH)

    run_script()

    assert os.path.isfile(BACKUP_PATH), "The script did not create the backup."
    assert load_json(BACKUP_PATH) == ORIGINAL, "The newly created backup does not contain the original configuration."
    assert load_json(CONFIG_PATH) == EXPECTED_UPDATED, "The script did not transform the original configuration correctly."
    assert_four_space_indentation(CONFIG_PATH)

    with open(BACKUP_PATH, "rb") as f:
        preserved_backup = f.read()

    changed_input = {
        "global_timeout": 45,
        "endpoints": [
            {
                "name": "db_service",
                "url": "http://localhost:5432/ping"
            },
            {
                "name": "other_service",
                "url": "http://localhost:9090/health"
            }
        ]
    }
    changed_expected = {
        "global_timeout": 45,
        "endpoints": [
            {
                "name": "db_service",
                "url": "http://localhost:5432/ping"
            },
            {
                "name": "other_service",
                "url": "http://localhost:9090/health"
            },
            {
                "name": "cache_service",
                "url": "http://localhost:8081/health"
            }
        ]
    }
    write_json(CONFIG_PATH, changed_input)
    run_script()

    with open(BACKUP_PATH, "rb") as f:
        assert f.read() == preserved_backup, "The script overwrote an existing backup."
    assert load_json(CONFIG_PATH) == changed_expected, "The script did not correctly update a changed configuration."
    assert_four_space_indentation(CONFIG_PATH)

    write_json(CONFIG_PATH, ORIGINAL)
    run_script()
    with open(BACKUP_PATH, "rb") as f:
        assert f.read() == preserved_backup, "The script overwrote the preserved backup on a later run."
    assert load_json(CONFIG_PATH) == EXPECTED_UPDATED
    assert_four_space_indentation(CONFIG_PATH)

def test_idempotency():
    """Test that running the script again does not duplicate the endpoint."""
    run_script()
    data = load_json(CONFIG_PATH)
    endpoints = data.get("endpoints", [])
    cache_endpoints = [ep for ep in endpoints if ep.get("name") == "cache_service"]
    assert len(cache_endpoints) == 1, "The script is not idempotent: 'cache_service' was added multiple times."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
