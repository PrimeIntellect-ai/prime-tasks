#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_netmon.py
import os
import pwd
import socket
import subprocess
import threading
import time
import uuid
from pathlib import Path

import pytest

BASE = Path('/home/user/netmon')
CHECKER = BASE / 'check_ports'
SOURCE = BASE / 'check_ports.c'
TRIGGER = BASE / 'trigger_alert.sh'
INIT = BASE / 'netmon-init.sh'
CONFIG = BASE / 'services.conf'
USERS = BASE / 'valid_users.txt'
LOG = BASE / 'alerts.log'
PIDFILE = BASE / 'netmon.pid'
ACCOUNT = pwd.getpwnam('user')


def demote():
    os.setgid(ACCOUNT.pw_gid)
    os.setuid(ACCOUNT.pw_uid)


def run_user(argv, timeout=10, check=False):
    result = subprocess.run(
        [str(x) for x in argv],
        cwd=str(BASE),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
        preexec_fn=demote,
    )
    if check and result.returncode != 0:
        raise AssertionError(f'{argv[0]} exited with status {result.returncode}')
    return result


def write_inputs(users, entries):
    USERS.write_text(''.join(f'{name}\n' for name in users))
    CONFIG.write_text(''.join(f'{port}:{owner}\n' for port, owner in entries))
    os.chmod(USERS, 0o666)
    os.chmod(CONFIG, 0o666)


def clear_log():
    try:
        LOG.unlink()
    except FileNotFoundError:
        pass


def log_lines():
    if not LOG.exists():
        return []
    return LOG.read_text().splitlines()


