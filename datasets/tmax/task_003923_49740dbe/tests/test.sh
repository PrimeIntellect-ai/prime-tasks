#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import socket
import struct
import subprocess
import threading
import time
from pathlib import Path

import pytest

SCRIPT = '/home/user/generate_audit.py'
OUTPUT = '/home/user/clean_audit.log'
LOGS = '/app/logs.txt'
TOKEN = b'AUTH_REQ_COMPLIANCE_2024_XYZ\n'


def generate_test_data():
    rows = []
    for _ in range(180):
        marker = secrets.token_hex(8)
        ip = '.'.join(str(secrets.randbelow(256)) for _ in range(4))
        card = '-'.join(f'{secrets.randbelow(10000):04d}' for _ in range(4))
        api = secrets.token_hex(16)
        normal = secrets.token_urlsafe(14)
        cases = [
            (f'{marker} User login from {ip} successful.',
             f'{marker} User login from [REDACTED] successful.'),
            (f'{marker} Payment processed with card {card}.',
             f'{marker} Payment processed with card [REDACTED].'),
            (f'{marker} API token {api} used.',
             f'{marker} API token [REDACTED] used.'),
            (f'{marker} Normal event {normal} without sensitive data.',
             f'{marker} Normal event {normal} without sensitive data.'),
            (f'{marker} Invalid card 123-456-789 must remain.',
             f'{marker} Invalid card 123-456-789 must remain.'),
            (f'{marker} Short hex a1b2c3 must remain.',
             f'{marker} Short hex a1b2c3 must remain.'),
            (f'{marker} Multiple values {ip} {card} {api}.',
             f'{marker} Multiple values [REDACTED] [REDACTED] [REDACTED].'),
            (f'{marker} Text version 1.2.3 and number 1234567890123456 remain.',
             f'{marker} Text version 1.2.3 and number 1234567890123456 remain.'),
        ]
        rows.extend(cases)
    random.SystemRandom().shuffle(rows)
    return [r for r, _ in rows], [e for _, e in rows]


def packet_monitor(stop, ready, evidence):
    try:
        sniffer = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
        sniffer.bind(('lo', 0))
        sniffer.settimeout(0.1)
    except Exception as exc:
        evidence['error'] = repr(exc)
        ready.set()
        return

    ready.set()
    try:
        while not stop.is_set():
            try:
                frame = sniffer.recv(65535)
            except socket.timeout:
                continue
            if len(frame) < 54 or frame[12:14] != b'\x08\x00':
                continue
            ipoff = 14
            ihl = (frame[ipoff] & 0x0f) * 4
            if ihl < 20 or frame[ipoff + 9] != 6:
                continue
            tcpoff = ipoff + ihl
            if len(frame) < tcpoff + 20:
                continue
            src, dst = struct.unpack('!HH', frame[tcpoff:tcpoff + 4])
            doff = ((frame[tcpoff + 12] >> 4) & 0x0f) * 4
            payload = frame[tcpoff + doff:]
            if not payload:
                continue

            # A genuine TLS handshake must be visible on the required frontend.
            if dst == 9443 and len(payload) >= 3 and payload[0] == 0x16 and payload[1] == 0x03:
                evidence['tls_client'] = True
            if src == 9443 and len(payload) >= 3 and payload[0] == 0x16 and payload[1] == 0x03:
                evidence['tls_server'] = True

            # The plaintext token must emerge from the proxy on the daemon side.
            if dst == 9000:
                evidence.setdefault('backend_bytes', bytearray()).extend(payload)
                if TOKEN in evidence['backend_bytes']:
                    evidence['backend_auth'] = True
    finally:
        sniffer.close()


def daemon_monitor(stop, evidence):
    while not stop.is_set():
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            try:
                exe = os.readlink(f'/proc/{entry}/exe')
                if exe == '/app/audit_daemon':
                    evidence['real_daemon'] = True
                    return
            except (FileNotFoundError, PermissionError, OSError):
                pass
        time.sleep(0.002)


def valid_fresh_self_signed_cert(start_time):
    cert_dir = Path('/home/user/certs')
    if not cert_dir.is_dir():
        return False
    for candidate in cert_dir.rglob('*'):
        if not candidate.is_file() or candidate.stat().st_mtime < start_time - 1:
            continue
        probe = subprocess.run(
            ['openssl', 'x509', '-in', str(candidate), '-noout'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if probe.returncode != 0:
            continue
        verify = subprocess.run(
            ['openssl', 'verify', '-CAfile', str(candidate), str(candidate)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if verify.returncode == 0:
            return True
    return False


def test_complete_secure_pipeline_and_redaction():
    assert os.path.isfile(SCRIPT), f'Agent script {SCRIPT} not found.'

    subprocess.run(['pkill', '-f', '^/app/audit_daemon'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree('/home/user/certs', ignore_errors=True)
    os.makedirs('/home/user/certs', exist_ok=True)
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass

    raw_lines, expected_lines = generate_test_data()
    with open(LOGS, 'w', encoding='utf-8') as f:
        f.write('\n'.join(raw_lines) + '\n')

    evidence = {}
    stop = threading.Event()
    ready = threading.Event()
    packets = threading.Thread(target=packet_monitor, args=(stop, ready, evidence), daemon=True)
    processes = threading.Thread(target=daemon_monitor, args=(stop, evidence), daemon=True)
    packets.start()
    assert ready.wait(2), 'Packet monitor did not start.'
    assert 'error' not in evidence, f"Could not monitor loopback pipeline: {evidence.get('error')}"
    processes.start()

    start_time = time.time()
    try:
        result = subprocess.run(['python3', SCRIPT], timeout=45)
    except subprocess.TimeoutExpired:
        pytest.fail('Agent script timed out after 45 seconds.')
    finally:
        # Allow final loopback packets and process state to be observed.
        time.sleep(0.2)
        stop.set()
        packets.join(2)
        processes.join(2)

    assert result.returncode == 0, f'Agent script exited with status {result.returncode}.'
    assert evidence.get('real_daemon'), 'The real /app/audit_daemon was not started.'
    assert evidence.get('tls_client'), 'No TLS ClientHello was observed on 127.0.0.1:9443.'
    assert evidence.get('tls_server'), 'No TLS server handshake was observed on 127.0.0.1:9443.'
    assert evidence.get('backend_auth'), 'The required authentication token was not forwarded to port 9000.'
    assert valid_fresh_self_signed_cert(start_time), 'No fresh valid self-signed certificate was generated under /home/user/certs/.'

    assert os.path.isfile(OUTPUT), f'Output log {OUTPUT} was not generated.'
    assert os.path.getmtime(OUTPUT) >= start_time - 1, 'Output log was not freshly generated.'
    with open(OUTPUT, encoding='utf-8') as f:
        agent_lines = f.read().splitlines()

    assert len(agent_lines) == len(expected_lines), (
        f'Line count mismatch: expected {len(expected_lines)}, got {len(agent_lines)}.')
    correct = sum(a == e for a, e in zip(agent_lines, expected_lines))
    accuracy = correct / len(expected_lines)
    assert accuracy >= 0.98, f'Redaction accuracy {accuracy:.4f} is below 0.98.'

    subprocess.run(['pkill', '-f', '^/app/audit_daemon'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
