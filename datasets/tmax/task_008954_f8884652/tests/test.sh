#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import time
import uuid

USER = pwd.getpwnam("user")


def demote_to_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def process_group_has_socat(pgid):
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat", "r") as f:
                stat_data = f.read()
            fields_after_comm = stat_data[stat_data.rfind(")") + 2:].split()
            if int(fields_after_comm[2]) != pgid:
                continue
            exe = os.path.basename(os.readlink(f"/proc/{name}/exe"))
            if exe == "socat":
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError, IndexError):
            pass
    return False


def test_start_forwarding_sh():
    script_path = "/home/user/start_forwarding.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    # Check if executable
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "socat" in content, "The script does not contain a socat command."
    assert "8333" in content, "The script does not contain the port 8333."
    assert "9333" in content, "The script does not contain the port 9333."
    assert "127.0.0.1" in content, "The script does not bind/connect to 127.0.0.1."
    assert "/home/user/raw_traffic.log" in content, "The script does not log to /home/user/raw_traffic.log."

    raw_log = "/home/user/raw_traffic.log"
    if os.path.exists(raw_log):
        os.remove(raw_log)

    request = ("REQUEST_" + uuid.uuid4().hex).encode()
    response = ("RESPONSE_" + uuid.uuid4().hex).encode()
    received = []
    backend_error = []
    stop_backend = threading.Event()

    backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    backend.bind(("127.0.0.1", 9333))
    backend.listen(5)
    backend.settimeout(0.2)

    def serve_backend():
        try:
            while not stop_backend.is_set():
                try:
                    conn, _ = backend.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(2)
                    data = conn.recv(65536)
                    if data:
                        received.append(data)
                        conn.sendall(response)
                        return
        except Exception as exc:
            backend_error.append(exc)

    thread = threading.Thread(target=serve_backend, daemon=True)
    thread.start()

    proc = None
    try:
        proc = subprocess.Popen(
            [script_path],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user", "USER": "user", "LOGNAME": "user"},
            stdout=subprocess.DEVNULL,
            start_new_session=True,
            preexec_fn=demote_to_user,
        )

        deadline = time.time() + 5
        while time.time() < deadline and not process_group_has_socat(proc.pid):
            if proc.poll() is not None and not process_group_has_socat(proc.pid):
                break
            time.sleep(0.05)
        assert process_group_has_socat(proc.pid), "The forwarding script did not actually run socat."

        client = None
        last_error = None
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                client = socket.create_connection(("127.0.0.1", 8333), timeout=0.5)
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.05)
        assert client is not None, f"Nothing listened on 127.0.0.1:8333: {last_error}"

        with client:
            client.settimeout(3)
            client.sendall(request)
            forwarded_response = client.recv(65536)

        thread.join(timeout=3)
        assert not backend_error, f"Backend failed while testing forwarding: {backend_error}"
        assert received and received[0] == request, "Traffic sent to port 8333 was not forwarded to port 9333."
        assert forwarded_response == response, "Return traffic from port 9333 was not forwarded to the client."

        deadline = time.time() + 3
        log_bytes = b""
        while time.time() < deadline:
            if os.path.exists(raw_log):
                with open(raw_log, "rb") as f:
                    log_bytes = f.read()
                if request in log_bytes and response in log_bytes:
                    break
            time.sleep(0.05)
        assert request in log_bytes, "The forwarded request was not logged to raw_traffic.log."
        assert response in log_bytes, "The forwarded response was not logged to raw_traffic.log."
    finally:
        stop_backend.set()
        backend.close()
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        thread.join(timeout=1)


