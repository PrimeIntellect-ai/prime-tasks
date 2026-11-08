#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import time
import secrets
import pytest


def read_pid(pid_file):
    if not os.path.exists(pid_file):
        return None
    try:
        with open(pid_file, 'r') as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def is_running(pid_file):
    pid = read_pid(pid_file)
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        with open(f'/proc/{pid}/stat', 'r') as f:
            return f.read().split()[2] != 'Z'
    except OSError:
        return False


def process_runs_script(pid, expected_script):
    if pid is None or not is_running_pid(pid):
        return False
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            args = [a.decode(errors='replace') for a in f.read().split(b'\0') if a]
        cwd = os.readlink(f'/proc/{pid}/cwd')
    except OSError:
        return False

    expected = os.path.realpath(expected_script)
    for arg in args:
        if not arg.endswith('.py'):
            continue
        candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        if os.path.realpath(candidate) == expected:
            return True
    return False


def is_running_pid(pid):
    try:
        os.kill(pid, 0)
        with open(f'/proc/{pid}/stat', 'r') as f:
            return f.read().split()[2] != 'Z'
    except OSError:
        return False


def script_pids(expected_script):
    result = set()
    for name in os.listdir('/proc'):
        if name.isdigit():
            pid = int(name)
            if process_runs_script(pid, expected_script):
                result.add(pid)
    return result


