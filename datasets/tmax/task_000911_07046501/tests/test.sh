#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import queue
import random
import secrets
import socket
import subprocess
import threading
import time

import pytest

BACKENDS = {5001: None, 5002: None}
EVENTS = queue.Queue()
STOP = threading.Event()


def kill_original_backends():
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            exe = os.path.basename(os.readlink(f'/proc/{name}/exe'))
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                args = [x.decode(errors='ignore') for x in f.read().split(b'\0') if x]
        except (OSError, PermissionError):
            continue
        if exe in ('nc', 'netcat', 'netcat-openbsd') and any(x in ('5001', '5002') for x in args):
            try:
                os.kill(int(name), 15)
            except ProcessLookupError:
                pass
    time.sleep(0.3)


def socket_owner_executables(conn):
    peer_ip, peer_port = conn.getpeername()
    local_ip, local_port = conn.getsockname()

    def encoded(ip, port):
        return socket.inet_aton(ip)[::-1].hex().upper() + f':{port:04X}'

    wanted_local = encoded(peer_ip, peer_port)
    wanted_remote = encoded(local_ip, local_port)
    inodes = set()
    try:
        with open('/proc/net/tcp', 'r') as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1] == wanted_local and fields[2] == wanted_remote and len(fields) > 9:
                    inodes.add(fields[9])
    except OSError:
        return set()

    owners = set()
    if not inodes:
        return owners
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    try:
                        owners.add(os.path.basename(os.readlink(f'/proc/{pid}/exe')))
                    except OSError:
                        pass
        except (OSError, PermissionError):
            continue
    return owners


def backend_loop(port, ready):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', port))
    srv.listen(20)
    srv.settimeout(0.2)
    BACKENDS[port] = srv
    ready.set()
    try:
        while not STOP.is_set():
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with conn:
                conn.settimeout(1.0)
                owners = set()
                deadline = time.time() + 0.25
                while time.time() < deadline and 'ssh' not in owners:
                    owners.update(socket_owner_executables(conn))
                    if 'ssh' not in owners:
                        time.sleep(0.01)
                chunks = []
                while True:
                    try:
                        data = conn.recv(65536)
                    except socket.timeout:
                        break
                    if not data:
                        break
                    chunks.append(data)
                EVENTS.put((port, b''.join(chunks), owners))
    finally:
        try:
            srv.close()
        except OSError:
            pass


def ssh_forward_specs():
    specs = []
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.basename(os.readlink(f'/proc/{pid}/exe'))
            if exe != 'ssh':
                continue
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                args = [x.decode(errors='ignore') for x in f.read().split(b'\0') if x]
        except (OSError, PermissionError):
            continue
        i = 1
        while i < len(args):
            if args[i] == '-L' and i + 1 < len(args):
                specs.append(args[i + 1])
                i += 2
                continue
            if args[i].startswith('-L') and len(args[i]) > 2:
                specs.append(args[i][2:])
            i += 1
    return specs


def has_mapping(specs, local_port, target_port):
    for spec in specs:
        parts = spec.split(':')
        if len(parts) < 3:
            continue
        if parts[-3] == str(local_port) and parts[-2] in ('127.0.0.1', 'localhost') and parts[-1] == str(target_port):
            return True
    return False


def get_event(timeout=3):
    try:
        return EVENTS.get(timeout=timeout)
    except queue.Empty:
        pytest.fail('No TCP payload reached either backend')


def probe_tunnel(local_port, expected_backend):
    token = ('probe-' + secrets.token_hex(16)).encode()
    with socket.create_connection(('127.0.0.1', local_port), timeout=2) as sock:
        sock.sendall(token)
        sock.shutdown(socket.SHUT_WR)
    port, data, owners = get_event()
    assert port == expected_backend
    assert data == token
    assert 'ssh' in owners, f'Backend connection was not owned by ssh: {owners}'


def test_delivery_accuracy_and_failure_behavior():
    if os.path.isfile('/home/user/mail_router.py'):
        cmd = ['python3', '/home/user/mail_router.py']
    elif os.path.isfile('/home/user/mail_router.sh'):
        cmd = ['bash', '/home/user/mail_router.sh']
    else:
        pytest.fail('Neither /home/user/mail_router.py nor /home/user/mail_router.sh was found.')

    kill_original_backends()
    ready = []
    threads = []
    for port in (5001, 5002):
        event = threading.Event()
        thread = threading.Thread(target=backend_loop, args=(port, event), daemon=True)
        thread.start()
        assert event.wait(2), f'Could not start backend on port {port}'
        ready.append(event)
        threads.append(thread)

    try:
        specs = ssh_forward_specs()
        assert has_mapping(specs, 8001, 5001), f'Missing active SSH -L mapping 8001 to 5001; found {specs}'
        assert has_mapping(specs, 8002, 5002), f'Missing active SSH -L mapping 8002 to 5002; found {specs}'

        probe_tunnel(8001, 5001)
        probe_tunnel(8002, 5002)

        routes = {'alice': 5001, 'bob': 5001, 'charlie': 5002, 'dave': 5002}
        senders = list(routes)
        cases = []
        # Preserve coverage of all four original ACL members, then test a
        # randomized total of 100 recognized messages.
        for sender in senders:
            cases.append((sender, 'test-' + secrets.token_hex(18)))
        for _ in range(96):
            cases.append((random.choice(senders), 'mail-' + secrets.token_hex(24)))
        random.shuffle(cases)

        correct = 0
        total = len(cases)
        for sender, body in cases:
            payload = json.dumps({'sender': sender, 'body': body})
            result = subprocess.run(cmd, input=payload.encode(), stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=3)
            assert result.returncode == 0, result.stderr.decode(errors='replace')
            port, received, owners = get_event()
            if port == routes[sender] and received == payload.encode() and 'ssh' in owners:
                correct += 1

        accuracy = correct / total
        assert accuracy >= 1.0, (
            f'Delivery accuracy is {accuracy}, expected >= 1.0. '
            f'Correctly routed: {correct}/{total}'
        )

        # Unknown names and bodies are generated at verification time. They
        # must return exactly 1 and must produce no backend TCP connection.
        for _ in range(12):
            unknown = 'unknown-' + secrets.token_hex(10)
            payload = json.dumps({'sender': unknown, 'body': 'drop-' + secrets.token_hex(20)})
            result = subprocess.run(cmd, input=payload.encode(), stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=3)
            assert result.returncode == 1, f'Unknown sender exited with {result.returncode}, expected 1'
            try:
                event = EVENTS.get(timeout=0.2)
            except queue.Empty:
                event = None
            assert event is None, f'Unknown sender produced backend traffic: {event}'

        # Tunnels must still be active after all router invocations.
        probe_tunnel(8001, 5001)
        probe_tunnel(8002, 5002)
    finally:
        STOP.set()
        for srv in BACKENDS.values():
            if srv is not None:
                try:
                    srv.close()
                except OSError:
                    pass
        for thread in threads:
            thread.join(timeout=1)
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
