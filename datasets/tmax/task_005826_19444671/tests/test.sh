#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import struct
import subprocess
import time
import pytest

WORKER_PATH = '/home/user/app/worker.py'
EXPECTED_ERROR = {"status": "error", "message": "Invalid payload format"}


def recv_exact(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise AssertionError(f"Connection closed with {remaining} response bytes still expected")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b''.join(chunks)


def send_request(payload, declared_length=None):
    if declared_length is None:
        declared_length = len(payload)

    with socket.create_connection(('127.0.0.1', 9000), timeout=2.0) as sock:
        sock.settimeout(2.0)
        sock.sendall(struct.pack('>BI', 2, declared_length) + payload)
        header = recv_exact(sock, 5)
        msg_type = header[0]
        response_length = struct.unpack('>I', header[1:])[0]
        assert msg_type == 2, f"Unexpected response message type: {msg_type}"
        assert response_length < 1024 * 1024, "Unreasonably large response"
        response_data = recv_exact(sock, response_length)

    return json.loads(response_data.decode('utf-8'))


def assert_running(proc):
    if proc.poll() is not None:
        stdout, stderr = proc.communicate()
        pytest.fail(
            "worker.py is no longer running. "
            f"stdout={stdout.decode(errors='replace')!r}, "
            f"stderr={stderr.decode(errors='replace')!r}"
        )


def test_attacker_ip():
    ip_file = '/home/user/attacker_ip.txt'
    assert os.path.isfile(ip_file), f"File {ip_file} is missing"
    with open(ip_file, 'r') as f:
        content = f.read().strip()
    assert content == '192.168.100.42', (
        f"Incorrect attacker IP in {ip_file}. "
        f"Expected 192.168.100.42, got {content}"
    )


def test_worker_patch_and_protocol_behavior():
    assert os.path.isfile(WORKER_PATH), f"File {WORKER_PATH} is missing"
    proc = subprocess.Popen(
        ['python3', WORKER_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    time.sleep(1)

    try:
        assert_running(proc)

        # Preserve the original captured anomalous request assertion.
        captured_payload = b'{"test":"\xc3'
        assert send_request(captured_payload, declared_length=100) == EXPECTED_ERROR
        assert_running(proc)

        # Valid protocol requests must still be parsed and handled normally.
        valid_objects = [
            {"test": secrets.token_hex(12)},
            {"number": secrets.randbelow(1_000_000), "enabled": True},
            {"unicode": "snowman-\u2603-" + secrets.token_hex(5)},
            {"items": [secrets.token_hex(4), None, 17]},
        ]
        for obj in valid_objects:
            payload = json.dumps(obj, ensure_ascii=False).encode('utf-8')
            assert json.loads(payload.decode('utf-8')) == obj
            assert send_request(payload) == {"status": "ok"}
            assert_running(proc)

        # Exercise independently generated decoding and JSON parsing failures.
        token = secrets.token_hex(10).encode('ascii')
        malformed_payloads = [
            b'{"value":"' + token + b'\xc3',
            b'{"number":' + str(secrets.randbelow(1_000_000)).encode('ascii'),
            b'["' + token + b'",]',
            b'{"binary":"' + token + b'\xff"}',
        ]

        for payload in malformed_payloads:
            try:
                json.loads(payload.decode('utf-8'))
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass
            else:
                pytest.fail("Verifier generated a payload that was not malformed")

            assert send_request(payload) == EXPECTED_ERROR
            assert_running(proc)

            # Confirm each parsing exception leaves the same worker able to
            # process a fresh valid request, rather than merely staying idle.
            followup = {"after_error": secrets.token_hex(16)}
            followup_payload = json.dumps(followup).encode('utf-8')
            assert send_request(followup_payload) == {"status": "ok"}
            assert_running(proc)

        time.sleep(0.5)
        assert_running(proc)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
