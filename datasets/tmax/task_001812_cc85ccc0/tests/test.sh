#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import sys

EXPECTED_SERVICE = '''#!/usr/bin/env python3
import os
import json
import time

def run_service():
    # 1. Check symlink structure
    data_dir = '/home/user/app/data'
    if not os.path.islink(data_dir):
        print("CRITICAL: Data directory is not a symlink")
        exit(1)
    if os.readlink(data_dir) != '/home/user/data_mount/active':
        print("CRITICAL: Data directory symlink destination incorrect")
        exit(1)

    # 2. Check Timezone
    if os.environ.get('TZ') != 'UTC':
        print("CRITICAL: Service must run with TZ=UTC")
        exit(1)

    # 3. Check container lifecycle config
    try:
        with open('/home/user/config/containers.json', 'r') as f:
            config = json.load(f)
            if config.get('ingest-worker', {}).get('status') != 'running':
                print("CRITICAL: Container ingest-worker is not running")
                exit(1)
    except FileNotFoundError:
        print("CRITICAL: /home/user/config/containers.json missing")
        exit(1)

    # Success
    with open('/home/user/app/success.log', 'w') as f:
        f.write("SERVICE_STARTED_SUCCESSFULLY")
    print("Service started successfully.")

if __name__ == '__main__':
    run_service()
'''

def test_service_execution_with_utc():
    """Execute the required service with TZ=UTC and require it to regenerate the log."""
    script_path = '/home/user/app/ingest.py'
    log_path = '/home/user/app/success.log'

    assert os.path.isfile(script_path), f"CRITICAL: Service script {script_path} does not exist."
    assert not os.path.islink(script_path), f"CRITICAL: Service script {script_path} must be a regular file, not a symlink."

    with open(script_path, 'r') as f:
        assert f.read() == EXPECTED_SERVICE, f"CRITICAL: Service script {script_path} was modified."

    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env['TZ'] = 'UTC'
    result = subprocess.run(
        [sys.executable, script_path],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"CRITICAL: Service failed when executed with TZ=UTC. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(log_path), "CRITICAL: Service execution did not generate success.log."

def test_symlink_structure():
    """Check if the symlink /home/user/app/data exists and points to /home/user/data_mount/active."""
    link_path = '/home/user/app/data'
    target_path = '/home/user/data_mount/active'

    assert os.path.islink(link_path), f"CRITICAL: {link_path} is not a symlink or does not exist."
    assert os.readlink(link_path) == target_path, f"CRITICAL: Symlink {link_path} does not point to {target_path}."
    assert os.path.isdir(target_path), f"CRITICAL: Target directory {target_path} does not exist."

def test_config_file():
    """Check if /home/user/config/containers.json exists and contains the correct JSON structure."""
    config_path = '/home/user/config/containers.json'

    assert os.path.isfile(config_path), f"CRITICAL: Configuration file {config_path} does not exist."

    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, f"CRITICAL: {config_path} does not contain valid JSON."

    assert "ingest-worker" in config, f"CRITICAL: Key 'ingest-worker' missing in {config_path}."
    assert isinstance(config["ingest-worker"], dict), f"CRITICAL: 'ingest-worker' is not a JSON object."
    assert config["ingest-worker"].get("status") == "running", f"CRITICAL: 'ingest-worker' status is not 'running'."

def test_success_log():
    """Check if /home/user/app/success.log exists and contains the exact string 'SERVICE_STARTED_SUCCESSFULLY'."""
    log_path = '/home/user/app/success.log'

    assert os.path.isfile(log_path), f"CRITICAL: Success log {log_path} does not exist. The service may not have run successfully."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content == "SERVICE_STARTED_SUCCESSFULLY", f"CRITICAL: {log_path} content is incorrect. Expected 'SERVICE_STARTED_SUCCESSFULLY', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
