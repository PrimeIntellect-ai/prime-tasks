#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import signal
import subprocess
import tempfile
import time

import pytest

APP_DIR = "/home/user/app"
MONITOR_GO = os.path.join(APP_DIR, "monitor.go")
DEPLOY_SH = os.path.join(APP_DIR, "deploy.sh")
BIN_DIR = os.path.join(APP_DIR, "bin")
MONITOR_BIN = os.path.join(BIN_DIR, "monitor")
PID_FILE = os.path.join(APP_DIR, "monitor.pid")
MAIL_SPOOL = os.path.join(APP_DIR, "mail_spool")
TARGET_STATUS = os.path.join(APP_DIR, "target_status.txt")
ALERT_EML = os.path.join(MAIL_SPOOL, "alert.eml")
USER = pwd.getpwnam("user")
EXPECTED_EMAIL = (
    "To: admin@local\n"
    "From: monitor@local\n"
    "Subject: Service Critical\n"
    "\n"
    "The monitored service reported a CRITICAL state."
)


def user_pids():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.stat(os.path.join("/proc", entry)).st_uid == USER.pw_uid:
                result.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def kill_user_processes(except_pid=None):
    for pid in user_pids():
        if pid == except_pid:
            continue
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def wait_for(predicate, timeout=3.0, interval=0.05):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


