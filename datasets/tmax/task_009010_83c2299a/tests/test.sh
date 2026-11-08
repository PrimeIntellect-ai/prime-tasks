#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import secrets
import socket
import stat
import subprocess
import threading
import urllib.request
import urllib.error
import pytest


def listening_pids(address, port):
    """Return PIDs owning an IPv4 TCP listener at the exact address and port."""
    octets = address.split('.')
    addr_hex = ''.join(f'{int(x):02X}' for x in reversed(octets))
    endpoint = f'{addr_hex}:{port:04X}'
    inodes = set()

    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == endpoint and fields[3] == '0A':
                inodes.add(fields[9])

    pids = set()
    for proc_dir in glob.glob('/proc/[0-9]*'):
        pid = int(proc_dir.rsplit('/', 1)[1])
        for fd in glob.glob(proc_dir + '/fd/*'):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.digest()


def recv_exact(conn, length):
    chunks = []
    remaining = length
    while remaining:
        chunk = conn.recv(remaining)
        if not chunk:
            raise AssertionError(f'Connection closed with {remaining} bytes still expected')
        chunks.append(chunk)
        remaining -= len(chunk)
    return b''.join(chunks)


def test_backend_permissions_fixed():
    """Verify that the permissions on /home/user/backend are no longer 000."""
    path = "/home/user/backend"
    assert os.path.exists(path), f"Directory {path} does not exist."
    st = os.stat(path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms != 0, f"Permissions on {path} are still 000. They must be fixed to allow access."


def test_symlink_logs_created():
    """Verify that /home/user/logs is a symlink to /home/user/backend/logs."""
    link_path = "/home/user/logs"
    target_path = "/home/user/backend/logs"

    assert os.path.islink(link_path), f"{link_path} is not a symbolic link."
    actual_target = os.readlink(link_path)
    assert actual_target == target_path, f"Symlink {link_path} points to {actual_target}, expected {target_path}."


def test_startup_log_exists():
    """Verify that the Rust application wrote startup.log into the logs directory."""
    log_file = "/home/user/logs/startup.log"
    assert os.path.isfile(log_file), f"Startup log file {log_file} does not exist."


def test_final_output_content():
    """Verify that final_output.txt contains the correct backend response."""
    output_file = "/home/user/final_output.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected_content = "BACKEND_SUCCESS_77812"
    assert content == expected_content, f"Content of {output_file} was '{content}', expected '{expected_content}'."


def test_rust_project_compiled_and_is_listener():
    project = '/home/user/rust_forwarder'
    manifest = os.path.join(project, 'Cargo.toml')
    assert os.path.isdir(project), f'Rust project directory {project} does not exist.'
    assert os.path.isfile(manifest), f'{manifest} does not exist.'
    assert glob.glob(os.path.join(project, 'src', '**', '*.rs'), recursive=True), 'Rust project has no .rs source files.'

    result = subprocess.run(
        ['cargo', 'build', '--offline', '--manifest-path', manifest],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert result.returncode == 0, f'Rust project does not compile:\n{result.stdout}'

    pids = listening_pids('127.0.0.1', 8081)
    assert pids, 'No process is listening on 127.0.0.1:8081.'

    built_hashes = set()
    target_dir = os.path.join(project, 'target')
    for root, dirs, files in os.walk(target_dir):
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    with open(path, 'rb') as f:
                        if f.read(4) == b'\x7fELF':
                            built_hashes.add(file_hash(path))
            except OSError:
                pass
    assert built_hashes, 'Cargo produced no executable artifact under the project target directory.'

    matched = False
    for pid in pids:
        exe = f'/proc/{pid}/exe'
        try:
            with open(exe, 'rb') as f:
                assert f.read(4) == b'\x7fELF'
            if file_hash(exe) in built_hashes:
                matched = True
                break
        except (OSError, AssertionError):
            continue
    assert matched, 'The process listening on 127.0.0.1:8081 is not a compiled artifact of the Rust project.'

    nginx_pids = listening_pids('127.0.0.1', 8080)
    assert nginx_pids, 'No process is listening on 127.0.0.1:8080.'
    assert any(os.path.basename(os.readlink(f'/proc/{pid}/exe')).startswith('nginx')
               for pid in nginx_pids if os.path.exists(f'/proc/{pid}/exe')), \
        'The listener on 127.0.0.1:8080 is not Nginx.'


def test_forwarder_bridges_dynamic_bidirectional_traffic():
    """Replace the socket briefly with a challenge backend and test both forwarding hops."""
    socket_path = '/home/user/backend/app.sock'
    saved_path = f'/home/user/backend/app.sock.verifier-{os.getpid()}'
    assert os.path.exists(socket_path), f'Backend socket {socket_path} is missing.'

    first = secrets.token_bytes(193)
    second = secrets.token_bytes(127)
    first_reply = secrets.token_bytes(211)
    second_reply = hashlib.sha256(first + second).digest()
    http_token = secrets.token_hex(20)
    http_body = ('DYNAMIC_BACKEND_' + secrets.token_hex(24)).encode()
    observations = {}
    server_errors = []
    server = None

    os.rename(socket_path, saved_path)
    try:
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(socket_path)
        server.listen(4)

        def challenge_backend():
            try:
                conn, _ = server.accept()
                with conn:
                    observations['first'] = recv_exact(conn, len(first))
                    conn.sendall(first_reply[:73])
                    conn.sendall(first_reply[73:])
                    observations['second'] = recv_exact(conn, len(second))
                    conn.sendall(second_reply)

                conn, _ = server.accept()
                with conn:
                    request = b''
                    while b'\r\n\r\n' not in request and len(request) < 65536:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        request += chunk
                    observations['http'] = request
                    response = (b'HTTP/1.1 200 OK\r\nContent-Length: ' +
                                str(len(http_body)).encode() +
                                b'\r\nConnection: close\r\n\r\n' + http_body)
                    conn.sendall(response)
            except BaseException as exc:
                server_errors.append(exc)

        thread = threading.Thread(target=challenge_backend, daemon=True)
        thread.start()

        with socket.create_connection(('127.0.0.1', 8081), timeout=3) as client:
            client.settimeout(3)
            client.sendall(first)
            assert recv_exact(client, len(first_reply)) == first_reply
            client.sendall(second)
            assert recv_exact(client, len(second_reply)) == second_reply

        url = f'http://127.0.0.1:8080/api?verifier_token={http_token}'
        with urllib.request.urlopen(url, timeout=3) as response:
            assert response.read() == http_body

        thread.join(3)
        assert not thread.is_alive(), 'Challenge backend did not finish; traffic was not fully forwarded.'
        assert not server_errors, f'Challenge backend failed: {server_errors}'
        assert observations.get('first') == first
        assert observations.get('second') == second
        assert http_token.encode() in observations.get('http', b'')
    finally:
        if server is not None:
            server.close()
        try:
            if os.path.lexists(socket_path):
                os.unlink(socket_path)
        finally:
            if os.path.lexists(saved_path):
                os.rename(saved_path, socket_path)


def test_nginx_and_forwarder_active():
    """Verify that Nginx is running and proxying through the Rust forwarder successfully."""
    url = "http://127.0.0.1:8080/api"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode('utf-8').strip()
            assert body == "BACKEND_SUCCESS_77812", f"Live request to {url} returned '{body}', expected 'BACKEND_SUCCESS_77812'."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url} or received an error. Is Nginx and the Rust forwarder running? Error: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
