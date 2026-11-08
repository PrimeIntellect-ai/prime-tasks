#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import random
import re
import signal
import socket
import subprocess
import time
import pytest

SOURCE = "/home/user/ids_sink.c"
BINARY = "/home/user/ids_sink"
COMPILED_COPY = "/tmp/ids_sink_from_source"
HOST = "127.0.0.1"
PORT = 8080
ALERT = "ALERT: MALICIOUS REDIRECT DETECTED\n"
OK = "OK\n"


def test_files_exist():
    assert os.path.isfile(SOURCE), "/home/user/ids_sink.c does not exist"
    assert os.path.isfile(BINARY), "/home/user/ids_sink executable does not exist"
    assert os.access(BINARY, os.X_OK), "/home/user/ids_sink is not executable"


def send_tcp_request(host, port, payload):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2.0)
            s.connect((host, port))
            s.sendall(payload)
            response = s.recv(1024)
            return response.decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with {host}:{port}: {e}")


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == PORT:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pids():
    inodes = listener_inodes()
    pids = set()
    if not inodes:
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def kill_port_listeners():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 1.5
        while time.time() < deadline and listener_inodes():
            time.sleep(0.03)
    assert not listener_inodes(), "Could not clear port 8080 before launching submission"


def wait_for_listener(proc):
    deadline = time.time() + 3.0
    while time.time() < deadline:
        if listener_inodes():
            return
        if proc.poll() is not None:
            pytest.fail(f"Server exited before listening (status {proc.returncode})")
        time.sleep(0.03)
    pytest.fail("Server did not listen on 127.0.0.1:8080")


def extract_verified_token():
    result = subprocess.run(
        ["tesseract", "/app/suspicious_login.png", "stdout", "--psm", "7"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"OCR failed: {result.stderr}"
    text = result.stdout.strip()
    candidates = re.findall(r"[A-Za-z0-9+/=]{40,}", text)
    compact = re.sub(r"\s+", "", text)
    if compact not in candidates:
        candidates.append(compact)

    for candidate in candidates:
        try:
            decoded = base64.b64decode(candidate + "=" * (-len(candidate) % 4), validate=True)
            decoded_text = decoded.decode("utf-8")
        except Exception:
            continue
        match = re.fullmatch(r"EXPLOIT_TOKEN:([^|]+)\|HASH:([0-9a-fA-F]{64})", decoded_text)
        if not match:
            continue
        token, stated_hash = match.groups()
        actual_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        assert actual_hash == stated_hash.lower(), "The hash embedded in the image does not verify"
        return token
    pytest.fail(f"Could not decode and validate the payload extracted from the image; OCR output was {text!r}")


def test_ids_sink_malicious_redirect():
    payload = b"GET /login?redirect=http://evil.com/?token=SEC-99887766\r\n"
    expected_response = ALERT
    response = send_tcp_request(HOST, PORT, payload)
    assert response == expected_response, f"Expected '{expected_response}', but got '{response}'"


def test_ids_sink_normal_redirect():
    payload = b"GET /login?redirect=/dashboard\r\n"
    expected_response = OK
    response = send_tcp_request(HOST, PORT, payload)
    assert response == expected_response, f"Expected '{expected_response}', but got '{response}'"


def test_ids_sink_missing_redirect_path():
    payload = b"POST /api/data HTTP/1.1\r\nHost: example.com\r\n\r\ntoken=SEC-99887766"
    expected_response = OK
    response = send_tcp_request(HOST, PORT, payload)
    assert response == expected_response, f"Expected '{expected_response}', but got '{response}'"


def make_cases(token):
    marker = "GET /login?redirect="
    nonce = os.urandom(12).hex()
    wrong = token[:-1] + ("X" if token[-1:] != "X" else "Y")
    cases = [
        (f"{marker}https://{nonce}.invalid/a?x={token}\r\n", ALERT),
        (f"Host: {nonce}.invalid\r\n{marker}{token}\r\n", ALERT),
        (f"{marker}/safe\r\nX-Random: {nonce}\r\nX-Token: {token}\r\n\r\n", ALERT),
        (f"prefix-{nonce} {marker}abc{token}suffix", ALERT),
        (f"{marker}{token}", ALERT),
        (f"{marker}/dashboard?value={wrong}&n={nonce}\r\n", OK),
        (f"{token}\r\n{marker}/dashboard/{nonce}\r\n", OK),
        (f"GET /login?Redirect={token}&n={nonce}\r\n", OK),
        (f"GET /login/redirect={token}&n={nonce}\r\n", OK),
        (f"POST /api/{nonce} HTTP/1.1\r\n\r\n{token}", OK),
        (f"{marker}/dashboard/{nonce}\r\n", OK),
        (f"GET /other?redirect={token}&n={nonce}\r\n", OK),
    ]
    rng = random.SystemRandom()
    for _ in range(12):
        salt = os.urandom(8).hex()
        if rng.randrange(2):
            cases.append((f"X-{salt}: a\r\n{marker}/to/{salt}?token={token}\r\n", ALERT))
        else:
            cases.append((f"{marker}/to/{salt}?token={wrong}\r\nX-{salt}: {token[:3]}\r\n", OK))
    rng.shuffle(cases)
    return cases


def exercise_dynamic_cases(token):
    cases = make_cases(token)
    assert any(expected == ALERT for _, expected in cases)
    assert any(expected == OK for _, expected in cases)
    for payload, expected in cases:
        response = send_tcp_request(HOST, PORT, payload.encode("utf-8"))
        assert response == expected, (
            f"For payload {payload!r}, expected {expected!r}, got {response!r}"
        )


def run_and_exercise(path, token):
    kill_port_listeners()
    proc = subprocess.Popen(
        [path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_listener(proc)
        exercise_dynamic_cases(token)
    finally:
        try:
            proc.terminate()
        except ProcessLookupError:
            pass
        kill_port_listeners()


def test_submitted_executable_and_source_behavior():
    token = extract_verified_token()

    # Launch the exact executable requested by the instruction, rather than trusting
    # whichever process happened to be occupying port 8080.
    run_and_exercise(BINARY, token)

    build = subprocess.run(
        ["gcc", SOURCE, "-o", COMPILED_COPY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"ids_sink.c did not compile: {build.stderr}"
    assert os.path.isfile(COMPILED_COPY) and os.access(COMPILED_COPY, os.X_OK)
    run_and_exercise(COMPILED_COPY, token)


# The original assertions require the agent to have left a listening server.
def test_initial_server_is_listening():
    assert listener_inodes(), "No server was listening on port 8080 after the agent finished"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
