#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import socket
import stat
import subprocess
import time


def assert_regular_file(path, nonempty=True):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"{path} is not a regular file"
    assert not os.path.islink(path), f"{path} must not be a symlink"
    if nonempty:
        assert st.st_size > 0, f"{path} is empty"


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            local_addr, state, inode = fields[1], fields[3], fields[9]
            address, local_port = local_addr.split(':')
            if address == '0100007F' and local_port == wanted and state == '0A':
                found.add(inode)
    return found


def owners_of_inodes(inodes):
    owners = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        for fd in fds:
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target.endswith(']'):
                inode = target[8:-1]
                if inode in inodes:
                    owners.setdefault(int(entry), set()).add(inode)
    return owners


def wait_for_listener(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        inodes = listener_inodes(port)
        owners = owners_of_inodes(inodes)
        if inodes and owners:
            return owners
        time.sleep(0.1)
    raise AssertionError(f"No process-backed listener appeared on 127.0.0.1:{port}")


def process_exe(pid):
    return os.readlink(f'/proc/{pid}/exe')


def process_cmdline(pid):
    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        return f.read().replace(b'\0', b' ').decode(errors='replace')


def assert_receiver_listener():
    owners = wait_for_listener(9090)
    expected = '/home/user/alert_receiver'
    matches = []
    for pid in owners:
        try:
            if process_exe(pid) == expected:
                matches.append(pid)
        except OSError:
            pass
    assert matches, f"Port 9090 is not listened on by the running {expected} executable"


def assert_ssh_tunnel():
    owners = wait_for_listener(8080)
    matches = []
    details = []
    for pid in owners:
        try:
            exe = process_exe(pid)
            cmdline = process_cmdline(pid)
        except OSError:
            continue
        details.append((pid, exe, cmdline))
        login_ok = ('monitor_user@127.0.0.1' in cmdline or
                    ('-l monitor_user' in cmdline and '127.0.0.1' in cmdline))
        if os.path.basename(exe) == 'ssh' and login_ok:
            matches.append(pid)
    assert matches, f"Port 8080 is not owned by an SSH process logged in as monitor_user@127.0.0.1; owners={details!r}"


def restart_tunnel_from_script():
    inodes = listener_inodes(8080)
    owners = owners_of_inodes(inodes)
    for pid in owners:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass

    deadline = time.time() + 5
    while time.time() < deadline and listener_inodes(8080):
        time.sleep(0.1)
    assert not listener_inodes(8080), "Existing port 8080 listener did not stop"

    result = subprocess.run(
        ['/usr/bin/expect', '/home/user/start_tunnel.exp'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=25,
        text=True,
    )
    assert result.returncode == 0, f"start_tunnel.exp failed:\n{result.stdout}"
    assert_ssh_tunnel()


def run_protocol(port, metric_name, metric_value):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect(('127.0.0.1', port))

            s.sendall(b"HELO PROBE_SYS_v2\n")
            resp = s.recv(1024)
            assert resp == b"OK READY\n", f"Expected 'OK READY\\n', got {resp!r} on port {port}"

            metric_msg = f"METRIC {metric_name} {metric_value}\n".encode()
            s.sendall(metric_msg)
            resp = s.recv(1024)
            expected_ack = f"ACK {metric_name}\n".encode()
            assert resp == expected_ack, f"Expected {expected_ack!r}, got {resp!r} on port {port}"

            s.sendall(b"BYE\n")
            resp = s.recv(1024)
            assert resp == b"", f"Expected connection close after BYE, got {resp!r} on port {port}"
    except ConnectionRefusedError:
        raise AssertionError(f"Connection refused on port {port}. Is the service/tunnel running?")
    except socket.timeout:
        raise AssertionError(f"Socket timeout while communicating on port {port}.")


def test_complete_receiver_and_tunnel():
    source = '/home/user/alert_receiver.c'
    binary = '/home/user/alert_receiver'
    tunnel_script = '/home/user/start_tunnel.exp'

    assert_regular_file(source)
    assert_regular_file(binary)
    assert_regular_file(tunnel_script)
    assert os.access(binary, os.X_OK), f"{binary} is not executable"
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{binary} is not an ELF executable"

    syntax = subprocess.run(
        ['gcc', '-fsyntax-only', source],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
        text=True,
    )
    assert syntax.returncode == 0, f"alert_receiver.c is not valid compilable C:\n{syntax.stdout}"

    assert_receiver_listener()
    restart_tunnel_from_script()
    assert_receiver_listener()

    log_path = '/home/user/alerts.log'
    before = pathlib.Path(log_path).read_text() if os.path.exists(log_path) else ''

    cases = [
        (9090, 'TEST_MEM', '2048'),
        (8080, 'TEST_CPU', '99'),
    ]
    for index in range(4):
        token = secrets.token_hex(8).upper()
        cases.append((9090 if index % 2 == 0 else 8080,
                      f'RANDOM_{index}_{token}',
                      str(secrets.randbelow(900000) + 100000)))

    for port, name, value in cases:
        run_protocol(port, name, value)

    prober = subprocess.run(
        ['/app/prober'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
        text=True,
    )
    assert prober.returncode == 0, f"The supplied legacy prober failed:\n{prober.stdout}"

    assert os.path.exists(log_path), f"Alerts log file {log_path} does not exist."
    content = pathlib.Path(log_path).read_text()
    assert content.startswith(before), "alerts.log was replaced or truncated instead of appended to"
    appended = content[len(before):]

    assert '[ALERT_RECEIVED] TEST_MEM: 2048' in content, 'Log file missing expected entry for TEST_MEM.'
    assert '[ALERT_RECEIVED] TEST_CPU: 99' in content, 'Log file missing expected entry for TEST_CPU.'
    for _, name, value in cases:
        expected = f'[ALERT_RECEIVED] {name}: {value}\n'
        assert expected in appended, f"New log output missing exact entry {expected!r}"
    assert '[ALERT_RECEIVED] CPU_USAGE: 85\n' in appended, 'The alert sent by /app/prober was not logged.'

    assert_receiver_listener()
    assert_ssh_tunnel()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
