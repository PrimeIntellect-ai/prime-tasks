#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import json
import pytest

def test_deploy_script_exists_and_executable():
    """Check if deploy.sh exists and has executable permissions."""
    path = "/home/user/deploy.sh"
    assert os.path.exists(path), f"File {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

def test_config_file_correct():
    """Check if the config file was created and formatted correctly."""
    path = "/home/user/config/site_users.ini"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) > 0, f"File {path} is empty."
    assert lines[0] == "[Users]", f"First line of {path} is not exactly '[Users]'."

    expected_entries = {"alice=editor", "bob=viewer", "charlie=admin"}
    actual_entries = set(lines[1:])

    for entry in expected_entries:
        assert entry in actual_entries, f"Expected entry '{entry}' not found in {path}."

def test_archive_directory_correct():
    """Check if the archive directory exists and contains the processed files."""
    archive_dir = "/home/user/archive"
    assert os.path.isdir(archive_dir), f"Directory {archive_dir} does not exist."

    expected_files = ["alice.txt", "bob.txt", "charlie.txt"]
    for f in expected_files:
        filepath = os.path.join(archive_dir, f)
        assert os.path.exists(filepath), f"File {filepath} was not moved to the archive."

def test_requests_directory_empty():
    """Check if the processed files were removed from the requests directory."""
    requests_dir = "/home/user/requests"
    assert os.path.isdir(requests_dir), f"Directory {requests_dir} does not exist."

    expected_missing = ["alice.txt", "bob.txt", "charlie.txt"]
    for f in expected_missing:
        filepath = os.path.join(requests_dir, f)
        assert not os.path.exists(filepath), f"File {filepath} still exists in the requests directory."

def test_idp_received_log():
    """Check if the mock IdP received the correct JSON payloads."""
    log_path = "/home/user/idp_received.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist. Did the script successfully POST to the mock IdP through the SSH tunnel?"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    parsed_logs = []
    for line in lines:
        try:
            parsed_logs.append(json.loads(line))
        except json.JSONDecodeError:
            pass

    expected_logs = [
        {"username": "alice", "role": "editor"},
        {"username": "bob", "role": "viewer"},
        {"username": "charlie", "role": "admin"}
    ]

    for expected in expected_logs:
        assert expected in parsed_logs, f"Expected JSON payload {expected} not found in {log_path}."
TEST_EOF

cat << 'INTEGRATION_EOF' > /tmp/test_dynamic_pipeline.py
import http.server
import json
import os
import secrets
import socket
import subprocess
import threading
import time

REQUESTS = "/home/user/requests"
ARCHIVE = "/home/user/archive"
CONFIG = "/home/user/config/site_users.ini"


def socket_owner_is_sshd(conn):
    local_ip, local_port = conn.getsockname()[:2]
    peer_ip, peer_port = conn.getpeername()[:2]
    wanted_inode = None

    def encode_ip(ip):
        return ''.join(f'{int(part):02X}' for part in ip.split('.')[::-1])

    wanted_local = f"{encode_ip(local_ip)}:{local_port:04X}"
    wanted_peer = f"{encode_ip(peer_ip)}:{peer_port:04X}"
    try:
        with open('/proc/net/tcp') as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1] == wanted_local and fields[2] == wanted_peer:
                    wanted_inode = fields[9]
                    break
    except OSError:
        return False

    if not wanted_inode:
        return False
    target = f"socket:[{wanted_inode}]"
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f'{fd_dir}/{fd}') == target:
                        with open(f'/proc/{pid}/comm') as f:
                            comm = f.read().strip()
                        with open(f'/proc/{pid}/cmdline', 'rb') as f:
                            cmd = f.read().replace(b'\0', b' ').decode(errors='replace')
                        return comm == 'sshd' or 'sshd:' in cmd or '/sshd ' in cmd
                except (OSError, PermissionError):
                    pass
        except (OSError, PermissionError):
            pass
    return False


received = []
lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length)
        through_sshd = socket_owner_is_sshd(self.connection)
        try:
            body = json.loads(raw.decode('utf-8'))
        except Exception:
            body = None
        record = {
            'path': self.path,
            'content_type': self.headers.get('Content-Type'),
            'body': body,
            'through_sshd': through_sshd,
        }
        with lock:
            received.append(record)
        with open('/home/user/idp_received.log', 'a') as f:
            f.write(raw.decode('utf-8', errors='replace') + '\n')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

    def log_message(self, *args):
        pass


def port_is_listening(port):
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[1] == wanted and fields[3] == '0A':
                        return True
        except OSError:
            pass
    return False


assert not port_is_listening(9090), 'Local port 9090 was already occupied before deploy.sh was run.'

suffix = secrets.token_hex(6)
expected = {
    f'dynamic_{suffix}_one': 'editor',
    f'dynamic_{suffix}_two': 'viewer',
}
os.makedirs(REQUESTS, exist_ok=True)
for username, role in expected.items():
    path = os.path.join(REQUESTS, username + '.txt')
    with open(path, 'w') as f:
        f.write(f'role: {role}\n')
    os.chown(path, 1000, 1000)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 8000), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    result = subprocess.run(
        ['timeout', '40s', 'runuser', '-u', 'user', '--',
         'env', 'HOME=/home/user', 'USER=user', '/home/user/deploy.sh'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)

assert result.returncode == 0, (
    f'deploy.sh failed with status {result.returncode}.\n'
    f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
)

with open(CONFIG) as f:
    lines = [line.strip() for line in f if line.strip()]
assert lines and lines[0] == '[Users]'
for username, role in expected.items():
    assert f'{username}={role}' in lines, f'Fresh user {username} was not added to the config.'
    request_path = os.path.join(REQUESTS, username + '.txt')
    archive_path = os.path.join(ARCHIVE, username + '.txt')
    assert not os.path.exists(request_path), f'Fresh request {request_path} was not removed.'
    assert os.path.isfile(archive_path), f'Fresh request {archive_path} was not archived.'
    with open(archive_path) as f:
        assert f.read().strip() == f'role: {role}'

with lock:
    records = list(received)
for username, role in expected.items():
    matches = [r for r in records if r['body'] == {'username': username, 'role': role}]
    assert matches, f'No POST was received for fresh user {username}.'
    assert any(r['path'] == '/sync' for r in matches), f'Wrong HTTP path for {username}.'
    assert any(r['content_type'] == 'application/json' for r in matches), f'Wrong Content-Type for {username}.'
    assert any(r['through_sshd'] for r in matches), (
        f'The POST for {username} did not reach port 8000 through an SSH server connection.'
    )

for _ in range(50):
    if not port_is_listening(9090):
        break
    time.sleep(0.1)
assert not port_is_listening(9090), 'The SSH tunnel on port 9090 was not terminated after processing.'
INTEGRATION_EOF

# Restore the SSH authentication permissions that sshd requires; setup originally
# made the whole home tree world-writable after creating the key.
chown user:user /home/user /home/user/.ssh /home/user/.ssh/id_rsa /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys /home/user/.ssh/config 2>/dev/null
chmod 755 /home/user
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/id_rsa /home/user/.ssh/authorized_keys /home/user/.ssh/config
chmod 644 /home/user/.ssh/id_rsa.pub
mkdir -p /run/sshd
ssh-keygen -A >/dev/null 2>&1
pgrep -x sshd >/dev/null 2>&1 || /usr/sbin/sshd
pkill -f '[m]ock_idp.py' >/dev/null 2>&1
sleep 0.2

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_dynamic_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
