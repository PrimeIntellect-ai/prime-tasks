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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import threading
import time

import pytest
import requests


def test_responder_source_exists():
    path = '/home/user/responder.c'
    assert os.path.isfile(path), f"The C source file {path} is missing."


def test_responder_binary_exists():
    path = '/home/user/responder'
    assert os.path.isfile(path), f"The compiled binary {path} is missing."
    assert os.access(path, os.X_OK), f"The compiled binary {path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"The compiled binary {path} is not an ELF executable."


def kill_matching_processes(names):
    me = os.getpid()
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode('utf-8', 'replace')
            if any(name in cmdline for name in names):
                os.kill(int(entry), signal.SIGKILL)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


def kill_port_listeners(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    if state == '0A' and int(local_address.rsplit(':', 1)[1], 16) == port:
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    if not inodes:
        return

    me = os.getpid()
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            for fd in os.listdir(f'/proc/{entry}/fd'):
                try:
                    target = os.readlink(f'/proc/{entry}/fd/{fd}')
                    if target.startswith('socket:[') and target[8:-1] in inodes:
                        os.kill(int(entry), signal.SIGKILL)
                        break
                except (FileNotFoundError, PermissionError):
                    pass
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


def test_remediate_endpoint():
    kill_matching_processes(['rogue_actor.py', 'backend_server.py'])
    kill_port_listeners(8080)
    kill_port_listeners(9000)
    time.sleep(0.2)

    token = secrets.token_hex(24)
    nonce = secrets.token_hex(20)
    expected_content = 'SUCCESS: FLAG_PROC_LEAK_REMEDIATED_9921'
    backend_response = f'{expected_content} {nonce}\n'.encode()
    expected_payload = f'REVOKE_TOKEN {token}\n'.encode()
    received_payloads = []
    backend_errors = []

    backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    backend.bind(('127.0.0.1', 9000))
    backend.listen(5)
    backend.settimeout(10)

    def serve_backend():
        try:
            for _ in range(2):
                conn, _ = backend.accept()
                with conn:
                    conn.settimeout(5)
                    data = b''
                    while not data.endswith(b'\n') and len(data) < 4096:
                        chunk = conn.recv(1024)
                        if not chunk:
                            break
                        data += chunk
                    received_payloads.append(data)
                    if data == expected_payload:
                        conn.sendall(backend_response)
                    else:
                        conn.sendall(b'ERROR: INVALID TOKEN\n')
        except Exception as exc:
            backend_errors.append(exc)
        finally:
            backend.close()

    backend_thread = threading.Thread(target=serve_backend, daemon=True)
    backend_thread.start()

    rogue = subprocess.Popen([
        'python3',
        '/home/user/incident/rogue_actor.py',
        f'--stolen-auth-token={token}',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    responder = None

    try:
        assert rogue.poll() is None, 'Failed to launch the controlled rogue process.'
        responder = subprocess.Popen(
            ['/home/user/responder'],
            cwd='/home/user',
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        url = 'http://127.0.0.1:8080/remediate'
        response = None
        last_error = None
        deadline = time.time() + 7
        while time.time() < deadline:
            if responder.poll() is not None:
                pytest.fail(f'The responder exited early with status {responder.returncode}.')
            try:
                response = requests.get(url, timeout=2)
                break
            except requests.exceptions.RequestException as exc:
                last_error = exc
                time.sleep(0.1)

        if response is None:
            pytest.fail(
                f'Failed to connect to the responder service at {url}. '
                f'Is it running? Error: {last_error}'
            )

        assert response.status_code == 200, (
            f'Expected HTTP 200 OK, but got {response.status_code}.'
        )
        actual_content = response.text.strip()
        assert expected_content in actual_content, (
            'The response from the /remediate endpoint did not match the expected output.\n'
            f'Expected to contain: {expected_content}\nActual response: {actual_content}'
        )
        assert response.content == backend_response, (
            'The responder did not return the exact dynamically generated backend response.'
        )

        second = requests.get(url, timeout=5)
        assert second.status_code == 200, 'The responder did not stay alive for another request.'
        assert second.content == backend_response, (
            'The second request did not return the exact backend response.'
        )

        backend_thread.join(timeout=7)
        assert not backend_thread.is_alive(), 'The responder did not complete both backend requests.'
        assert not backend_errors, f'Controlled backend failed: {backend_errors}'
        assert received_payloads == [expected_payload, expected_payload], (
            'The backend did not receive the exact revocation payload using the token '
            'from the controlled rogue process.'
        )
    finally:
        for proc in (responder, rogue):
            if proc is not None and proc.poll() is None:
                proc.kill()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
        try:
            backend.close()
        except OSError:
            pass
        kill_port_listeners(8080)
        kill_port_listeners(9000)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
