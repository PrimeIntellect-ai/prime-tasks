#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import socket
import stat
import subprocess
import threading
import time
import uuid
from pathlib import Path

BASE = Path('/home/user/migration')
FSTAB = BASE / 'fstab_mock'
MONITOR = BASE / 'monitor.py'
WRAPPER = BASE / 'run_monitor.sh'
LOGS = BASE / 'logs'


class ListeningPort:
    def __init__(self, port=0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', port))
        self.port = self.sock.getsockname()[1]
        self.sock.listen(8)
        self.sock.settimeout(0.1)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def _serve(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.sock.accept()
                conn.close()
            except socket.timeout:
                pass
            except OSError:
                break

    def __enter__(self):
        self.thread.start()
        return self.port

    def __exit__(self, exc_type, exc, tb):
        self.stop.set()
        self.sock.close()
        self.thread.join(timeout=1)


class ClosedPort:
    """Reserve a TCP port without listening, so connection attempts are refused."""
    def __init__(self, port=0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', port))
        self.port = self.sock.getsockname()[1]

    def __enter__(self):
        return self.port

    def __exit__(self, exc_type, exc, tb):
        self.sock.close()


def run(command, env=None):
    result = subprocess.run(
        command,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_json(path):
    with open(path, 'r') as f:
        return json.load(f)


def test_scripts_are_executed_and_behave_correctly():
    assert WRAPPER.is_file(), f"Wrapper script {WRAPPER} does not exist."
    assert bool(WRAPPER.stat().st_mode & stat.S_IXUSR), f"Wrapper script {WRAPPER} is not executable."
    assert MONITOR.is_file(), f"Python script {MONITOR} does not exist."

    # Verify that the wrapper creates the logs directory, exports the exact
    # LOG_DIR value, and actually executes monitor.py.
    original_monitor = MONITOR.read_bytes()
    original_mode = MONITOR.stat().st_mode
    marker = Path('/tmp/wrapper_monitor_probe.json')
    marker.unlink(missing_ok=True)
    shutil.rmtree(LOGS, ignore_errors=True)
    probe = '''#!/usr/bin/env python3
import json, os
with open("/tmp/wrapper_monitor_probe.json", "w") as f:
    json.dump({"log_dir": os.environ.get("LOG_DIR"), "logs_exists": os.path.isdir("/home/user/migration/logs")}, f)
'''
    try:
        MONITOR.write_text(probe)
        MONITOR.chmod(0o755)
        env = os.environ.copy()
        env['LOG_DIR'] = '/tmp/incorrect_inherited_log_dir'
        run([str(WRAPPER)], env=env)
        assert marker.is_file(), 'run_monitor.sh did not execute /home/user/migration/monitor.py.'
        probe_result = read_json(marker)
        assert probe_result['log_dir'] == '/home/user/migration/logs', 'Wrapper did not explicitly export the required LOG_DIR.'
        assert probe_result['logs_exists'] is True, 'Wrapper did not create the logs directory before executing monitor.py.'
    finally:
        MONITOR.write_bytes(original_monitor)
        os.chmod(MONITOR, stat.S_IMODE(original_mode))
        marker.unlink(missing_ok=True)

    token = uuid.uuid4().hex
    mount1 = Path(f'/home/user/monitor_test_{token}_one')
    mount2 = Path(f'/home/user/monitor_test_{token}_two')
    custom_output = Path(f'/tmp/monitor_output_{token}')
    decoy_output = Path(f'/tmp/monitor_decoy_{token}')
    shutil.rmtree(mount1, ignore_errors=True)
    shutil.rmtree(mount2, ignore_errors=True)
    shutil.rmtree(custom_output, ignore_errors=True)
    shutil.rmtree(decoy_output, ignore_errors=True)
    custom_output.mkdir()

    with ListeningPort() as reachable_port, ClosedPort() as closed_port:
        FSTAB.write_text(
            f'{mount1} ext4 {reachable_port}\n'
            f'{mount2} xfs {closed_port}\n'
        )
        expected = {
            str(mount1): {'fs_type': 'ext4', 'backup_reachable': True},
            str(mount2): {'fs_type': 'xfs', 'backup_reachable': False},
        }

        # Execute monitor.py directly with a caller-supplied LOG_DIR. This
        # checks parsing, directory creation, TCP diagnostics, and env handling.
        env = os.environ.copy()
        env['LOG_DIR'] = str(custom_output)
        run(['python3', str(MONITOR)], env=env)
        assert mount1.is_dir(), f'{mount1} was not created by monitor.py.'
        assert mount2.is_dir(), f'{mount2} was not created by monitor.py.'
        assert read_json(custom_output / 'status.json') == expected

        # With LOG_DIR absent, monitor.py must use /tmp.
        Path('/tmp/status.json').unlink(missing_ok=True)
        shutil.rmtree(mount1)
        shutil.rmtree(mount2)
        env = os.environ.copy()
        env.pop('LOG_DIR', None)
        run(['python3', str(MONITOR)], env=env)
        assert mount1.is_dir() and mount2.is_dir(), 'monitor.py did not recreate configured mount directories.'
        assert read_json('/tmp/status.json') == expected

        # Execute the restored real wrapper on derived inputs and ensure it
        # overrides an inherited LOG_DIR rather than writing to the decoy.
        shutil.rmtree(LOGS, ignore_errors=True)
        shutil.rmtree(mount1)
        shutil.rmtree(mount2)
        env = os.environ.copy()
        env['LOG_DIR'] = str(decoy_output)
        run([str(WRAPPER)], env=env)
        assert LOGS.is_dir(), 'Wrapper did not create /home/user/migration/logs.'
        assert read_json(LOGS / 'status.json') == expected
        assert not (decoy_output / 'status.json').exists(), 'Wrapper failed to override inherited LOG_DIR.'

    # Restore the exact required configuration and produce the required final
    # report while controlling the promised 8081/8082 service states.
    required_fstab = '/home/user/data_vol1 ext4 8081\n/home/user/data_vol2 xfs 8082\n'
    FSTAB.write_text(required_fstab)
    shutil.rmtree('/home/user/data_vol1', ignore_errors=True)
    shutil.rmtree('/home/user/data_vol2', ignore_errors=True)
    shutil.rmtree(LOGS, ignore_errors=True)

    with ListeningPort(8081), ClosedPort(8082):
        env = os.environ.copy()
        env['LOG_DIR'] = '/tmp/another_incorrect_log_dir'
        run([str(WRAPPER)], env=env)

    assert FSTAB.read_text() == required_fstab


def test_run_monitor_sh_exists_and_executable():
    path = '/home/user/migration/run_monitor.sh'
    assert os.path.isfile(path), f'Wrapper script {path} does not exist.'
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Wrapper script {path} is not executable.'


def test_monitor_py_exists():
    path = '/home/user/migration/monitor.py'
    assert os.path.isfile(path), f'Python script {path} does not exist.'


def test_mount_directories_created():
    assert os.path.isdir('/home/user/data_vol1'), 'Directory /home/user/data_vol1 was not created.'
    assert os.path.isdir('/home/user/data_vol2'), 'Directory /home/user/data_vol2 was not created.'


def test_status_json_exists_and_correct():
    path = '/home/user/migration/logs/status.json'
    assert os.path.isfile(path), f'JSON output file {path} does not exist. Ensure the wrapper script creates the logs directory and sets LOG_DIR properly.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {path} does not contain valid JSON.'

    expected = {
        '/home/user/data_vol1': {
            'fs_type': 'ext4',
            'backup_reachable': True
        },
        '/home/user/data_vol2': {
            'fs_type': 'xfs',
            'backup_reachable': False
        }
    }

    assert data == expected, f'JSON content in {path} does not match expected output.\nExpected: {expected}\nGot: {data}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
