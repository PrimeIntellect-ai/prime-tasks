#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import signal
import socket
import subprocess
import threading
from pathlib import Path

import pytest

PROJECT_PATH = Path('/home/user/audit_tool')
REPORT_PATH = Path('/home/user/audit_report.json')
AUTH_KEYS_PATH = Path('/home/user/.ssh/authorized_keys')
COMPROMISED_PATH = Path('/home/user/compromised.txt')
EXPECTED_PAYLOAD = b'U0NBTl9DT01NQU5E\n'


def stop_original_server():
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes().replace(b'\0', b' ')
            if b'/home/user/server.py' in cmdline:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


def make_server(response_bytes):
    candidates = list(range(8000, 8011))
    secrets.SystemRandom().shuffle(candidates)
    listener = None
    selected_port = None

    for port in candidates:
        candidate = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        candidate.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            candidate.bind(('127.0.0.1', port))
            candidate.listen(20)
            listener = candidate
            selected_port = port
            break
        except OSError:
            candidate.close()

    assert listener is not None, 'No free port was available in the required range'
    listener.settimeout(0.2)
    stop_event = threading.Event()
    encoded_response = base64.b64encode(response_bytes) + b'\n'

    def handle(conn):
        try:
            conn.settimeout(2)
            received = b''
            while len(received) < 4096 and b'\n' not in received:
                chunk = conn.recv(1024)
                if not chunk:
                    break
                received += chunk
            if received == EXPECTED_PAYLOAD:
                conn.sendall(encoded_response)
        except (OSError, socket.timeout):
            pass
        finally:
            conn.close()

    def serve():
        while not stop_event.is_set():
            try:
                conn, _ = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=handle, args=(conn,), daemon=True).start()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return listener, selected_port, stop_event, thread


@pytest.fixture(scope='session')
def expected_state():
    assert PROJECT_PATH.is_dir(), f'Missing Rust project directory {PROJECT_PATH}'
    assert (PROJECT_PATH / 'Cargo.toml').is_file(), 'The Rust project is missing Cargo.toml'
    rust_sources = [p for p in PROJECT_PATH.rglob('*.rs') if p.is_file()]
    assert rust_sources, 'The project contains no Rust source files'
    assert any(p.read_text(encoding='utf-8', errors='ignore').strip() for p in rust_sources), \
        'The Rust source files are empty'

    original_auth = AUTH_KEYS_PATH.read_bytes()
    original_compromised = COMPROMISED_PATH.read_bytes()

    stop_original_server()
    for _ in range(30):
        try:
            with socket.create_connection(('127.0.0.1', 8005), timeout=0.05):
                pass
        except OSError:
            break

    compromised_key = base64.b64encode(secrets.token_bytes(48)).decode('ascii')
    safe_key = base64.b64encode(secrets.token_bytes(48)).decode('ascii')
    compromised_digest = hashlib.sha256(compromised_key.encode('utf-8')).hexdigest()
    unrelated_digest = hashlib.sha256(secrets.token_bytes(32)).hexdigest()

    AUTH_KEYS_PATH.write_text(
        f'ssh-rsa {safe_key} safe@verification\n'
        f'ssh-rsa {compromised_key} compromised@verification\n',
        encoding='utf-8',
    )
    COMPROMISED_PATH.write_text(
        f'{compromised_digest}\n{unrelated_digest}\n', encoding='utf-8'
    )

    decoded_response = f'AUDIT_RESPONSE_{secrets.token_hex(16)}'
    listener, open_port, stop_event, server_thread = make_server(
        decoded_response.encode('utf-8')
    )

    try:
        if REPORT_PATH.exists():
            REPORT_PATH.unlink()

        env = os.environ.copy()
        env['HOME'] = '/home/user'
        env['CARGO_HOME'] = '/home/user/.cargo'
        result = subprocess.run(
            ['cargo', 'run', '--quiet'],
            cwd=str(PROJECT_PATH),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=240,
        )
        assert result.returncode == 0, \
            f'The Rust program failed when executed with cargo run:\n{result.stdout}'
        assert REPORT_PATH.is_file(), \
            'The executed Rust program did not generate /home/user/audit_report.json'

        yield {
            'compromised_keys': [compromised_digest],
            'open_port': open_port,
            'decoded_response': decoded_response,
            'response_hash': hashlib.sha256(decoded_response.encode('utf-8')).hexdigest(),
        }
    finally:
        stop_event.set()
        listener.close()
        server_thread.join(timeout=1)
        AUTH_KEYS_PATH.write_bytes(original_auth)
        COMPROMISED_PATH.write_bytes(original_compromised)


@pytest.fixture(scope='session')
def report_data(expected_state):
    assert REPORT_PATH.is_file(), f'The report file {REPORT_PATH} was not found'
    try:
        with REPORT_PATH.open('r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'The report does not contain valid JSON: {exc}')


def test_rust_project_exists(expected_state):
    assert PROJECT_PATH.is_dir()
    assert (PROJECT_PATH / 'Cargo.toml').is_file()


def test_report_structure(report_data):
    expected_keys = {'compromised_keys', 'open_port', 'decoded_response', 'response_hash'}
    missing_keys = expected_keys - set(report_data.keys())
    assert not missing_keys, f'The JSON report is missing required keys: {missing_keys}'


def test_compromised_keys(report_data, expected_state):
    actual = report_data.get('compromised_keys')
    assert isinstance(actual, list), "The 'compromised_keys' value must be a JSON array"
    assert sorted(actual) == sorted(expected_state['compromised_keys']), \
        f"Expected {expected_state['compromised_keys']}, got {actual}"


def test_open_port(report_data, expected_state):
    assert report_data.get('open_port') == expected_state['open_port'], \
        f"Expected open port {expected_state['open_port']}, got {report_data.get('open_port')}"


def test_decoded_response(report_data, expected_state):
    assert report_data.get('decoded_response') == expected_state['decoded_response'], \
        'The decoded service response is incorrect'


def test_response_hash(report_data, expected_state):
    assert report_data.get('response_hash') == expected_state['response_hash'], \
        'The SHA256 hash of the decoded response is incorrect'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
