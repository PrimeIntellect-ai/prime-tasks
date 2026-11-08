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

cat << 'TEST_EOF' > /tmp/test_workflow.py
import os
import re
import stat
import tarfile
import subprocess
import time

import pytest
import requests

IMAGE = "/app/config_snapshot.png"
BACKUP = "/app/backup/backend_backup.tar.gz"
SOCKET = "/app/run/app_backend.sock"
CONFIG = "/app/nginx/nginx.conf"
EXPECT_SCRIPT = "/app/automate_init.exp"

EXPECTED_INIT = '''#!/bin/bash
read -p "Enter PIN: " pin
expected_pin="$(tesseract /app/config_snapshot.png stdout 2>/dev/null | sed -n 's/.*Init PIN:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p' | head -n 1)"
if [ "$pin" == "$expected_pin" ]; then
    echo "PIN verified. Writing token..."
    echo "AUTH_OK" > /app/backend/.auth_token
else
    echo "Invalid PIN."
    exit 1
fi
'''.encode()

EXPECTED_SERVER = '''import argparse
import os
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--socket', required=True)
args = parser.parse_args()

flask_app = """
from flask import Flask
import os

app = Flask(__name__)

@app.route('/status')
def status():
    auth_token = "MISSING"
    if os.path.exists("/app/backend/.auth_token"):
        with open("/app/backend/.auth_token", "r") as f:
            auth_token = f.read().strip()
    return f"AUTH_OK" if auth_token == "AUTH_OK" else "FAIL"
"""
with open("/app/backend/app.py", "w") as f:
    f.write(flask_app)

print(f"Starting gunicorn on unix:{args.socket}")
subprocess.run(["gunicorn", "--bind", f"unix:{args.socket}", "app:app"], cwd="/app/backend")
'''.encode()


def recovered_values():
    text = subprocess.check_output(
        ["tesseract", IMAGE, "stdout"], stderr=subprocess.DEVNULL, text=True
    )
    socket_match = re.search(r"Backend\s+Socket\s*:\s*(/\S+\.sock)", text, re.I)
    pin_match = re.search(r"Init\s+PIN\s*:\s*([0-9]+)", text, re.I)
    assert socket_match, f"OCR did not recover a backend socket from: {text!r}"
    assert pin_match, f"OCR did not recover an Init PIN from: {text!r}"
    return socket_match.group(1), pin_match.group(1)


def processes():
    result = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='replace').strip()
            uid = os.stat(f'/proc/{name}').st_uid
            result.append((int(name), uid, cmd))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def pids_holding_inode(inode):
    holders = set()
    target = f'socket:[{inode}]'
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f'{fd_dir}/{fd}') == target:
                        holders.add(int(name))
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    return holders


def tcp_listener_inode(port):
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].rsplit(':', 1)[1].upper() == wanted and fields[3] == '0A':
                    return fields[9]
    return None


def unix_listener_inode(path):
    with open('/proc/net/unix') as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == path:
                return fields[6]
    return None


