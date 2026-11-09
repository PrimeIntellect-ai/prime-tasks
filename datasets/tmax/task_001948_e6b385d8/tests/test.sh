#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time

HEALTHCHECK = "/home/user/healthcheck.exp"
MONITOR = "/home/user/monitor.sh"
CTL = "/home/user/service_ctl.sh"
LOG = "/home/user/uptime.log"


def test_healthcheck_exp_exists_and_executable():
    assert os.path.isfile(HEALTHCHECK), f"Expect script {HEALTHCHECK} is missing."
    assert os.access(HEALTHCHECK, os.X_OK), f"Expect script {HEALTHCHECK} is not executable."

    with open(HEALTHCHECK, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!\s*(?:/usr/bin/expect|/usr/bin/env(?:\s+-S)?\s+expect)(?:\s|$)", first_line), \
        "healthcheck.exp must be an Expect script with an Expect shebang."
    assert re.search(r"(?m)^\s*spawn\s+(?:--\s+)?(?:\S*/)?nc(?:\s|$)", source), \
        "healthcheck.exp must spawn nc to perform the TCP login."


def test_monitor_sh_exists_and_executable():
    assert os.path.isfile(MONITOR), f"Bash script {MONITOR} is missing."
    assert os.access(MONITOR, os.X_OK), f"Bash script {MONITOR} is not executable."
    with open(MONITOR, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert re.match(r"^#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)", first_line), \
        "monitor.sh must be a Bash script."


def _auth_server(response, captured, errors, ready):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 8022))
        server.listen(1)
        server.settimeout(8)
        ready.set()
        conn, _ = server.accept()
        with conn:
            conn.settimeout(5)
            conn.sendall(b"User: ")
            user = conn.recv(1024).decode(errors="replace").strip()
            conn.sendall(b"Pass: ")
            password = conn.recv(1024).decode(errors="replace").strip()
            captured.extend([user, password])
            conn.sendall(response)
    except Exception as exc:
        errors.append(exc)
        ready.set()
    finally:
        server.close()


def _run_healthcheck_against(response):
    captured = []
    errors = []
    ready = threading.Event()
    thread = threading.Thread(
        target=_auth_server,
        args=(response, captured, errors, ready),
        daemon=True,
    )
    thread.start()
    assert ready.wait(3), "Test authentication server did not start."
    assert not errors, f"Test authentication server failed: {errors}"
    result = subprocess.run([HEALTHCHECK], capture_output=True, text=True, timeout=10)
    thread.join(3)
    assert not thread.is_alive(), "healthcheck.exp did not complete the TCP exchange."
    assert not errors, f"Test authentication server failed: {errors}"
    return result, captured


def test_healthcheck_performs_interactive_authentication():
    subprocess.run([CTL, "stop"], capture_output=True)
    time.sleep(0.3)

    result, captured = _run_healthcheck_against(b"AUTH_SUCCESS: System Healthy\n")
    assert captured == ["sre_admin", "KeepAlive42!"], \
        f"healthcheck.exp supplied incorrect credentials: {captured!r}"
    assert result.returncode == 0, \
        f"healthcheck.exp must exit 0 after AUTH_SUCCESS, got {result.returncode}."

    result, captured = _run_healthcheck_against(b"AUTH_FAILED\n")
    assert captured == ["sre_admin", "KeepAlive42!"], \
        f"healthcheck.exp supplied incorrect credentials: {captured!r}"
    assert result.returncode == 1, \
        f"healthcheck.exp must exit 1 after AUTH_FAILED, got {result.returncode}."


def test_monitor_runs_healthcheck_and_uses_its_status():
    subprocess.run([CTL, "stop"], capture_output=True)
    time.sleep(0.3)

    with tempfile.TemporaryDirectory() as tmp:
        hc_backup = os.path.join(tmp, "healthcheck.exp")
        ctl_backup = os.path.join(tmp, "service_ctl.sh")
        shutil.copy2(HEALTHCHECK, hc_backup)
        shutil.copy2(CTL, ctl_backup)
        hc_marker = os.path.join(tmp, "healthcheck_calls")
        ctl_marker = os.path.join(tmp, "ctl_calls")

        try:
            with open(HEALTHCHECK, "w") as f:
                f.write("#!/bin/bash\necho called >> " + repr(hc_marker) + "\nexit \"${HC_RESULT:-0}\"\n")
            os.chmod(HEALTHCHECK, 0o755)

            with open(CTL, "w") as f:
                f.write("#!/bin/bash\necho \"$1\" >> " + repr(ctl_marker) + "\nexit 0\n")
            os.chmod(CTL, 0o755)

            if os.path.exists(LOG):
                os.remove(LOG)

            env = os.environ.copy()
            env["HC_RESULT"] = "0"
            subprocess.run([MONITOR], capture_output=True, text=True, env=env, timeout=10)
            assert os.path.isfile(hc_marker), "monitor.sh did not run /home/user/healthcheck.exp."
            with open(LOG) as f:
                lines = f.read().splitlines()
            assert lines == ["STATUS: UP"], \
                f"A successful health check must append exactly STATUS: UP, got {lines!r}."
            if os.path.exists(ctl_marker):
                with open(ctl_marker) as f:
                    calls = f.read().splitlines()
                assert "restart" not in calls, "monitor.sh restarted after a successful health check."

            env["HC_RESULT"] = "7"
            subprocess.run([MONITOR], capture_output=True, text=True, env=env, timeout=10)
            with open(hc_marker) as f:
                assert len(f.read().splitlines()) == 2, \
                    "monitor.sh did not run healthcheck.exp on every invocation."
            with open(LOG) as f:
                lines = f.read().splitlines()
            assert lines == ["STATUS: UP", "STATUS: DOWN - RESTARTED"], \
                f"A failed health check must append exactly STATUS: DOWN - RESTARTED, got {lines!r}."
            assert os.path.isfile(ctl_marker), "monitor.sh did not invoke service_ctl.sh on failure."
            with open(ctl_marker) as f:
                calls = f.read().splitlines()
            assert "restart" in calls, "monitor.sh did not execute service_ctl.sh restart on failure."
        finally:
            shutil.copy2(hc_backup, HEALTHCHECK)
            shutil.copy2(ctl_backup, CTL)


def test_monitor_behavior():
    if os.path.exists(LOG):
        os.remove(LOG)

    subprocess.run([CTL, "start"], capture_output=True)
    time.sleep(0.5)

    subprocess.run([MONITOR], capture_output=True, timeout=15)
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    with open(LOG, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) > 0, f"Log file {LOG} is empty."
    assert lines[-1] == "STATUS: UP", \
        f"Expected last line of log to be 'STATUS: UP', got '{lines[-1]}'"

    subprocess.run([CTL, "stop"], capture_output=True)
    time.sleep(0.5)

    subprocess.run([MONITOR], capture_output=True, timeout=15)
    with open(LOG, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) > 1, f"Log file {LOG} did not get a new line appended."
    assert lines[-1] == "STATUS: DOWN - RESTARTED", \
        f"Expected last line of log to be 'STATUS: DOWN - RESTARTED', got '{lines[-1]}'"

    res_status = subprocess.run([CTL, "status"], capture_output=True, text=True)
    assert "Service is running" in res_status.stdout, \
        "Service was not successfully restarted by monitor.sh."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
