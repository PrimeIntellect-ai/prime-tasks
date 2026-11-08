#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import socket
import subprocess
import tempfile
import threading
import time

USER = pwd.getpwnam("user")
EXPECTED = b"HELO local\nMAIL FROM:<test@local>\nRCPT TO:<admin@local>\nDATA\nSTATUS: FIXED\n.\n"


def demote_to_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_as_user(argv, **kwargs):
    env = os.environ.copy()
    env.update({"HOME": USER.pw_dir, "USER": USER.pw_name, "LOGNAME": USER.pw_name})
    kwargs.setdefault("env", env)
    kwargs.setdefault("preexec_fn", demote_to_user)
    return subprocess.run(argv, **kwargs)


def user_systemctl(*args, check=True):
    runtime = f"/run/user/{USER.pw_uid}"
    env = os.environ.copy()
    env.update({
        "HOME": USER.pw_dir,
        "USER": USER.pw_name,
        "LOGNAME": USER.pw_name,
        "XDG_RUNTIME_DIR": runtime,
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={runtime}/bus",
    })
    return subprocess.run(
        ["runuser", "-u", USER.pw_name, "--", "systemctl", "--user", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=check,
    )


def capture_one(port, command):
    received = []
    ready = threading.Event()
    errors = []

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", port))
                listener.listen(1)
                listener.settimeout(8)
                ready.set()
                conn, _ = listener.accept()
                with conn:
                    conn.settimeout(3)
                    data = bytearray()
                    while True:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data.extend(chunk)
                    received.append(bytes(data))
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(3), "Test listener did not become ready"
    assert not errors, f"Could not create test listener: {errors}"
    result = run_as_user(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
    thread.join(8)
    assert result.returncode == 0, f"{command[0]} failed: {result.stderr.decode(errors='replace')}"
    assert not thread.is_alive(), "Application did not finish sending its payload"
    assert not errors, f"Listener failed: {errors}"
    assert received == [EXPECTED], f"Application sent an unexpected payload: {received!r}"


def test_port_forward_service_exists_and_correct():
    path = "/home/user/.config/systemd/user/port-forward.service"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "Restart=always" in content, f"File {path} is missing 'Restart=always'."
    assert "socat" in content, f"File {path} does not seem to run socat."
    assert "10025" in content, f"File {path} does not configure port 10025."
    assert "2525" in content, f"File {path} does not configure forwarding to port 2525."


def test_mailer_app_cpp_fixed():
    path = "/home/user/mailer_app.cpp"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "htons(10025)" in content, f"File {path} does not contain the fixed port htons(10025)."
    assert "htons(10024)" not in content, f"File {path} still contains the buggy port htons(10024)."


def test_mailer_app_compiled():
    path = "/home/user/mailer_app"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def test_mailer_app_service_dependencies():
    path = "/home/user/.config/systemd/user/mailer_app.service"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert re.search(r"^Requires=.*port-forward\.service", content, re.MULTILINE), f"File {path} is missing Requires=port-forward.service."
    assert re.search(r"^After=.*port-forward\.service", content, re.MULTILINE), f"File {path} is missing After=port-forward.service."


def test_compiled_artifacts_and_services_really_work():
    # Free both ports before independently exercising the submitted and rebuilt apps.
    user_systemctl("stop", "mailer_app.service", check=False)
    user_systemctl("stop", "port-forward.service", check=False)
    user_systemctl("stop", "backend-mailer.service", check=False)

    capture_one(10025, ["/home/user/mailer_app"])

    # Compile the submitted source independently and ensure it has the same behavior.
    with tempfile.TemporaryDirectory(prefix="mailer-build-") as build_dir:
        rebuilt = os.path.join(build_dir, "mailer_app")
        subprocess.run(
            ["g++", "/home/user/mailer_app.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=True,
        )
        os.chown(rebuilt, USER.pw_uid, USER.pw_gid)
        os.chmod(rebuilt, 0o755)
        capture_one(10025, [rebuilt])

    # Supply the backend that setup claimed was already running. It records every
    # connection in the real spool while the submitted systemd services are tested.
    spool = "/home/user/mail_spool.log"
    with open(spool, "wb"):
        pass
    os.chown(spool, USER.pw_uid, USER.pw_gid)
    os.chmod(spool, 0o666)

    captures = []
    errors = []
    ready = threading.Event()
    stop = threading.Event()

    def backend():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", 2525))
                listener.listen(5)
                listener.settimeout(0.2)
                ready.set()
                while not stop.is_set():
                    try:
                        conn, _ = listener.accept()
                    except socket.timeout:
                        continue
                    with conn:
                        conn.settimeout(2)
                        data = bytearray()
                        while True:
                            chunk = conn.recv(4096)
                            if not chunk:
                                break
                            data.extend(chunk)
                    payload = bytes(data)
                    captures.append(payload)
                    with open(spool, "ab") as output:
                        output.write(payload)
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(3), "Backend test server did not become ready"
    assert not errors, f"Backend test server failed: {errors}"

    try:
        user_systemctl("daemon-reload")
        user_systemctl("restart", "port-forward.service")

        deadline = time.time() + 5
        while time.time() < deadline:
            if user_systemctl("is-active", "port-forward.service", check=False).returncode == 0:
                break
            time.sleep(0.1)
        assert user_systemctl("is-active", "port-forward.service", check=False).returncode == 0, \
            "port-forward.service is not active"

        # A random value must traverse the submitted forwarder to the controlled backend.
        nonce = os.urandom(32)
        with socket.create_connection(("127.0.0.1", 10025), timeout=3) as probe:
            probe.sendall(nonce)
        deadline = time.time() + 5
        while len(captures) < 1 and time.time() < deadline:
            time.sleep(0.05)
        assert captures and captures[0] == nonce, "Port 10025 did not forward data to 127.0.0.1:2525"

        # Remove probe data, then run the actual oneshot unit through the actual forwarder.
        with open(spool, "wb"):
            pass
        user_systemctl("reset-failed", "mailer_app.service", check=False)
        user_systemctl("start", "mailer_app.service")

        deadline = time.time() + 5
        while len(captures) < 2 and time.time() < deadline:
            time.sleep(0.05)
        assert len(captures) >= 2, "mailer_app.service made no connection through the forwarder"
        assert captures[1] == EXPECTED, f"mailer_app.service sent an unexpected payload: {captures[1]!r}"

        properties = user_systemctl(
            "show", "mailer_app.service", "--property=Result", "--property=ExecMainStatus"
        ).stdout
        assert "Result=success" in properties, f"mailer_app.service did not complete successfully: {properties}"
        assert "ExecMainStatus=0" in properties, f"mailer_app.service exited unsuccessfully: {properties}"
        assert user_systemctl("is-active", "port-forward.service", check=False).returncode == 0, \
            "port-forward.service stopped while mailer_app.service ran"
    finally:
        stop.set()
        thread.join(3)

    assert not errors, f"Backend test server failed: {errors}"


def test_mail_spool_log_contains_status_fixed():
    path = "/home/user/mail_spool.log"
    assert os.path.isfile(path), f"File {path} does not exist. The application may not have run successfully."
    with open(path, "r") as f:
        content = f.read()
    assert "STATUS: FIXED" in content, f"File {path} does not contain 'STATUS: FIXED'. The mailer app did not successfully deliver the message."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