def test_alert_py():
    script_path = "/home/user/alert.py"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    dummy_log = "/home/user/dummy_traffic.log"
    blocked_log = "/home/user/blocked.log"

    # Clean up blocked_log if it exists from previous tests
    if os.path.exists(blocked_log):
        os.remove(blocked_log)

    with open(dummy_log, "w") as f:
        f.write("Normal traffic data\n")
        f.write("BLOCKED_IP from 192.168.1.1\n")
        f.write("More traffic\n")
        f.write("Another BLOCKED_IP recorded\n")

    try:
        subprocess.run(["python3", script_path, dummy_log], check=True)

        assert os.path.exists(blocked_log), f"The script did not create {blocked_log}."

        with open(blocked_log, "r") as f:
            lines = f.read().splitlines()

        assert len(lines) == 2, f"Expected 2 lines in {blocked_log}, but got {len(lines)}."
        assert lines[0] == "ALERT: A blocked connection was detected.", "Incorrect alert message."
        assert lines[1] == "ALERT: A blocked connection was detected.", "Incorrect alert message."

        # Exercise scanning and append behavior with unpredictable inputs/counts.
        sentinel = "preexisting-" + uuid.uuid4().hex
        with open(blocked_log, "w") as f:
            f.write(sentinel + "\n")

        expected_alerts = 0
        for invocation in range(2):
            hit_count = secrets.randbelow(5) + 1
            expected_alerts += hit_count
            generated = tempfile.NamedTemporaryFile(mode="w", delete=False, dir="/home/user")
            try:
                for i in range(hit_count):
                    generated.write(f"{uuid.uuid4().hex} BLOCKED_IP {invocation}-{i}\n")
                    generated.write(f"ordinary-{uuid.uuid4().hex}\n")
                generated.write("blocked_ip has the wrong case\n")
                generated.write("BLOCKED-IP is not the exact string\n")
                generated.close()
                subprocess.run(["python3", script_path, generated.name], check=True)
            finally:
                generated.close()
                if os.path.exists(generated.name):
                    os.remove(generated.name)

        with open(blocked_log, "r") as f:
            lines = f.read().splitlines()
        alert = "ALERT: A blocked connection was detected."
        assert lines == [sentinel] + [alert] * expected_alerts, (
            "alert.py did not append exactly one alert for every supplied line containing BLOCKED_IP."
        )
    finally:
        if os.path.exists(dummy_log):
            os.remove(dummy_log)
        if os.path.exists(blocked_log):
            os.remove(blocked_log)


def test_alert_rotate_conf():
    conf_path = "/home/user/alert_rotate.conf"
    assert os.path.exists(conf_path), f"File {conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "/home/user/blocked.log" in content, "The logrotate config does not target /home/user/blocked.log."

    keywords = ["daily", "rotate 5", "compress", "missingok", "notifempty"]
    for kw in keywords:
        # allow multiple spaces between rotate and 5
        if kw == "rotate 5":
            assert "rotate" in content and "5" in content, "The logrotate config does not specify 'rotate 5'."
        else:
            assert kw in content, f"The logrotate config does not contain the directive '{kw}'."

    # Ignore comments and inspect directives in the block that actually targets blocked.log.
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    match = re.search(r"(?:^|\n)\s*/home/user/blocked\.log\s*\{([^{}]*)\}", uncommented, re.S)
    assert match, "No valid logrotate block targets /home/user/blocked.log."
    directives = [line.strip().split() for line in match.group(1).splitlines() if line.strip()]

    assert ["daily"] in directives, "The blocked.log block does not specify daily rotation."
    rotate_values = [parts[1:] for parts in directives if parts and parts[0] == "rotate"]
    assert rotate_values == [["5"]], "The blocked.log block must specify exactly 'rotate 5'."
    assert ["compress"] in directives and ["nocompress"] not in directives, "Compression is not enabled."
    assert ["missingok"] in directives and ["nomissingok"] not in directives, "missingok is not enabled."
    assert ["notifempty"] in directives and ["ifempty"] not in directives, "notifempty is not enabled."
    assert not any(parts and parts[0] in {"hourly", "weekly", "monthly", "yearly"} for parts in directives), (
        "A conflicting rotation interval is present."
    )

    state_path = "/tmp/logrotate-state-" + uuid.uuid4().hex
    try:
        result = subprocess.run(
            ["logrotate", "--debug", "--state", state_path, conf_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            preexec_fn=demote_to_user,
        )
        assert result.returncode == 0, f"logrotate rejected the configuration:\n{result.stdout}"
    finally:
        if os.path.exists(state_path):
            os.remove(state_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
