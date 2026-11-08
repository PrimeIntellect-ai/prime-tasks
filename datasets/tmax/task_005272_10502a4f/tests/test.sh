#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import signal
import socket
import ssl
import subprocess
import time
from pathlib import Path

import pytest
import requests

HOME = Path('/home/user')
VIDEO = Path('/app/server_status.mp4')
EXPECTED = None
GATEWAY_PROC = None


def listening_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == '0A':
                if int(fields[1].rsplit(':', 1)[1], 16) == port:
                    inodes.add(fields[9])
    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m and m.group(1) in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            pass
    return pids


def kill_port(port):
    pids = listening_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.05)
    for pid in listening_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.05)
    assert not listening_pids(port), f'Could not free port {port}'


def demote_to_user():
    account = pwd.getpwnam('user')
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def start_program(path):
    proc = subprocess.Popen(
        [str(path)], cwd='/home/user', stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=demote_to_user, start_new_session=True)
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f'{path} exited early with status {proc.returncode}')
        if listening_pids(8080):
            return proc
        time.sleep(0.05)
    proc.terminate()
    pytest.fail(f'{path} did not listen on 127.0.0.1:8080')


def raw_http(port, authorization=None):
    headers = ['GET /metrics HTTP/1.1', f'Host: 127.0.0.1:{port}', 'Connection: close']
    if authorization is not None:
        headers.append(f'Authorization: {authorization}')
    request = ('\r\n'.join(headers) + '\r\n\r\n').encode()
    with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
        sock.sendall(request)
        chunks = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
    response = b''.join(chunks)
    head, sep, body = response.partition(b'\r\n\r\n')
    assert sep, f'Malformed HTTP response: {response!r}'
    status = int(head.split(b'\r\n', 1)[0].split()[1])
    return status, body.decode('utf-8', errors='replace')


def assert_backend_behavior(expected):
    status, body = raw_http(8080, 'Bearer SRE-SECRET-TOKEN')
    assert status == 200
    assert body.strip() == f'downtime_events_total {expected}'
    assert len(body.strip().splitlines()) == 1
    status, _ = raw_http(8080, None)
    assert status == 401
    status, _ = raw_http(8080, 'Bearer wrong-token')
    assert status == 401


def derive_flash_count():
    assert VIDEO.is_file(), f'Missing video {VIDEO}'
    result = subprocess.run([
        'ffmpeg', '-v', 'error', '-i', str(VIDEO),
        '-vf', 'fps=25,scale=1:1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'
    ], check=True, stdout=subprocess.PIPE)
    pixels = result.stdout
    assert pixels and len(pixels) % 3 == 0
    count = 0
    was_red = False
    for i in range(0, len(pixels), 3):
        r, g, b = pixels[i:i+3]
        is_red = r > 180 and g < 100 and b < 100 and r > g * 2
        if is_red and not was_red:
            count += 1
        was_red = is_red
    assert count > 0
    return count


def test_setup_script_exists_and_executable():
    script_path = '/home/user/setup_gateway.sh'
    assert os.path.isfile(script_path), f'Setup script missing at {script_path}'
    assert os.access(script_path, os.X_OK), f'Setup script at {script_path} is not executable'


def test_gateway_source_compiles_and_artifacts_exist():
    assert Path('/home/user/gateway.cpp').is_file(), 'gateway.cpp is missing'
    gateway = Path('/home/user/gateway')
    assert gateway.is_file(), 'Compiled gateway is missing'
    assert os.access(gateway, os.X_OK), 'Compiled gateway is not executable'
    assert gateway.read_bytes()[:4] == b'\x7fELF', 'gateway is not an ELF executable'
    subprocess.run([
        'g++', '-std=c++17', '-O2', '-pthread', '/home/user/gateway.cpp',
        '-o', '/tmp/gateway_from_source'
    ], check=True, timeout=30)
    assert Path('/tmp/gateway_from_source').read_bytes()[:4] == b'\x7fELF'


