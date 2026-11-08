#!/bin/bash
mkdir -p /logs/verifier

ORIGINAL_DAEMON=/tmp/graph_daemon.original
rm -f "$ORIGINAL_DAEMON" /tmp/graph_requests.log /tmp/graph_daemon_args.json /tmp/start_test.log

cleanup() {
    pkill -f '/home/user/etl_service' >/dev/null 2>&1 || true
    pkill -f '/app/graph_daemon' >/dev/null 2>&1 || true
    sleep 0.2
    if [ -f "$ORIGINAL_DAEMON" ]; then
        rm -f /app/graph_daemon
        mv "$ORIGINAL_DAEMON" /app/graph_daemon
    fi
    rm -f /tmp/graph.sock
}
trap cleanup EXIT

pkill -f '/home/user/etl_service' >/dev/null 2>&1 || true
pkill -f '/app/graph_daemon' >/dev/null 2>&1 || true
sleep 0.5

mv /app/graph_daemon "$ORIGINAL_DAEMON"
cat <<'DAEMON_EOF' > /app/graph_daemon
#!/usr/bin/env python3
import json
import os
import socket
import sys
import threading

if len(sys.argv) < 3:
    sys.exit(1)

socket_path = sys.argv[1]
data_path = sys.argv[2]
with open('/tmp/graph_daemon_args.json', 'w') as f:
    json.dump(sys.argv[1:], f)

