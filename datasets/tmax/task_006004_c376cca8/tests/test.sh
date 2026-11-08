#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time
import uuid

import pytest

PROVISION_SCRIPT = "/home/user/provision.sh"
HEALTH_SCRIPT = "/home/user/check_health.sh"
RAW_FILE = "/home/user/raw_settings.conf"
MOCK_APP = "/home/user/mock_app.sh"
ENV_FILE = "/home/user/service.env"
PID_FILE = "/home/user/app.pid"
LOG_FILE = "/home/user/app.log"

ORIGINAL_RAW = """# Deployment configuration for edge node 04
Timezone: Pacific/Fiji
Environment: production
Locale: en_NZ.UTF-8

# Container overrides
RestartPolicy: always
"""
ORIGINAL_MOCK = """#!/bin/bash
while true; do
    echo "HEARTBEAT - $(date)"
    sleep 1
done
"""

active_pids = []


def read_pid():
    assert os.path.isfile(PID_FILE), f"{PID_FILE} was not created."
    with open(PID_FILE) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"{PID_FILE} does not contain a valid PID."
    return int(pid_str)


def assert_running(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")


def stop_process(pid):
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.1)


def process_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    result = {}
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            result[key.decode(errors="replace")] = value.decode(errors="replace")
    return result


def assert_mock_process(pid, timezone, locale):
    assert_running(pid)

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    assert MOCK_APP in argv, f"PID {pid} is not the launched {MOCK_APP}: {argv}"

    environment = process_environment(pid)
    assert environment.get("TZ") == timezone, "TZ was not sourced and exported to the app."
    assert environment.get("LC_ALL") == locale, "LC_ALL was not sourced and exported to the app."

    log_stat = os.stat(LOG_FILE)
    for fd in (1, 2):
        fd_stat = os.stat(f"/proc/{pid}/fd/{fd}")
        assert (fd_stat.st_dev, fd_stat.st_ino) == (log_stat.st_dev, log_stat.st_ino), \
            f"File descriptor {fd} is not redirected to {LOG_FILE}."


def run_provision():
    result = subprocess.run(
        [PROVISION_SCRIPT], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, \
        f"{PROVISION_SCRIPT} did not exit cleanly. stderr: {result.stderr}"
    pid = read_pid()
    active_pids.append(pid)
    return pid


def run_health(expected):
    result = subprocess.run(
        [HEALTH_SCRIPT], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, f"{HEALTH_SCRIPT} failed to run."
    output = result.stdout.strip()
    assert output == expected, f"Expected '{expected}' but got '{output}'"


@pytest.fixture(scope="session", autouse=True)
def cleanup_and_preserve_inputs():
    with open(RAW_FILE) as f:
        assert f.read() == ORIGINAL_RAW, f"{RAW_FILE} was modified."
    with open(MOCK_APP) as f:
        assert f.read() == ORIGINAL_MOCK, f"{MOCK_APP} was modified."
    assert os.access(MOCK_APP, os.X_OK), f"{MOCK_APP} is not executable."

    yield

    for pid in active_pids:
        stop_process(pid)
    with open(RAW_FILE, "w") as f:
        f.write(ORIGINAL_RAW)
    with open(MOCK_APP, "w") as f:
        f.write(ORIGINAL_MOCK)
    os.chmod(MOCK_APP, 0o755)


def test_scripts_exist_and_executable():
    assert os.path.isfile(PROVISION_SCRIPT), f"{PROVISION_SCRIPT} does not exist."
    assert os.access(PROVISION_SCRIPT, os.X_OK), f"{PROVISION_SCRIPT} is not executable."
    assert os.path.isfile(HEALTH_SCRIPT), f"{HEALTH_SCRIPT} does not exist."
    assert os.access(HEALTH_SCRIPT, os.X_OK), f"{HEALTH_SCRIPT} is not executable."


def test_provision_script_behavior():
    pid = run_provision()

    assert os.path.isfile(ENV_FILE), f"{ENV_FILE} was not created."
    with open(ENV_FILE) as f:
        env_contents = f.read().splitlines()
    assert "TZ=Pacific/Fiji" in env_contents, f"TZ not correctly set in {ENV_FILE}"
    assert "LC_ALL=en_NZ.UTF-8" in env_contents, f"LC_ALL not correctly set in {ENV_FILE}"
    assert env_contents == ["TZ=Pacific/Fiji", "LC_ALL=en_NZ.UTF-8"], \
        f"{ENV_FILE} must contain exactly the two required lines."

    time.sleep(2)
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created."
    assert_mock_process(pid, "Pacific/Fiji", "en_NZ.UTF-8")


def test_check_health_script_healthy():
    run_health("HEALTHY")


def test_health_requires_heartbeat_on_last_line():
    pid = read_pid()
    os.kill(pid, signal.SIGSTOP)
    try:
        with open(LOG_FILE, "a") as f:
            f.write("NO_PULSE\n")
        assert_running(pid)
        run_health("UNHEALTHY")

        with open(LOG_FILE, "a") as f:
            f.write("HEARTBEAT\n")
        run_health("HEALTHY")
    finally:
        os.kill(pid, signal.SIGCONT)


def test_provision_parses_changed_configuration_and_exports_it():
    old_pid = read_pid()
    stop_process(old_pid)

    nonce = uuid.uuid4().hex
    timezone = f"TestZone/{nonce}"
    locale = f"zz_{nonce}.UTF-8"
    changed_raw = f"""# A different deployment configuration

Environment: staging
Timezone: {timezone}
# This setting must be ignored
RestartPolicy: never
Locale: {locale}

"""
    with open(RAW_FILE, "w") as f:
        f.write(changed_raw)

    for path in (ENV_FILE, PID_FILE, LOG_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    pid = run_provision()
    with open(ENV_FILE) as f:
        env_contents = f.read().splitlines()
    assert env_contents == [f"TZ={timezone}", f"LC_ALL={locale}"], \
        f"{ENV_FILE} was not generated from the current configuration."

    time.sleep(2)
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created."
    assert_mock_process(pid, timezone, locale)
    run_health("HEALTHY")


def test_check_health_script_unhealthy():
    pid = read_pid()
    stop_process(pid)
    time.sleep(1)
    run_health("UNHEALTHY")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