def test_setup_script_is_idempotent_as_user():
    for _ in range(2):
        subprocess.run(
            ['runuser', '-u', 'user', '--', '/home/user/setup_gateway.sh'],
            check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_logrotate_conf():
    conf_path = '/home/user/logrotate.conf'
    assert os.path.isfile(conf_path), f'logrotate.conf missing at {conf_path}'
    content = Path(conf_path).read_text()
    assert '/home/user/logs/access.log' in content, 'logrotate.conf does not target /home/user/logs/access.log'
    assert 'daily' in content, "logrotate.conf missing 'daily' directive"
    assert re.search(r'\brotate\s+3\b', content), "logrotate.conf missing 'rotate 3' directive"
    assert re.search(r'\bcompress\b', content), "logrotate.conf missing 'compress' directive"
    subprocess.run(['logrotate', '-d', conf_path], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_nginx_configuration_and_tls_files():
    conf = Path('/home/user/nginx.conf')
    assert conf.is_file(), 'nginx.conf is missing'
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'nginx', '-T', '-p', '/home/user', '-c', str(conf)],
        check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = result.stdout
    assert re.search(r'listen\s+127\.0\.0\.1:8443\s+ssl\b', text), 'Missing TLS listen on 127.0.0.1:8443'
    assert re.search(r'location\s+/\s*\{[^}]*proxy_pass\s+http://127\.0\.0\.1:8080\s*;', text, re.S), 'Nginx does not proxy all requests to the C++ backend'
    assert re.search(r'access_log\s+/home/user/logs/access\.log\b', text)
    assert re.search(r'error_log\s+/home/user/logs/error\.log\b', text)
    cert_match = re.search(r'ssl_certificate\s+([^;]+);', text)
    key_match = re.search(r'ssl_certificate_key\s+([^;]+);', text)
    assert cert_match and key_match, 'TLS certificate directives are missing'
    cert = Path(cert_match.group(1).strip())
    key = Path(key_match.group(1).strip())
    assert str(cert).startswith('/home/user/certs/') and cert.is_file()
    assert str(key).startswith('/home/user/certs/') and key.is_file()
    subprocess.run(['openssl', 'x509', '-in', str(cert), '-noout'], check=True, stdout=subprocess.PIPE)
    subprocess.run(['openssl', 'pkey', '-in', str(key), '-noout'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(['openssl', 'verify', '-CAfile', str(cert), str(cert)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    cert_pub = subprocess.check_output(['openssl', 'x509', '-in', str(cert), '-pubkey', '-noout'])
    key_pub = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-pubout'])
    assert cert_pub == key_pub, 'TLS certificate and private key do not match'


def test_compiled_source_and_installed_gateway_behavior():
    global EXPECTED, GATEWAY_PROC
    EXPECTED = derive_flash_count()
    kill_port(8080)
    source_proc = start_program('/tmp/gateway_from_source')
    try:
        assert_backend_behavior(EXPECTED)
    finally:
        source_proc.terminate()
        try:
            source_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            source_proc.kill()
        kill_port(8080)
    GATEWAY_PROC = start_program('/home/user/gateway')
    assert_backend_behavior(EXPECTED)
    pids = listening_pids(8080)
    assert pids, 'Gateway C++ backend is not running'
    assert any(os.path.realpath(f'/proc/{pid}/exe') == '/home/user/gateway' for pid in pids), 'Port 8080 is not served by /home/user/gateway'


def test_nginx_running_and_https_proxying():
    global GATEWAY_PROC
    assert EXPECTED is not None and GATEWAY_PROC is not None
    pids = listening_pids(8443)
    assert pids, 'Nginx is not running on port 8443'
    assert all(os.path.basename(os.path.realpath(f'/proc/{pid}/exe')).startswith('nginx') for pid in pids), 'Port 8443 is not served by Nginx'

    requests.packages.urllib3.disable_warnings()
    url = 'https://127.0.0.1:8443/metrics'
    response = requests.get(url, headers={'Authorization': 'Bearer SRE-SECRET-TOKEN'}, verify=False, timeout=5)
    assert response.status_code == 200, f'Expected status 200, got {response.status_code}'
    assert response.text.strip() == f'downtime_events_total {EXPECTED}'
    assert len(response.text.strip().splitlines()) == 1

    response = requests.get(url, verify=False, timeout=5)
    assert response.status_code == 401, f'Expected status 401, got {response.status_code}'
    response = requests.get(url, headers={'Authorization': 'Bearer incorrect'}, verify=False, timeout=5)
    assert response.status_code == 401, f'Expected status 401 for incorrect token, got {response.status_code}'

    expanded = subprocess.check_output(
        ['runuser', '-u', 'user', '--', 'nginx', '-T', '-p', '/home/user', '-c', '/home/user/nginx.conf'],
        text=True, stderr=subprocess.STDOUT)
    cert_path = re.search(r'ssl_certificate\s+([^;]+);', expanded).group(1).strip()
    expected_der = subprocess.check_output(['openssl', 'x509', '-in', cert_path, '-outform', 'DER'])
    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', 8443), timeout=3) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as tls:
            assert tls.getpeercert(binary_form=True) == expected_der, 'Endpoint is not serving the configured certificate'

    GATEWAY_PROC.terminate()
    try:
        GATEWAY_PROC.wait(timeout=2)
    except subprocess.TimeoutExpired:
        GATEWAY_PROC.kill()
    kill_port(8080)
    response = requests.get(url, headers={'Authorization': 'Bearer SRE-SECRET-TOKEN'}, verify=False, timeout=5)
    assert response.status_code in (502, 504), 'HTTPS response did not fail when the proxied backend was stopped'

    GATEWAY_PROC = start_program('/home/user/gateway')
    response = requests.get(url, headers={'Authorization': 'Bearer SRE-SECRET-TOKEN'}, verify=False, timeout=5)
    assert response.status_code == 200
    assert response.text.strip() == f'downtime_events_total {EXPECTED}'
    assert Path('/home/user/logs/access.log').is_file()
    assert Path('/home/user/logs/error.log').is_file()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
