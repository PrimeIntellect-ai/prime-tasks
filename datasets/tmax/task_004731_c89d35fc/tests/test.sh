#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import stat
import subprocess
import shutil
import uuid
import pytest


def test_monitor_profile_exists_and_correct():
    profile_path = "/home/user/.monitor_profile"
    assert os.path.isfile(profile_path), f"File {profile_path} does not exist."

    with open(profile_path, "r") as f:
        content = f.read()

    # Check for LOG_DIR
    assert re.search(r'(export\s+LOG_DIR=|LOG_DIR=.*?export\s+LOG_DIR)', content) is not None, "LOG_DIR is not properly exported."
    assert "LOG_DIR=/home/user/service_logs" in content or "LOG_DIR=\"/home/user/service_logs\"" in content or "LOG_DIR='/home/user/service_logs'" in content, "LOG_DIR is not set to /home/user/service_logs."

    # Check for ALERT_THRESHOLD
    assert re.search(r'(export\s+ALERT_THRESHOLD=|ALERT_THRESHOLD=.*?export\s+ALERT_THRESHOLD)', content) is not None, "ALERT_THRESHOLD is not properly exported."
    assert "ALERT_THRESHOLD=10" in content or "ALERT_THRESHOLD=\"10\"" in content or "ALERT_THRESHOLD='10'" in content, "ALERT_THRESHOLD is not set to 10."


def test_alert_pipeline_script_executable():
    script_path = "/home/user/monitor_repo/alert_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_active_alerts_log_correct():
    log_path = "/home/user/active_alerts.log"
    assert os.path.isfile(log_path), f"Alerts log {log_path} does not exist. Did you run the script?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ALERT: db failure rate at 20%",
        "ALERT: web failure rate at 15%"
    ]

    assert lines == expected_lines, f"Expected alerts to be exactly {expected_lines}, but got {lines}. Ensure alphabetical sorting and correct threshold/calculation."


def test_git_repo_and_pre_commit_hook():
    git_dir = "/home/user/monitor_repo/.git"
    assert os.path.isdir(git_dir), "Git repository was not initialized in /home/user/monitor_repo."

    hook_path = os.path.join(git_dir, "hooks", "pre-commit")
    assert os.path.isfile(hook_path), f"Pre-commit hook {hook_path} does not exist."

    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pre-commit hook {hook_path} is not executable."

    with open(hook_path, "r") as f:
        content = f.read()

    assert "bash -n" in content or "bash --noexec" in content, "Pre-commit hook does not seem to contain 'bash -n' or equivalent syntax check."

    script_path = "/home/user/monitor_repo/alert_pipeline.sh"
    with open(script_path, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(script_path).st_mode)

    try:
        with open(script_path, "w") as f:
            f.write("#!/bin/bash\nexit 0\n")
        os.chmod(script_path, original_mode)
        valid = subprocess.run(
            [hook_path],
            cwd="/home/user/monitor_repo",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert valid.returncode == 0, f"Pre-commit hook returned {valid.returncode} for a syntactically valid alert_pipeline.sh."

        nonce = uuid.uuid4().hex
        with open(script_path, "w") as f:
            f.write(f"#!/bin/bash\nif then # {nonce}\n  echo broken\nfi\n")
        os.chmod(script_path, original_mode)
        invalid = subprocess.run(
            [hook_path],
            cwd="/home/user/monitor_repo",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert invalid.returncode == 1, f"Pre-commit hook must exit 1 for invalid Bash syntax, but returned {invalid.returncode}."
    finally:
        with open(script_path, "wb") as f:
            f.write(original_script)
        os.chmod(script_path, original_mode)


def test_alert_pipeline_executes_on_changed_logs():
    script_path = "/home/user/monitor_repo/alert_pipeline.sh"
    log_dir = "/home/user/service_logs"
    alerts_path = "/home/user/active_alerts.log"
    backup_dir = f"/home/user/service_logs.verifier-backup-{uuid.uuid4().hex}"

    alerts_existed = os.path.exists(alerts_path)
    original_alerts = None
    original_alerts_mode = None
    if alerts_existed:
        with open(alerts_path, "rb") as f:
            original_alerts = f.read()
        original_alerts_mode = stat.S_IMODE(os.stat(alerts_path).st_mode)

    suffix = uuid.uuid4().hex[:8]
    fixtures = {
        f"zeta_{suffix}": ["[INFO] ok"] * 7 + ["[ERROR] failed", "[TIMEOUT] dropped"],
        f"alpha_{suffix}": ["[INFO] ok"] * 9 + ["[ERROR] failed"],
        f"middle_{suffix}": ["[INFO] ok"] * 10 + ["[ERROR] failed"],
        f"quiet_{suffix}": ["[INFO] ok"] * 10 + ["[WARNING] ERROR without exact marker"],
    }

    def expected_alerts(data):
        result = []
        for service, lines in data.items():
            failures = sum(1 for line in lines if "[ERROR]" in line or "[TIMEOUT]" in line)
            rate = (failures * 100) // len(lines)
            if rate >= 10:
                result.append(f"ALERT: {service} failure rate at {rate}%")
        return sorted(result, key=lambda line: line.split()[1])

    os.rename(log_dir, backup_dir)
    os.makedirs(log_dir)
    try:
        # Deliberately create services in non-alphabetical order.
        for service in reversed(list(fixtures.keys())):
            service_dir = os.path.join(log_dir, service)
            os.makedirs(service_dir)
            with open(os.path.join(service_dir, "app.log"), "w") as f:
                f.write("\n".join(fixtures[service]) + "\n")

        with open(alerts_path, "w") as f:
            f.write("ALERT: stale_service failure rate at 99%\n")

        completed = subprocess.run(
            [script_path],
            cwd="/home/user/monitor_repo",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert completed.returncode == 0, f"alert_pipeline.sh failed with code {completed.returncode}: {completed.stderr}"
        assert os.path.isfile(alerts_path), "Executing alert_pipeline.sh did not create /home/user/active_alerts.log."

        with open(alerts_path, "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        expected = expected_alerts(fixtures)
        assert actual == expected, f"On changed service logs, expected {expected}, but got {actual}."
    finally:
        if os.path.isdir(log_dir):
            shutil.rmtree(log_dir)
        os.rename(backup_dir, log_dir)
        if alerts_existed:
            with open(alerts_path, "wb") as f:
                f.write(original_alerts)
            os.chmod(alerts_path, original_alerts_mode)
        elif os.path.exists(alerts_path):
            os.remove(alerts_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
