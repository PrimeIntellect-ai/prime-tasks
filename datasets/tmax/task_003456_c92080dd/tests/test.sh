#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier controls the required serial bridge.
pkill -f '[m]ock_router.py' 2>/dev/null || true
if command -v fuser >/dev/null 2>&1; then
    fuser -k 5000/tcp >/dev/null 2>&1 || true
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shlex
import socket
import subprocess
import threading
import traceback

import pytest

SCRIPT = '/home/user/deploy.py'
V1 = '/home/user/deployments/v1.conf'
V2 = '/home/user/deployments/v2.conf'
ACTIVE = '/home/user/deployments/active'
STATE = '/home/user/router_state.json'
AUDIT_LOG = '/tmp/pexpect_spawn_audit.jsonl'


def _router_session(listener, expected_lines, result):
    conn = None
    stream = None
    try:
        listener.settimeout(20)
        conn, _ = listener.accept()
        conn.settimeout(10)
        stream = conn.makefile('rb')

        def send(data):
            conn.sendall(data)

        def receive():
            data = stream.readline()
            if not data:
                raise AssertionError('Router client disconnected unexpectedly')
            return data.decode('utf-8', errors='replace').rstrip('\r\n')

        send(b'Username: ')
        assert receive() == 'admin', 'Incorrect router username'
        send(b'Password: ')
        assert receive() == 'enable_secret', 'Incorrect router password'
        send(b'edge-router# ')

        assert receive() == 'configure terminal', "Missing 'configure terminal' command"
        send(b'edge-router(config)# ')

        staged = []
        for expected in expected_lines:
            command = receive()
            assert command == expected, f'Expected configuration line {expected!r}, got {command!r}'
            staged.append(command)
            send(b'edge-router(config)# ')

        assert receive() == 'commit', "Missing 'commit' command"
        with open(STATE, 'w') as f:
            json.dump({'active_config': staged}, f)
        send(b'Commit successful.\r\nedge-router(config)# ')

        assert receive() == 'exit', "Missing 'exit' command after commit"
        send(b'edge-router# ')
        assert receive() == 'logout', "Missing 'logout' command"
        send(b'Logged out\r\n')
        result['completed'] = True
    except Exception:
        result['error'] = traceback.format_exc()
    finally:
        if stream is not None:
            stream.close()
        if conn is not None:
            conn.close()
        listener.close()


def _used_pexpect_to_spawn_telnet():
    if not os.path.isfile(AUDIT_LOG):
        return False
    with open(AUDIT_LOG, 'r') as f:
        records = [json.loads(line) for line in f if line.strip()]

    for record in records:
        command = record.get('command', '')
        arguments = record.get('args', [])
        try:
            tokens = shlex.split(command)
        except ValueError:
            continue
        tokens.extend(str(value) for value in arguments)
        if len(tokens) >= 3 and os.path.basename(tokens[0]) == 'telnet' and tokens[1:3] == ['localhost', '5000']:
            return True
    return False


@pytest.fixture(scope='session', autouse=True)
def execute_deployment_script():
    assert os.path.isfile(SCRIPT), f'Expected deployment script {SCRIPT} does not exist.'
    assert not os.path.islink(SCRIPT), f'Expected {SCRIPT} to be a regular Python script, not a symlink.'

    with open(SCRIPT, 'r') as f:
        source = f.read()
    try:
        ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT} is not valid Python: {exc}')

    with open(V2, 'r') as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    if os.path.lexists(ACTIVE):
        os.unlink(ACTIVE)
    os.symlink(V1, ACTIVE)
    if os.path.exists(STATE):
        os.unlink(STATE)
    if os.path.exists(AUDIT_LOG):
        os.unlink(AUDIT_LOG)

    audit_dir = '/tmp/pexpect_audit'
    os.makedirs(audit_dir, exist_ok=True)
    with open(os.path.join(audit_dir, 'sitecustomize.py'), 'w') as f:
        f.write(r'''import json
import os
import pexpect

_real_spawn = pexpect.spawn
_log = os.environ.get('PEXPECT_AUDIT_LOG')

def audited_spawn(command, args=[], *pargs, **kwargs):
    def text(value):
        if isinstance(value, bytes):
            return value.decode('utf-8', errors='replace')
        return os.fspath(value) if isinstance(value, os.PathLike) else str(value)
    with open(_log, 'a') as audit:
        audit.write(json.dumps({'command': text(command), 'args': [text(v) for v in (args or [])]}) + '\n')
    return _real_spawn(command, args, *pargs, **kwargs)

pexpect.spawn = audited_spawn
''')

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 5000))
    listener.listen(1)
    result = {'completed': False}
    thread = threading.Thread(target=_router_session, args=(listener, expected_lines, result), daemon=True)
    thread.start()

    env = os.environ.copy()
    env['PEXPECT_AUDIT_LOG'] = AUDIT_LOG
    env['PYTHONPATH'] = audit_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    try:
        completed = subprocess.run(
            ['python3', SCRIPT], cwd='/home/user', env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=30
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f'{SCRIPT} timed out while deploying: {exc.stdout or ""}')

    thread.join(timeout=10)
    assert not thread.is_alive(), 'Router interaction did not finish.'
    assert completed.returncode == 0, f'{SCRIPT} exited with status {completed.returncode}:\n{completed.stdout}'
    assert _used_pexpect_to_spawn_telnet(), 'deploy.py did not use pexpect.spawn to launch telnet localhost 5000.'
    assert result.get('completed'), result.get('error', 'Required router interaction was not completed.')
    yield


def test_symlink_points_to_v2():
    symlink_path = '/home/user/deployments/active'
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."

    target = os.readlink(symlink_path)
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    expected_target = '/home/user/deployments/v2.conf'

    assert resolved_target == expected_target, (
        f"Symlink {symlink_path} points to {resolved_target}, expected {expected_target}."
    )


def test_router_state_json_matches_v2_conf():
    state_file = '/home/user/router_state.json'
    v2_conf_file = '/home/user/deployments/v2.conf'

    assert os.path.isfile(state_file), f"Expected router state file {state_file} does not exist. Did the commit succeed?"
    assert os.path.isfile(v2_conf_file), f"Expected configuration file {v2_conf_file} is missing."

    with open(v2_conf_file, 'r') as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    with open(state_file, 'r') as f:
        try:
            state_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {state_file} is not valid JSON.")

    assert "active_config" in state_data, f"'active_config' key missing from {state_file}."

    actual_config = state_data["active_config"]
    assert actual_config == expected_lines, (
        f"The committed configuration in {state_file} does not match the contents of {v2_conf_file}.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_config}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
