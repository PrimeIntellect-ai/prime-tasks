#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/deploy_edge.py')
CLI = Path('/home/user/mock_device_cli.py')
SERVICE = Path('/home/user/edge_service.py')
CONFIG = Path('/home/user/config.json')
BACKUP = Path('/home/user/backup/data_backup.tar.gz')
REPORT = Path('/home/user/deploy_report.json')
SENSOR = Path('/home/user/sensor_data')
STATE = Path('/tmp/deploy_verifier_state')
CLI_EVENT = STATE / 'cli_event.json'
TERM_EVENT = STATE / 'termination_event.json'
SERVICE_EVENT = STATE / 'service_event.json'
OLD_PID_FILE = STATE / 'old_pid'

EXPECTED_FILES = {
    'readings.txt': b'sensor_1: verifier-73921\n',
    'nested/calibration.bin': b'calibration-verifier-18467\x00\x01',
    'nested/status.txt': b'deployment challenge data\n',
}


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            cols = line.split()
            if len(cols) >= 10 and cols[3] == '0A':
                try:
                    local_port = int(cols[1].rsplit(':', 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port:
                    inodes.add(cols[9])
    result = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(proc.name))
        except (OSError, PermissionError):
            pass
    return result


def stop_existing_listeners():
    pids = listener_pids(8080)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    assert not listener_pids(8080), 'Could not clear port 8080 before the deployment test'


def archive_contains_expected(path):
    if not path.is_file() or not tarfile.is_tarfile(path):
        return False
    try:
        with tarfile.open(path, 'r:gz') as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            for relative, expected in EXPECTED_FILES.items():
                normalized = relative.replace(os.sep, '/')
                matches = [m for m in members if m.name.lstrip('./') == normalized or m.name.rstrip('/').endswith('/' + normalized)]
                if not matches:
                    return False
                extracted = tar.extractfile(matches[0])
                if extracted is None or extracted.read() != expected:
                    return False
        return True
    except (OSError, tarfile.TarError):
        return False


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert SCRIPT.is_file(), 'Required automation script /home/user/deploy_edge.py is missing'
    assert os.access(SCRIPT, os.X_OK), 'deploy_edge.py must be executable'

    source = SCRIPT.read_text()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f'deploy_edge.py is not valid Python: {exc}')

    imported_pexpect = False
    imported_spawn_names = set()
    spawn_calls = []
    expect_calls = []
    send_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == 'pexpect' for alias in node.names):
                imported_pexpect = True
        elif isinstance(node, ast.ImportFrom) and node.module == 'pexpect':
            imported_pexpect = True
            for alias in node.names:
                if alias.name == 'spawn':
                    imported_spawn_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute):
                if isinstance(func.value, ast.Name) and func.value.id == 'pexpect' and func.attr == 'spawn':
                    spawn_calls.append(node)
                if func.attr == 'expect':
                    expect_calls.append(node)
                if func.attr in ('send', 'sendline'):
                    send_calls.append(node)
            elif isinstance(func, ast.Name) and func.id in imported_spawn_names:
                spawn_calls.append(node)

    assert imported_pexpect, 'deploy_edge.py must import and use pexpect'
    assert spawn_calls, 'deploy_edge.py must use pexpect.spawn for the legacy CLI'
    assert expect_calls, 'deploy_edge.py must wait for prompts with pexpect expect calls'
    assert send_calls, 'deploy_edge.py must send responses through the pexpect child'
    assert '/home/user/mock_device_cli.py' in source, 'deploy_edge.py must launch the supplied legacy CLI'
    assert '/home/user/edge_service.py' in source, 'deploy_edge.py must launch the supplied edge service'

    stop_existing_listeners()
    shutil.rmtree(STATE, ignore_errors=True)
    STATE.mkdir(parents=True)
    shutil.rmtree(SENSOR, ignore_errors=True)
    SENSOR.mkdir(parents=True)
    for relative, contents in EXPECTED_FILES.items():
        target = SENSOR / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(contents)

    for artifact in (CONFIG, BACKUP, REPORT):
        try:
            artifact.unlink()
        except FileNotFoundError:
            pass
    BACKUP.parent.mkdir(parents=True, exist_ok=True)

    original_cli = STATE / 'original_mock_device_cli.py'
    original_service = STATE / 'original_edge_service.py'
    shutil.copy2(CLI, original_cli)
    shutil.copy2(SERVICE, original_service)

    cli_wrapper = f'''#!/usr/bin/env python3
import json, os, subprocess, sys, time
original = {str(original_cli)!r}
tty = os.isatty(0)
rc = subprocess.call([sys.executable, original])
event = {{"tty": tty, "returncode": rc, "completed_ns": time.time_ns()}}
with open({str(CLI_EVENT)!r}, "w") as f:
    json.dump(event, f)
sys.exit(rc)
'''
    service_wrapper = f'''#!/usr/bin/env python3
import json, os, sys, time
pid = int(open({str(OLD_PID_FILE)!r}).read())
alive = False
try:
    state = open(f"/proc/{{pid}}/stat").read().split()[2]
    alive = state != "Z"
except (OSError, IndexError):
    alive = False
with open({str(SERVICE_EVENT)!r}, "w") as f:
    json.dump({{"launched_ns": time.time_ns(), "old_process_alive": alive}}, f)
os.execv(sys.executable, [sys.executable, {str(original_service)!r}])
'''

    old_server_source = f'''import json, os, signal, sys, tarfile, time
from http.server import BaseHTTPRequestHandler, HTTPServer
expected = {{
    "readings.txt": {EXPECTED_FILES['readings.txt']!r},
    "nested/calibration.bin": {EXPECTED_FILES['nested/calibration.bin']!r},
    "nested/status.txt": {EXPECTED_FILES['nested/status.txt']!r},
}}
def archive_ok(path):
    try:
        with tarfile.open(path, "r:gz") as tar:
            files = [m for m in tar.getmembers() if m.isfile()]
            for rel, data in expected.items():
                found = [m for m in files if m.name.lstrip("./") == rel or m.name.rstrip("/").endswith("/" + rel)]
                if not found:
                    return False
                f = tar.extractfile(found[0])
                if f is None or f.read() != data:
                    return False
        return True
    except Exception:
        return False
def stopped(signum, frame):
    config_ok = False
    try:
        with open({str(CONFIG)!r}) as f:
            config_ok = json.load(f) == {{"device_id": "EDGE-404", "telemetry": True, "port": 8080}}
    except Exception:
        pass
    cli_ok = os.path.isfile({str(CLI_EVENT)!r})
    event = {{"signal": signum, "terminated_ns": time.time_ns(), "config_ready": config_ok,
             "cli_completed": cli_ok, "backup_ready": archive_ok({str(BACKUP)!r})}}
    with open({str(TERM_EVENT)!r}, "w") as f:
        json.dump(event, f)
    sys.exit(0)
signal.signal(signal.SIGTERM, stopped)
signal.signal(signal.SIGINT, stopped)
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"OLD-SERVICE")
    def log_message(self, *args):
        pass
server = HTTPServer(("127.0.0.1", 8080), H)
open({str(STATE / 'old_ready')!r}, "w").write("ready")
server.serve_forever()
'''

    old_server = None
    try:
        CLI.write_text(cli_wrapper)
        SERVICE.write_text(service_wrapper)
        CLI.chmod(0o755)
        SERVICE.chmod(0o755)

        old_server = subprocess.Popen([sys.executable, '-c', old_server_source], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        OLD_PID_FILE.write_text(str(old_server.pid))
        deadline = time.time() + 3
        while time.time() < deadline and not (STATE / 'old_ready').exists():
            if old_server.poll() is not None:
                pytest.fail('The verifier could not start its previous listener')
            time.sleep(0.05)
        assert (STATE / 'old_ready').exists(), 'Previous listener did not become ready'

        output_file = STATE / 'deployment_output.txt'
        with output_file.open('wb') as output:
            proc = subprocess.Popen([sys.executable, str(SCRIPT)], cwd='/home/user', stdout=output, stderr=subprocess.STDOUT)
            try:
                rc = proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                pytest.fail('deploy_edge.py did not finish within 15 seconds')
        output_text = output_file.read_text(errors='replace')
        assert rc == 0, f'deploy_edge.py exited with status {rc}. Output:\n{output_text}'

        try:
            old_server.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail('deploy_edge.py did not terminate the previous port-8080 listener')

        assert CLI_EVENT.is_file(), 'The submitted script did not execute the supplied legacy CLI'
        cli_event = json.loads(CLI_EVENT.read_text())
        assert cli_event['tty'] is True, 'The legacy CLI was not run through a terminal/pexpect session'
        assert cli_event['returncode'] == 0, 'The pexpect interaction did not complete successfully'

        assert TERM_EVENT.is_file(), 'The previous listener was not terminated safely with SIGTERM or SIGINT'
        term_event = json.loads(TERM_EVENT.read_text())
        assert term_event['config_ready'], 'The old listener was terminated before interactive configuration completed'
        assert term_event['cli_completed'], 'The old listener was terminated before the legacy CLI completed'
        assert term_event['backup_ready'], 'The old listener was terminated before the complete sensor-data backup existed'
        assert cli_event['completed_ns'] <= BACKUP.stat().st_mtime_ns, 'The backup was created before interactive configuration completed'

        assert SERVICE_EVENT.is_file(), 'The submitted script did not start /home/user/edge_service.py'
        service_event = json.loads(SERVICE_EVENT.read_text())
        assert not service_event['old_process_alive'], 'The new service was started before the old listener terminated'
        assert term_event['terminated_ns'] <= service_event['launched_ns'], 'Service lifecycle operations occurred out of order'
    finally:
        if original_cli.exists():
            shutil.copy2(original_cli, CLI)
        if original_service.exists():
            shutil.copy2(original_service, SERVICE)
        if old_server is not None and old_server.poll() is None:
            old_server.terminate()
            try:
                old_server.wait(timeout=1)
            except subprocess.TimeoutExpired:
                old_server.kill()
                old_server.wait()

    yield


def test_config_json_exists():
    config_path = '/home/user/config.json'
    assert os.path.isfile(config_path), f'Expected configuration file is missing: {config_path}'
    with open(config_path, 'r') as f:
        try:
            config_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {config_path} is not valid JSON.')
    assert config_data.get('device_id') == 'EDGE-404', 'Incorrect device_id in config.json'
    assert config_data.get('telemetry') is True, 'Incorrect telemetry setting in config.json'
    assert config_data.get('port') == 8080, 'Incorrect port in config.json'


def test_backup_tarball_created():
    backup_path = '/home/user/backup/data_backup.tar.gz'
    assert os.path.isfile(backup_path), f'Backup tarball missing: {backup_path}'
    assert tarfile.is_tarfile(backup_path), f'File {backup_path} is not a valid tar archive.'
    with tarfile.open(backup_path, 'r:gz') as tar:
        names = tar.getnames()
        assert any('readings.txt' in name for name in names), 'Backup archive does not contain readings.txt'
    assert archive_contains_expected(Path(backup_path)), 'Backup archive does not contain the complete challenged sensor_data directory'


def test_deploy_report_json():
    report_path = '/home/user/deploy_report.json'
    assert os.path.isfile(report_path), f'Deployment report missing: {report_path}'
    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {report_path} is not valid JSON.')
    assert report_data.get('config_generated') is True, "Report 'config_generated' should be True."
    assert report_data.get('backup_created') is True, "Report 'backup_created' should be True."
    assert report_data.get('health_status') == 'OK-EDGE-ACTIVE', "Report 'health_status' does not match expected output."


def test_service_is_running_and_healthy():
    url = 'http://127.0.0.1:8080/health'
    try:
        req = urllib.request.urlopen(url, timeout=2)
        resp = req.read().decode('utf-8')
        assert resp == 'OK-EDGE-ACTIVE', f'Service responded with unexpected payload: {resp}'
        assert req.getcode() == 200, f'Service responded with unexpected status code: {req.getcode()}'
    except urllib.error.URLError as e:
        pytest.fail(f'Failed to connect to service at {url}: {e}')
    except Exception as e:
        pytest.fail(f'Unexpected error during health check: {e}')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
