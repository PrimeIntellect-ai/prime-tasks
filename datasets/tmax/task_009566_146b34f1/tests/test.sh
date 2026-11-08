#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat <<'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import pathlib
import pwd
import re
import secrets
import socket
import subprocess
import time

ROOT = pathlib.Path('/home/user/mail_router')
SOURCE = ROOT / 'router.cpp'
BINARY = ROOT / 'router'
SUPERVISOR_CFG = ROOT / 'supervisord.conf'
HAPROXY_CFG = ROOT / 'haproxy.cfg'
SPOOL = pathlib.Path('/home/user/mail_spool')
USER = pwd.getpwnam('user')


def is_process_running(proc_name):
    try:
        output = subprocess.check_output(['ps', '-A', '-o', 'comm='], text=True)
        return proc_name in output.splitlines()
    except subprocess.CalledProcessError:
        return False


def proc_exists(pid):
    return os.path.exists(f'/proc/{pid}')


def proc_uid(pid):
    return os.stat(f'/proc/{pid}').st_uid


def proc_cmdline(pid):
    return pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')


def proc_comm(pid):
    return pathlib.Path(f'/proc/{pid}/comm').read_text().strip()


def pids_named(name):
    result = []
    for entry in pathlib.Path('/proc').iterdir():
        if entry.name.isdigit():
            try:
                if proc_comm(int(entry.name)) == name:
                    result.append(int(entry.name))
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass
    return result


def has_ancestor(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        try:
            status = pathlib.Path(f'/proc/{pid}/status').read_text()
            pid = int(re.search(r'^PPid:\s+(\d+)', status, re.M).group(1))
        except (FileNotFoundError, AttributeError):
            return False
    return pid == ancestor


def listener_inode(port):
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if local.rsplit(':', 1)[1].upper() == wanted and state == '0A':
                    return fields[9]
    raise AssertionError(f'No TCP listener on port {port}')


def listener_pid(port):
    inode = listener_inode(port)
    target = f'socket:[{inode}]'
    owners = set()
    for entry in pathlib.Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            for fd in (entry / 'fd').iterdir():
                try:
                    if os.readlink(fd) == target:
                        owners.add(int(entry.name))
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert len(owners) == 1, f'Expected one owner for port {port}, found {owners}'
    return owners.pop()


def wait_for(predicate, timeout=8.0, interval=0.05):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = predicate()
            if last:
                return last
        except (AssertionError, FileNotFoundError, ConnectionRefusedError, OSError):
            pass
        time.sleep(interval)
    raise AssertionError(f'Condition not met within {timeout}s; last value: {last!r}')


def recv_to_eof(sock):
    chunks = []
    while True:
        data = sock.recv(4096)
        if not data:
            return b''.join(chunks)
        chunks.append(data)


def request(port, data, expected):
    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(data)
        reply = recv_to_eof(sock)
    assert reply == expected, f'Expected exact reply {expected!r}, got {reply!r}'


def send_message(host, port, message, expected_reply=None):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((host, port))
        s.sendall(message.encode('utf-8'))
        reply = s.recv(1024).decode('utf-8')
        if expected_reply:
            assert expected_reply in reply, f"Expected '{expected_reply}' in reply, got '{reply}'"


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def demote():
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def exercise_executable(executable, label):
    port = free_port()
    token = secrets.token_hex(12)
    email = f'{label}-{token}@local.test'
    payload = f'payload-{secrets.token_hex(20)}'
    logfile = SPOOL / f'{email}.log'
    proc = subprocess.Popen([str(executable), str(port)], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, preexec_fn=demote)
    try:
        wait_for(lambda: listener_pid(port) == proc.pid, timeout=5)
        with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
            sock.settimeout(0.3)
            sock.sendall(f'ROUTE {email}\n'.encode())
            try:
                premature = sock.recv(1024)
                assert not premature, 'Router replied before receiving the required second line'
                raise AssertionError('Router closed before receiving the required second line')
            except socket.timeout:
                pass
            sock.settimeout(5)
            sock.sendall((payload + '\n').encode())
            assert recv_to_eof(sock) == b'DELIVERED\n'
        assert logfile.is_file()
        assert logfile.read_text() == payload + '\n'
        request(port, b'CRASH\n\n', b'BYE\n')
        assert proc.wait(timeout=5) == 1, 'CRASH must terminate the router with status 1'
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=3)
        try:
            logfile.unlink()
        except FileNotFoundError:
            pass


