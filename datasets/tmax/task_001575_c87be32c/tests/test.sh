#!/bin/bash
mkdir -p /logs/verifier

SERVER_PID=""

kill_port_8888() {
python3 - <<'PY'
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].split(':')[-1].upper() == '22B8' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit() or int(name) == os.getpid():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass

for sig in (signal.SIGTERM, signal.SIGKILL):
    for pid in list(pids):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
    if sig == signal.SIGTERM and pids:
        time.sleep(0.2)
PY
}

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill -TERM -- "-$SERVER_PID" 2>/dev/null || kill -TERM "$SERVER_PID" 2>/dev/null || true
        sleep 0.2
        kill -KILL -- "-$SERVER_PID" 2>/dev/null || kill -KILL "$SERVER_PID" 2>/dev/null || true
    fi
    kill_port_8888 >/dev/null 2>&1 || true
}

verify() {
    [ -f /home/user/mock_server.py ] || return 1
    [ ! -L /home/user/mock_server.py ] || return 1
    python3 -m py_compile /home/user/mock_server.py || return 1

    kill_port_8888 || return 1
    rm -f /home/user/test_report.log

    setsid python3 /home/user/mock_server.py >/tmp/mock_server.verifier.log 2>&1 &
    SERVER_PID=$!

    python3 - <<'PY' || return 1
import socket
import time

deadline = time.monotonic() + 5.0
while True:
    try:
        with socket.create_connection(('127.0.0.1', 8888), timeout=0.25):
            break
    except OSError:
        if time.monotonic() >= deadline:
            raise SystemExit('mock_server.py did not listen on 127.0.0.1:8888')
        time.sleep(0.05)
PY

    kill -0 "$SERVER_PID" 2>/dev/null || return 1

    timeout 15s python3 /home/user/test_client.py || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import time
import pytest

def test_test_report_exists():
    """Verify that the test_report.log file was created."""
    log_path = '/home/user/test_report.log'
    assert os.path.exists(log_path), (
        f"The file {log_path} does not exist. Did you run the test_client.py script?"
    )
    assert os.path.isfile(log_path), (
        f"The path {log_path} exists but is not a file."
    )

def test_test_report_success_status():
    """Verify that the test_report.log file ends with the success status."""
    log_path = '/home/user/test_report.log'

    # Ensure the file exists before reading
    assert os.path.exists(log_path), f"Cannot check status, {log_path} is missing."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content, f"The file {log_path} is empty."

    lines = content.split('\n')
    last_line = lines[-1]

    expected_status = "STATUS: ALL TESTS PASSED"

    assert last_line == expected_status, (
        f"Expected the last line of {log_path} to be '{expected_status}', "
        f"but got '{last_line}'. This indicates the test client failed one or more assertions."
    )

def recv_line(sock):
    data = b''
    while not data.endswith(b'\n'):
        chunk = sock.recv(1024)
        assert chunk, f"connection closed before a complete response: {data!r}"
        data += chunk
        assert len(data) < 4096, "response was unexpectedly large"
    return data.decode('ascii')

def connect():
    sock = socket.create_connection(('127.0.0.1', 8888), timeout=2)
    sock.settimeout(2)
    return sock

def test_randomized_protocol_and_state_machine():
    client_id = secrets.token_hex(8)
    command1 = secrets.token_hex(7)
    command2 = secrets.token_hex(7)
    command3 = secrets.token_hex(7)
    command4 = secrets.token_hex(7)

    with connect() as sock:
        sock.sendall(f'NOPE {client_id}\n'.encode())
        assert recv_line(sock) == 'ERR 500 UNKNOWN\n'

        sock.sendall(f'EXEC {command1}\n'.encode())
        assert recv_line(sock) == 'ERR 403 FORBIDDEN\n'

        sock.sendall(f'HELO {client_id}\n'.encode())
        assert recv_line(sock) == f'ACK {client_id}\n'

        sock.sendall(f'HELO {client_id}\n'.encode())
        assert recv_line(sock) == 'ERR 400 BAD REQUEST\n'

        sock.sendall(f'EXEC {command1}\n'.encode())
        assert recv_line(sock) == f'RUN {command1}\n'
        sock.sendall(f'EXEC {command2}\n'.encode())
        assert recv_line(sock) == f'RUN {command2}\n'
        sock.sendall(f'EXEC {command3}\n'.encode())
        assert recv_line(sock) == 'ERR 429 TOO MANY REQUESTS\n'

        time.sleep(1.15)
        sock.sendall(f'EXEC {command4}\n'.encode())
        assert recv_line(sock) == f'RUN {command4}\n'

        sock.sendall(b'QUIT\n')
        assert recv_line(sock) == 'BYE\n'
        assert sock.recv(1) == b''

def test_randomized_validation_failure():
    client_id = secrets.token_hex(6)
    invalid = secrets.token_hex(4) + '-bad!'
    with connect() as sock:
        sock.sendall(f'HELO {client_id}\n'.encode())
        assert recv_line(sock) == f'ACK {client_id}\n'
        sock.sendall(f'EXEC {invalid}\n'.encode())
        assert recv_line(sock) == 'ERR 400 BAD REQUEST\n'
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
}

if verify; then
    reward=1
else
    reward=0
fi
cleanup
echo "$reward" > /logs/verifier/reward.txt