def test_complete_required_workflow():
    socket_path, pin = recovered_values()
    assert socket_path == SOCKET

    # Keep the original backup assertions and additionally verify that it is a
    # pre-initialization copy of the complete original backend with metadata.
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} does not exist."
    try:
        with tarfile.open(BACKUP, 'r:gz') as tar:
            members = tar.getmembers()
            assert members, 'Tar archive is empty.'
            assert any('server.py' in m.name or 'init.sh' in m.name for m in members), \
                'Backup does not seem to contain the backend files.'
            regular = [m for m in members if m.isfile()]
            by_base = {os.path.basename(m.name): m for m in regular}
            assert set(by_base) == {'init.sh', 'server.py'}, \
                f"Backup is not the original entire backend; files were {sorted(by_base)}"
            assert tar.extractfile(by_base['init.sh']).read() == EXPECTED_INIT
            assert tar.extractfile(by_base['server.py']).read() == EXPECTED_SERVER
            assert by_base['init.sh'].mode == 0o755
            assert by_base['server.py'].mode == 0o644
            assert by_base['init.sh'].uid == by_base['server.py'].uid == 0
            assert by_base['init.sh'].gid == by_base['server.py'].gid == 0
            assert '.auth_token' not in by_base and 'app.py' not in by_base
    except tarfile.TarError as e:
        pytest.fail(f"Backup file {BACKUP} is not a valid gzip-compressed tarball: {e}")

    assert open('/app/backend/init.sh', 'rb').read() == EXPECTED_INIT, \
        'The supplied initialization program was replaced or modified.'
    assert open('/app/backend/server.py', 'rb').read() == EXPECTED_SERVER, \
        'The supplied backend server was replaced or modified.'

    # Validate and actually execute the requested expect automation using the
    # PIN independently recovered from the image.
    assert os.path.isfile(EXPECT_SCRIPT), f"Missing expect script {EXPECT_SCRIPT}"
    expect_text = open(EXPECT_SCRIPT, errors='replace').read()
    assert re.search(r'\bspawn\b[^\n]*(?:/app/backend/)?init\.sh', expect_text), \
        'Expect script does not spawn /app/backend/init.sh.'
    assert re.search(r'\bexpect\b[^\n]*(?:Enter PIN|PIN)', expect_text, re.I), \
        'Expect script does not wait for the PIN prompt.'
    assert re.search(r'\bsend\b[^\n]*' + re.escape(pin), expect_text), \
        'Expect script does not send the OCR-recovered PIN.'

    token = '/app/backend/.auth_token'
    if os.path.lexists(token):
        os.unlink(token)
    run = subprocess.run(
        ['expect', EXPECT_SCRIPT], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=15
    )
    assert run.returncode == 0, f"Expect initialization failed:\n{run.stdout}"
    assert 'PIN verified' in run.stdout, f"init.sh success was not observed:\n{run.stdout}"
    assert os.path.isfile(token) and open(token).read().strip() == 'AUTH_OK', \
        'Executing the expect script did not generate the authorization token.'
    assert os.path.getmtime(BACKUP) <= os.path.getmtime(token), \
        'Backup is newer than the initialization token.'

    # Keep the original socket assertions.
    assert os.path.exists(socket_path), f"Socket file {socket_path} does not exist."
    file_stat = os.stat(socket_path)
    assert stat.S_ISSOCK(file_stat.st_mode), f"{socket_path} is not a Unix socket."
    permissions = file_stat.st_mode & 0o777
    assert permissions == 0o666, f"Expected socket permissions 666, got {oct(permissions)}."

    # Keep the original nginx configuration assertions.
    assert os.path.isfile(CONFIG), f"Nginx config {CONFIG} does not exist."
    content = open(CONFIG).read()
    assert 'wrong.sock' not in content
    assert socket_path in content
    assert re.search(r'proxy_pass\s+http://unix:' + re.escape(socket_path) + r'\s*;', content), \
        'The proxy_pass directive does not target the recovered socket.'

    procs = {pid: (uid, cmd) for pid, uid, cmd in processes()}
    backend_pids = {
        pid for pid, (uid, cmd) in procs.items()
        if '/app/backend/server.py' in cmd and '--socket' in cmd and socket_path in cmd
    }
    assert backend_pids, 'No running python3 /app/backend/server.py process uses the recovered socket.'

    unix_inode = unix_listener_inode(socket_path)
    assert unix_inode, 'The recovered Unix socket is not an active listening socket.'
    unix_holders = pids_holding_inode(unix_inode)
    assert any(pid in procs and 'gunicorn' in procs[pid][1] and 'app:app' in procs[pid][1]
               for pid in unix_holders), \
        'The Unix listener is not held by the gunicorn service launched by server.py.'

    tcp_inode = tcp_listener_inode(8080)
    assert tcp_inode, 'Nothing is listening on TCP port 8080.'
    tcp_holders = pids_holding_inode(tcp_inode)
    nginx_holders = [pid for pid in tcp_holders if pid in procs and 'nginx' in procs[pid][1]]
    assert nginx_holders, 'Port 8080 is not owned by Nginx.'
    nginx_commands = [(uid, cmd) for pid, (uid, cmd) in procs.items() if 'nginx' in cmd]
    assert any(uid != 0 and '-p /app/nginx' in cmd and '-c nginx.conf' in cmd
               for uid, cmd in nginx_commands), \
        'Nginx was not started as non-root with -p /app/nginx -c nginx.conf.'

    # Keep the original end-to-end HTTP assertions after establishing which
    # processes own both listeners.
    url = 'http://127.0.0.1:8080/status'
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e}")
    assert response.status_code == 200, \
        f"Expected HTTP 200, got {response.status_code}: {response.text}"
    assert 'AUTH_OK' in response.text, \
        f"Expected AUTH_OK in response, got: {response.text}"
TEST_EOF

if python3 -m pytest /tmp/test_workflow.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
