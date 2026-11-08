#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import random
import signal
import socket
import stat
import string
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

APP_PATH = "/home/user/backend/app.py"
CONFIG_PATH = "/home/user/backend/config.json"
WATCHER_PATH = "/home/user/watcher.sh"
PROXY_PATH = "/home/user/proxy.py"
CHECK_PATH = "/home/user/check.py"
RESULT_PATH = "/home/user/result.log"

EXPECTED_CONFIG = '''{
    "status": "Service_Operational_9921"
}
'''

EXPECTED_APP = '''import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            try:
                with open('config.json', 'r') as f:
                    data = json.load(f)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(data).encode('utf-8'))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    # Deliberately crash if config.json is not in the current working directory
    if not os.path.exists('config.json'):
        raise FileNotFoundError("config.json not found in the current working directory. Startup failed.")
    server = HTTPServer(('127.0.0.1', 9090), RequestHandler)
    server.serve_forever()
'''


def listening_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(':', 1)[1], 16) == port and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pids(port):
    inodes = listening_inodes(port)
    result = set()
    if not inodes:
        return result
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
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return result


def kill_port(port):
    pids = listener_pids(port)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(port):
        time.sleep(0.05)
    assert not listening_inodes(port), f"Could not clear port {port}"


def wait_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.2)
            if s.connect_ex(('127.0.0.1', port)) == 0:
                return
        time.sleep(0.05)
    raise AssertionError(f"Port {port} did not become ready")


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except FileNotFoundError:
        return ''


def launch_watcher():
    completed = subprocess.run(
        [WATCHER_PATH], cwd='/', timeout=5,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    assert completed.returncode == 0, "watcher.sh exited unsuccessfully"
    wait_port(9090)
    pids = listener_pids(9090)
    assert pids, "watcher.sh did not start a listener on port 9090"
    assert any(APP_PATH in cmdline(pid) for pid in pids), (
        "The port 9090 listener started by watcher.sh is not backend/app.py"
    )


def launch_proxy():
    subprocess.Popen(
        ['python3', PROXY_PATH], cwd='/',
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_port(8080)
    pids = listener_pids(8080)
    assert pids, "proxy.py did not listen on port 8080"
    assert any(PROXY_PATH in cmdline(pid) for pid in pids), (
        "The port 8080 listener is not /home/user/proxy.py"
    )


def request(port, path):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
    connection.request('GET', path)
    response = connection.getresponse()
    status = response.status
    headers = response.getheaders()
    body = response.read()
    connection.close()
    return status, headers, body


def test_00_execute_and_exercise_required_artifacts():
    for path in (WATCHER_PATH, PROXY_PATH, CHECK_PATH):
        assert os.path.exists(path), f"Required artifact {path} does not exist"
        assert not os.path.islink(path), f"Required artifact {path} must not be a symlink"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required artifact {path} is not a regular file"

    assert os.access(WATCHER_PATH, os.X_OK), "watcher.sh is not executable"
    with open(APP_PATH, 'r') as f:
        assert f.read() == EXPECTED_APP, "app.py was altered"
    with open(CONFIG_PATH, 'r') as f:
        assert f.read() == EXPECTED_CONFIG, "config.json was altered"

    kill_port(8080)
    kill_port(9090)
    launch_watcher()

    status, _, body = request(9090, '/api/health')
    assert status == 200
    assert json.loads(body.decode())['status'] == 'Service_Operational_9921'

    launch_proxy()

    # Replace the backend temporarily with a verifier-controlled service. Its
    # responses are derived from fresh random data and exercise arbitrary GET
    # paths, non-200 statuses, headers, and bodies.
    kill_port(9090)
    token = ''.join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=28))
    random_status = 'Verifier_' + token

    paths = [
        '/api/health',
        '/items/' + token,
        '/search?q=' + token + '&page=3',
        '/missing/' + token,
    ]

    def expected_for(path):
        if path == '/api/health':
            code = 200
            body = json.dumps({'status': random_status, 'nonce': token}, separators=(',', ':')).encode()
        elif path.startswith('/items/'):
            code = 201
            body = ('created:' + path + ':' + token).encode()
        elif path.startswith('/search?'):
            code = 202
            body = ('query:' + path + ':' + token).encode()
        else:
            code = 404
            body = ('not-found:' + path + ':' + token).encode()
        headers = [
            ('Content-Type', 'application/json' if path == '/api/health' else 'application/octet-stream'),
            ('X-Backend-Token', token),
            ('X-Request-Path', path),
            ('Content-Length', str(len(body))),
        ]
        return code, headers, body

    class ChallengeHandler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def do_GET(self):
            code, headers, body = expected_for(self.path)
            self.send_response_only(code)
            for name, value in headers:
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = HTTPServer(('127.0.0.1', 9090), ChallengeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    wait_port(9090)

    try:
        for path in paths:
            actual = request(8080, path)
            expected = expected_for(path)
            assert actual[0] == expected[0], f"Proxy changed status for {path}"
            assert actual[1] == expected[1], f"Proxy changed headers for {path}: {actual[1]!r} != {expected[1]!r}"
            assert actual[2] == expected[2], f"Proxy changed body for {path}"

        if os.path.exists(RESULT_PATH):
            os.unlink(RESULT_PATH)
        completed = subprocess.run(
            ['python3', CHECK_PATH], cwd='/', timeout=5,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
        )
        assert completed.returncode == 0, f"check.py failed: {completed.stderr}"
        assert os.path.isfile(RESULT_PATH), "check.py did not create result.log"
        with open(RESULT_PATH) as f:
            assert f.read().strip() == random_status, "check.py did not extract the live JSON status"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    # Restore the required final state using watcher.sh and regenerate the
    # original result through check.py.
    launch_watcher()
    completed = subprocess.run(
        ['python3', CHECK_PATH], cwd='/', timeout=5,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
    )
    assert completed.returncode == 0, f"check.py failed against restored backend: {completed.stderr}"


def test_result_log_content():
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    expected_status = "Service_Operational_9921"
    assert content == expected_status, f"Expected '{expected_status}' in {log_path}, got '{content}'."


def test_backend_listening():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        result = s.connect_ex(('127.0.0.1', 9090))
        assert result == 0, "No process is listening on 127.0.0.1:9090 (backend service)."


def test_proxy_listening():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2)
        result = s.connect_ex(('127.0.0.1', 8080))
        assert result == 0, "No process is listening on 127.0.0.1:8080 (reverse proxy)."


def test_proxy_functionality():
    status, _, body = request(8080, '/api/health')
    assert status == 200, f"Expected HTTP 200 from proxy, got {status}."
    data = json.loads(body.decode('utf-8'))
    expected_status = "Service_Operational_9921"
    assert "status" in data, "Response JSON does not contain 'status' key."
    assert data["status"] == expected_status, f"Expected status '{expected_status}' from proxy, got '{data['status']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
