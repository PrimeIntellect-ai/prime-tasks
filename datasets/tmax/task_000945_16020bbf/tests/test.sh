#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import time
import uuid
import pytest

COLLECTOR = '/home/user/bin/collector'
LOGGER = '/app/logger.sh'
LOG_FILE = '/home/user/logs/capacity.log'


def socket_inodes(path, port, listen_only=False):
    wanted = f'{port:04X}'
    found = set()
    try:
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                local_port = fields[1].split(':')[1].upper()
                state = fields[3]
                if local_port == wanted and (not listen_only or state == '0A'):
                    found.add(fields[9])
    except FileNotFoundError:
        pass
    return found


def pids_owning(inodes):
    owners = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
    except OSError:
        return []


def parent_pid(pid):
    try:
        with open(f'/proc/{pid}/status') as f:
            for line in f:
                if line.startswith('PPid:'):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def find_collector_pid():
    inodes = socket_inodes('/proc/net/tcp', 8888, True)
    inodes |= socket_inodes('/proc/net/tcp6', 8888, True)
    expected = os.stat(COLLECTOR)
    for pid in pids_owning(inodes):
        try:
            actual = os.stat(f'/proc/{pid}/exe')
            if (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino):
                return pid
        except OSError:
            continue
    return None


def test_compiled_collector_exists():
    assert os.path.isfile(COLLECTOR), f'Compiled executable {COLLECTOR} is missing.'
    assert os.access(COLLECTOR, os.X_OK), f'File {COLLECTOR} is not executable.'
    with open(COLLECTOR, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'collector is not a compiled ELF executable.'


def test_logger_script_updated():
    assert os.path.isfile(LOGGER), f'Logger script {LOGGER} is missing.'
    with open(LOGGER) as f:
        content = f.read()
    assert 'PORT=9090' in content, 'logger.sh was not updated to listen on port 9090.'
    assert 'PORT=9999' not in content, 'logger.sh still contains the misconfigured port 9999.'

    source = open('/app/collector.cpp').read()
    logger_target = re.search(r'send_to_logger[\s\S]*?sin_port\s*=\s*htons\((\d+)\)', source)
    assert logger_target, 'Could not derive the logger port from collector.cpp.'
    assert int(logger_target.group(1)) == 9090


def test_logrotate_config():
    config_path = '/home/user/config/logrotate.conf'
    assert os.path.isfile(config_path), f'Logrotate config {config_path} is missing.'
    with open(config_path) as f:
        content = f.read()
    assert LOG_FILE in content, 'Logrotate config missing target log file.'
    assert 'daily' in content, "Logrotate config missing 'daily' directive."
    assert 'rotate 3' in content, "Logrotate config missing 'rotate 3' directive."

    active = '\n'.join(line.split('#', 1)[0] for line in content.splitlines())
    block = re.search(re.escape(LOG_FILE) + r'\s*\{([^}]*)\}', active, re.S)
    assert block, 'No active logrotate block targets capacity.log.'
    directives = block.group(1)
    assert re.search(r'(?m)^\s*daily\s*$', directives), "'daily' is not an active directive."
    assert re.search(r'(?m)^\s*rotate\s+3\s*$', directives), "'rotate 3' is not an active directive."


def test_collector_running_in_unshare():
    pid = find_collector_pid()
    assert pid is not None, 'Port 8888 is not owned by /home/user/bin/collector.'

    process_ns = os.readlink(f'/proc/{pid}/ns/user')
    verifier_ns = os.readlink('/proc/self/ns/user')
    assert process_ns != verifier_ns, 'Collector is not running in a separate user namespace.'

    with open(f'/proc/{pid}/uid_map') as f:
        uid_map = f.read().strip()
    assert uid_map, 'Collector user namespace has no UID mapping.'


def test_logger_is_running_from_script():
    inodes = socket_inodes('/proc/net/udp', 9090)
    inodes |= socket_inodes('/proc/net/udp6', 9090)
    owners = pids_owning(inodes)
    assert owners, 'No process is listening on the collector-derived UDP port 9090.'

    launched_by_script = False
    for owner in owners:
        pid = owner
        for _ in range(8):
            args = cmdline(pid)
            if LOGGER in args:
                try:
                    exe = os.path.basename(os.readlink(f'/proc/{pid}/exe'))
                except OSError:
                    exe = ''
                if exe in ('bash', 'sh'):
                    launched_by_script = True
                    break
            pid = parent_pid(pid)
            if pid <= 1:
                break
        if launched_by_script:
            break
    assert launched_by_script, 'The UDP logger was not launched by /app/logger.sh.'


def exchange(message, expect_response=True):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect(('127.0.0.1', 8888))
        s.sendall(message)
        response = s.recv(1024)
    if expect_response:
        assert response == b'OK_RECORDED\n', \
            f"Expected response 'OK_RECORDED\\n', but got {response!r}"
    else:
        assert response == b'', f'Collector responded to an invalid report: {response!r}'


def test_tcp_collector_response_and_logger_forwarding():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    start = os.path.getsize(LOG_FILE) if os.path.exists(LOG_FILE) else 0

    fixed = b'CAPACITY_REPORT 500\n'
    nonce1 = ('CAPACITY_REPORT ' + uuid.uuid4().hex + '\n').encode()
    nonce2 = ('prefix-' + uuid.uuid4().hex + '-CAPACITY_REPORT-' + uuid.uuid4().hex + '\n').encode()

    try:
        exchange(fixed)
        exchange(nonce1)
        exchange(nonce2)
        exchange(('NOT_A_REPORT ' + uuid.uuid4().hex + '\n').encode(), False)
    except ConnectionRefusedError:
        pytest.fail('Connection refused to 127.0.0.1:8888. Is the collector running?')
    except socket.timeout:
        pytest.fail('Timeout waiting for the collector on 127.0.0.1:8888.')
    except OSError as exc:
        pytest.fail(f'Unexpected error communicating with collector: {exc}')

    deadline = time.time() + 5
    appended = b''
    while time.time() < deadline:
        if os.path.isfile(LOG_FILE):
            with open(LOG_FILE, 'rb') as f:
                f.seek(start)
                appended = f.read()
            if fixed in appended and nonce1 in appended and nonce2 in appended:
                break
        time.sleep(0.1)

    assert os.path.isfile(LOG_FILE), f'Log file {LOG_FILE} was not created by the logger.'
    assert b'CAPACITY_REPORT 500' in appended, 'The logger did not record the forwarded capacity report.'
    assert fixed in appended, 'The fixed report was not forwarded unchanged.'
    assert nonce1 in appended, 'A runtime-generated report was not forwarded unchanged.'
    assert nonce2 in appended, 'A second runtime-generated report was not forwarded unchanged.'


if __name__ == '__main__':
    raise SystemExit(pytest.main([__file__]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
