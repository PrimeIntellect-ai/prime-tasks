#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HOME = Path('/home/user')
DEPLOY = HOME / 'deploy_pipeline.py'
MONITOR = HOME / 'monitor.py'
WIZARD = HOME / 'config_wizard.py'
SERVER = HOME / 'server.py'
CONF = HOME / 'app.conf'
LOG = HOME / 'deployment_status.log'


def pids_listening_on(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except (OSError, PermissionError):
            continue
    return pids


def stop_port(port):
    pids = pids_listening_on(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and pids_listening_on(port):
        time.sleep(0.05)
    for pid in pids_listening_on(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def wait_for_status(expected_environment, timeout=6):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen('http://localhost:8123/status', timeout=1) as response:
                data = json.loads(response.read().decode('utf-8'))
                if response.status == 200 and data.get('status') == 'ok' and data.get('environment') == expected_environment:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f'Server did not become healthy for {expected_environment!r}: {last_error}')


def run_script(path, timeout=15):
    result = subprocess.run(
        [sys.executable, str(path)],
        cwd=str(HOME),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
    )
    assert result.returncode == 0, f'{path} exited with status {result.returncode}'


def test_00_scripts_actually_implement_and_execute_automation():
    for path in (DEPLOY, MONITOR):
        assert path.exists(), f'{path} does not exist.'
        assert path.is_file(), f'{path} is not a regular file.'
        assert path.stat().st_size > 0, f'{path} is empty.'
        source = path.read_text()
        compile(source, str(path), 'exec')

    wizard_original = WIZARD.read_bytes()
    server_original = SERVER.read_bytes()
    wizard_mode = stat.S_IMODE(WIZARD.stat().st_mode)
    server_mode = stat.S_IMODE(SERVER.stat().st_mode)
    wizard_marker = Path('/tmp/wizard_invocation.json')
    server_marker = Path('/tmp/server_invocation.txt')
    request_marker = Path('/tmp/monitor_request.txt')

    probe_wizard = r'''#!/usr/bin/env python3
import json
import sys
print("Starting configuration wizard...")
print("Environment Name: ", end="", flush=True)
env = sys.stdin.readline().strip()
print("Port Number: ", end="", flush=True)
port = sys.stdin.readline().strip()
with open('/tmp/wizard_invocation.json', 'w') as f:
    json.dump({'environment': env, 'port': port}, f)
with open('/home/user/app.conf', 'w') as f:
    f.write(f"ENV={env}\nPORT={port}\n")
print("Configuration saved to app.conf.")
'''
    probe_server = r'''#!/usr/bin/env python3
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

env = 'unknown'
port = 8000
with open('/home/user/app.conf') as f:
    for line in f:
        if line.startswith('ENV='):
            env = line.strip().split('=', 1)[1]
        elif line.startswith('PORT='):
            port = int(line.strip().split('=', 1)[1])
with open('/tmp/server_invocation.txt', 'w') as f:
    f.write(str(os.getpid()))
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok', 'environment': env}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass
HTTPServer(('localhost', port), Handler).serve_forever()
'''

    try:
        stop_port(8123)
        for path in (CONF, LOG, wizard_marker, server_marker, request_marker):
            try:
                path.unlink()
            except FileNotFoundError:
                pass

        WIZARD.write_text(probe_wizard)
        SERVER.write_text(probe_server)
        os.chmod(WIZARD, 0o755)
        os.chmod(SERVER, 0o755)

        run_script(DEPLOY)
        assert wizard_marker.exists(), 'deploy_pipeline.py did not execute /home/user/config_wizard.py.'
        invocation = json.loads(wizard_marker.read_text())
        assert invocation == {'environment': 'production', 'port': '8123'}, \
            f'deploy_pipeline.py supplied incorrect wizard input: {invocation}'
        assert CONF.exists(), 'The invoked configuration wizard did not create app.conf.'
        assert 'ENV=production' in CONF.read_text()
        assert 'PORT=8123' in CONF.read_text()
        wait_for_status('production')
        assert server_marker.exists(), 'deploy_pipeline.py did not start /home/user/server.py.'
        server_pid = int(server_marker.read_text().strip())
        os.kill(server_pid, 0)

        LOG.unlink(missing_ok=True)
        run_script(MONITOR)
        expected = '[HEALTHY] Service running on port 8123 in production mode'
        assert expected in LOG.read_text().splitlines(), 'monitor.py did not write the required health entry.'

        # Exercise the monitor against a response chosen by the verifier so a
        # hard-coded production log cannot pass the dynamic parsing requirement.
        stop_port(8123)
        dynamic_environment = 'probe_' + uuid.uuid4().hex[:10]
        CONF.write_text(f'ENV={dynamic_environment}\nPORT=8123\n')
        LOG.unlink(missing_ok=True)
        dynamic_server = Path('/tmp/dynamic_status_server.py')
        dynamic_server.write_text(r'''import json, sys
from http.server import HTTPServer, BaseHTTPRequestHandler
environment = sys.argv[1]
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open('/tmp/monitor_request.txt', 'w') as f:
            f.write(self.path)
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok', 'environment': environment}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass
HTTPServer(('localhost', 8123), Handler).serve_forever()
''')
        proc = subprocess.Popen(
            [sys.executable, str(dynamic_server), dynamic_environment],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            wait_for_status(dynamic_environment)
            request_marker.unlink(missing_ok=True)
            run_script(MONITOR)
            assert request_marker.read_text() == '/status', 'monitor.py did not request /status.'
            dynamic_expected = f'[HEALTHY] Service running on port 8123 in {dynamic_environment} mode'
            assert dynamic_expected in LOG.read_text().splitlines(), \
                'monitor.py did not dynamically use the health response/configuration values.'
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    finally:
        stop_port(8123)
        WIZARD.write_bytes(wizard_original)
        SERVER.write_bytes(server_original)
        os.chmod(WIZARD, wizard_mode)
        os.chmod(SERVER, server_mode)

    # Re-run the submitted pipeline and monitor with the real supplied artifacts,
    # leaving the required real server running for the original final-state tests.
    CONF.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    run_script(DEPLOY)
    wait_for_status('production')
    run_script(MONITOR)


def test_app_conf_exists_and_correct():
    conf_path = "/home/user/app.conf"
    assert os.path.exists(conf_path), f"{conf_path} does not exist. The config_wizard.py was likely not run correctly."

    with open(conf_path, 'r') as f:
        content = f.read()

    assert "ENV=production" in content, "app.conf does not contain the correct ENV value."
    assert "PORT=8123" in content, "app.conf does not contain the correct PORT value."


def test_server_running_and_serving_status():
    url = "http://localhost:8123/status"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Server returned status {response.status} instead of 200."
            data = json.loads(response.read().decode('utf-8'))
            assert data.get("status") == "ok", "Server response JSON does not contain 'status': 'ok'."
            assert data.get("environment") == "production", "Server response JSON does not contain 'environment': 'production'."
    except urllib.error.URLError as e:
        assert False, f"Could not connect to the server on port 8123: {e}. Is the server running in the background?"


def test_deployment_status_log():
    log_path = "/home/user/deployment_status.log"
    assert os.path.exists(log_path), f"{log_path} does not exist. Did monitor.py create it?"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_log = "[HEALTHY] Service running on port 8123 in production mode"
    assert expected_log in content, f"Log content does not match the expected string. Found: {content}"


def test_student_scripts_exist():
    deploy_script = "/home/user/deploy_pipeline.py"
    monitor_script = "/home/user/monitor.py"

    assert os.path.exists(deploy_script), f"{deploy_script} does not exist."
    assert os.path.exists(monitor_script), f"{monitor_script} does not exist."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