@pytest.fixture(scope="session", autouse=True)
def clean_deploy_and_build_check():
    assert os.path.isfile(MONITOR_GO) and not os.path.islink(MONITOR_GO), "monitor.go missing or not a regular file."
    assert os.path.isfile(DEPLOY_SH) and not os.path.islink(DEPLOY_SH), "deploy.sh missing or not a regular file."
    assert os.access(DEPLOY_SH, os.X_OK), "deploy.sh is not executable."

    # Remove every pre-existing user process and all deploy-generated state, then
    # require deploy.sh itself to recreate and start the service.
    kill_user_processes()
    for path in (BIN_DIR, MAIL_SPOOL):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    for path in (PID_FILE, TARGET_STATUS):
        if os.path.lexists(path):
            os.unlink(path)

    env = os.environ.copy()
    env.update({"HOME": USER.pw_dir, "USER": "user", "LOGNAME": "user"})
    result = subprocess.run(
        ["setpriv", f"--reuid={USER.pw_uid}", f"--regid={USER.pw_gid}", "--init-groups", DEPLOY_SH],
        cwd=APP_DIR,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"
    assert os.path.isdir(BIN_DIR), "deploy.sh did not create bin."
    assert os.path.isdir(MAIL_SPOOL), "deploy.sh did not create mail_spool."
    assert os.path.isfile(TARGET_STATUS), "deploy.sh did not initialize target_status.txt."
    with open(TARGET_STATUS) as f:
        assert f.read().strip() == "OK", "deploy.sh did not initialize target_status.txt to OK."
    assert os.path.isfile(MONITOR_BIN) and os.access(MONITOR_BIN, os.X_OK), "Compiled monitor executable missing."

    # Require a real Go executable and verify that it is the deterministic build
    # of the submitted monitor.go, rather than an unrelated helper artifact.
    go_info = subprocess.run(["go", "version", "-m", MONITOR_BIN], capture_output=True, text=True)
    assert go_info.returncode == 0, "bin/monitor is not a Go executable."
    fd, expected_bin = tempfile.mkstemp(prefix="expected-monitor-", dir="/tmp")
    os.close(fd)
    os.unlink(expected_bin)
    build = subprocess.run(
        ["setpriv", f"--reuid={USER.pw_uid}", f"--regid={USER.pw_gid}", "--init-groups",
         "go", "build", "-o", expected_bin, MONITOR_GO],
        cwd=APP_DIR,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"monitor.go does not compile: {build.stderr}"
    assert open(MONITOR_BIN, "rb").read() == open(expected_bin, "rb").read(), \
        "deploy.sh did not install the executable built from monitor.go."
    os.unlink(expected_bin)

    assert os.path.isfile(PID_FILE), "deploy.sh did not create monitor.pid."
    with open(PID_FILE) as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), "PID file does not contain a valid PID."
    pid = int(pid_text)
    os.kill(pid, 0)
    assert os.stat(f"/proc/{pid}").st_uid == USER.pw_uid, "Monitor is not running as user."
    assert os.path.samefile(f"/proc/{pid}/exe", MONITOR_BIN), "PID does not refer to bin/monitor."

    # A deploy-created helper must not be able to impersonate the monitor during
    # the behavioral tests; retain only the process named by monitor.pid.
    kill_user_processes(except_pid=pid)
    os.kill(pid, 0)
    yield
    kill_user_processes()


def test_monitor_running():
    """Verify that the PID file exists and the monitor process is running."""
    assert os.path.exists(PID_FILE), "PID file missing."
    with open(PID_FILE, "r") as f:
        pid = f.read().strip()
    assert pid.isdigit(), "PID file does not contain a valid PID."
    try:
        os.kill(int(pid), 0)
    except OSError:
        pytest.fail(f"Monitor process {pid} is not running.")


def test_mail_spool_acls():
    """Verify the default POSIX ACLs on the mail_spool directory."""
    assert os.path.isdir(MAIL_SPOOL), "mail_spool directory missing."
    result = subprocess.run(["getfacl", MAIL_SPOOL], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run getfacl."
    output = result.stdout
    assert "default:user::rw-" in output, "Incorrect default user ACL on mail_spool."
    assert "default:group::r--" in output, "Incorrect default group ACL on mail_spool."
    assert "default:other::---" in output, "Incorrect default other ACL on mail_spool."


def test_noncritical_status_is_ignored():
    """A dynamically chosen non-trigger value must remain untouched and send no mail."""
    if os.path.exists(ALERT_EML):
        os.remove(ALERT_EML)
    value = "HEALTHY-" + secrets.token_hex(12)
    with open(TARGET_STATUS, "w") as f:
        f.write(value)
    time.sleep(1.5)
    with open(TARGET_STATUS) as f:
        assert f.read() == value, "Monitor modified a non-CRITICAL status."
    assert not os.path.exists(ALERT_EML), "Monitor generated an alert for a non-CRITICAL status."


def test_monitor_behavior_and_duplicate_prevention():
    """Verify whitespace handling, acknowledgement, exact mail, and no duplicate alert."""
    assert os.path.exists(TARGET_STATUS), "target_status.txt missing."
    if os.path.exists(ALERT_EML):
        os.remove(ALERT_EML)

    whitespace = [" ", "\t", "\n", "\r\n"]
    trigger = secrets.choice(whitespace) + "CRITICAL" + secrets.choice(whitespace)
    with open(TARGET_STATUS, "w") as f:
        f.write(trigger)

    assert wait_for(lambda: os.path.exists(ALERT_EML), timeout=3.0), "alert.eml was not generated."
    assert wait_for(lambda: open(TARGET_STATUS).read().strip() == "OK", timeout=1.0), \
        "target_status.txt was not reset to OK."

    with open(TARGET_STATUS, "r") as f:
        status = f.read().strip()
    assert status == "OK", f"target_status.txt was not reset to OK. Current: '{status}'"
    assert os.path.exists(ALERT_EML), "alert.eml was not generated."
    with open(ALERT_EML, "r") as f:
        actual_email = f.read()
    assert actual_email.strip() == EXPECTED_EMAIL.strip(), "Email content mismatch."

    first_stat = os.stat(ALERT_EML)
    first_bytes = open(ALERT_EML, "rb").read()
    time.sleep(1.5)
    second_stat = os.stat(ALERT_EML)
    assert second_stat.st_mtime_ns == first_stat.st_mtime_ns, "Alert was rewritten after acknowledgement."
    assert open(ALERT_EML, "rb").read() == first_bytes, "Alert changed after acknowledgement."

    with open(TARGET_STATUS) as f:
        assert f.read().strip() == "OK", "Acknowledged status did not remain OK."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
