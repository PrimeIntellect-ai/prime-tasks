#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import ssl
import subprocess
import time
import urllib.request
import pytest

APP_DIR = "/home/user/app"
SUPERVISOR_SCRIPT = os.path.join(APP_DIR, "supervisor.sh")
DEPLOY_CHECK_SCRIPT = os.path.join(APP_DIR, "deploy_check.py")
DIAGNOSTIC_JSON = os.path.join(APP_DIR, "diagnostic.json")
RESTARTS_LOG = os.path.join(APP_DIR, "restarts.log")
HEALTH_URL = "https://127.0.0.1:8443/health"
CRASH_URL = "https://127.0.0.1:8443/crash"
TLS_CONTEXT = ssl._create_unverified_context()


def server_pids():
    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if not args or not os.path.basename(args[0]).startswith("python"):
                continue
            has_server_arg = any(
                arg == "/home/user/app/server.py" or os.path.basename(arg) == "server.py"
                for arg in args[1:]
            )
            if not has_server_arg:
                continue
            if "/home/user/app/server.py" not in args:
                cwd = os.path.realpath(f"/proc/{entry}/cwd")
                if cwd != APP_DIR:
                    continue
            found.add(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            pass
    return found


def wait_for_health(timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(HEALTH_URL, context=TLS_CONTEXT, timeout=1) as response:
                body = response.read()
                if response.status == 200 and body == b"OK":
                    return response.status
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"HTTPS health endpoint did not become ready: {last_error}")


def wait_for_new_server(old_pid, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        candidates = server_pids() - {old_pid}
        if candidates:
            try:
                wait_for_health(1)
                return next(iter(candidates))
            except BaseException:
                pass
        time.sleep(0.05)
    pytest.fail(f"server.py was not restarted after PID {old_pid} exited")


def read_log():
    assert os.path.exists(RESTARTS_LOG), f"{RESTARTS_LOG} was not created by the supervisor script."
    with open(RESTARTS_LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def validate_log(lines):
    assert lines, f"{RESTARTS_LOG} is empty, expected at least one restart timestamp."
    for line in lines:
        assert re.fullmatch(r"[0-9]{10,}", line), f"Invalid UNIX timestamp found in restarts.log: '{line}'"


def test_scripts_exist_and_executable():
    assert os.path.exists(SUPERVISOR_SCRIPT), f"{SUPERVISOR_SCRIPT} does not exist."
    assert os.path.isfile(SUPERVISOR_SCRIPT), f"{SUPERVISOR_SCRIPT} is not a regular file."
    assert os.access(SUPERVISOR_SCRIPT, os.X_OK), f"{SUPERVISOR_SCRIPT} is not executable."
    assert os.path.exists(DEPLOY_CHECK_SCRIPT), f"{DEPLOY_CHECK_SCRIPT} does not exist."
    assert os.path.isfile(DEPLOY_CHECK_SCRIPT), f"{DEPLOY_CHECK_SCRIPT} is not a regular file."
    assert os.access(DEPLOY_CHECK_SCRIPT, os.X_OK), f"{DEPLOY_CHECK_SCRIPT} is not executable."


def test_execution_and_output():
    subprocess.run(["pkill", "-f", "supervisor.sh"], capture_output=True)
    subprocess.run(["pkill", "-f", "server.py"], capture_output=True)
    time.sleep(0.2)

    for path in (DIAGNOSTIC_JSON, RESTARTS_LOG):
        if os.path.exists(path):
            os.remove(path)

    supervisor_proc = subprocess.Popen(
        [SUPERVISOR_SCRIPT],
        cwd=APP_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid,
    )

    try:
        assert wait_for_health() == 200
        assert supervisor_proc.poll() is None, "supervisor.sh exited instead of running continuously."
        initial = server_pids()
        assert initial, "supervisor.sh did not start server.py with python3."
        initial_pid = next(iter(initial))

        deploy_started = time.time()
        check_proc = subprocess.run(
            ["python3", DEPLOY_CHECK_SCRIPT],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=15,
        )
        deploy_finished = time.time()
        assert check_proc.returncode == 0, (
            f"deploy_check.py failed with return code {check_proc.returncode}. "
            f"Stderr: {check_proc.stderr}"
        )
        assert deploy_finished - deploy_started >= 1.8, "deploy_check.py did not perform the required recovery wait."

        assert initial_pid not in server_pids(), "deploy_check.py did not cause the running server.py process to crash."
        after_deploy_pid = wait_for_new_server(initial_pid)
        assert wait_for_health() == 200
        assert supervisor_proc.poll() is None, "supervisor.sh exited after the server crash."

        assert os.path.exists(DIAGNOSTIC_JSON), f"{DIAGNOSTIC_JSON} was not created by deploy_check.py."
        with open(DIAGNOSTIC_JSON, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"{DIAGNOSTIC_JSON} does not contain valid JSON.")
        assert data.get("check1") == 200, f"Expected 'check1' to be 200, got {data.get('check1')}."
        assert data.get("check2") == 200, f"Expected 'check2' to be 200, got {data.get('check2')}."

        lines_after_deploy = read_log()
        validate_log(lines_after_deploy)
        assert any(deploy_started - 2 <= int(line) <= deploy_finished + 2 for line in lines_after_deploy), (
            "No restart timestamp corresponds to the crash during deploy_check.py."
        )

        # Independently exercise the real HTTPS crash endpoint and verify that the
        # submitted supervisor performs another restart, rather than trusting JSON.
        independent_crash_time = time.time()
        try:
            urllib.request.urlopen(CRASH_URL, context=TLS_CONTEXT, timeout=2).read()
        except Exception:
            pass
        else:
            pytest.fail("The HTTPS /crash endpoint unexpectedly returned a normal response.")

        new_pid = wait_for_new_server(after_deploy_pid)
        assert new_pid != after_deploy_pid
        assert wait_for_health() == 200
        assert supervisor_proc.poll() is None, "supervisor.sh did not remain running after an independent crash."

        deadline = time.time() + 3
        final_lines = read_log()
        while len(final_lines) <= len(lines_after_deploy) and time.time() < deadline:
            time.sleep(0.05)
            final_lines = read_log()
        validate_log(final_lines)
        assert len(final_lines) > len(lines_after_deploy), "The independent server crash was not logged as a restart."
        assert any(independent_crash_time - 2 <= int(line) <= time.time() + 2 for line in final_lines[len(lines_after_deploy):]), (
            "The independent restart was not logged with a current UNIX timestamp."
        )
    finally:
        try:
            os.killpg(os.getpgid(supervisor_proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        subprocess.run(["pkill", "-f", "supervisor.sh"], capture_output=True)
        subprocess.run(["pkill", "-f", "server.py"], capture_output=True)
        try:
            supervisor_proc.wait(timeout=1)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