try:
    os.unlink(socket_path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(50)
counts = {}
lock = threading.Lock()

def handle(conn):
    try:
        conn.settimeout(2)
        data = b''
        while len(data) < 5:
            chunk = conn.recv(5 - len(data))
            if not chunk:
                break
            data += chunk

        key = data.hex()
        with lock:
            attempt = counts.get(key, 0) + 1
            counts[key] = attempt
            with open('/tmp/graph_requests.log', 'a') as log:
                log.write('%s %d\n' % (key, attempt))

        if len(data) != 5 or data[0] != 0x01:
            return
        # Deterministically force the retry path on the first occurrence of
        # every distinct parameterized query.
        if attempt == 1:
            conn.sendall(b'\xff')
        else:
            node = data[2]
            conn.sendall(('%d,%d,%d\n' % (node, node + 1, node + 2)).encode())
    finally:
        conn.close()

while True:
    conn, _ = server.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
DAEMON_EOF
chmod 755 /app/graph_daemon

(
    cd /home/user || exit 1
    timeout 10s ./start.sh
) > /tmp/start_test.log 2>&1
START_STATUS=$?

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import time
import requests
import pytest
import threading

BASE_URL = 'http://127.0.0.1:9090/traverse'
AUTH = {'Authorization': 'Bearer secret-etl-token'}

def wait_for_service():
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            requests.get(BASE_URL + '?start_node=1&depth=1', timeout=0.3)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail('Service did not start: %s' % last_error)

wait_for_service()

def test_files_exist():
    assert os.path.exists('/home/user/etl_service'), '/home/user/etl_service does not exist'
    assert os.access('/home/user/etl_service', os.X_OK), '/home/user/etl_service is not executable'
    assert os.path.exists('/home/user/start.sh'), '/home/user/start.sh does not exist'
    assert os.access('/home/user/start.sh', os.X_OK), '/home/user/start.sh is not executable'
    with open('/home/user/etl_service', 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/etl_service is not a compiled executable'

def test_unauthorized_request():
    url = BASE_URL + '?start_node=1&depth=1'
    try:
        response = requests.get(url, timeout=2)
        assert response.status_code in (401, 403), 'Expected 401 or 403 for unauthorized request, got %s' % response.status_code
    except requests.exceptions.RequestException as e:
        pytest.fail('Failed to connect to the service: %s' % e)

def test_authorized_request():
    url = BASE_URL + '?start_node=1&depth=1'
    try:
        response = requests.get(url, headers=AUTH, timeout=5)
        assert response.status_code == 200, 'Expected 200 OK, got %s' % response.status_code
        data = response.json()
        assert isinstance(data, list) or 'nodes' in data, "Response should be a JSON array of node IDs or an object with 'nodes' array"
        if isinstance(data, dict) and 'nodes' in data:
            assert isinstance(data['nodes'], list), "'nodes' field must be a list"
        assert isinstance(data, list), 'The traversal result must be returned as a JSON array'
        assert data == [1, 2, 3], 'Result does not match the graph daemon response: %r' % data
    except requests.exceptions.RequestException as e:
        pytest.fail('Failed to connect to the service: %s' % e)
    except ValueError:
        pytest.fail('Response is not valid JSON')

def test_parameterized_queries_and_depth_encoding():
    cases = [(2, 1), (2, 3), (3, 2)]
    for start, depth in cases:
        response = requests.get(
            BASE_URL + '?start_node=%d&depth=%d' % (start, depth),
            headers=AUTH,
            timeout=5,
        )
        assert response.status_code == 200
        assert response.json() == [start, start + 1, start + 2]

def test_concurrent_requests():
    url = BASE_URL + '?start_node=1&depth=2'
    results = []
    bodies = []

    def make_request():
        try:
            response = requests.get(url, headers=AUTH, timeout=10)
            results.append(response.status_code)
            bodies.append(response.json() if response.status_code == 200 else None)
        except Exception as e:
            results.append(str(e))

    threads = [threading.Thread(target=make_request) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    for res in results:
        assert res == 200, 'Concurrent request failed with status/error: %s' % res
    assert len(bodies) == 5
    assert all(body == [1, 2, 3] for body in bodies)

def test_daemon_invocation_protocol_and_deadlock_retries():
    assert os.path.exists('/tmp/graph_daemon_args.json'), 'start.sh did not start /app/graph_daemon'
    with open('/tmp/graph_daemon_args.json') as f:
        args = json.load(f)
    assert len(args) >= 2
    assert args[0] == '/tmp/graph.sock', 'Daemon was not started on /tmp/graph.sock'
    assert args[1] == '/home/user/data.csv', 'Daemon was not initialized with the provided dataset'

    assert os.path.exists('/tmp/graph_requests.log'), 'The ETL service never queried the graph daemon'
    entries = []
    with open('/tmp/graph_requests.log') as f:
        for line in f:
            packet, attempt = line.split()
            raw = bytes.fromhex(packet)
            entries.append((packet, int(attempt), raw))

    assert entries, 'No graph protocol requests were recorded'
    assert all(len(raw) == 5 and raw[0] == 0x01 for _, _, raw in entries), 'Malformed graph protocol request'

    # start_node is encoded in the byte consumed by the supplied daemon.
    for expected_start in (1, 2, 3):
        assert any(raw[2] == expected_start for _, _, raw in entries), 'start_node=%d was not sent to the daemon' % expected_start

    # The two queries for node 2 use different depths, so their parameterized
    # binary requests must differ.
    node_two_packets = {packet for packet, _, raw in entries if raw[2] == 2}
    assert len(node_two_packets) >= 2, 'depth was not encoded in the daemon query'

    # The controlled daemon returns 0xFF on the first attempt for every new
    # packet. Each node-2 packet must therefore have been resent unchanged.
    packet_counts = collections.Counter(packet for packet, _, _ in entries)
    for packet in node_two_packets:
        assert packet_counts[packet] >= 2, 'DEADLOCK_DETECTED was not retried for packet %s' % packet
TEST_EOF

if [ "$START_STATUS" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    if [ "$START_STATUS" -ne 0 ]; then
        echo "start.sh failed or did not leave its processes in the background (status $START_STATUS)"
        cat /tmp/start_test.log 2>/dev/null || true
    fi
    echo "0" > /logs/verifier/reward.txt
fi
