#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time

import pytest

HOST = "127.0.0.1"
TRACE = "/tmp/db_load_audit.log"


def listening_inodes(port):
    wanted = f"{port:04X}"
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1] == wanted and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port(port):
    inodes = listening_inodes(port)
    if not inodes:
        return
    victims = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
        except (FileNotFoundError, PermissionError):
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listening_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.2)
            if s.connect_ex((HOST, port)) == 0:
                return
        time.sleep(0.05)
    raise AssertionError(f"Port {port} did not start listening")


def send_bytes(port, payload):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect((HOST, port))
        s.sendall(payload)
        return s.recv(1024)


@pytest.fixture(scope="session", autouse=True)
def audit_real_pipeline():
    # The requested artifacts must remain executable shell handlers.
    for path in ("/app/ingest_handler.sh", "/app/db_handler.sh"):
        st = os.stat(path)
        assert stat.S_ISREG(st.st_mode), f"{path} must be a regular file"
        assert st.st_mode & 0o111, f"{path} must be executable"
        with open(path, "rb") as f:
            assert f.read(2) == b"#!", f"{path} must be an executable script"

    wait_port(8000)
    wait_port(8001)

    # Replace only the DB listener temporarily with an observing backend. This
    # proves that port 8000 actually invokes the ingest path, sanitizes bytes,
    # appends a timestamp, and forwards the resulting record to port 8001.
    kill_port(8001)
    captured = []
    ready = threading.Event()
    token = secrets.token_hex(5)
    ingest_inputs = [
        f"METRIC good_{token} 17 29\n".encode(),
        f"METRIC cr_{token} 31\r 47\n".encode(),
        f"METRIC nul_{token} 5\x00 13\n".encode(),
        f"METRIC nan_{token} 71 NaN\n".encode(),
        f"METRIC na_{token} 73\r N/A\n".encode(),
        f"METRIC missing_{token} 79\n".encode(),
    ]

    def observing_db():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind((HOST, 8001))
            server.listen(10)
            server.settimeout(8)
            ready.set()
            for _ in ingest_inputs:
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(2)
                    data = b""
                    while not data.endswith(b"\n"):
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    captured.append(data)
                    conn.sendall(b"OK\n")

    backend = threading.Thread(target=observing_db, daemon=True)
    backend.start()
    assert ready.wait(2), "Could not start observing DB backend"

    for payload in ingest_inputs:
        assert send_bytes(8000, payload) == b"OK\n"
    backend.join(8)
    assert not backend.is_alive(), "Ingest service did not forward every request"
    assert len(captured) == len(ingest_inputs)

    for raw, forwarded in zip(ingest_inputs, captured):
        clean = raw.replace(b"\r", b"").replace(b"\x00", b"").rstrip(b"\n")
        assert b"\r" not in forwarded and b"\x00" not in forwarded
        match = re.fullmatch(re.escape(clean) + rb" ([0-9]{9,})\n", forwarded)
        assert match, f"Incorrect sanitized/timestamped forwarding: {forwarded!r}"

    # Restart the supplied DB service with a DEBUG audit hook. Besides checking
    # its public response, this observes the original `load` result and verifies
    # that it equals cpu + sanitized/defaulted memory for runtime-random inputs.
    kill_port(8001)
    try:
        os.unlink(TRACE)
    except FileNotFoundError:
        pass
    open(TRACE, "w").close()
    os.chmod(TRACE, 0o666)
    bash_env = "/tmp/db_audit_env.sh"
    with open(bash_env, "w") as f:
        f.write("trap 'if [[ ${load+x} ]]; then printf \"LOAD=%s\\n\" \"$load\" >> \"$AUDIT_TRACE\"; fi' DEBUG\n")
    os.chmod(bash_env, 0o644)
    env = os.environ.copy()
    env["BASH_ENV"] = bash_env
    env["AUDIT_TRACE"] = TRACE
    subprocess.Popen(
        ["/app/db_service.sh"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_port(8001)

    cpu = secrets.randbelow(300) + 100
    mem = secrets.randbelow(300) + 100
    ts = secrets.randbelow(800000000) + 1700000000
    db_cases = [
        (f"METRIC valid_{token} {cpu} {mem} {ts}\n".encode(), cpu + mem),
        (f"METRIC nan_{token} {cpu + 1} NaN {ts}\n".encode(), cpu + 1),
        (f"METRIC na_{token} {cpu + 2} N/A {ts}\n".encode(), cpu + 2),
        # With memory omitted, the fourth field is the ingest timestamp.
        (f"METRIC missing_{token} {cpu + 3} {ts}\n".encode(), cpu + 3),
        (f"METRIC cr_{token} {cpu + 4} {mem + 4}\r {ts}\n".encode(), cpu + mem + 8),
    ]
    for payload, expected_load in db_cases:
        before = os.path.getsize(TRACE)
        assert send_bytes(8001, payload) == b"OK\n"
        deadline = time.time() + 2
        addition = ""
        while time.time() < deadline:
            with open(TRACE) as f:
                f.seek(before)
                addition = f.read()
            if f"LOAD={expected_load}\n" in addition:
                break
            time.sleep(0.03)
        assert f"LOAD={expected_load}\n" in addition, (
            f"DB handler did not compute expected load {expected_load}; trace was {addition!r}"
        )

    yield


def test_ports_open():
    """Verify that both ingest service and DB service are listening."""
    for port in [8000, 8001]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            result = s.connect_ex(('127.0.0.1', port))
            assert result == 0, f"Port {port} is not open. Ensure both services are started in the background."


def send_payload(payload):
    """Helper to send a payload to the ingest service and return the response."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        try:
            s.connect(('127.0.0.1', 8000))
            s.sendall(payload.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            return response
        except Exception as e:
            pytest.fail(f"Failed to communicate with ingest service on port 8000: {e}")


def test_valid_request():
    """Test a normal, healthy metric payload."""
    payload = "METRIC webapp 80 40\n"
    resp = send_payload(payload)
    assert resp == "OK\n", f"Expected 'OK\\n' for valid payload, got {repr(resp)}"


def test_corrupted_input():
    """Test a payload with a carriage return injected."""
    payload = "METRIC cache 50\r 60\n"
    resp = send_payload(payload)
    assert resp == "OK\n", f"Expected 'OK\\n' for carriage-return payload, got {repr(resp)}. Ensure ingest_handler.sh strips \\r."


def test_edge_case_format():
    """Test a payload with a non-numeric memory value."""
    payload = "METRIC worker 90 NaN\n"
    resp = send_payload(payload)
    assert resp == "OK\n", f"Expected 'OK\\n' for non-numeric memory payload, got {repr(resp)}. Ensure db_handler.sh defaults non-numeric mem to 0."


def test_corrupted_and_edge_case():
    """Test a payload with both carriage return and non-numeric memory value."""
    payload = "METRIC DB 75\r N/A\n"
    resp = send_payload(payload)
    assert resp == "OK\n", f"Expected 'OK\\n' for combined corrupted/edge-case payload, got {repr(resp)}."


def test_runtime_randomized_pipeline_cases():
    token = secrets.token_hex(6)
    cpu = secrets.randbelow(500) + 1
    mem = secrets.randbelow(500) + 1
    payloads = [
        f"METRIC {token} {cpu} {mem}\n",
        f"METRIC {token} {cpu}\r {mem}\n",
        f"METRIC {token} {cpu} NaN\n",
        f"METRIC {token} {cpu} N/A\n",
        f"METRIC {token} {cpu}\n",
    ]
    for payload in payloads:
        assert send_payload(payload) == "OK\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
