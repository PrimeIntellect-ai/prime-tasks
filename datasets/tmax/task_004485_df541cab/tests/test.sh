#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import stat
import subprocess
import time
import urllib.request
from pathlib import Path

import pytest

PIPELINE_DIR = Path('/home/user/ci_pipeline')
AUTOMATE = PIPELINE_DIR / 'automate_setup.py'
PIPELINE = PIPELINE_DIR / 'run_pipeline.sh'
SETUP = Path('/home/user/legacy_service/setup.sh')
CONFIG = Path('/home/user/legacy_service/config.json')
PID_FILE = PIPELINE_DIR / 'service.pid'
HEALTH_LOG = PIPELINE_DIR / 'health_check.log'
EXPECTED_CONFIG = {
    'user': 'ci_admin',
    'pass': 'ci_supersecret',
    'port': 8080,
    'token': 'TOKEN_842X',
}
EXPECTED_HEALTH = {
    'status': 'ok',
    'service': 'legacy',
    'token': 'TOKEN_842X',
}


def read_pid():
    pid_str = PID_FILE.read_text().strip()
    assert pid_str.isdigit(), f'PID file {PID_FILE} does not contain a valid PID.'
    return int(pid_str)


def assert_daemon_process(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f'Process with PID {pid} is not running.')
    cmdline_path = Path(f'/proc/{pid}/cmdline')
    assert cmdline_path.is_file(), f'No process metadata exists for PID {pid}.'
    cmdline = cmdline_path.read_bytes().replace(b'\0', b' ').decode(errors='replace')
    assert '/home/user/legacy_service/daemon.py' in cmdline, (
        f'PID {pid} is not the required service daemon. Command line: {cmdline}'
    )


def assert_config_correct():
    assert CONFIG.is_file(), f'File {CONFIG} is missing.'
    try:
        config = json.loads(CONFIG.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'File {CONFIG} is not valid JSON.')
    assert config.get('user') == 'ci_admin', 'Config user is incorrect.'
    assert config.get('pass') == 'ci_supersecret', 'Config pass is incorrect.'
    assert str(config.get('port')) == '8080', 'Config port is incorrect.'
    assert config.get('token') == 'TOKEN_842X', 'Config token is incorrect.'


def test_venv_exists():
    path = '/home/user/ci_pipeline/venv/bin/python'
    assert os.path.isfile(path) or os.path.isfile('/home/user/ci_pipeline/venv/bin/python3'), f'Virtual environment python executable not found at {path}'


def test_automate_setup_exists():
    path = '/home/user/ci_pipeline/automate_setup.py'
    assert os.path.isfile(path), f'File {path} is missing.'
    with open(path, 'r') as f:
        content = f.read()
    assert 'pexpect' in content, f'File {path} does not appear to use pexpect.'


def test_run_pipeline_exists_and_executable():
    path = '/home/user/ci_pipeline/run_pipeline.sh'
    assert os.path.isfile(path), f'File {path} is missing.'
    assert os.access(path, os.X_OK), f'File {path} is not executable.'


def test_config_json_correct():
    assert_config_correct()


def test_daemon_running():
    assert PID_FILE.is_file(), f'PID file {PID_FILE} is missing.'
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f'Process with PID {pid} is not running.')
    assert_daemon_process(pid)


def test_health_check_log():
    path = '/home/user/ci_pipeline/health_check.log'
    assert os.path.isfile(path), f'File {path} is missing.'
    with open(path, 'r') as f:
        content = f.read().strip()

    expected = '{"status": "ok", "service": "legacy", "token": "TOKEN_842X"}'
    try:
        log_json = json.loads(content)
        expected_json = json.loads(expected)
        assert log_json == expected_json, f'Health check log content does not match expected JSON. Got: {content}'
    except json.JSONDecodeError:
        assert content == expected, f'Health check log content does not match exactly. Got: {content}'


