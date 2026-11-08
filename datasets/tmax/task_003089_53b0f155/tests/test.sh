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
set +e
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

cleanup() {
    if [ -f /tmp/verifier_legacy_auth_original ]; then
        cp -f /tmp/verifier_legacy_auth_original /app/legacy_auth 2>/dev/null
        chmod 755 /app/legacy_auth 2>/dev/null
    fi
    if [ ! -f /logs/verifier/reward.txt ]; then
        echo "0" > /logs/verifier/reward.txt
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pty
import random
import re
import select
import shutil
import signal
import socket
import stat
import string
import subprocess
import time

import requests

FACADE = "/home/user/auth_facade.py"
START_SCRIPT = "/home/user/start_services.sh"
PID_FILE = "/home/user/service.pid"
LEGACY = "/app/legacy_auth"
ORIGINAL = "/tmp/verifier_legacy_auth_original"
RULES = "/tmp/verifier_auth_rules.json"
CALL_LOG = "/tmp/verifier_auth_calls.jsonl"


def random_token(prefix, length=18):
    alphabet = string.ascii_letters + string.digits
    return prefix + "".join(random.SystemRandom().choice(alphabet) for _ in range(length))


DYNAMIC_USER = random_token("verify_user_")
DYNAMIC_PASSWORD = random_token("verify_pass_")
INVALID_PAIRS = [
    (DYNAMIC_USER, random_token("bad_")),
    (random_token("unknown_"), DYNAMIC_PASSWORD),
    (random_token("other_"), random_token("wrong_")),
]


def install_instrumented_legacy_auth():
    assert os.path.isfile(LEGACY), f"Missing required legacy authenticator: {LEGACY}"
    assert os.access(LEGACY, os.X_OK), f"Legacy authenticator is not executable: {LEGACY}"
    shutil.copy2(LEGACY, ORIGINAL)
    os.chmod(ORIGINAL, 0o755)
    with open(RULES, "w") as f:
        json.dump({"user": DYNAMIC_USER, "password": DYNAMIC_PASSWORD}, f)
    open(CALL_LOG, "w").close()

    wrapper = r'''#!/usr/bin/env python3
import json
import os
import sys

RULES = "/tmp/verifier_auth_rules.json"
LOG = "/tmp/verifier_auth_calls.jsonl"
ORIGINAL = "/tmp/verifier_legacy_auth_original"

with open(LOG, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")

with open(RULES) as f:
    rule = json.load(f)

if len(sys.argv) == 3 and sys.argv[1] == rule["user"] and sys.argv[2] == rule["password"]:
    print("AUTH_SUCCESS")
    raise SystemExit(0)

os.execv(ORIGINAL, [ORIGINAL] + sys.argv[1:])
'''
    temporary = LEGACY + ".verifier_tmp"
    with open(temporary, "w") as f:
        f.write(wrapper)
    os.chmod(temporary, 0o755)
    os.replace(temporary, LEGACY)


install_instrumented_legacy_auth()


def listening_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_owners(port):
    inodes = listening_inodes(port)
    owners = set()
    if not inodes:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def ppid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, ValueError):
        pass
    return 0


def descends_from(pid, roots):
    seen = set()
    while pid > 0 and pid not in seen:
        if pid in roots:
            return True
        seen.add(pid)
        pid = ppid(pid)
    return False


