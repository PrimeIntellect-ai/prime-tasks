#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess

def test_analyze_script_exists_and_executable():
    """Verify that /home/user/analyze.sh exists and is executable."""
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

def test_sampled_tokens_content():
    """Verify the contents of /home/user/logs/sampled_tokens.txt."""
    output_path = "/home/user/logs/sampled_tokens.txt"
    assert os.path.isfile(output_path), f"{output_path} does not exist. Did you run the script?"

    with open(output_path, "r") as f:
        actual_lines = f.read().splitlines()

    expected_lines = [
        "brown",
        "over",
        "dog",
        "database",
        "retrying",
        "login",
        "forty"
    ]

    assert actual_lines == expected_lines, f"Contents of {output_path} do not match the expected sampled tokens."

def test_cron_job_configured():
    """Verify that the cron job is configured for the user."""
    try:
        # Check the crontab for the 'user' (assuming tests run as root or user)
        # We can just run `crontab -l` if running as user, or `crontab -u user -l`
        result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
        if result.returncode != 0:
            # Fallback if running as user
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)

        assert result.returncode == 0, "Failed to read crontab. Is it set up?"

        crontab_content = result.stdout

        # Look for a line that starts with * * * * * and contains analyze.sh
        cron_found = False
        for line in crontab_content.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 6:
                schedule = " ".join(parts[:5])
                command = " ".join(parts[5:])
                if schedule == "* * * * *" and "analyze.sh" in command:
                    cron_found = True
                    break

        assert cron_found, "Cron job for analyze.sh running every minute (* * * * *) was not found."
    except FileNotFoundError:
        assert False, "crontab command not found."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
