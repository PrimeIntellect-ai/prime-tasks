#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verifier_api.py
import http.server
import socketserver
import json

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

class APIHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {"status": "ok", "metric": 42, "source": "api"}
        self.wfile.write(json.dumps(response).encode())

with ReusableTCPServer(("127.0.0.1", 8081), APIHandler) as httpd:
    httpd.serve_forever()
PY_EOF

cat <<'PY_EOF' > /tmp/verifier_dashboard.py
import http.server
import socketserver
import urllib.request
import json

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        try:
            req = urllib.request.Request("http://127.0.0.1:9090/")
            with urllib.request.urlopen(req, timeout=2) as response:
                data = json.loads(response.read().decode())
            res = {"dashboard": "up", "data": data}
            status = 200
        except Exception as e:
            res = {"dashboard": "down", "error": str(e)}
            status = 502
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(res).encode())

with ReusableTCPServer(("127.0.0.1", 8082), DashboardHandler) as httpd:
    httpd.serve_forever()
PY_EOF

cat <<'PY_EOF' > /tmp/start_fixture_services.py
import os
import signal
import socket
import subprocess
import time


def listener_pids(port):
    inodes = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == '0A':
                        if int(fields[1].rsplit(':', 1)[1], 16) == port:
                            inodes.add(fields[9])
        except OSError:
            pass
    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = '/proc/%s/fd' % name
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except OSError:
            pass
    return result


