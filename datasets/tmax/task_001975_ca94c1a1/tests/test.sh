#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path

import pytest

HOME = Path('/home/user')
PROJECT = HOME / 'monitor_src'
SOURCE = PROJECT / 'src/main.rs'
DEPLOY_SCRIPT = HOME / 'deploy.sh'
STAGING = HOME / 'deploy/staging/monitor'
PRODUCTION = HOME / 'deploy/production/monitor'
TARGET = PROJECT / 'target/release/monitor'
LOG = HOME / 'deployment.log'
SPOOL = HOME / 'mail_spool'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def run_as_user(cmd, timeout=600):
    return run(['runuser', '-u', 'user', '--'] + cmd, timeout=timeout)


def wait_port(port, open_expected=True, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.25)
        try:
            connected = sock.connect_ex(('127.0.0.1', port)) == 0
        finally:
            sock.close()
        if connected == open_expected:
            return True
        time.sleep(0.1)
    return False


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def clear_spool():
    SPOOL.mkdir(parents=True, exist_ok=True)
    for entry in SPOOL.iterdir():
        if entry.is_dir():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def valid_alert_files():
    result = []
    for path in SPOOL.iterdir():
        if not path.is_file():
            continue
        content = path.read_text(errors='ignore')
        has_subject = 'Subject: ALERT: Service Down' in content
        has_from = ('From: sre@localhost' in content or
                    'From: <sre@localhost>' in content)
        has_to = ('To: admin@localhost' in content or
                  'To: <admin@localhost>' in content)
        if has_subject and has_from and has_to:
            result.append(path)
    return result


def test_complete_rust_deployment_and_monitor_behavior():
    dummy = None
    error_server = None
    try:
        assert SOURCE.is_file(), f'Rust source {SOURCE} does not exist.'
        assert DEPLOY_SCRIPT.is_file(), f'Deployment script {DEPLOY_SCRIPT} does not exist.'

        script = DEPLOY_SCRIPT.read_text(errors='ignore')
        assert re.search(r'(^|\n)\s*set\s+-[^\n]*e', script), 'deploy.sh does not enable immediate error handling.'
        assert re.search(r'cargo\s+build\s+--release', script), 'deploy.sh does not run cargo build --release.'

        subprocess.run(['chown', '-R', 'user:user', str(PROJECT),
                        str(HOME / 'deploy'), str(SPOOL)], check=True)

        # Independently compile the submitted Rust source, then force deploy.sh
        # to recreate and deploy that artifact.
        build = run_as_user(['cargo', 'build', '--release'], timeout=600)
        assert build.returncode == 0, f'Submitted Rust project does not compile:\n{build.stderr}'
        assert TARGET.is_file(), 'cargo build did not create target/release/monitor.'
        assert TARGET.read_bytes().startswith(b'\x7fELF'), 'Cargo output is not a native executable.'
        expected_hash = digest(TARGET)

        TARGET.unlink()
        for path in (STAGING, PRODUCTION):
            if path.exists() or path.is_symlink():
                path.unlink()
        if LOG.exists():
            LOG.unlink()

        deployed = run_as_user(['bash', str(DEPLOY_SCRIPT)], timeout=600)
        assert deployed.returncode == 0, f'deploy.sh failed:\n{deployed.stdout}\n{deployed.stderr}'

        assert TARGET.is_file(), 'deploy.sh did not recreate the release Cargo binary.'
        assert STAGING.is_file(), f'Staging binary {STAGING} does not exist.'
        assert os.access(STAGING, os.X_OK), f'Staging binary {STAGING} is not executable.'
        assert PRODUCTION.is_file(), f'Production binary {PRODUCTION} does not exist.'
        assert os.access(PRODUCTION, os.X_OK), f'Production binary {PRODUCTION} is not executable.'
        assert digest(TARGET) == expected_hash, 'deploy.sh did not build the submitted Rust source.'
        assert digest(STAGING) == expected_hash, 'Staging binary is not the compiled Rust monitor.'
        assert digest(PRODUCTION) == expected_hash, 'Production binary is not the compiled Rust monitor.'

        assert LOG.is_file(), f'Deployment log {LOG} does not exist.'
        assert 'Deployment successful' in LOG.read_text(), "The deployment.log does not contain 'Deployment successful'."

        clear_spool()
        subprocess.run(['pkill', '-u', 'user', '-x', 'ssh'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        assert wait_port(8080, False, 10), 'Port 8080 remained occupied before the tunnel test.'

        subprocess.run(['ssh-keygen', '-A'], check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        subprocess.run(['chown', '-R', 'user:user', str(HOME / '.ssh')], check=True)
        os.chmod(HOME / '.ssh', 0o700)
        for key in (HOME / '.ssh/id_ed25519', HOME / '.ssh/authorized_keys'):
            if key.exists():
                os.chmod(key, 0o600)
        subprocess.run(['/usr/sbin/sshd'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)

        subprocess.run(['pkill', '-f', '/home/user/dummy_server.py'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dummy = subprocess.Popen(['python3', str(HOME / 'dummy_server.py')],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert wait_port(9090, True, 10), 'Dummy health service did not start on port 9090.'

        tunnel = run_as_user([
            'ssh', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes',
            '-f', '-N', '-L', '127.0.0.1:8080:localhost:9090',
            'user@localhost'
        ], timeout=30)
        assert tunnel.returncode == 0, f'Could not establish the required SSH tunnel:\n{tunnel.stderr}'
        assert wait_port(8080, True, 10), 'SSH tunnel did not listen on local port 8080.'

        up = run_as_user([str(PRODUCTION)], timeout=30)
        assert up.returncode == 0, f'Monitor failed while service was healthy:\n{up.stderr}'
        assert 'Service is UP' in up.stdout, "Healthy monitor run did not print 'Service is UP'."

        subprocess.run(['pkill', '-u', 'user', '-x', 'ssh'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        assert wait_port(8080, False, 10), 'SSH tunnel did not stop.'

        clear_spool()
        down = run_as_user([str(PRODUCTION)], timeout=30)
        alerts = valid_alert_files()
        assert alerts, 'A connection failure did not generate an alert email with the required headers.'
        assert any(path.suffix == '.eml' for path in alerts), 'The monitor did not create an .eml alert file.'

        # A reachable endpoint returning non-200 must also alert.
        clear_spool()
        code = """from http.server import BaseHTTPRequestHandler,HTTPServer
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(503); self.end_headers(); self.wfile.write(b'down')
 def log_message(self,*args): pass
HTTPServer(('127.0.0.1',8080),H).serve_forever()
"""
        error_server = subprocess.Popen(['python3', '-c', code],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert wait_port(8080, True, 10), 'Could not start the non-200 test service.'
        non_200 = run_as_user([str(PRODUCTION)], timeout=30)
        alerts = valid_alert_files()
        assert alerts, 'An HTTP non-200 response did not generate an alert email with the required headers.'
        assert any(path.suffix == '.eml' for path in alerts), 'The non-200 alert was not written as an .eml file.'

        # Preserve the original final-state assertions explicitly.
        assert LOG.is_file()
        assert 'Deployment successful' in LOG.read_text()
        assert PRODUCTION.is_file() and os.access(PRODUCTION, os.X_OK)
        assert any(path.is_file() for path in SPOOL.iterdir()), f'No files found in {SPOOL}.'
        assert valid_alert_files(), 'No email file contains the correct Subject, From, and To headers.'
    finally:
        subprocess.run(['pkill', '-u', 'user', '-x', 'ssh'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        for proc in (error_server, dummy):
            if proc is not None and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