def test_automate_setup_interacts_with_setup_script():
    backup = Path('/tmp/setup.sh.verifier-backup')
    observed = Path('/tmp/automate_setup_observed.json')
    backup.unlink(missing_ok=True)
    observed.unlink(missing_ok=True)
    original_mode = stat.S_IMODE(SETUP.stat().st_mode)
    os.replace(SETUP, backup)
    SETUP.write_text(r'''#!/bin/bash
# Require a terminal, as supplied by pexpect, rather than accepting fabricated files or piped input.
[ -t 0 ] && [ -t 1 ] || exit 41
read -p "Enter Admin Username: " user
read -p "Enter Admin Password: " pass
read -p "Enter Service Port: " port
read -p "Enter Configuration Token: " token
cat > /tmp/automate_setup_observed.json <<JSON
{"user":"$user","pass":"$pass","port":"$port","token":"$token"}
JSON
cat > /home/user/legacy_service/config.json <<JSON
{"user":"$user","pass":"$pass","port":$port,"token":"$token"}
JSON
echo "Setup complete. Configuration saved."
''')
    SETUP.chmod(0o755)
    try:
        python = PIPELINE_DIR / 'venv/bin/python'
        if not python.is_file():
            python = PIPELINE_DIR / 'venv/bin/python3'
        result = subprocess.run(
            [str(python), str(AUTOMATE)],
            cwd=str(PIPELINE_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f'automate_setup.py failed:\n{result.stdout}'
        assert observed.is_file(), 'automate_setup.py did not execute the interactive setup script.'
        values = json.loads(observed.read_text())
        assert values == {k: str(v) for k, v in EXPECTED_CONFIG.items()}, (
            f'automate_setup.py supplied incorrect interactive answers: {values}'
        )
        assert_config_correct()
    finally:
        SETUP.unlink(missing_ok=True)
        if backup.exists():
            os.replace(backup, SETUP)
            SETUP.chmod(original_mode)
        observed.unlink(missing_ok=True)


def test_pipeline_executes_and_produces_live_deployment():
    old_pid = read_pid()
    assert_daemon_process(old_pid)
    try:
        os.kill(old_pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    time.sleep(1)

    hidden_automate = PIPELINE_DIR / '.automate_setup.verifier-original.py'
    marker = Path('/tmp/pipeline_invoked_automate')
    output = Path('/tmp/pipeline_verifier_output.log')
    hidden_automate.unlink(missing_ok=True)
    marker.unlink(missing_ok=True)
    original_mode = stat.S_IMODE(AUTOMATE.stat().st_mode)
    os.replace(AUTOMATE, hidden_automate)
    AUTOMATE.write_text('''#!/usr/bin/env python3
from pathlib import Path
import runpy
Path("/tmp/pipeline_invoked_automate").write_text("invoked")
runpy.run_path("/home/user/ci_pipeline/.automate_setup.verifier-original.py", run_name="__main__")
''')
    AUTOMATE.chmod(original_mode)

    for artifact in (CONFIG, PID_FILE, HEALTH_LOG):
        artifact.unlink(missing_ok=True)

    try:
        with output.open('w') as stream:
            result = subprocess.run(
                [str(PIPELINE)],
                cwd=str(PIPELINE_DIR),
                stdout=stream,
                stderr=subprocess.STDOUT,
                timeout=180,
            )
        diagnostic = output.read_text(errors='replace')
        assert result.returncode == 0, f'run_pipeline.sh failed:\n{diagnostic}'
        assert marker.is_file(), 'run_pipeline.sh did not execute automate_setup.py.'
    finally:
        AUTOMATE.unlink(missing_ok=True)
        if hidden_automate.exists():
            os.replace(hidden_automate, AUTOMATE)
            AUTOMATE.chmod(original_mode)

    python = PIPELINE_DIR / 'venv/bin/python'
    if not python.is_file():
        python = PIPELINE_DIR / 'venv/bin/python3'
    assert python.is_file(), 'The pipeline did not leave a Python virtual environment.'
    imported = subprocess.run([str(python), '-c', 'import pexpect'], timeout=15)
    assert imported.returncode == 0, 'pexpect is not installed in the pipeline virtual environment.'

    assert_config_correct()
    assert PID_FILE.is_file(), f'PID file {PID_FILE} is missing after running the pipeline.'
    new_pid = read_pid()
    assert_daemon_process(new_pid)
    assert new_pid != old_pid, 'The pipeline did not start a new service daemon.'

    assert HEALTH_LOG.is_file(), f'File {HEALTH_LOG} is missing after running the pipeline.'
    logged_bytes = HEALTH_LOG.read_bytes()
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=5) as response:
            assert response.status == 200
            live_bytes = response.read()
    except Exception as exc:
        pytest.fail(f'The required live health endpoint is unavailable: {exc}')

    assert logged_bytes == live_bytes, (
        'health_check.log is not the exact standard output returned by the live health endpoint.'
    )
    assert json.loads(live_bytes.decode()) == EXPECTED_HEALTH

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
