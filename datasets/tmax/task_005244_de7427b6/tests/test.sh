#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import string
import random
import re
import urllib.request
import pytest

def test_nginx_config_restored():
    config_path = "/etc/nginx/sites-available/default"
    backup_path = "/var/backups/nginx/default.bak"

    assert os.path.exists(config_path), f"NGINX config missing at {config_path}"
    assert os.path.exists(backup_path), f"NGINX backup missing at {backup_path}"

    with open(config_path, "r") as f:
        config_content = f.read()
    with open(backup_path, "r") as f:
        backup_content = f.read()

    assert config_content == backup_content, "NGINX config does not match the backup file."

def test_nginx_running():
    result = subprocess.run(["systemctl", "is-active", "nginx"], capture_output=True, text=True)
    assert result.stdout.strip() == "active", "NGINX service is not active."

def test_mail_receiver_running_and_healthy():
    result = subprocess.run(["systemctl", "is-active", "mail-receiver"], capture_output=True, text=True)
    assert result.stdout.strip() == "active", "mail-receiver service is not active."

    try:
        req = urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=2)
        assert req.getcode() == 200, f"Expected 200 OK, got {req.getcode()}"
    except Exception as e:
        pytest.fail(f"Failed to connect to mail-receiver at port 8080: {e}")

def test_cron_job_configured():
    result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
    crontab_output = result.stdout.strip()
    expected_cmd = "cp /var/log/mail-receiver.log /home/user/backups/mail-receiver.log.bak"

    found = False
    for line in crontab_output.splitlines():
        if line.startswith("0 0 * * *") and expected_cmd in line:
            found = True
            break

    assert found, f"Expected cron job not found in user's crontab. Current crontab:\n{crontab_output}"

def test_email_filter_fuzz_equivalence():
    agent_script = "/home/user/email_filter.py"

    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script at {agent_script} is not executable"

    random.seed(42)
    charset = string.ascii_letters + string.digits + " -" + "!@#$%^&*()_+={}|[]\\:\";'<>?,./"

    for _ in range(1000):
        length = random.randint(1, 256)
        test_input = "".join(random.choice(charset) for _ in range(length))
        expected_output = re.sub(r'[^a-zA-Z0-9 \-]', '', test_input)

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=test_input,
            capture_output=True,
            text=True
        )
        agent_output = agent_proc.stdout

        assert agent_output == expected_output, (
            f"Mismatch found!\n"
            f"Input: {repr(test_input)}\n"
            f"Expected: {repr(expected_output)}\n"
            f"Got (agent): {repr(agent_output)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
