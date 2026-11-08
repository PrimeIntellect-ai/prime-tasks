#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

RESOLUTION_FILE = "/home/user/ticket_resolution.txt"

def test_resolution_file_exists():
    """Verify that the ticket_resolution.txt file exists."""
    assert os.path.exists(RESOLUTION_FILE), f"Missing resolution file: {RESOLUTION_FILE}"
    assert os.path.isfile(RESOLUTION_FILE), f"Not a file: {RESOLUTION_FILE}"

def test_resolution_file_contents():
    """Verify the contents, configured directory, environment assignment, and repaired script."""
    assert os.path.exists(RESOLUTION_FILE), f"Missing resolution file: {RESOLUTION_FILE}"

    with open(RESOLUTION_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {RESOLUTION_FILE}, found {len(lines)}"

    # Check Token
    assert lines[0] == "TOKEN: AUTH_SEC_x92bF81mP_99xyz", f"Incorrect TOKEN line: {lines[0]}"

    # Check Crash String
    assert lines[1] == "CRASH_STRING: xzblk", f"Incorrect CRASH_STRING line: {lines[1]}"

    # Check Config Dir
    assert lines[2].startswith("CONFIG_DIR: "), f"Line 3 does not start with 'CONFIG_DIR: ': {lines[2]}"

    config_dir = lines[2].split("CONFIG_DIR: ")[1].strip()
    assert os.path.isabs(config_dir), f"CONFIG_DIR must be an absolute path, got: {config_dir}"

    # Verify settings.ini exists in the specified config dir
    settings_file = os.path.join(config_dir, "settings.ini")
    assert os.path.exists(settings_file), f"Expected settings.ini not found at {settings_file}"
    assert os.path.isfile(settings_file), f"Not a file: {settings_file}"

    # Load standard persistent environment configuration, verify CONFIG_PATH
    # names the reported directory, and exercise the repaired script.
    shell_script = r'''
unset CONFIG_PATH
set -a
[ ! -r /etc/environment ] || source /etc/environment
set +a
[ ! -r /etc/profile ] || source /etc/profile
for startup_file in /home/user/.profile /home/user/.bash_profile /home/user/.bash_login /home/user/.bashrc; do
    [ ! -r "$startup_file" ] || source "$startup_file"
done
if [ "${CONFIG_PATH+x}" != x ]; then
    echo "CONFIG_PATH is not assigned" >&2
    exit 20
fi
if [ "$CONFIG_PATH" != "$EXPECTED_CONFIG_DIR" ]; then
    echo "CONFIG_PATH '$CONFIG_PATH' does not match reported directory '$EXPECTED_CONFIG_DIR'" >&2
    exit 21
fi
cd /home/user
exec /usr/bin/python3 /home/user/process_config.py hello
'''
    env = os.environ.copy()
    env.pop("CONFIG_PATH", None)
    env["EXPECTED_CONFIG_DIR"] = config_dir
    env["HOME"] = "/home/user"

    result = subprocess.run(
        ["/bin/bash", "--noprofile", "--norc", "-ic", shell_script],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        "The repaired environment did not run process_config.py successfully. "
        f"exit={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert "Processed hello successfully." in result.stdout, (
        f"Unexpected process_config.py output: {result.stdout!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
