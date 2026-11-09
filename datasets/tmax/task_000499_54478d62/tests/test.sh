#!/bin/bash
set +e
mkdir -p /logs/verifier

prepare_services() {
    cat << 'SRC_EOF' > /tmp/auth-daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void handle_client(int client_sock) {
    int is_admin = 0;
    char buffer[32];

    // Vulnerability: buffer overflow
    read(client_sock, buffer, 128);

    if (is_admin != 0) {
        write(client_sock, "ADMIN_GRANTED", 13);
    } else {
        write(client_sock, "ACCESS_DENIED", 13);
    }
    close(client_sock);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    server_addr.sin_port = htons(9000);

    if (bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        exit(1);
    }
    listen(server_sock, 5);

    while (1) {
        client_sock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        if (client_sock >= 0) {
            handle_client(client_sock);
        }
    }
    return 0;
}
SRC_EOF

    gcc -fno-stack-protector -z execstack -o /tmp/auth-daemon.reference /tmp/auth-daemon.c || return 1
    test -f /app/auth-daemon || return 1
    test -x /app/auth-daemon || return 1
    cmp -s /app/auth-daemon /tmp/auth-daemon.reference || return 1
    test -f /app/app.py || return 1
    test -f /app/nginx.conf || return 1

    # Stop anything currently occupying the required ports so the verifier can
    # execute the submitted artifacts itself rather than trusting prestarted daemons.
    python3 - << 'PY_EOF'
import os
import signal
import time

ports = {5000, 8080, 9000}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[3] != '0A':
                    continue
                port = int(fields[1].rsplit(':', 1)[1], 16)
                if port in ports:
                    inodes.add(fields[9])
    except OSError:
        pass

victims = set()
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) <= 1 or int(entry) == os.getpid():
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                victims.add(int(entry))
                break
    except OSError:
        pass

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
time.sleep(0.5)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
PY_EOF

    /app/auth-daemon >/tmp/verifier-auth.log 2>&1 &
    echo $! > /tmp/verifier-auth.pid
    python3 /app/app.py >/tmp/verifier-flask.log 2>&1 &
    echo $! > /tmp/verifier-flask.pid
    /usr/sbin/nginx -c /app/nginx.conf -g 'daemon off;' >/tmp/verifier-nginx.log 2>&1 &
    echo $! > /tmp/verifier-nginx.pid

    python3 - << 'PY_EOF'
import socket
import time

for port in (5000, 8080, 9000):
    deadline = time.time() + 5
    while True:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.25):
                break
        except OSError:
            if time.time() >= deadline:
                raise SystemExit(f'port {port} did not become ready')
            time.sleep(0.1)
PY_EOF
}

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import re
import socket
import string
import subprocess
import uuid

import flask
import pytest
import requests


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    result = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{entry}/fd'):
                target = os.readlink(f'/proc/{entry}/fd/{fd}')
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(entry))
                    break
        except OSError:
            pass
    return result


def test_submitted_artifacts_and_process_identity():
    assert os.path.isfile('/app/nginx.conf')
    assert os.path.isfile('/app/app.py')
    assert os.path.isfile('/app/auth-daemon')
    assert os.access('/app/auth-daemon', os.X_OK)

    with open('/app/auth-daemon', 'rb') as submitted, open('/tmp/auth-daemon.reference', 'rb') as reference:
        assert submitted.read() == reference.read(), 'The original auth-daemon was modified or replaced'

    daemon_pids = listener_pids(9000)
    assert daemon_pids, 'No process is listening on port 9000'
    assert any(os.path.realpath(f'/proc/{pid}/exe') == '/app/auth-daemon' for pid in daemon_pids), \
        'Port 9000 is not served by the original /app/auth-daemon executable'

    flask_pids = listener_pids(5000)
    assert flask_pids, 'No process is listening on port 5000'
    assert any('/app/app.py' in open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\\x00', b' ').decode(errors='ignore')
               for pid in flask_pids), 'Port 5000 is not served by /app/app.py'

    nginx_pids = listener_pids(8080)
    assert nginx_pids, 'No process is listening on port 8080'
    assert any(os.path.basename(os.path.realpath(f'/proc/{pid}/exe')) == 'nginx' for pid in nginx_pids), \
        'Port 8080 is not owned by Nginx'

    spec = importlib.util.spec_from_file_location('submitted_app', '/app/app.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert isinstance(getattr(module, 'app', None), flask.Flask), '/app/app.py does not define a Flask application'


def test_nginx_configuration_and_dynamic_proxying():
    proc = subprocess.run(
        ['/usr/sbin/nginx', '-T', '-c', '/app/nginx.conf'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=5
    )
    assert proc.returncode == 0, f'nginx.conf is invalid: {proc.stdout}'
    effective = re.sub(r'#.*', '', proc.stdout)
    assert re.search(r'\blisten\s+8080(?:\s|;)', effective), 'nginx.conf does not listen on port 8080'
    assert re.search(r'\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;', effective), \
        'nginx.conf does not proxy to 127.0.0.1:5000'

    path = '/verifier-' + uuid.uuid4().hex
    direct = requests.get('http://127.0.0.1:5000' + path, timeout=2)
    proxied = requests.get('http://127.0.0.1:8080' + path, timeout=2)
    assert proxied.status_code == direct.status_code
    assert proxied.content == direct.content, 'Port 8080 is not transparently routing dynamic requests to Flask'


def test_original_daemon_denies_derived_benign_inputs():
    rng = random.SystemRandom()
    for _ in range(5):
        value = ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(rng.randint(1, 16)))
        with socket.create_connection(('127.0.0.1', 9000), timeout=2) as sock:
            sock.sendall(value.encode())
            assert sock.recv(1024) == b'ACCESS_DENIED', f'Original daemon improperly granted benign input {value!r}'


def test_nginx_routing():
    """Verify Nginx is listening on 8080 and routing to the Flask app."""
    try:
        response = requests.get("http://127.0.0.1:8080/", timeout=2)
        assert response.status_code == 200, f"Expected HTTP 200 from Nginx routing to Flask, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")