def terminate_existing_listeners():
    victims = listener_owners(2222) | listener_owners(8080)
    ancestry = set()
    current = os.getpid()
    while current > 0 and current not in ancestry:
        ancestry.add(current)
        current = ppid(current)
    assert not (victims & ancestry), "Refusing to terminate the verifier process tree"
    assert all(pid > 1 for pid in victims), "A required port is unexpectedly owned by PID 1"

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and (listener_owners(2222) or listener_owners(8080)):
        time.sleep(0.1)
    for pid in listener_owners(2222) | listener_owners(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if not listener_owners(2222) and not listener_owners(8080):
            return
        time.sleep(0.1)
    assert False, "Existing services did not stop cleanly for lifecycle testing"


def wait_for_services(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_owners(2222) and listener_owners(8080):
            try:
                response = requests.get("http://127.0.0.1:8080/health", timeout=1)
                if response.status_code == 200:
                    return
            except requests.exceptions.RequestException:
                pass
        time.sleep(0.2)
    assert False, "Services did not start listening on ports 2222 and 8080"


def run_ssh_with_password(user, password, port=2222):
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("ssh", [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "PubkeyAuthentication=no",
            "-o", "PreferredAuthentications=password",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "ConnectTimeout=5",
            "-p", str(port),
            f"{user}@127.0.0.1",
        ])

    output = b""
    password_sent = False
    deadline = time.time() + 12
    status = None
    try:
        while time.time() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    data = b""
                if data:
                    output += data
                    if b"password:" in output.lower() and not password_sent:
                        os.write(fd, password.encode() + b"\n")
                        password_sent = True
            waited, candidate = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                status = candidate
                break
        if status is None:
            os.kill(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
            output += b"\n[ssh client timed out]"
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
    exit_code = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else (status >> 8)
    return exit_code, output.decode(errors="ignore")


def read_auth_calls():
    calls = []
    with open(CALL_LOG) as f:
        for line in f:
            if line.strip():
                calls.append(json.loads(line))
    return calls


def test_artifacts_and_lifecycle():
    for path in (FACADE, START_SCRIPT):
        info = os.stat(path)
        assert stat.S_ISREG(info.st_mode), f"Expected a regular file at {path}"
        assert info.st_size > 0, f"Expected a non-empty file at {path}"

    with open(START_SCRIPT, "rb") as f:
        assert f.read(2) == b"#!", "start_services.sh must be a shell script with a shebang"

    terminate_existing_listeners()
    try:
        os.unlink(PID_FILE)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["bash", START_SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"start_services.sh failed: {result.stdout}\n{result.stderr}"
    wait_for_services()

    assert os.path.isfile(PID_FILE), "start_services.sh did not create /home/user/service.pid"
    with open(PID_FILE) as f:
        contents = f.read()
    pids = {int(value) for value in re.findall(r"\b\d+\b", contents)}
    assert pids, "service.pid did not contain any service PIDs"
    for pid in pids:
        assert pid > 1 and os.path.isdir(f"/proc/{pid}"), f"service.pid contains non-running PID {pid}"

    facade_processes = []
    for pid in pids:
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="ignore")
        except OSError:
            cmdline = ""
        if "auth_facade.py" in cmdline:
            facade_processes.append(pid)
    assert facade_processes, "The recorded service PIDs do not execute /home/user/auth_facade.py"

    for port in (2222, 8080):
        owners = listener_owners(port)
        assert owners, f"No process owns listening port {port}"
        assert any(descends_from(owner, pids) for owner in owners), \
            f"Port {port} is not managed by a PID recorded in service.pid"


def test_http_health_check():
    try:
        response = requests.get("http://127.0.0.1:8080/health", timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to HTTP API on port 8080: {e}"
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.text.strip() == "OK", f"Expected body 'OK', got '{response.text}'"


def test_ssh_pubkey_auth_fails():
    key_path = "/tmp/verifier_client_key"
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key_path], check=True)
    result = subprocess.run([
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "PasswordAuthentication=no",
        "-o", "PreferredAuthentications=publickey",
        "-o", "IdentitiesOnly=yes",
        "-o", f"IdentityFile={key_path}",
        "-o", "ConnectTimeout=5",
        "-p", "2222",
        "sysadmin@127.0.0.1",
    ], capture_output=True, text=True, timeout=10)
    assert result.returncode != 0, "Public key authentication should have failed, but it succeeded."
    assert "Permission denied" in result.stderr or "Connection closed" in result.stderr, \
        f"Expected permission denied or connection closed for pubkey auth, got: {result.stderr}"


def test_ssh_wrong_password_fails():
    exit_code, output = run_ssh_with_password("sysadmin", "wrongpass")
    assert exit_code != 0, "Authentication with wrong password should have failed."
    assert "Welcome sysadmin" not in output, "Should not see welcome message with wrong password."


def test_ssh_correct_password_succeeds():
    exit_code, output = run_ssh_with_password("sysadmin", "legacy_p4ss")
    assert "Welcome sysadmin" in output, f"Expected 'Welcome sysadmin' in output, got: {output}"


def test_ssh_authentication_is_driven_by_legacy_binary():
    exit_code, output = run_ssh_with_password(DYNAMIC_USER, DYNAMIC_PASSWORD)
    assert f"Welcome {DYNAMIC_USER}" in output, \
        f"Credential accepted by the instrumented legacy binary was rejected: {output}"

    for username, password in INVALID_PAIRS:
        exit_code, output = run_ssh_with_password(username, password)
        assert exit_code != 0, f"Invalid credentials unexpectedly succeeded for {username}"
        assert f"Welcome {username}" not in output, f"Invalid credentials received a welcome message: {output}"

    calls = read_auth_calls()
    assert [DYNAMIC_USER, DYNAMIC_PASSWORD] in calls, \
        "The facade did not invoke /app/legacy_auth with the dynamically valid credentials"
    for username, password in INVALID_PAIRS:
        assert [username, password] in calls, \
            f"The facade did not invoke /app/legacy_auth for invalid credentials belonging to {username}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
