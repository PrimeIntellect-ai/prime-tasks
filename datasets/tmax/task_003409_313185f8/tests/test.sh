#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import time
import pytest

CONF_PATH = "/home/user/supervisor/supervisord.conf"
EXPECT_SCRIPT = "/home/user/setup_netmon.exp"
SETTINGS_PATH = "/home/user/service/conf/settings.json"
LOG_PATH = "/home/user/service/logs/status.log"


def supervisorctl(*args, timeout=15):
    return subprocess.run(
        ["supervisorctl", "-c", CONF_PATH, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


def test_directories_and_symlinks():
    real_conf = "/home/user/real_conf"
    real_logs = "/home/user/real_logs"
    sym_conf = "/home/user/service/conf"
    sym_logs = "/home/user/service/logs"

    assert os.path.isdir(real_conf), f"{real_conf} is missing or not a directory"
    assert os.path.isdir(real_logs), f"{real_logs} is missing or not a directory"

    assert os.path.islink(sym_conf), f"{sym_conf} is not a symlink"
    assert os.readlink(sym_conf) == real_conf, f"{sym_conf} does not point to {real_conf}"

    assert os.path.islink(sym_logs), f"{sym_logs} is not a symlink"
    assert os.readlink(sym_logs) == real_logs, f"{sym_logs} does not point to {real_logs}"


def test_expect_script_exists_and_performs_setup():
    assert os.path.isfile(EXPECT_SCRIPT), f"{EXPECT_SCRIPT} is missing"

    # Remove any pre-fabricated configuration, then require the submitted Expect
    # artifact to recreate it by running the interactive setup as the task user.
    if os.path.lexists(SETTINGS_PATH):
        os.unlink(SETTINGS_PATH)

    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "expect", EXPECT_SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{EXPECT_SCRIPT} did not complete the interactive setup")

    assert result.returncode == 0, (
        f"{EXPECT_SCRIPT} failed with exit code {result.returncode}:\n{result.stdout}"
    )
    assert os.path.isfile(SETTINGS_PATH), (
        f"{EXPECT_SCRIPT} did not generate {SETTINGS_PATH}"
    )


def test_settings_json():
    assert os.path.isfile(SETTINGS_PATH), f"{SETTINGS_PATH} is missing"

    with open(SETTINGS_PATH, "r") as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SETTINGS_PATH} is not valid JSON")

    assert settings.get("configured") is True, "settings.json does not have 'configured': true"
    assert settings.get("user") == "sysadmin", "settings.json does not have correct user"
    assert settings.get("group") == "netops", "settings.json does not have correct group"


def test_supervisord_conf():
    assert os.path.isfile(CONF_PATH), f"{CONF_PATH} is missing"

    with open(CONF_PATH, "r") as f:
        content = f.read()

    # Preserve the original configuration assertion.
    assert "command=python3 /home/user/service/netmon.py --serve" in content or \
           "command = python3 /home/user/service/netmon.py --serve" in content, \
           "supervisord.conf does not contain the correct command for netmon"


def test_processes_running_and_managed_by_supervisor():
    # Preserve the original process assertions.
    proc_supervisord = subprocess.run(["pgrep", "-f", "supervisord"], stdout=subprocess.PIPE)
    assert proc_supervisord.returncode == 0, "supervisord is not running"

    proc_netmon = subprocess.run(["pgrep", "-f", "netmon.py --serve"], stdout=subprocess.PIPE)
    assert proc_netmon.returncode == 0, "netmon.py --serve is not running"

    # Query the supervisor instance through the configured control socket.
    status = supervisorctl("status", "netmon")
    assert status.returncode == 0, f"cannot query netmon through supervisorctl:\n{status.stdout}"
    fields = status.stdout.split()
    assert len(fields) >= 2 and fields[0] == "netmon" and fields[1] == "RUNNING", \
        f"netmon is not in supervisor RUNNING state:\n{status.stdout}"

    child_result = supervisorctl("pid", "netmon")
    assert child_result.returncode == 0 and child_result.stdout.strip().isdigit(), \
        f"supervisor did not report a netmon PID:\n{child_result.stdout}"
    child_pid = int(child_result.stdout.strip())
    assert child_pid > 1 and os.path.isdir(f"/proc/{child_pid}"), "reported netmon PID is not alive"

    with open("/home/user/supervisor/supervisord.pid", "r") as f:
        supervisor_pid_text = f.read().strip()
    assert supervisor_pid_text.isdigit(), "supervisord.pid does not contain a PID"
    supervisor_pid = int(supervisor_pid_text)
    assert os.path.isdir(f"/proc/{supervisor_pid}"), "configured supervisord PID is not alive"

    with open(f"/proc/{child_pid}/status", "r") as f:
        child_status = f.read().splitlines()
    ppid_line = next((line for line in child_status if line.startswith("PPid:")), None)
    assert ppid_line is not None and int(ppid_line.split()[1]) == supervisor_pid, \
        "netmon is not a child managed by the configured supervisord"

    with open(f"/proc/{child_pid}/cmdline", "rb") as f:
        child_cmd = [x.decode() for x in f.read().split(b"\0") if x]
    assert child_cmd[-2:] == ["/home/user/service/netmon.py", "--serve"], \
        f"supervisor's netmon process has the wrong command: {child_cmd}"
    assert os.path.basename(child_cmd[0]).startswith("python3"), \
        f"netmon is not being run with python3: {child_cmd}"

    with open(f"/proc/{supervisor_pid}/cmdline", "rb") as f:
        supervisor_cmd = [x.decode() for x in f.read().split(b"\0") if x]
    assert any("supervisord" in os.path.basename(x) for x in supervisor_cmd), \
        f"PID file does not identify supervisord: {supervisor_cmd}"
    assert CONF_PATH in supervisor_cmd, \
        f"supervisord was not started with {CONF_PATH}: {supervisor_cmd}"

    # Prove that this supervisor can launch netmon and that netmon itself creates
    # a fresh status log, rather than accepting a stale fabricated file.
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)
    restarted = supervisorctl("restart", "netmon", timeout=20)
    assert restarted.returncode == 0, f"supervisor could not restart netmon:\n{restarted.stdout}"

    deadline = time.time() + 10
    while time.time() < deadline:
        current = supervisorctl("status", "netmon")
        if current.returncode == 0 and "RUNNING" in current.stdout and os.path.isfile(LOG_PATH):
            break
        time.sleep(0.2)
    else:
        pytest.fail("supervisor did not return netmon to RUNNING state with a fresh status log")

    with open(LOG_PATH, "r") as f:
        assert f.read().strip() == "SERVICE_ONLINE", "fresh netmon status log is incorrect"


def test_logs_and_success_file():
    success_path = "/home/user/success.txt"

    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is missing"
    with open(LOG_PATH, "r") as f:
        log_content = f.read().strip()
    assert "SERVICE_ONLINE" in log_content, f"{LOG_PATH} does not contain 'SERVICE_ONLINE'"

    assert os.path.isfile(success_path), f"{success_path} is missing"
    with open(success_path, "r") as f:
        success_content = f.read().strip()
    assert success_content == "SERVICE_ONLINE", f"{success_path} does not contain exactly 'SERVICE_ONLINE'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