def wait_until(predicate, timeout, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return predicate()


def test_directories_and_repo():
    assert os.path.isdir('/home/user/repo/app.git/refs'), "Bare git repository not found at /home/user/repo/app.git"
    assert os.path.isdir('/home/user/deployments'), "/home/user/deployments directory missing"
    assert os.path.isdir('/home/user/logs'), "/home/user/logs directory missing"
    probe = subprocess.run(
        ['git', '--git-dir=/home/user/repo/app.git', 'rev-parse', '--is-bare-repository'],
        capture_output=True, text=True
    )
    assert probe.returncode == 0 and probe.stdout.strip() == 'true', "app.git is not a valid bare Git repository"


def test_git_hook():
    hook_path = '/home/user/repo/app.git/hooks/post-receive'
    assert os.path.isfile(hook_path), f"Hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), "Hook is not executable"
    with open(hook_path, 'r') as f:
        first_line = f.readline()
    assert 'python' in first_line.lower(), "Hook does not appear to be a Python script (missing python in shebang)"


def test_logrotate_conf():
    conf_path = '/home/user/logrotate.conf'
    assert os.path.isfile(conf_path), f"logrotate.conf not found at {conf_path}"
    with open(conf_path, 'r') as f:
        conf = f.read()

    # Preserve the original checks.
    assert 'rotate 5' in conf, "logrotate.conf missing 'rotate 5'"
    assert 'copytruncate' in conf, "logrotate.conf missing 'copytruncate'"
    assert 'compress' in conf, "logrotate.conf missing 'compress'"
    assert 'daily' in conf, "logrotate.conf missing 'daily'"
    assert '/home/user/logs/app.log' in conf, "logrotate.conf missing target /home/user/logs/app.log"

    # Require active, exact directives rather than comments or misleading substrings.
    active = '\n'.join(line.split('#', 1)[0] for line in conf.splitlines())
    assert re.search(r'(?m)^\s*(?:"/home/user/logs/app\.log"|/home/user/logs/app\.log)\s*\{?\s*$', active), "app.log is not an active logrotate target"
    assert re.search(r'(?m)^\s*rotate\s+5\s*$', active), "active 'rotate 5' directive missing"
    assert re.search(r'(?m)^\s*copytruncate\s*$', active), "active copytruncate directive missing"
    assert re.search(r'(?m)^\s*compress\s*$', active), "active compress directive missing"
    assert re.search(r'(?m)^\s*daily\s*$', active), "active daily directive missing"


def test_background_processes():
    assert is_running('/home/user/proxy.pid'), "Proxy process is not running or proxy.pid is missing/invalid"
    assert is_running('/home/user/monitor.pid'), "Monitor process is not running or monitor.pid is missing/invalid"
    proxy_pid = read_pid('/home/user/proxy.pid')
    monitor_pid = read_pid('/home/user/monitor.pid')
    assert process_runs_script(proxy_pid, '/home/user/proxy.py'), "proxy.pid does not identify the running proxy.py process"
    assert process_runs_script(monitor_pid, '/home/user/monitor.py'), "monitor.pid does not identify the running monitor.py process"


def test_full_workflow():
    server_secret = secrets.token_bytes(24)
    deployment_marker = secrets.token_hex(16)
    server_code = f'''#!/usr/bin/env python3
# deployment-marker: {deployment_marker}
import hashlib
import socket
import sys

SECRET = {server_secret!r}

def run():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 9090))
    s.listen(20)
    print("Server started on 9090")
    sys.stdout.flush()
    while True:
        conn, addr = s.accept()
        try:
            data = b""
            while not data.endswith(b"\\n"):
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            conn.sendall(hashlib.sha256(SECRET + data).hexdigest().encode())
        finally:
            conn.close()

if __name__ == "__main__":
    run()
'''

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(['git', 'init', '-b', 'master'], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(['git', 'config', 'user.email', 'test@example.com'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'config', 'user.name', 'Test User'], cwd=tmpdir, check=True)
        server_path = os.path.join(tmpdir, 'server.py')
        with open(server_path, 'w') as f:
            f.write(server_code)
        os.chmod(server_path, 0o755)
        subprocess.run(['git', 'add', 'server.py'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'commit', '-m', 'Verifier deployment'], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(['git', 'remote', 'add', 'origin', '/home/user/repo/app.git'], cwd=tmpdir, check=True)
        push_res = subprocess.run(
            ['git', 'push', '--force', 'origin', 'HEAD:refs/heads/master'],
            cwd=tmpdir, capture_output=True
        )
        assert push_res.returncode == 0, f"Git push failed: {push_res.stderr.decode()}"

    deployed = '/home/user/deployments/app/server.py'
    assert wait_until(lambda: os.path.isfile(deployed), 4), "server.py not checked out to /home/user/deployments/app"
    assert os.path.islink('/home/user/current_app'), "/home/user/current_app is not a symlink"
    assert os.readlink('/home/user/current_app') == '/home/user/deployments/app', "Symlink does not point to /home/user/deployments/app"
    with open(deployed, 'r') as f:
        assert deployment_marker in f.read(), "The hook did not check out the revision that was pushed"

    initial_pids = wait_until(lambda: script_pids('/home/user/current_app/server.py'), 6)
    assert initial_pids, "The post-receive hook did not start the deployed server.py"

    def proxy_request(payload, timeout=3):
        with socket.create_connection(('127.0.0.1', 8080), timeout=timeout) as s:
            s.settimeout(timeout)
            s.sendall(payload)
            s.shutdown(socket.SHUT_WR)
            response = b''
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
            return response

    # Stop the monitor and deployed server temporarily, then put an independently
    # controlled backend on 9090. This proves the proxy actually reaches port 9090.
    monitor_pid = read_pid('/home/user/monitor.pid')
    assert process_runs_script(monitor_pid, '/home/user/monitor.py')
    os.kill(monitor_pid, signal.SIGSTOP)
    backend = None
    try:
        for pid in script_pids('/home/user/current_app/server.py'):
            os.kill(pid, signal.SIGTERM)
        assert wait_until(lambda: not script_pids('/home/user/current_app/server.py'), 4), "Unable to stop deployed server for proxy test"

        backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        deadline = time.time() + 4
        while True:
            try:
                backend.bind(('127.0.0.1', 9090))
                break
            except OSError:
                if time.time() >= deadline:
                    raise
                time.sleep(0.1)
        backend.listen(10)
        backend.settimeout(6)

        backend_secret = secrets.token_bytes(32)
        payloads = [(secrets.token_bytes(40).hex().encode() + b'\n') for _ in range(4)]
        received = []
        backend_errors = []

        def serve_backend():
            try:
                for _ in payloads:
                    conn, _ = backend.accept()
                    with conn:
                        conn.settimeout(3)
                        data = b''
                        while not data.endswith(b'\n'):
                            chunk = conn.recv(4096)
                            if not chunk:
                                break
                            data += chunk
                        received.append(data)
                        conn.sendall(hashlib.sha256(backend_secret + data).digest())
            except Exception as exc:
                backend_errors.append(exc)

        thread = threading.Thread(target=serve_backend, daemon=True)
        thread.start()
        for payload in payloads:
            expected = hashlib.sha256(backend_secret + payload).digest()
            assert proxy_request(payload) == expected, "Proxy did not forward arbitrary traffic to the server correctly"
        thread.join(4)
        assert not backend_errors, f"Backend failed while testing proxy forwarding: {backend_errors}"
        assert received == payloads, "Traffic sent to the proxy did not arrive unchanged at port 9090"
    finally:
        if backend is not None:
            backend.close()
        try:
            os.kill(monitor_pid, signal.SIGCONT)
        except OSError:
            pass

    # The monitor must start the actual deployed server after the independent
    # backend disappears, not merely leave some unrelated live PID behind.
    restarted = wait_until(lambda: script_pids('/home/user/current_app/server.py'), 12)
    assert restarted, "Monitor did not restart the deployed server.py after it was killed"
    assert restarted.isdisjoint(initial_pids), "Monitor did not create a new server.py process"

    payload = secrets.token_bytes(30).hex().encode() + b'\n'
    expected = hashlib.sha256(server_secret + payload).hexdigest().encode()
    assert wait_until(lambda: _proxy_matches(proxy_request, payload, expected), 5), "Restarted server is not reachable through the proxy"

    # Kill it a second time to verify that monitor.py continues monitoring rather
    # than performing one fixed delayed launch.
    first_restart = set(restarted)
    for pid in first_restart:
        os.kill(pid, signal.SIGTERM)
    assert wait_until(lambda: not (script_pids('/home/user/current_app/server.py') & first_restart), 4), "Restarted server did not terminate"
    second_restart = wait_until(
        lambda: script_pids('/home/user/current_app/server.py') - first_restart,
        12
    )
    assert second_restart, "Monitor did not continuously restart server.py after a second failure"

    payload2 = secrets.token_bytes(35).hex().encode() + b'\n'
    expected2 = hashlib.sha256(server_secret + payload2).hexdigest().encode()
    assert wait_until(lambda: _proxy_matches(proxy_request, payload2, expected2), 5), "Proxy did not reach the server after the second monitor restart"

    log_path = '/home/user/logs/app.log'
    assert os.path.isfile(log_path), "Log file /home/user/logs/app.log not created"
    assert os.path.getsize(log_path) > 0, "Log file /home/user/logs/app.log is empty"


def _proxy_matches(request_fn, payload, expected):
    try:
        return request_fn(payload) == expected
    except Exception:
        return False
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
