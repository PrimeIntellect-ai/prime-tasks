#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import signal
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def test_audit_trail_json_exists_and_valid():
    """Preserve the original final-state assertions."""
    audit_file = '/home/user/audit_trail.json'
    assert os.path.isfile(audit_file), f"{audit_file} does not exist."

    with open(audit_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{audit_file} does not contain valid JSON."

    assert 'httponly_flag_present' in data, "Key 'httponly_flag_present' missing in JSON."
    assert data['httponly_flag_present'] is False, "Expected 'httponly_flag_present' to be false."

    expected_hash = hashlib.sha256(b'COMPLIANCE_CONFIDENTIAL_DATA_9921').hexdigest()
    assert 'file_sha256' in data, "Key 'file_sha256' missing in JSON."
    assert data['file_sha256'] == expected_hash, f"Expected 'file_sha256' to be {expected_hash}, got {data['file_sha256']}."


def test_run_isolated_sh_exists_and_correct():
    """Preserve the original script-content assertions."""
    script_file = '/home/user/run_isolated.sh'
    assert os.path.isfile(script_file), f"{script_file} does not exist."

    with open(script_file, 'r') as f:
        content = f.read()

    assert 'bwrap' in content, "bwrap command not found in the script."
    assert '--ro-bind / /' in content, "--ro-bind / / not found in the script."
    assert '--bind /home/user/audit_trail.json /home/user/audit_trail.json' in content, "--bind for audit_trail.json not found in the script."
    assert '--share-net' in content, "--share-net not found in the script."
    assert '/usr/bin/python3 /home/user/audit.py' in content, "Command to run python script not found in the script."


def _stop_original_server():
    me = os.getpid()
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == me:
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ')
            if b'/tmp/server.py' in cmdline:
                os.kill(int(name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


def test_audit_script_performs_live_authentication_cookie_check_and_hashing():
    audit_script = '/home/user/audit.py'
    audit_file = '/home/user/audit_trail.json'
    assert os.path.isfile(audit_script), f"{audit_script} does not exist."

    _stop_original_server()
    state = {'token': '', 'body': b'', 'httponly': False, 'logins': 0, 'gets': 0}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            assert self.path == '/login'
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw)
            except Exception:
                payload = None
            if payload != {'user': 'auditor', 'pass': 'audit123'}:
                self.send_response(401)
                self.end_headers()
                return
            state['logins'] += 1
            cookie = f"session_token={state['token']}; Path=/; Secure"
            if state['httponly']:
                cookie += '; HttpOnly'
            self.send_response(200)
            self.send_header('Set-Cookie', cookie)
            self.end_headers()
            self.wfile.write(b'Success')

        def do_GET(self):
            if self.path != '/secure_data.txt':
                self.send_response(404)
                self.end_headers()
                return
            expected = f"session_token={state['token']}"
            if expected not in self.headers.get('Cookie', ''):
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b'Forbidden')
                return
            state['gets'] += 1
            self.send_response(200)
            self.end_headers()
            self.wfile.write(state['body'])

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(('127.0.0.1', 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for flag in (False, True):
            state['token'] = 'tok_' + secrets.token_hex(16)
            state['body'] = ('DYNAMIC_AUDIT_DATA_' + secrets.token_hex(24)).encode()
            state['httponly'] = flag
            before_logins, before_gets = state['logins'], state['gets']
            try:
                os.unlink(audit_file)
            except FileNotFoundError:
                pass

            result = subprocess.run(
                ['/usr/bin/python3', audit_script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
                text=True,
            )
            assert result.returncode == 0, result.stderr
            assert state['logins'] == before_logins + 1, 'audit.py did not perform the required login'
            assert state['gets'] == before_gets + 1, 'audit.py did not make an authenticated secure-data request'
            assert os.path.isfile(audit_file), 'audit.py did not create audit_trail.json'
            with open(audit_file) as f:
                data = json.load(f)
            assert set(data) == {'httponly_flag_present', 'file_sha256'}
            assert data['httponly_flag_present'] is flag
            assert data['file_sha256'] == hashlib.sha256(state['body']).hexdigest()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_run_isolated_actually_invokes_bwrap_with_required_arguments(tmp_path):
    script = '/home/user/run_isolated.sh'
    real_bwrap = '/usr/bin/bwrap'
    backup = '/usr/bin/bwrap.verifier-backup'
    capture = tmp_path / ('calls-' + secrets.token_hex(8) + '.jsonl')

    assert os.path.isfile(script)
    assert os.path.exists(real_bwrap)
    if os.path.exists(backup):
        os.unlink(backup)
    os.rename(real_bwrap, backup)
    wrapper = f'''#!/usr/bin/python3
import json, sys
with open({str(capture)!r}, 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(0)
'''
    try:
        with open(real_bwrap, 'w') as f:
            f.write(wrapper)
        os.chmod(real_bwrap, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        result = subprocess.run(
            ['/bin/bash', script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            text=True,
            env={**os.environ, 'PATH': '/usr/bin:/bin:/usr/local/bin'},
        )
        assert result.returncode == 0, result.stderr
    finally:
        try:
            os.unlink(real_bwrap)
        except FileNotFoundError:
            pass
        os.rename(backup, real_bwrap)

    assert capture.is_file(), 'run_isolated.sh did not execute bwrap'
    with open(capture) as f:
        calls = [json.loads(line) for line in f if line.strip()]

    target = '/home/user/audit_trail.json'

    def has_triplet(args, triplet):
        return any(args[i:i + 3] == list(triplet) for i in range(len(args) - 2))

    def valid(args):
        if not has_triplet(args, ('--ro-bind', '/', '/')):
            return False
        if not has_triplet(args, ('--bind', target, target)):
            return False
        if '--share-net' not in args:
            return False
        if args[-2:] != ['/usr/bin/python3', '/home/user/audit.py']:
            return False
        writable = {'--bind', '--bind-try', '--dev-bind', '--dev-bind-try'}
        for i, arg in enumerate(args):
            if arg in writable:
                if i + 2 >= len(args) or args[i:i + 3] != ['--bind', target, target]:
                    return False
        return True

    assert any(valid(args) for args in calls), 'No executed bwrap command had the required read-only root, sole writable audit file, shared network, and Python command'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