class ListeningPort:
    def __init__(self, port=0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', port))
        self.sock.listen(32)
        self.port = self.sock.getsockname()[1]
        self.done = False
        self.thread = threading.Thread(target=self._accept, daemon=True)
        self.thread.start()

    def _accept(self):
        self.sock.settimeout(0.2)
        while not self.done:
            try:
                conn, _ = self.sock.accept()
                conn.close()
            except socket.timeout:
                pass
            except OSError:
                return

    def close(self):
        self.done = True
        self.sock.close()
        self.thread.join(timeout=1)


class RefusedPort:
    """Reserves a TCP port without listening, so connects are refused."""
    def __init__(self, port=0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('127.0.0.1', port))
        self.port = self.sock.getsockname()[1]

    def close(self):
        self.sock.close()


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    stat = Path(f'/proc/{pid}/stat')
    if stat.exists():
        try:
            return stat.read_text().split()[2] != 'Z'
        except (OSError, IndexError):
            pass
    return True


def wait_dead(pid, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return True
        time.sleep(0.1)
    return not process_alive(pid)


def test_complete_netmon_behavior():
    # Preserve the original artifact assertions and require the requested source.
    assert CHECKER.is_file(), f'{CHECKER} does not exist. Did you compile the C program?'
    assert os.access(CHECKER, os.X_OK), f'{CHECKER} is not executable.'
    assert SOURCE.is_file(), f'{SOURCE} does not exist.'
    assert CHECKER.read_bytes()[:4] == b'\x7fELF', 'check_ports is not a compiled executable.'

    assert TRIGGER.is_file(), f'{TRIGGER} does not exist.'
    assert os.access(TRIGGER, os.X_OK), f'{TRIGGER} is not executable.'
    assert INIT.is_file(), f'{INIT} does not exist.'
    assert os.access(INIT, os.X_OK), f'{INIT} is not executable.'

    # The requested final state is stopped.
    assert not PIDFILE.exists(), f'PID file {PIDFILE} still exists. Did you properly stop the service?'

    # Exercise argument-count and user validation with unpredictable values.
    tag = uuid.uuid4().hex[:12]
    valid = f'valid_{tag}'
    invalid = f'invalid_{tag}'
    port_text = '43123'
    write_inputs([valid], [])

    for args in ([], [valid], [valid, port_text, 'extra'], [invalid, port_text]):
        clear_log()
        run_user([TRIGGER, *args])
        assert log_lines() == [], f'trigger_alert.sh produced an alert for invalid arguments {args}'

    clear_log()
    run_user([TRIGGER, valid, port_text], check=True)
    expected_direct = f'ALERT: Service for [{valid}] on port [{port_text}] is unreachable!'
    assert log_lines() == [expected_direct], 'trigger_alert.sh did not append the exact required alert.'

    # Exercise the compiled checker against one live port, one refused port,
    # and a refused service owned by a user absent from valid_users.txt.
    live = ListeningPort()
    closed = RefusedPort()
    invalid_closed = RefusedPort()
    try:
        write_inputs(
            [valid],
            [(live.port, valid), (closed.port, valid), (invalid_closed.port, invalid)],
        )
        clear_log()
        run_user([CHECKER], timeout=10, check=True)
        expected = f'ALERT: Service for [{valid}] on port [{closed.port}] is unreachable!'
        assert log_lines() == [expected], (
            'check_ports must alert exactly for the refused valid-user service, '
            'not for the live service or invalid owner.'
        )
    finally:
        live.close()
        closed.close()
        invalid_closed.close()

    # Exercise actual start/repeat/stop lifecycle behavior for over three seconds.
    live = ListeningPort()
    closed = RefusedPort()
    lifecycle_pid = None
    try:
        write_inputs([valid], [(live.port, valid), (closed.port, valid)])
        clear_log()
        if PIDFILE.exists():
            PIDFILE.unlink()

        run_user([INIT, 'bogus'])
        assert not PIDFILE.exists(), 'An unsupported init action created a PID file.'

        run_user([INIT, 'start'], timeout=5, check=True)
        assert PIDFILE.is_file(), 'start did not create netmon.pid.'
        raw_pid = PIDFILE.read_text().strip()
        assert raw_pid.isdigit() and int(raw_pid) > 1, 'netmon.pid does not contain a valid PID.'
        lifecycle_pid = int(raw_pid)
        assert process_alive(lifecycle_pid), 'The background monitoring process is not running.'
        assert Path(f'/proc/{lifecycle_pid}').stat().st_uid == ACCOUNT.pw_uid, 'Daemon was not started as the unprivileged user.'

        time.sleep(3.2)
        expected = f'ALERT: Service for [{valid}] on port [{closed.port}] is unreachable!'
        lines = log_lines()
        assert lines.count(expected) >= 2, 'The checker was not repeated approximately once per second.'
        assert all(str(live.port) not in line for line in lines), 'The lifecycle checker alerted for a live port.'
    finally:
        if PIDFILE.exists():
            run_user([INIT, 'stop'], timeout=5)
        live.close()
        closed.close()

    assert not PIDFILE.exists(), f'PID file {PIDFILE} still exists. Did you properly stop the service?'
    if lifecycle_pid is not None:
        assert wait_dead(lifecycle_pid), 'stop did not terminate the background monitoring process.'

    # Recreate and verify the original required final log. Port 8081 is made live;
    # the other configured ports are reserved without listeners and thus refused.
    fixed_live = ListeningPort(8081)
    fixed_refused = [RefusedPort(8082), RefusedPort(8083), RefusedPort(8084)]
    try:
        write_inputs(
            ['alice', 'bob'],
            [(8081, 'alice'), (8082, 'bob'), (8083, 'charlie'), (8084, 'alice')],
        )
        clear_log()
        run_user([CHECKER], timeout=10, check=True)
    finally:
        fixed_live.close()
        for reserved in fixed_refused:
            reserved.close()

    assert LOG.is_file(), f'{LOG} does not exist. Did the service run?'
    content = LOG.read_text()
    assert 'ALERT: Service for [bob] on port [8082] is unreachable!' in content, \
        'Expected alert for bob on port 8082 not found in alerts.log.'
    assert 'ALERT: Service for [alice] on port [8084] is unreachable!' in content, \
        'Expected alert for alice on port 8084 not found in alerts.log.'
    assert 'charlie' not in content, \
        'Alert for charlie found in alerts.log, but charlie is not in valid_users.txt.'
    assert '8081' not in content, \
        'Alert for port 8081 found in alerts.log, but port 8081 should be up.'
    assert not PIDFILE.exists(), f'PID file {PIDFILE} still exists. Did you properly stop the service?'
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_netmon.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