def assert_configs():
    for path in (SOURCE, BINARY, SUPERVISOR_CFG, HAPROXY_CFG):
        assert path.is_file() and not path.is_symlink(), f'Missing or invalid required file: {path}'
    assert os.access(BINARY, os.X_OK), 'Compiled router is not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'router must be a compiled ELF executable'
    assert SPOOL.is_dir(), 'Mail spool directory is missing'

    subprocess.run(['haproxy', '-c', '-f', str(HAPROXY_CFG)], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    text = re.sub(r'#.*', '', HAPROXY_CFG.read_text())
    assert re.search(r'^\s*bind\s+127\.0\.0\.1:8080(?:\s|$)', text, re.M | re.I)
    assert re.search(r'^\s*balance\s+roundrobin(?:\s|$)', text, re.M | re.I)
    targets = set(re.findall(r'^\s*server\s+\S+\s+127\.0\.0\.1:(900[123])(?:\s|$)', text, re.M | re.I))
    assert targets == {'9001', '9002', '9003'}, f'HAProxy backend targets are incomplete: {targets}'

    cp = configparser.RawConfigParser()
    cp.read(SUPERVISOR_CFG)
    commands = []
    for section in cp.sections():
        if not section.lower().startswith('program:'):
            continue
        command = cp.get(section, 'command', fallback='')
        count = cp.getint(section, 'numprocs', fallback=1)
        start = cp.getint(section, 'process_num_start', fallback=0)
        restart = cp.get(section, 'autorestart', fallback='false').strip().lower()
        exitcodes = {x.strip() for x in cp.get(section, 'exitcodes', fallback='0,2').split(',')}
        assert restart == 'true' or (restart == 'unexpected' and '1' not in exitcodes), \
            f'{section} will not necessarily restart after exit status 1'
        for number in range(start, start + count):
            expanded = command.replace('%(process_num)s', str(number))
            expanded = re.sub(r'%\(process_num\)(0?\d*)d',
                              lambda m: format(number, ('0' + m.group(1)) if m.group(1) else 'd'), expanded)
            commands.append(expanded)
    configured_ports = {p for cmd in commands for p in re.findall(r'(?<!\d)(900[123])(?!\d)', cmd)}
    assert configured_ports == {'9001', '9002', '9003'}, \
        f'supervisord does not configure all three router ports: {configured_ports}'


def assert_runtime_instances():
    supervisors = [p for p in pids_named('supervisord') if str(SUPERVISOR_CFG) in proc_cmdline(p)]
    assert supervisors, 'The required supervisord configuration is not running'
    supervisor = supervisors[0]
    assert proc_uid(supervisor) == USER.pw_uid, 'supervisord is not running as the unprivileged user'

    haproxies = [p for p in pids_named('haproxy') if str(HAPROXY_CFG) in proc_cmdline(p)]
    assert haproxies, 'The required HAProxy configuration is not running'
    assert any(proc_uid(p) == USER.pw_uid for p in haproxies), 'HAProxy is not running as the unprivileged user'
    assert listener_pid(8080) in haproxies, 'Port 8080 is not owned by the configured HAProxy process'

    result = {}
    binary_real = os.path.realpath(BINARY)
    for port in (9001, 9002, 9003):
        pid = listener_pid(port)
        assert os.path.realpath(f'/proc/{pid}/exe') == binary_real, f'Port {port} is not served by router'
        assert re.search(rf'(^|\s){port}(\s|$)', proc_cmdline(pid)), f'Router on {port} lacks its port argument'
        assert has_ancestor(pid, supervisor), f'Router on {port} is not supervised by supervisord'
        assert proc_uid(pid) == USER.pw_uid, f'Router on {port} is not running as the unprivileged user'
        result[port] = pid
    assert len(set(result.values())) == 3, 'Three distinct router instances are required'
    return supervisor, result


def test_artifacts_topology_round_robin_and_recovery():
    assert_configs()

    built_from_source = pathlib.Path(f'/tmp/router-source-{secrets.token_hex(8)}')
    try:
        subprocess.run(['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(built_from_source)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        exercise_executable(built_from_source, 'source')
        exercise_executable(BINARY, 'binary')
    finally:
        try:
            built_from_source.unlink()
        except FileNotFoundError:
            pass

    supervisor, original = assert_runtime_instances()

    # Three consecutive proxy connections must hit three distinct round-robin
    # backends. Each CRASH must really terminate the selected original process.
    killed = set()
    for _ in range(3):
        request(8080, b'CRASH\n\n', b'BYE\n')
        newly_dead = wait_for(lambda: {pid for pid in original.values() if not proc_exists(pid)} - killed,
                              timeout=2)
        assert len(newly_dead) == 1, f'One backend should die per CRASH, got {newly_dead}'
        killed.update(newly_dead)
    assert killed == set(original.values()), \
        'Three consecutive connections did not rotate across all three original backends'

    def restarted_instances():
        _, current = assert_runtime_instances()
        if all(current[p] != original[p] for p in original):
            return current
        return None

    restarted = wait_for(restarted_instances, timeout=10)
    assert len(set(restarted.values())) == 3

    # Exercise the live proxy with unpredictable addresses and payloads.
    for _ in range(7):
        email = f'probe-{secrets.token_hex(10)}@local.test'
        payload = f'message-{secrets.token_hex(24)}'
        logfile = SPOOL / f'{email}.log'
        request(8080, f'ROUTE {email}\n{payload}\n'.encode(), b'DELIVERED\n')
        assert logfile.read_text() == payload + '\n'
        logfile.unlink()


def test_processes_running():
    """Verify that supervisord and haproxy are running."""
    assert is_process_running('supervisord'), 'supervisord is not running'
    assert is_process_running('haproxy'), 'haproxy is not running'


def test_mail_routing_and_recovery():
    """Original routing, crashing, recovery, and file-output assertions."""
    host = '127.0.0.1'
    port = 8080
    send_message(host, port, 'ROUTE user1@test.com\nHello 1\n', 'DELIVERED\n')
    send_message(host, port, 'ROUTE user2@test.com\nHello 2\n', 'DELIVERED\n')
    send_message(host, port, 'CRASH\n\n', 'BYE\n')
    time.sleep(2)
    send_message(host, port, 'ROUTE user1@test.com\nHello 3\n', 'DELIVERED\n')

    user1_log = '/home/user/mail_spool/user1@test.com.log'
    assert os.path.isfile(user1_log), f'{user1_log} does not exist.'
    with open(user1_log) as f:
        content1 = f.read()
    assert 'Hello 1\n' in content1, "user1 log missing 'Hello 1'"
    assert 'Hello 3\n' in content1, "user1 log missing 'Hello 3'"

    user2_log = '/home/user/mail_spool/user2@test.com.log'
    assert os.path.isfile(user2_log), f'{user2_log} does not exist.'
    with open(user2_log) as f:
        content2 = f.read()
    assert 'Hello 2\n' in content2, "user2 log missing 'Hello 2'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
