#!/bin/bash
mkdir -p /logs/verifier

cat << 'PREP_EOF' > /tmp/prepare_deploy_test.py
import json
import os
import shutil
import signal
import stat
import tarfile
import tempfile
import time
import uuid

# Stop any server left by the agent's initial deployment so the submitted
# deployment script must recreate the complete state itself.
pids = []
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    try:
        with open(f'/proc/{entry}/cmdline', 'rb') as f:
            cmdline = f.read()
        if b'server.py' in cmdline:
            os.kill(int(entry), signal.SIGTERM)
            pids.append(int(entry))
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass

time.sleep(1)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass

shutil.rmtree('/home/user/app', ignore_errors=True)
try:
    os.unlink('/home/user/deploy.log')
except FileNotFoundError:
    pass

# Replace the archive with an equivalent fresh fixture containing unpredictable
# files. This verifies that deploy.py really extracts the supplied archive and
# applies permission hardening to every directly contained file.
token = uuid.uuid4().hex
bin_probe = f'probe_{token}.dat'
config_probe = f'probe_{token}.conf'
bin_content = f'bin-probe-{token}\n'
config_content = f'config-probe-{token}\n'

server_source = '''#!/usr/bin/env python3
import configparser
import http.server
import os
import socketserver
import sys

config_path = os.path.join(os.path.dirname(__file__), '../config/worker.ini')
config = configparser.ConfigParser()
config.read(config_path)
try:
    port = int(config['Service']['Port'])
except KeyError:
    sys.exit(1)

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
    httpd.serve_forever()
'''

with tempfile.TemporaryDirectory() as root:
    bin_dir = os.path.join(root, 'bin')
    config_dir = os.path.join(root, 'config')
    os.makedirs(bin_dir)
    os.makedirs(config_dir)

    server_path = os.path.join(bin_dir, 'server.py')
    with open(server_path, 'w') as f:
        f.write(server_source)
    os.chmod(server_path, 0o755)

    with open(os.path.join(bin_dir, bin_probe), 'w') as f:
        f.write(bin_content)
    os.chmod(os.path.join(bin_dir, bin_probe), 0o644)

    with open(os.path.join(config_dir, 'worker.ini'), 'w') as f:
        f.write('[Unit]\nDescription=Mock Worker\n\n[Service]\nPort=8080\n')
    os.chmod(os.path.join(config_dir, 'worker.ini'), 0o644)

    with open(os.path.join(config_dir, config_probe), 'w') as f:
        f.write(config_content)
    os.chmod(os.path.join(config_dir, config_probe), 0o666)

    with tarfile.open('/home/user/source.tar.gz', 'w:gz') as archive:
        archive.add(bin_dir, arcname='bin')
        archive.add(config_dir, arcname='config')

with open('/tmp/deploy_probe.json', 'w') as f:
    json.dump({
        'bin_probe': bin_probe,
        'config_probe': config_probe,
        'bin_content': bin_content,
        'config_content': config_content,
    }, f)
PREP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import configparser
import json
import os
import re
import stat
import urllib.error
import urllib.request


def test_deploy_script_exists_and_is_python():
    path = "/home/user/deploy.py"
    assert os.path.exists(path), f"Deployment script {path} does not exist."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular file."
    with open(path, "r") as f:
        ast.parse(f.read(), filename=path)


def test_deploy_log_and_process():
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"Deployment log {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in deploy.log, found {len(lines)}."
    assert lines[0] == "[SUCCESS] Extracted files", "Line 1 of deploy.log is incorrect."
    assert lines[1] == "[SUCCESS] Permissions hardened", "Line 2 of deploy.log is incorrect."
    assert lines[2] == "[SUCCESS] Config updated", "Line 3 of deploy.log is incorrect."

    match = re.match(r"\[SUCCESS\] Service running on PID (\d+)", lines[3])
    assert match, "Line 4 of deploy.log does not match expected format."

    pid = int(match.group(1))

    cmdline_path = f"/proc/{pid}/cmdline"
    assert os.path.exists(cmdline_path), f"Process with PID {pid} is not running."

    with open(cmdline_path, "r") as f:
        cmdline = f.read().replace('\x00', ' ')

    assert "server.py" in cmdline, f"Process {pid} does not appear to be server.py. Cmdline: {cmdline}"


def test_server_running_on_port_9090():
    url = "http://127.0.0.1:9090/"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode('utf-8')
            assert body == "OK", f"Expected response 'OK', got '{body}'"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to server on port 9090: {e}"


def test_permissions():
    bin_dir = "/home/user/app/bin"
    config_dir = "/home/user/app/config"

    assert os.path.isdir(bin_dir), f"{bin_dir} does not exist."
    assert os.path.isdir(config_dir), f"{config_dir} does not exist."

    for filename in os.listdir(bin_dir):
        filepath = os.path.join(bin_dir, filename)
        if os.path.isfile(filepath):
            mode = stat.S_IMODE(os.stat(filepath).st_mode)
            assert mode == 0o500, f"File {filepath} has permissions {oct(mode)}, expected 0o500."

    for filename in os.listdir(config_dir):
        filepath = os.path.join(config_dir, filename)
        if os.path.isfile(filepath):
            mode = stat.S_IMODE(os.stat(filepath).st_mode)
            assert mode == 0o400, f"File {filepath} has permissions {oct(mode)}, expected 0o400."


def test_archive_was_extracted():
    with open('/tmp/deploy_probe.json', 'r') as f:
        probe = json.load(f)

    bin_path = os.path.join('/home/user/app/bin', probe['bin_probe'])
    config_path = os.path.join('/home/user/app/config', probe['config_probe'])

    assert os.path.isfile(bin_path), "The fresh archive's bin probe was not extracted."
    assert os.path.isfile(config_path), "The fresh archive's config probe was not extracted."
    with open(bin_path, 'r') as f:
        assert f.read() == probe['bin_content'], "Extracted bin probe content is incorrect."
    with open(config_path, 'r') as f:
        assert f.read() == probe['config_content'], "Extracted config probe content is incorrect."


def test_config_updated():
    config_path = "/home/user/app/config/worker.ini"
    assert os.path.isfile(config_path), f"Config file {config_path} does not exist."

    try:
        config = configparser.ConfigParser()
        config.read(config_path)
    except Exception as e:
        assert False, f"Failed to parse {config_path}: {e}"

    assert "Unit" in config, "Missing [Unit] section in worker.ini"
    assert "Service" in config, "Missing [Service] section in worker.ini"
    assert config.get("Unit", "After", fallback="") == "network.target", "After=network.target missing or incorrect in [Unit] section."
    assert config.get("Service", "Port", fallback="") == "9090", "Port=9090 missing or incorrect in [Service] section."
TEST_EOF

if python3 - <<'CHECK_EOF'
import ast
import os
import stat
path = '/home/user/deploy.py'
assert os.path.exists(path), f'{path} does not exist'
assert stat.S_ISREG(os.lstat(path).st_mode), f'{path} is not a regular file'
with open(path, 'r') as f:
    ast.parse(f.read(), filename=path)
CHECK_EOF
then
    if python3 /tmp/prepare_deploy_test.py \
       && timeout 20s python3 /home/user/deploy.py </dev/null >/tmp/deploy_execution.out 2>&1 \
       && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        echo "1" > /logs/verifier/reward.txt
    else
        echo "0" > /logs/verifier/reward.txt
    fi
else
    echo "0" > /logs/verifier/reward.txt
fi
