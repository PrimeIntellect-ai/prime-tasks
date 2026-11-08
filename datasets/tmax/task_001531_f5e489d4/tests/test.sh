#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import shutil
import socket
import subprocess
import time

LOGS_DIR = "/home/user/logs"


def require_script(path):
    assert os.path.isfile(path), f"Missing script or not a regular file: {path}"


def stop_process(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def connect_with_retry(port, process, timeout=4):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError("Port forwarder exited before accepting connections")
        sock = socket.socket()
        sock.settimeout(2)
        try:
            sock.connect(("127.0.0.1", port))
            return sock
        except OSError as exc:
            last_error = exc
            sock.close()
            time.sleep(0.05)
    raise AssertionError(f"Could not connect to port {port}: {last_error}")


def recv_exact(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        assert chunk, f"Connection closed with {remaining} bytes still expected"
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def test_port_forwarder():
    forwarder_script = "/home/user/port_forwarder.py"
    log_file = os.path.join(LOGS_DIR, "traffic.log")
    require_script(forwarder_script)
    assert os.path.isdir(LOGS_DIR), f"Missing directory: {LOGS_DIR}"

    with open(log_file, "wb"):
        pass

    cases = []
    for _ in range(2):
        greeting = b"HELLO:" + secrets.token_bytes(37)
        payload = secrets.token_bytes(257 + secrets.randbelow(500))
        cases.append((greeting, payload))

    encoded_cases = [
        [base64.b64encode(g).decode("ascii"), base64.b64encode(p).decode("ascii")]
        for g, p in cases
    ]
    backend_code = r'''
import base64
import hashlib
import json
import os
import socket
import sys

cases = [(base64.b64decode(g), base64.b64decode(p))
         for g, p in json.loads(os.environ["FORWARD_TEST_CASES"])]
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080))
s.listen(5)
s.settimeout(8)
print("READY", flush=True)
for greeting, expected_payload in cases:
    c, _ = s.accept()
    c.settimeout(5)
    c.sendall(greeting)
    received = bytearray()
    while len(received) < len(expected_payload):
        chunk = c.recv(len(expected_payload) - len(received))
        if not chunk:
            break
        received.extend(chunk)
    if bytes(received) != expected_payload:
        c.close()
        s.close()
        sys.exit(3)
    c.sendall(hashlib.sha256(greeting + b"|" + expected_payload).digest())
    c.close()
s.close()
'''
    env = os.environ.copy()
    env["FORWARD_TEST_CASES"] = json.dumps(encoded_cases)
    backend_proc = subprocess.Popen(
        ["python3", "-u", "-c", backend_code],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    forwarder_proc = None
    try:
        ready = backend_proc.stdout.readline().strip()
        assert ready == "READY", f"Backend failed to start: {backend_proc.stderr.read()}"

        forwarder_proc = subprocess.Popen(
            ["python3", forwarder_script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        for greeting, payload in cases:
            client = connect_with_retry(9090, forwarder_proc)
            try:
                received_greeting = recv_exact(client, len(greeting))
                assert b"HELLO" in received_greeting, "Did not receive expected response from backend via port forwarder."
                assert received_greeting == greeting, "Backend-to-client data was altered or not fully forwarded"
                client.sendall(payload)
                expected_reply = hashlib.sha256(greeting + b"|" + payload).digest()
                assert recv_exact(client, len(expected_reply)) == expected_reply, "Client data did not reach the backend correctly"
            finally:
                client.close()

        backend_proc.wait(timeout=4)
        backend_error = backend_proc.stderr.read()
        assert backend_proc.returncode == 0, f"Backend did not receive forwarded client data: {backend_error}"
        time.sleep(0.2)
    finally:
        stop_process(forwarder_proc)
        stop_process(backend_proc)

    assert os.path.exists(log_file), f"Log file missing: {log_file}"
    with open(log_file, "rb") as f:
        log_content = f.read()
    assert b"FORWARD_SUCCESS" in log_content, f"Expected 'FORWARD_SUCCESS' in {log_file}"
    assert log_content == b"FORWARD_SUCCESS\nFORWARD_SUCCESS\n", "Log must contain exactly one exact FORWARD_SUCCESS line per accepted connection"


def run_rotation_case(source_data, old_rotated_data):
    script = "/home/user/log_manager.py"
    log_file = os.path.join(LOGS_DIR, "traffic.log")
    rotated_log = os.path.join(LOGS_DIR, "traffic.log.1")
    with open(log_file, "wb") as f:
        f.write(source_data)
    with open(rotated_log, "wb") as f:
        f.write(old_rotated_data)

    subprocess.run(["python3", script], check=True, timeout=5)

    assert os.path.exists(rotated_log), f"Rotated log missing: {rotated_log}"
    assert os.path.getsize(rotated_log) == len(source_data), f"Rotated log size incorrect: expected {len(source_data)}, got {os.path.getsize(rotated_log)}"
    with open(rotated_log, "rb") as f:
        assert f.read() == source_data, "Rotated log does not contain the original traffic.log data"
    assert os.path.exists(log_file), f"New log file missing: {log_file}"
    assert os.path.getsize(log_file) == 0, f"New log file not empty: expected 0, got {os.path.getsize(log_file)}"


def test_log_manager():
    script = "/home/user/log_manager.py"
    require_script(script)

    # Preserve the original 2000-byte assertion, then exercise a randomized size.
    run_rotation_case(os.urandom(2000), os.urandom(73))
    run_rotation_case(os.urandom(1025 + secrets.randbelow(4096)), os.urandom(91))

    # At and below the threshold, both files must remain unchanged.
    for size in (1024, secrets.randbelow(1024)):
        log_file = os.path.join(LOGS_DIR, "traffic.log")
        rotated_log = os.path.join(LOGS_DIR, "traffic.log.1")
        source_data = os.urandom(size)
        rotated_data = os.urandom(117)
        with open(log_file, "wb") as f:
            f.write(source_data)
        with open(rotated_log, "wb") as f:
            f.write(rotated_data)
        subprocess.run(["python3", script], check=True, timeout=5)
        with open(log_file, "rb") as f:
            assert f.read() == source_data, "Log manager changed a log that was not greater than 1024 bytes"
        with open(rotated_log, "rb") as f:
            assert f.read() == rotated_data, "Log manager overwrote the rotated log below the threshold"


def reset_logs():
    if os.path.exists(LOGS_DIR):
        shutil.rmtree(LOGS_DIR)
    os.makedirs(LOGS_DIR)


def verify_quota_case(files, expected_original=None):
    script = "/home/user/quota_check.py"
    report_file = "/home/user/quota_report.txt"
    reset_logs()
    for name, data in files.items():
        with open(os.path.join(LOGS_DIR, name), "wb") as f:
            f.write(data)

    expected = sum(
        os.path.getsize(os.path.join(LOGS_DIR, name))
        for name in os.listdir(LOGS_DIR)
        if os.path.isfile(os.path.join(LOGS_DIR, name))
    )
    if expected_original is not None:
        assert expected == expected_original

    subprocess.run(["python3", script], check=True, timeout=5)
    assert os.path.exists(report_file), f"Report file missing: {report_file}"
    with open(report_file, "r") as f:
        report_content = f.read().strip()
    assert report_content == f"TOTAL_BYTES: {expected}", f"Incorrect report content: expected 'TOTAL_BYTES: {expected}', got '{report_content}'"


def test_quota_check():
    script = "/home/user/quota_check.py"
    require_script(script)

    # Preserve the original 2005-byte fixture and assertion.
    verify_quota_case({
        "traffic.log.1": os.urandom(2000),
        "traffic.log": b"",
        "extra.log": b"TEST\n",
    }, expected_original=2005)

    for _ in range(2):
        files = {}
        for index in range(3 + secrets.randbelow(4)):
            name = f"{secrets.token_hex(5)}-{index}.log"
            files[name] = os.urandom(secrets.randbelow(3500))
        verify_quota_case(files)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
