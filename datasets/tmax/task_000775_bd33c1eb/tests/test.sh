#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import signal
import subprocess
import tempfile
import time
import pytest

USER = "user"
USER_INFO = pwd.getpwnam(USER)
USER_ENV = [
    "env",
    "HOME=/home/user",
    "USER=user",
    "LOGNAME=user",
    f"XDG_RUNTIME_DIR=/run/user/{USER_INFO.pw_uid}",
    f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{USER_INFO.pw_uid}/bus",
]


def as_user(args, **kwargs):
    return subprocess.run(["runuser", "-u", USER, "--", *USER_ENV, *args], **kwargs)


def systemctl_user(*args):
    return as_user(["systemctl", "--user", *args], capture_output=True, text=True)


def curl(url):
    return subprocess.run(
        ["curl", "--silent", "--show-error", "--fail", "--max-time", "3", url],
        capture_output=True,
        text=True,
    )


def matching_tunnel_pids():
    res = subprocess.run(
        ["pgrep", "-f", "ssh.*-L.*8443.*4433"], capture_output=True, text=True
    )
    if res.returncode != 0:
        return []
    return [int(pid) for pid in res.stdout.split()]


def listening_inodes(port):
    wanted = f"{port:04X}"
    inodes = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[-1].upper() == wanted and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pid_socket_inodes(pid):
    result = set()
    try:
        names = os.listdir(f"/proc/{pid}/fd")
    except (FileNotFoundError, PermissionError):
        return result
    for name in names:
        try:
            target = os.readlink(f"/proc/{pid}/fd/{name}")
        except (FileNotFoundError, PermissionError):
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def is_real_required_tunnel(pid, listener_inodes):
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except (FileNotFoundError, PermissionError):
        return False

    if os.path.basename(exe) != "ssh":
        return False

    forward_specs = []
    for i, arg in enumerate(argv):
        if arg == "-L" and i + 1 < len(argv):
            forward_specs.append(argv[i + 1])
        elif arg.startswith("-L") and len(arg) > 2:
            forward_specs.append(arg[2:])

    required = re.compile(
        r"^(?:[^:]+:)?8443:(?:localhost|127\.0\.0\.1|\[::1\]):4433$"
    )
    if not any(required.fullmatch(spec) for spec in forward_specs):
        return False
    return bool(pid_socket_inodes(pid) & listener_inodes)


def test_result_log():
    log_path = "/home/user/result.log"
    assert os.path.exists(log_path), f"{log_path} does not exist"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SECURE_SERVER_OK", \
        f"Expected 'SECURE_SERVER_OK' in {log_path}, got '{content}'"


def test_server_source_has_working_null_fallback():
    source_path = "/home/user/app/server.c"
    assert os.path.isfile(source_path), f"{source_path} does not exist"
    source = open(source_path).read()
    assert re.search(r'getenv\s*\(\s*"APP_CERTS_DIR"\s*\)', source), \
        "server.c no longer reads APP_CERTS_DIR"
    assert '"/home/user/certs"' in source, \
        "server.c does not contain the required /home/user/certs fallback"

    fd, candidate = tempfile.mkstemp(prefix="server-from-source-")
    os.close(fd)
    os.unlink(candidate)
    compile_res = subprocess.run(
        ["gcc", source_path, "-o", candidate], capture_output=True, text=True, timeout=20
    )
    assert compile_res.returncode == 0, f"server.c does not compile: {compile_res.stderr}"
    os.chmod(candidate, 0o755)

    stop = systemctl_user("stop", "secure-backend.service")
    assert stop.returncode == 0, f"Could not stop service for source test: {stop.stderr}"
    proc = None
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            if curl("http://localhost:4433/status").returncode != 0:
                break
            time.sleep(0.1)
        else:
            pytest.fail("Port 4433 remained served after secure-backend.service was stopped")

        proc = subprocess.Popen(
            [
                "runuser", "-u", USER, "--", *USER_ENV,
                "env", "-u", "APP_CERTS_DIR", candidate,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        response = None
        deadline = time.time() + 5
        while time.time() < deadline:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors="replace")
                pytest.fail(f"server compiled from server.c exited with APP_CERTS_DIR unset: {stderr}")
            attempt = curl("http://localhost:4433/status")
            if attempt.returncode == 0:
                response = attempt.stdout
                break
            time.sleep(0.1)
        assert response == "SECURE_SERVER_OK", \
            f"server compiled from server.c did not work with APP_CERTS_DIR unset; got {response!r}"
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        try:
            os.unlink(candidate)
        except FileNotFoundError:
            pass
        start = systemctl_user("start", "secure-backend.service")
        assert start.returncode == 0, f"Could not restart service: {start.stderr}"


def test_server_binary():
    bin_path = "/home/user/app/server"
    assert os.path.isfile(bin_path), f"{bin_path} does not exist"
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable"
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled ELF program"


def test_service_active_and_enabled():
    unit_path = "/home/user/.config/systemd/user/secure-backend.service"
    assert os.path.isfile(unit_path), f"{unit_path} does not exist"
    unit = open(unit_path).read()
    assert re.search(r"^ExecStart=/home/user/app/server\s*$", unit, re.MULTILINE), \
        "secure-backend.service does not execute /home/user/app/server"

    active = systemctl_user("is-active", "secure-backend.service")
    assert active.stdout.strip() == "active", \
        f"secure-backend.service is not active. Output: {active.stdout.strip()} {active.stderr.strip()}"
    enabled = systemctl_user("is-enabled", "secure-backend.service")
    assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", \
        f"secure-backend.service is not enabled. Output: {enabled.stdout.strip()} {enabled.stderr.strip()}"


def test_ssh_tunnel_running_and_functional():
    pids = matching_tunnel_pids()
    assert len(pids) >= 1, "SSH tunnel process forwarding port 8443 to 4433 not found"

    listeners = listening_inodes(8443)
    assert listeners, "Nothing is listening on local port 8443"
    real_tunnels = [pid for pid in pids if is_real_required_tunnel(pid, listeners)]
    assert real_tunnels, \
        "Port 8443 is not owned by a real ssh -L tunnel forwarding to localhost:4433"

    response = curl("http://localhost:8443/status")
    assert response.returncode == 0, f"curl through port 8443 failed: {response.stderr}"
    assert response.stdout == "SECURE_SERVER_OK", \
        f"Unexpected response through SSH tunnel: {response.stdout!r}"

    with open("/home/user/result.log") as f:
        logged = f.read().strip()
    assert logged == response.stdout, "result.log does not match the live tunneled response"


def test_setup_script_idempotent():
    script_path = "/home/user/setup.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    res = as_user([script_path], capture_output=True, text=True, timeout=30)
    assert res.returncode == 0, f"setup.sh failed on execution. stderr: {res.stderr}"

    pids = matching_tunnel_pids()
    assert len(pids) == 1, \
        f"Idempotency failed: Expected exactly 1 SSH tunnel process, found {len(pids)}"

    listeners = listening_inodes(8443)
    assert is_real_required_tunnel(pids[0], listeners), \
        "The sole matching process is not the SSH listener on port 8443"
    response = curl("http://localhost:8443/status")
    assert response.returncode == 0 and response.stdout == "SECURE_SERVER_OK", \
        f"Tunnel was not functional after rerunning setup.sh: {response.stderr or response.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
