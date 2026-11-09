#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.request

SOCKET_PATH = '/home/user/backend.sock'
BACKEND_PATH = '/home/user/backend'


def socket_owner_pids(path):
    inode = None
    try:
        with open('/proc/net/unix', 'r') as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 8 and parts[-1] == path:
                    inode = parts[6]
    except OSError:
        return []
    if inode is None:
        return []

    target = f'socket:[{inode}]'
    owners = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f'{fd_dir}/{fd}') == target:
                        owners.append(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def stop_socket_server():
    for pid in socket_owner_pids(SOCKET_PATH):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and socket_owner_pids(SOCKET_PATH):
        time.sleep(0.05)
    for pid in socket_owner_pids(SOCKET_PATH):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


def wait_for_backend(expected_exe, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(SOCKET_PATH) and stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode):
            owners = socket_owner_pids(SOCKET_PATH)
            for pid in owners:
                try:
                    if os.path.realpath(f'/proc/{pid}/exe') == os.path.realpath(expected_exe):
                        return pid
                except OSError:
                    pass
        time.sleep(0.05)
    raise AssertionError(f'{expected_exe} did not create and own {SOCKET_PATH}')


def request_unix_socket():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect(SOCKET_PATH)
        s.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')
        chunks = []
        while True:
            data = s.recv(4096)
            if not data:
                break
            chunks.append(data)
    finally:
        s.close()
    response = b''.join(chunks)
    head, sep, body = response.partition(b'\r\n\r\n')
    assert sep, f'Backend returned a malformed HTTP response: {response!r}'
    assert head.startswith(b'HTTP/1.0 200') or head.startswith(b'HTTP/1.1 200'), head
    assert body == b'Backend active\n', f'Backend returned incorrect body: {body!r}'


def test_result_log_contents():
    log_path = '/home/user/result.log'
    assert os.path.isfile(log_path), f'File {log_path} is missing.'
    with open(log_path, 'r') as f:
        content = f.read()
    assert 'Backend active' in content, f"Expected 'Backend active' in {log_path}, got: {content}"
    assert content == 'Backend active\n', f'Unexpected contents in {log_path}: {content!r}'


def test_crontab_configured():
    try:
        output = subprocess.check_output(['crontab', '-l'], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        output = e.output
    assert '/home/user/start_backend.sh' in output, 'crontab does not contain a reference to /home/user/start_backend.sh'
    active = [line.strip() for line in output.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    assert any(re.match(r'^\*\s+\*\s+\*\s+\*\s+\*\s+/home/user/start_backend\.sh(?:\s|$)', line) for line in active), \
        'crontab does not run /home/user/start_backend.sh every minute'


def test_main_go_exists():
    go_path = '/home/user/main.go'
    assert os.path.isfile(go_path), f'File {go_path} is missing.'
    with open(go_path, 'r') as f:
        content = f.read()
    assert 'package main' in content, f'{go_path} does not appear to be valid Go code.'


def test_backend_executable_exists():
    exe_path = BACKEND_PATH
    assert os.path.isfile(exe_path), f'Executable {exe_path} is missing.'
    assert os.access(exe_path, os.X_OK), f'File {exe_path} is not executable.'
    info = subprocess.run(['go', 'version', '-m', exe_path], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert info.returncode == 0 and re.search(r'\bgo1\d', info.stdout), \
        f'{exe_path} is not a Go executable: {info.stdout}'


def test_start_script_exists_and_executable():
    script_path = '/home/user/start_backend.sh'
    assert os.path.isfile(script_path), f'Script {script_path} is missing.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} is not executable.'


def test_backend_socket_exists():
    sock_path = SOCKET_PATH
    assert os.path.exists(sock_path), f'Socket {sock_path} is missing.'
    mode = os.stat(sock_path).st_mode
    assert stat.S_ISSOCK(mode), f'File {sock_path} is not a socket.'


def test_go_source_binary_and_wrapper_really_work():
    # Compile and execute main.go, proving it is a functional Go implementation.
    build_dir = tempfile.mkdtemp(prefix='backend-build-')
    rebuilt = os.path.join(build_dir, 'backend-from-source')
    build = subprocess.run(['go', 'build', '-o', rebuilt, '/home/user/main.go'], text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, f'/home/user/main.go does not compile: {build.stdout}'

    stop_socket_server()
    source_proc = subprocess.Popen([rebuilt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_backend(rebuilt)
        assert source_proc.poll() is None, 'Backend built from main.go exited prematurely'
        request_unix_socket()
    finally:
        source_proc.terminate()
        try:
            source_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            source_proc.kill()
        stop_socket_server()

    # Execute the submitted Go binary itself and verify that it owns the socket.
    binary_proc = subprocess.Popen(['runuser', '-u', 'user', '--', BACKEND_PATH],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_backend(BACKEND_PATH)
        assert binary_proc.poll() is None, 'Submitted backend executable exited prematurely'
        request_unix_socket()
    finally:
        binary_proc.terminate()
        try:
            binary_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            binary_proc.kill()
        stop_socket_server()

    # Finally exercise the required persistent start wrapper. It must return after
    # launching /home/user/backend in the background, and that binary must own the socket.
    wrapper = subprocess.run(['runuser', '-u', 'user', '--', '/home/user/start_backend.sh'],
                             timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    assert wrapper.returncode == 0, f'start_backend.sh failed: {wrapper.stderr}'
    wait_for_backend(BACKEND_PATH)
    request_unix_socket()


def test_nginx_proxy_working():
    nginx_with_config = False
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            cmdline = open(f'/proc/{entry}/cmdline', 'rb').read().replace(b'\0', b' ').decode('utf-8', 'replace')
        except OSError:
            continue
        if 'nginx' in cmdline and '/home/user/nginx.conf' in cmdline:
            nginx_with_config = True
            break
    assert nginx_with_config, 'Nginx is not running with /home/user/nginx.conf'

    try:
        req = urllib.request.Request('http://127.0.0.1:8888/')
        with urllib.request.urlopen(req, timeout=5) as response:
            content = response.read().decode('utf-8')
            assert 'Backend active' in content, 'Nginx proxy did not return the expected backend response.'
            assert content == 'Backend active\n', f'Nginx returned an unexpected body: {content!r}'
    except Exception as e:
        assert False, f'Failed to connect to Nginx proxy or retrieve backend response: {e}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