def clear_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def wait_port(port, proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError('fixture service exited early')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError('fixture service did not listen on port %d' % port)

clear_port(8081)
clear_port(8082)
devnull = open(os.devnull, 'wb')
api = subprocess.Popen(['python3', '/tmp/verifier_api.py'], stdout=devnull, stderr=devnull, start_new_session=True)
wait_port(8081, api)
dash = subprocess.Popen(['python3', '/tmp/verifier_dashboard.py'], stdout=devnull, stderr=devnull, start_new_session=True)
wait_port(8082, dash)
with open('/tmp/verifier_api.pid', 'w') as f:
    f.write(str(api.pid))
with open('/tmp/verifier_dashboard.pid', 'w') as f:
    f.write(str(dash.pid))
PY_EOF

if ! python3 /tmp/start_fixture_services.py; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cleanup() {
    for pidfile in /tmp/verifier_api.pid /tmp/verifier_dashboard.pid; do
        if [ -f "$pidfile" ]; then
            kill "$(cat "$pidfile")" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import hashlib
import json
import os
import signal
import socket
import struct
import subprocess
import threading
import time
import urllib.request
import pytest

EXPECTED_DASHBOARD = {
    "dashboard": "up",
    "data": {"status": "ok", "metric": 42, "source": "api"},
}
EXPECTED_DASHBOARD_BYTES = json.dumps(EXPECTED_DASHBOARD).encode()


def get_running_pids(script_name):
    """Return a list of PIDs running the given script name, ignoring grep."""
    pids = []
    try:
        output = subprocess.check_output(['ps', '-eo', 'pid,args']).decode('utf-8')
        for line in output.strip().split('\n'):
            if script_name in line and 'grep' not in line and 'vim' not in line and 'nano' not in line:
                pid = int(line.split()[0])
                pids.append(pid)
    except Exception:
        pass
    return pids


def recv_exact(sock, length):
    chunks = []
    remaining = length
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise AssertionError('TCP stream closed before all expected bytes arrived')
        chunks.append(chunk)
        remaining -= len(chunk)
    return b''.join(chunks)


def stop_fixture_api():
    with open('/tmp/verifier_api.pid') as f:
        pid = int(f.read())
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)


def start_fixture_api():
    devnull = open(os.devnull, 'wb')
    proc = subprocess.Popen(
        ['python3', '/tmp/verifier_api.py'],
        stdout=devnull,
        stderr=devnull,
        start_new_session=True,
    )
    with open('/tmp/verifier_api.pid', 'w') as f:
        f.write(str(proc.pid))
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError('Metrics API fixture failed to restart')
        try:
            with socket.create_connection(('127.0.0.1', 8081), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError('Metrics API fixture did not restart')


def test_scripts_exist_and_executable():
    scripts = [
        '/home/user/proxy.py',
        '/home/user/supervisor.py',
        '/home/user/deploy.py'
    ]
    for script in scripts:
        assert os.path.isfile(script), f"{script} does not exist."
        assert os.access(script, os.X_OK), f"{script} is not executable."


def test_proxy_transparently_forwards_random_bidirectional_tcp_streams():
    stop_fixture_api()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    errors = []
    handler_threads = []

    def handle(conn):
        try:
            with conn:
                nonce = os.urandom(32)
                conn.sendall(nonce)
                size = struct.unpack('!I', recv_exact(conn, 4))[0]
                payload = recv_exact(conn, size)
                conn.sendall(hashlib.sha256(nonce + payload).digest())
        except BaseException as exc:
            errors.append(exc)

    def serve():
        try:
            server.bind(('127.0.0.1', 8081))
            server.listen(16)
            server.settimeout(6)
            for _ in range(6):
                conn, _ = server.accept()
                thread = threading.Thread(target=handle, args=(conn,))
                thread.start()
                handler_threads.append(thread)
        except BaseException as exc:
            errors.append(exc)

    try:
        serving = threading.Thread(target=serve)
        serving.start()
        time.sleep(0.15)

        def client(index):
            payload = os.urandom(65536 + index * 7919)
            with socket.create_connection(('127.0.0.1', 9090), timeout=3) as conn:
                conn.settimeout(5)
                nonce = recv_exact(conn, 32)
                conn.sendall(struct.pack('!I', len(payload)))
                conn.sendall(payload)
                response = recv_exact(conn, 32)
            assert response == hashlib.sha256(nonce + payload).digest()

        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            futures = [pool.submit(client, i) for i in range(6)]
            for future in futures:
                future.result(timeout=8)
        serving.join(timeout=8)
        for thread in handler_threads:
            thread.join(timeout=5)
        assert not serving.is_alive(), 'TCP target did not receive all forwarded connections'
        assert not errors, f'TCP forwarding failed: {errors}'
    finally:
        server.close()
        start_fixture_api()


def test_metrics_log():
    log_path = '/home/user/metrics.log'
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    raw = open(log_path, 'rb').read()
    try:
        data = json.loads(raw.decode())
    except (UnicodeDecodeError, json.JSONDecodeError):
        pytest.fail(f"{log_path} does not contain valid JSON.")

    assert data.get('dashboard') == 'up', "Dashboard status in metrics.log is not 'up'."
    assert data.get('data', {}).get('status') == 'ok', "Data status in metrics.log is not 'ok'."
    assert data.get('data', {}).get('metric') == 42, "Metric value in metrics.log is incorrect."
    assert data == EXPECTED_DASHBOARD, 'metrics.log is not the complete dashboard response.'
    assert raw == EXPECTED_DASHBOARD_BYTES, 'metrics.log is not the exact dashboard output.'


def test_dashboard_endpoint_live():
    try:
        req = urllib.request.Request("http://127.0.0.1:8082/")
        with urllib.request.urlopen(req, timeout=3) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            raw = response.read()
            data = json.loads(raw.decode())
            assert data.get('dashboard') == 'up', "Live dashboard status is not 'up'. Proxy may not be forwarding correctly."
            assert data == EXPECTED_DASHBOARD, 'Live dashboard did not return the full API response.'
            assert raw == EXPECTED_DASHBOARD_BYTES, 'Live dashboard output was not exact.'
            assert open('/home/user/metrics.log', 'rb').read() == raw, 'metrics.log differs from the exact live dashboard output.'
    except Exception as e:
        pytest.fail(f"Failed to contact dashboard endpoint: {e}")


def test_supervisor_and_proxy_running():
    supervisor_pids = get_running_pids('supervisor.py')
    assert len(supervisor_pids) > 0, "supervisor.py is not running."

    proxy_pids = get_running_pids('proxy.py')
    assert len(proxy_pids) > 0, "proxy.py is not running."


def test_supervisor_restarts_proxy():
    proxy_pids_before = get_running_pids('proxy.py')
    assert len(proxy_pids_before) > 0, "proxy.py is not running initially."

    for pid in proxy_pids_before:
        try:
            os.kill(pid, 9)
        except OSError:
            pass

    time.sleep(3)

    proxy_pids_after = get_running_pids('proxy.py')
    assert len(proxy_pids_after) > 0, "proxy.py was not restarted by supervisor after being killed."
    assert set(proxy_pids_before).isdisjoint(set(proxy_pids_after)), "proxy.py has the same PID, so it was not restarted."


def test_deploy_idempotent():
    try:
        subprocess.run(['python3', '/home/user/deploy.py'], check=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.py did not exit. It must run the supervisor in the background and exit.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"deploy.py failed when run a second time: {e}")

    time.sleep(1)

    supervisor_pids = get_running_pids('supervisor.py')
    supervisor_pids = [pid for pid in supervisor_pids if pid not in get_running_pids('deploy.py')]

    assert len(supervisor_pids) == 1, f"Expected exactly 1 supervisor.py running after redeploy, found {len(supervisor_pids)}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
