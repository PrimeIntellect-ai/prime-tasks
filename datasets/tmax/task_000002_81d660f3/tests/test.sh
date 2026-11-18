#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import os
import queue
import secrets
import socket
import socketserver
import stat
import subprocess
import threading
import time
import urllib.request

import pytest


def user_systemctl(action, unit):
    cmd = ['su', '-', 'user', '-c', f'systemctl --user {action} {unit}']
    return subprocess.run(cmd, capture_output=True, text=True, timeout=15)


def wait_for_port(port, accepting=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.2)
        try:
            sock.connect(('127.0.0.1', port))
            is_open = True
        except OSError:
            is_open = False
        finally:
            sock.close()
        if is_open == accepting:
            return
        time.sleep(0.05)
    pytest.fail(f'Port {port} did not become {"available" if accepting else "unavailable"}')


def run_verify_script():
    result = subprocess.run(
        ['su', '-', 'user', '-c', '/usr/bin/python3 /home/user/verify.py'],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f'verify.py failed: {result.stderr}'


def test_results_log():
    verify_path = '/home/user/verify.py'
    assert os.path.exists(verify_path), f'Missing {verify_path}'
    assert not os.path.islink(verify_path), f'{verify_path} must be a Python script, not a symlink'
    assert stat.S_ISREG(os.stat(verify_path).st_mode), f'{verify_path} is not a regular file'

    # Execute verify.py against unpredictable responses and count the requests,
    # so a script that merely hardcodes four API_OK lines cannot pass.
    bodies = [f'CHECK_{secrets.token_hex(16)}' for _ in range(4)]
    seen = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            index = len(seen)
            seen.append(self.path)
            body = bodies[index] if index < len(bodies) else 'UNEXPECTED_EXTRA_REQUEST'
            encoded = body.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def log_message(self, *args):
            pass

    class TestHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
        allow_reuse_address = True
        daemon_threads = True

    stop_result = user_systemctl('stop', 'lb.service')
    assert stop_result.returncode == 0, f'Failed to stop lb.service: {stop_result.stderr}'
    wait_for_port(9000, accepting=False)

    server = TestHTTPServer(('127.0.0.1', 9000), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    dynamic_lines = None
    dynamic_error = None
    try:
        if os.path.exists('/home/user/test_results.log'):
            os.unlink('/home/user/test_results.log')
        run_verify_script()
        assert os.path.exists('/home/user/test_results.log'), 'verify.py did not create test_results.log'
        with open('/home/user/test_results.log', 'r') as f:
            dynamic_lines = f.read().splitlines()
        assert len(seen) == 4, f'verify.py must send exactly 4 requests, but sent {len(seen)}'
        assert seen == ['/'] * 4, f'verify.py requested unexpected paths: {seen}'
        assert dynamic_lines == bodies, 'verify.py did not append the exact response body from each request'
    except BaseException as exc:
        dynamic_error = exc
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        start_result = user_systemctl('start', 'lb.service')
        assert start_result.returncode == 0, f'Failed to restart lb.service: {start_result.stderr}'
        wait_for_port(9000, accepting=True)

    if dynamic_error is not None:
        raise dynamic_error

    # Re-run against the real stack and preserve the original log assertions.
    if os.path.exists('/home/user/test_results.log'):
        os.unlink('/home/user/test_results.log')
    run_verify_script()

    path = '/home/user/test_results.log'
    assert os.path.exists(path), f'Missing {path}. Did the verify.py script run and create it?'
    with open(path, 'r') as f:
        content = f.read().strip()
    if not content:
        pytest.fail(f'{path} is empty.')
    lines = content.splitlines()
    assert len(lines) == 4, f'Expected exactly 4 lines in {path}, found {len(lines)}'
    for i, line in enumerate(lines):
        assert line == 'API_OK', f"Line {i+1} in {path} expected to be 'API_OK', got '{line}'"


def test_lb_service_dependencies():
    cmd = ['su', '-', 'user', '-c', 'systemctl --user show lb.service -p After -p Requires']
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f'Failed to run systemctl: {result.stderr}'
    output = result.stdout

    after_line = ''
    requires_line = ''
    for line in output.splitlines():
        if line.startswith('After='):
            after_line = line
        elif line.startswith('Requires='):
            requires_line = line

    assert 'api.service' in after_line, "lb.service 'After=' directive does not contain 'api.service'"
    assert 'tunnel.service' in after_line, "lb.service 'After=' directive does not contain 'tunnel.service'"
    assert 'api.service' in requires_line, "lb.service 'Requires=' directive does not contain 'api.service'"
    assert 'tunnel.service' in requires_line, "lb.service 'Requires=' directive does not contain 'tunnel.service'"


def test_lb_and_tunnel_running():
    for i in range(4):
        try:
            req = urllib.request.Request('http://127.0.0.1:9000/')
            with urllib.request.urlopen(req, timeout=2) as response:
                body = response.read().decode('utf-8').strip()
                assert body == 'API_OK', f"Request {i+1}: Expected 'API_OK', got '{body}'"
        except Exception as e:
            pytest.fail(f'Request {i+1}: Failed to connect to Load Balancer on port 9000 or receive correct response: {e}. Are all services running?')


def test_tunnel_is_bidirectional_tcp_forwarder():
    tunnel_path = '/home/user/tunnel.py'
    assert os.path.exists(tunnel_path), f'Missing {tunnel_path}'
    assert not os.path.islink(tunnel_path), f'{tunnel_path} must be a Python script, not a symlink'
    assert stat.S_ISREG(os.stat(tunnel_path).st_mode), f'{tunnel_path} is not a regular file'

    # Replace the fixed API temporarily with a verifier-controlled backend.
    # Only a real forwarder can relay both unpredictable byte streams.
    stop_result = user_systemctl('stop', 'api.service')
    assert stop_result.returncode == 0, f'Failed to stop api.service: {stop_result.stderr}'
    wait_for_port(9001, accepting=False)

    challenges = [secrets.token_bytes(32791), secrets.token_bytes(17011)]
    replies = [secrets.token_bytes(35003), secrets.token_bytes(19007)]
    errors = queue.Queue()
    ready = threading.Event()

    def recv_exact(sock, size):
        data = bytearray()
        while len(data) < size:
            chunk = sock.recv(min(4096, size - len(data)))
            if not chunk:
                raise AssertionError(f'Connection closed after {len(data)} of {size} bytes')
            data.extend(chunk)
        return bytes(data)

    def backend():
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('127.0.0.1', 9001))
            listener.listen(1)
            listener.settimeout(5)
            ready.set()
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(5)
                for challenge, reply in zip(challenges, replies):
                    received = recv_exact(conn, len(challenge))
                    assert received == challenge, 'Tunnel corrupted client-to-backend traffic'
                    for offset in range(0, len(reply), 997):
                        conn.sendall(reply[offset:offset + 997])
        except BaseException as exc:
            errors.put(exc)
            ready.set()
        finally:
            listener.close()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    ready.wait(5)

    try:
        if not errors.empty():
            raise errors.get()
        with socket.create_connection(('127.0.0.1', 9002), timeout=5) as client:
            client.settimeout(5)
            for challenge, reply in zip(challenges, replies):
                for offset in range(0, len(challenge), 733):
                    client.sendall(challenge[offset:offset + 733])
                received = recv_exact(client, len(reply))
                assert received == reply, 'Tunnel corrupted backend-to-client traffic'
        thread.join(timeout=6)
        assert not thread.is_alive(), 'Controlled backend did not finish; tunnel stalled continuous traffic'
        if not errors.empty():
            raise errors.get()
    finally:
        start_result = user_systemctl('start', 'api.service')
        assert start_result.returncode == 0, f'Failed to restart api.service: {start_result.stderr}'
        wait_for_port(9001, accepting=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
