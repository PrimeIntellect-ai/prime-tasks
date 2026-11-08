#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import sys
import uuid
from pathlib import Path

HOME = Path('/home/user')
PYTHON_SCRIPT = HOME / 'generate_fallback.py'
SETUP_SCRIPT = HOME / 'setup_monitor.sh'
LOG = HOME / 'monitor.log'
REMEDY = HOME / 'remedy.sh'


def clean_outputs():
    LOG.unlink(missing_ok=True)
    REMEDY.unlink(missing_ok=True)


def run_generator(primary_marker, fallback_marker):
    env = os.environ.copy()
    if primary_marker is None:
        env.pop('PRIMARY_IFACE', None)
    else:
        env['PRIMARY_IFACE'] = primary_marker
    if fallback_marker is None:
        env.pop('FALLBACK_IFACE', None)
    else:
        env['FALLBACK_IFACE'] = fallback_marker
    return subprocess.run(
        [sys.executable, str(PYTHON_SCRIPT)],
        env=env,
        cwd='/tmp',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_full_required_behavior_and_wrapper_execution():
    assert PYTHON_SCRIPT.is_file(), f'Python script {PYTHON_SCRIPT} is missing.'
    assert SETUP_SCRIPT.is_file(), f'Setup script {SETUP_SCRIPT} is missing.'

    # Each required variable must independently be mandatory.
    clean_outputs()
    result = run_generator(None, 'lo')
    assert result.returncode == 1, f'Missing PRIMARY_IFACE returned {result.returncode}, not 1.'

    clean_outputs()
    result = run_generator('lo', None)
    assert result.returncode == 1, f'Missing FALLBACK_IFACE returned {result.returncode}, not 1.'

    # A nonexistent primary must take the down branch, append the exact alert,
    # replace remedy contents, and make the remedy executable.
    missing_iface = 'missing_' + uuid.uuid4().hex
    assert not (Path('/sys/class/net') / missing_iface).exists()
    fallback = 'fb_' + uuid.uuid4().hex[:12]
    LOG.write_bytes(b'preexisting\n')
    REMEDY.write_bytes(b'old contents')
    os.chmod(REMEDY, 0o600)
    result = run_generator(missing_iface, fallback)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert REMEDY.read_bytes() == f'ip route replace default dev {fallback}'.encode()
    assert os.stat(REMEDY).st_mode & stat.S_IXUSR, 'Down-branch remedy is not executable.'
    assert LOG.read_bytes() == (
        b'preexisting\n' + f'[ALERT] Primary down. Generated fallback to {fallback}.\n'.encode()
    )

    # Exercise an existing interface whose state is not exactly "up".
    interfaces = []
    for entry in Path('/sys/class/net').iterdir():
        state_file = entry / 'operstate'
        if state_file.is_file():
            interfaces.append((entry.name, state_file.read_text().strip()))
    non_up = next(((name, state) for name, state in interfaces if state != 'up'), None)
    assert non_up is not None, 'Test environment has no existing non-up interface.'
    fallback2 = 'fb_' + uuid.uuid4().hex[:12]
    LOG.write_bytes(b'')
    result = run_generator(non_up[0], fallback2)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert REMEDY.read_bytes() == f'ip route replace default dev {fallback2}'.encode()
    assert LOG.read_bytes() == f'[ALERT] Primary down. Generated fallback to {fallback2}.\n'.encode()

    # Exercise the up branch using an interface whose actual operstate is "up".
    up_iface = next((name for name, state in interfaces if state == 'up'), None)
    assert up_iface is not None, 'Test environment has no interface with operstate up.'
    LOG.write_bytes(b'before-up\n')
    REMEDY.write_bytes(b'stale remedy')
    result = run_generator(up_iface, 'unused_' + uuid.uuid4().hex[:8])
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert REMEDY.is_file(), 'Up branch did not ensure remedy.sh exists.'
    assert REMEDY.read_bytes() == b'', 'Up branch did not completely empty remedy.sh.'
    assert LOG.read_bytes() == b'before-up\n[OK] Primary active.\n'

    # Replace the Python script temporarily with a probe to prove that the
    # wrapper exports the exact values and executes the required path.
    original_bytes = PYTHON_SCRIPT.read_bytes()
    original_mode = stat.S_IMODE(os.stat(PYTHON_SCRIPT).st_mode)
    marker = Path('/tmp/wrapper_probe_' + uuid.uuid4().hex + '.json')
    probe = (
        '#!/usr/bin/env python3\n'
        'import json, os\n'
        f'open({str(marker)!r}, "w").write(json.dumps([os.environ.get("PRIMARY_IFACE"), os.environ.get("FALLBACK_IFACE")]))\n'
    ).encode()
    try:
        PYTHON_SCRIPT.write_bytes(probe)
        os.chmod(PYTHON_SCRIPT, 0o755)
        env = os.environ.copy()
        env['PRIMARY_IFACE'] = 'hostile_primary'
        env['FALLBACK_IFACE'] = 'hostile_fallback'
        wrapped = subprocess.run(
            ['bash', str(SETUP_SCRIPT)],
            env=env,
            cwd='/tmp',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert wrapped.returncode == 0, wrapped.stderr.decode(errors='replace')
        assert marker.is_file(), 'setup_monitor.sh did not execute /home/user/generate_fallback.py.'
        assert json.loads(marker.read_text()) == ['dummy99', 'lo'], (
            'setup_monitor.sh did not export PRIMARY_IFACE=dummy99 and FALLBACK_IFACE=lo.'
        )
    finally:
        PYTHON_SCRIPT.write_bytes(original_bytes)
        os.chmod(PYTHON_SCRIPT, original_mode)
        marker.unlink(missing_ok=True)

    # Perform the requested final monitoring run and leave its artifacts behind.
    clean_outputs()
    final_run = subprocess.run(
        ['bash', str(SETUP_SCRIPT)],
        cwd='/tmp',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert final_run.returncode == 0, final_run.stderr.decode(errors='replace')
    assert LOG.read_bytes() == b'[ALERT] Primary down. Generated fallback to lo.\n'
    assert REMEDY.read_bytes() == b'ip route replace default dev lo'
    assert os.stat(REMEDY).st_mode & stat.S_IXUSR


# Preserve the original final-state assertions.
def test_setup_script_exists():
    script_path = '/home/user/setup_monitor.sh'
    assert os.path.isfile(script_path), f'Setup script {script_path} is missing.'


def test_python_script_exists():
    script_path = '/home/user/generate_fallback.py'
    assert os.path.isfile(script_path), f'Python script {script_path} is missing.'


def test_monitor_log_content():
    log_path = '/home/user/monitor.log'
    assert os.path.isfile(log_path), f'Log file {log_path} is missing.'
    with open(log_path, 'r') as f:
        content = f.read()
    expected_alert = '[ALERT] Primary down. Generated fallback to lo.'
    assert expected_alert in content, f'Expected alert message not found in {log_path}. Found: {content}'


def test_remedy_script_content_and_permissions():
    remedy_path = '/home/user/remedy.sh'
    assert os.path.isfile(remedy_path), f'Remedy script {remedy_path} is missing.'
    st = os.stat(remedy_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Remedy script {remedy_path} is not executable.'
    with open(remedy_path, 'r') as f:
        content = f.read().strip()
    expected_content = 'ip route replace default dev lo'
    assert content == expected_content, f'Remedy script content is incorrect. Expected: {expected_content!r}, Found: {content!r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