def test_exploit_payload_success():
    """Verify the exploit payload triggers the ADMIN_GRANTED state in the auth daemon."""
    payload_path = "/home/user/exploit_payload.txt"
    assert os.path.isfile(payload_path), f"Exploit payload file missing at {payload_path}"

    with open(payload_path, "rb") as f:
        payload = f.read()
    assert payload, 'Exploit payload must not be empty'

    try:
        with socket.create_connection(("127.0.0.1", 9000), timeout=2) as sock:
            sock.sendall(payload)
            response = sock.recv(1024).decode('utf-8', errors='ignore')
            assert "ADMIN_GRANTED" in response, f"Payload did not trigger ADMIN_GRANTED. Daemon responded with: {response}"
    except ConnectionRefusedError:
        pytest.fail("Could not connect to auth-daemon on 127.0.0.1:9000. Is it running?")
    except socket.timeout:
        pytest.fail("Connection to auth-daemon timed out.")


def test_patch_valid_username():
    """Verify the patched Flask app accepts valid usernames."""
    try:
        response = requests.post("http://127.0.0.1:8080/check_access", data={"username": "admin"}, timeout=2)
        assert response.status_code == 200, f"Expected HTTP 200 for valid username 'admin', got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Flask app via Nginx: {e}")


def test_patch_adversarial_length():
    """Verify the patched Flask app rejects usernames exceeding 16 characters."""
    long_username = "A" * 20
    try:
        response = requests.post("http://127.0.0.1:8080/check_access", data={"username": long_username}, timeout=2)
        assert response.status_code == 400, f"Expected HTTP 400 for overly long username, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Flask app via Nginx: {e}")


def test_patch_adversarial_characters():
    """Verify the patched Flask app rejects non-alphanumeric usernames."""
    bad_username = "admin;drop"
    try:
        response = requests.post("http://127.0.0.1:8080/check_access", data={"username": bad_username}, timeout=2)
        assert response.status_code == 400, f"Expected HTTP 400 for non-alphanumeric username, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Flask app via Nginx: {e}")


def test_patch_randomized_inputs():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    for _ in range(8):
        username = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 16)))
        response = requests.post('http://127.0.0.1:8080/check_access', data={'username': username}, timeout=2)
        assert response.status_code == 200, f'Valid generated username {username!r} was rejected'

    invalid = [
        ''.join(rng.choice(alphabet) for _ in range(rng.randint(17, 40))),
        'user_' + uuid.uuid4().hex[:6],
        'name ' + uuid.uuid4().hex[:5],
        'x-' + uuid.uuid4().hex[:6],
        'é' + uuid.uuid4().hex[:5],
    ]
    for username in invalid:
        response = requests.post('http://127.0.0.1:8080/check_access', data={'username': username}, timeout=2)
        assert response.status_code == 400, f'Invalid generated username {username!r} was not rejected'

    with open('/home/user/exploit_payload.txt', 'rb') as f:
        payload = f.read()
    response = requests.post(
        'http://127.0.0.1:8080/check_access',
        data={'username': payload.decode('latin1')}, timeout=2
    )
    assert response.status_code == 400, 'The submitted exploit is not rejected by the patched Flask endpoint'
TEST_EOF

prepare_services
PREP_STATUS=$?
if [ "$PREP_STATUS" -eq 0 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

# Clean up only the verifier-started top-level processes after recording reward.
for pidfile in /tmp/verifier-nginx.pid /tmp/verifier-flask.pid /tmp/verifier-auth.pid; do
    if [ -f "$pidfile" ]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
    fi
done
exit 0
