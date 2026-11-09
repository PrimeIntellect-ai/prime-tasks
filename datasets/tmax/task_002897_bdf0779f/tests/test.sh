#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop anything already listening on port 8888 so the submitted artifact itself
# must be executed for the tests.
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
                if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == '22B8' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
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

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
time.sleep(0.2)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
PY

cd /home/user
/home/user/audit_server >/tmp/audit_server.verifier.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import socket
import subprocess
import time
from collections import deque

import pytest


def get_graph():
    graph = {}
    with open('/app/entities.csv') as f:
        nodes = [int(line.strip()) for line in f if line.strip()]

    for node in nodes:
        output = subprocess.check_output(
            ['/app/legacy_audit_tool', str(node)], text=True, timeout=2
        ).strip()
        assert output.startswith('ACCESS:'), f'Unexpected oracle output for {node}: {output!r}'
        values = output[len('ACCESS:'):].strip()
        if not values or values == 'NONE':
            graph[node] = []
        else:
            graph[node] = [int(value) for value in values.split()]
    return graph


def bfs(graph, start, end):
    if start == end:
        return [start]
    queue = deque([[start]])
    visited = {start}
    while queue:
        path = queue.popleft()
        node = path[-1]
        for neighbor in graph[node]:
            if neighbor == end:
                return path + [neighbor]
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])
    return None


class Client:
    def __init__(self):
        self.sock = None
        self.buf = b''

    def close(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.buf = b''

    def _connect(self):
        self.close()
        self.sock = socket.create_connection(('127.0.0.1', 8888), timeout=2.0)
        self.sock.settimeout(2.0)

    def query(self, src, dst):
        message = f'CHECK {src} {dst}\n'.encode()
        last_error = None
        for _ in range(2):
            try:
                if self.sock is None:
                    self._connect()
                self.sock.sendall(message)
                while b'\n' not in self.buf:
                    chunk = self.sock.recv(4096)
                    if not chunk:
                        raise ConnectionError('server closed before returning a complete response')
                    self.buf += chunk
                line, self.buf = self.buf.split(b'\n', 1)
                return line.decode('utf-8').strip()
            except Exception as exc:
                last_error = exc
                self.close()
        pytest.fail(f'Failed to connect and query server for {src}->{dst}: {last_error}')


def check_path(src, dst, response, graph):
    expected_path = bfs(graph, src, dst)
    if expected_path is None:
        assert response == 'NONE', f"Expected 'NONE' for {src}->{dst}, got '{response}'"
        return

    assert response != 'NONE', f"Expected a valid path for {src}->{dst}, got 'NONE'"
    try:
        path = [int(x.strip()) for x in response.split(',')]
    except ValueError:
        pytest.fail(f"Could not parse response as comma-separated integers: '{response}'")

    assert path[0] == src, f'Path must start with {src}, got {path[0]}'
    assert path[-1] == dst, f'Path must end with {dst}, got {path[-1]}'
    assert len(path) == len(expected_path), (
        f'Expected shortest path of length {len(expected_path)}, '
        f'but got length {len(path)}: {response}'
    )
    for u, v in zip(path, path[1:]):
        assert v in graph[u], f'Invalid edge in path: no direct access from {u} to {v}'


def test_server_binary_exists_and_is_native_with_c_source():
    binary_path = '/home/user/audit_server'
    assert os.path.isfile(binary_path), f'Server binary {binary_path} not found'
    assert os.access(binary_path, os.X_OK), f'Server binary {binary_path} is not executable'
    with open(binary_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'audit_server must be a compiled native executable'

    candidates = []
    for path in pathlib.Path('/home/user').rglob('*.c'):
        try:
            source = path.read_text(errors='ignore')
        except OSError:
            continue
        if all(token in source for token in ('main', 'socket', 'bind', 'listen', 'accept')):
            candidates.append(path)

    assert candidates, 'No C source implementing the TCP server was found under /home/user'
    compiled = False
    errors = []
    for path in candidates:
        result = subprocess.run(
            ['gcc', '-fsyntax-only', str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            compiled = True
            break
        errors.append(f'{path}: {result.stderr}')
    assert compiled, 'TCP server C source did not compile:\n' + '\n'.join(errors)


def test_server_responses_for_complete_entity_graph():
    graph = get_graph()
    nodes = list(graph)

    # Preserve the original deterministic assertions first.
    test_pairs = [(1, 50), (2, 100), (10, 10), (20, 199), (150, 3)]
    random.seed(1337)
    for _ in range(15):
        test_pairs.append((random.randint(1, 200), random.randint(1, 200)))

    # Then cover every source-target pair, preventing a fixed-subset server.
    seen = set(test_pairs)
    test_pairs.extend(
        (src, dst)
        for src in nodes
        for dst in nodes
        if (src, dst) not in seen
    )

    client = Client()
    try:
        for src, dst in test_pairs:
            check_path(src, dst, client.query(src, dst), graph)
    finally:
        client.close()
TEST_EOF

# Give the freshly executed artifact a brief opportunity to bind the port.
for _ in $(seq 1 50); do
    if python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.1)
try:
    s.connect(('127.0.0.1', 8888))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
    then
        break
    fi
    sleep 0.1
done

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
