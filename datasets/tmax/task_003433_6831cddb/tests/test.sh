#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import signal
import socket
import subprocess
import time
import uuid

import pytest
import requests

APP = "/app/edgetelem-1.2.0"
BINARY = APP + "/edgetelem"
SCRIPT = "/home/user/edge_deploy.sh"
BASE_URL = "http://127.0.0.1:8080"
deploy_proc = None


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def kill_existing_deploy_scripts():
    me = os.getpid()
    ancestors = {me}
    p = me
    while True:
        try:
            with open(f"/proc/{p}/stat") as f:
                p = int(f.read().split()[3])
        except Exception:
            break
        if p <= 1 or p in ancestors:
            break
        ancestors.add(p)

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in ancestors:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ")
            if b"/home/user/edge_deploy.sh" in cmdline:
                os.kill(pid, signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


def listener_pid(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and local.rsplit(":", 1)[1].upper() == wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return None


def assert_pid_is_binary(pid):
    assert pid is not None, "No process owns the expected listening socket."
    try:
        assert os.path.samefile(f"/proc/{pid}/exe", BINARY), (
            f"Port is served by PID {pid}, not by the compiled edgetelem binary."
        )
    except FileNotFoundError:
        pytest.fail(f"Listening process {pid} disappeared unexpectedly.")


def wait_for_ping(url, timeout=4):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            response = requests.get(url + "/ping", timeout=0.5)
            if response.status_code == 200 and "pong" in response.text.lower():
                return response
            last = f"status={response.status_code}, body={response.text!r}"
        except requests.RequestException as exc:
            last = str(exc)
        time.sleep(0.1)
    pytest.fail(f"Service did not answer /ping correctly: {last}")


@pytest.fixture(scope="session", autouse=True)
def cleanup_processes():
    global deploy_proc
    kill_existing_deploy_scripts()
    subprocess.run(["killall", "edgetelem"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    yield
    if deploy_proc is not None and deploy_proc.poll() is None:
        try:
            os.killpg(deploy_proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    subprocess.run(["killall", "edgetelem"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_script_exists():
    assert os.path.isfile(SCRIPT), "Deployment script /home/user/edge_deploy.sh not found."


def test_binary_compiled_from_repaired_source():
    assert os.path.isfile(BINARY), "Compiled binary /app/edgetelem-1.2.0/edgetelem not found."
    assert os.access(BINARY, os.X_OK), "edgetelem is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "edgetelem is not a compiled ELF executable."

    # A pre-existing substitute must not turn into the real binary only because
    # the verifier rebuilt it. A normal make build is reproducible here.
    submitted_hash = sha256(BINARY)
    result = subprocess.run(["make", "clean"], cwd=APP, text=True, capture_output=True)
    assert result.returncode == 0, f"make clean failed:\n{result.stdout}\n{result.stderr}"
    result = subprocess.run(["make"], cwd=APP, text=True, capture_output=True)
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "make did not produce executable edgetelem."
    assert sha256(BINARY) == submitted_hash, "The submitted executable was not the binary produced by make from the submitted source."

    # Independently compile server.c with the package's strict flags and require
    # the installed artifact to be that program, rather than another server.
    reference = "/tmp/edgetelem-reference"
    result = subprocess.run(
        ["gcc", "-Wall", "-Werror=implicit-function-declaration", "-o", reference, "server.c"],
        cwd=APP, text=True, capture_output=True
    )
    assert result.returncode == 0, f"server.c does not compile under the required strict flags:\n{result.stdout}\n{result.stderr}"
    assert sha256(reference) == sha256(BINARY), "edgetelem is not compiled from the repaired server.c with the package build flags."


def test_binary_honors_environment_and_logs_dynamic_input():
    # Any old differently-named server would survive killall; reject that rather
    # than accidentally testing it.
    assert listener_pid(8080) is None, "Port 8080 is still occupied after stopping edgetelem; an unrelated server is masking the binary."

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]

    out_file = f"/tmp/telemetry-{uuid.uuid4().hex}.log"
    env = os.environ.copy()
    env["TELEM_PORT"] = str(port)
    env["TELEM_OUT"] = out_file
    proc = subprocess.Popen([BINARY], cwd=APP, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_ping(f"http://127.0.0.1:{port}")
        assert proc.poll() is None, "The compiled edgetelem process exited; another process answered the request."
        assert listener_pid(port) == proc.pid, "The compiled binary is not the process listening on TELEM_PORT."
        assert_pid_is_binary(proc.pid)

        nonce = uuid.uuid4().hex
        payload = '{"sensor":"temp","nonce":"' + nonce + '"}\n'
        response = requests.post(f"http://127.0.0.1:{port}/submit", data=payload, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK for /submit, got {response.status_code}"
        deadline = time.time() + 1
        while time.time() < deadline and (not os.path.exists(out_file) or nonce not in open(out_file).read()):
            time.sleep(0.05)
        assert os.path.isfile(out_file), "The compiled binary did not create TELEM_OUT."
        with open(out_file) as f:
            assert nonce in f.read(), "The compiled binary did not log the submitted dynamic payload."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_service_integration_and_real_watchdog_restart():
    global deploy_proc
    os.makedirs("/home/user/data", exist_ok=True)
    os.makedirs("/home/user/backups", exist_ok=True)
    for path in glob.glob("/home/user/backups/telemetry-*.bak"):
        os.remove(path)
    try:
        os.remove("/home/user/data/telemetry.log")
    except FileNotFoundError:
        pass

    deploy_proc = subprocess.Popen(
        ["bash", SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    response = wait_for_ping(BASE_URL)
    assert response.status_code == 200
    assert "pong" in response.text.lower()
    assert deploy_proc.poll() is None, "edge_deploy.sh is not running continuously."

    serving_pid = listener_pid(8080)
    assert_pid_is_binary(serving_pid)

    nonce = uuid.uuid4().hex
    payload = '{"sensor": "temp", "value": 22.5, "nonce": "' + nonce + '"}\n'
    for _ in range(5):
        response = requests.post(
            BASE_URL + "/submit", data=payload,
            headers={"Content-Type": "application/json"}, timeout=2
        )
        assert response.status_code == 200, f"Expected 200 OK for /submit, got {response.status_code}"

    time.sleep(3)
    backups = glob.glob("/home/user/backups/telemetry-*.bak")
    assert backups, "No backup files found in /home/user/backups/ after exceeding 100 bytes."
    assert all(re.fullmatch(r"telemetry-[0-9]+\.bak", os.path.basename(p)) for p in backups), "Backup filename does not contain a Unix epoch timestamp."

    found_payload = False
    for backup in backups:
        with open(backup) as f:
            content = f.read()
        if "sensor" in content and "temp" in content and nonce in content:
            found_payload = True
            break
    assert found_payload, "Backup file was created but does not contain the submitted telemetry data."

    old_pid = listener_pid(8080)
    assert_pid_is_binary(old_pid)
    subprocess.run(["killall", "edgetelem"], check=False)

    time.sleep(4)
    new_pid = listener_pid(8080)
    assert new_pid is not None, "Watchdog did not restore a listener after killall edgetelem."
    assert new_pid != old_pid, "killall edgetelem did not kill and replace the serving process."
    assert_pid_is_binary(new_pid)
    response = requests.get(BASE_URL + "/ping", timeout=2)
    assert response.status_code == 200, f"Service did not recover after being killed. Expected 200 OK, got {response.status_code}"
    assert "pong" in response.text.lower(), "Service recovered but returned unexpected response to /ping."
    assert deploy_proc.poll() is None, "edge_deploy.sh stopped instead of continuing as a watchdog."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
