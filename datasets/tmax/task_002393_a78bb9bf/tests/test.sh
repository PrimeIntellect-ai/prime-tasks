#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import secrets
import signal
import socket
import time

import pytest
import requests


def djb2_hash(key: str) -> int:
    hash_val = 5381
    for char in key:
        hash_val = ((hash_val << 5) + hash_val) + ord(char)
        hash_val &= 0xFFFFFFFF
    return hash_val


def admin_flush(hashed_key: int) -> str:
    with socket.create_connection(('127.0.0.1', 9000), timeout=2) as s:
        s.sendall(f'FLUSH {hashed_key}\n'.encode())
        return s.recv(1024).decode().strip()


def listener_pids(port: int):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                if int(fields[1].rsplit(':', 1)[1], 16) == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def test_libhasher_compiled():
    path = '/app/c_lib/libhasher.so'
    assert os.path.isfile(path), 'The C library was not compiled to /app/c_lib/libhasher.so'
    assert pathlib.Path(path).read_bytes()[:4] == b'\x7fELF', 'libhasher.so is not an ELF shared library'
    try:
        library = ctypes.CDLL(path)
        function = library.hash_api_key
    except Exception as exc:
        pytest.fail(f'Could not load hash_api_key from libhasher.so: {exc}')
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_uint32
    for key in ('', 'testkey123', 'key-' + secrets.token_hex(8)):
        assert function(key.encode('ascii')) == djb2_hash(key)


def test_services_are_the_required_artifacts():
    proxy_path = pathlib.Path('/app/proxy/proxy.py')
    assert proxy_path.is_file(), '/app/proxy/proxy.py does not exist'
    compile(proxy_path.read_text(), str(proxy_path), 'exec')
    assert pathlib.Path('/app/node_api/node_modules/express').is_dir(), 'Express was not installed locally'

    node_pids = listener_pids(3001)
    http_pids = listener_pids(8080)
    admin_pids = listener_pids(9000)
    assert node_pids, 'Nothing is listening on port 3001'
    assert http_pids, 'Nothing is listening on port 8080'
    assert admin_pids, 'Nothing is listening on port 9000'

    for pid in node_pids:
        exe = os.path.basename(os.readlink(f'/proc/{pid}/exe')).lower()
        cmdline = pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        assert exe.startswith('node') and 'index.js' in cmdline, 'Port 3001 is not served by the Node API'

    for pid in http_pids | admin_pids:
        exe = os.path.basename(os.readlink(f'/proc/{pid}/exe')).lower()
        cmdline = pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        assert 'python' in exe and '/app/proxy/proxy.py' in cmdline, 'Proxy ports are not served by proxy.py'

    maps = ''
    for pid in http_pids | admin_pids:
        try:
            maps += pathlib.Path(f'/proc/{pid}/maps').read_text()
        except OSError:
            pass
    assert '/app/c_lib/libhasher.so' in maps, 'The running Python proxy has not loaded libhasher.so'

    direct = requests.get('http://127.0.0.1:3001/direct-' + secrets.token_hex(8), timeout=2)
    assert direct.status_code == 200 and direct.text == 'API_SUCCESS'


def test_proxy_missing_api_key():
    url = 'http://127.0.0.1:8080/test'
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to Python proxy on 127.0.0.1:8080: {e}')
    assert response.status_code == 401, f'Expected 401 Unauthorized when missing X-API-Key, got {response.status_code}'


def test_proxy_rate_limiting_and_admin_flush():
    url = 'http://127.0.0.1:8080/test'
    api_key = 'testkey123'
    headers = {'X-API-Key': api_key}
    for i in range(5):
        try:
            response = requests.get(url, headers=headers, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f'Failed to connect to Python proxy on request {i+1}: {e}')
        assert response.status_code == 200, f'Expected 200 OK on request {i+1}, got {response.status_code}'
        assert 'API_SUCCESS' in response.text, f'Expected API_SUCCESS in response body on request {i+1}, got {response.text}'

    response = requests.get(url, headers=headers, timeout=2)
    assert response.status_code == 429, f'Expected 429 Too Many Requests on 6th request, got {response.status_code}'
    assert admin_flush(djb2_hash(api_key)) == 'OK'
    response = requests.get(url, headers=headers, timeout=2)
    assert response.status_code == 200, f'Expected 200 OK after flush, got {response.status_code}'
    assert 'API_SUCCESS' in response.text


def test_general_paths_keys_and_per_key_admin_state():
    path = '/generated/' + secrets.token_hex(10) + '?value=' + secrets.token_hex(4)
    url = 'http://127.0.0.1:8080' + path
    key_a = 'A-' + secrets.token_hex(12)
    key_b = 'B-' + secrets.token_hex(12)

    for _ in range(5):
        response = requests.get(url, headers={'X-API-Key': key_a}, timeout=2)
        assert response.status_code == 200 and response.text == 'API_SUCCESS'
    assert requests.get(url, headers={'X-API-Key': key_a}, timeout=2).status_code == 429

    response = requests.get(url, headers={'X-API-Key': key_b}, timeout=2)
    assert response.status_code == 200 and response.text == 'API_SUCCESS'

    wrong_hash = (djb2_hash(key_a) + 1) & 0xFFFFFFFF
    assert admin_flush(wrong_hash) == 'OK'
    assert requests.get(url, headers={'X-API-Key': key_a}, timeout=2).status_code == 429
    assert admin_flush(djb2_hash(key_a)) == 'OK'
    response = requests.get(url, headers={'X-API-Key': key_a}, timeout=2)
    assert response.status_code == 200 and response.text == 'API_SUCCESS'


def test_sliding_window_expires():
    key = 'expiry-' + secrets.token_hex(12)
    url = 'http://127.0.0.1:8080/window/' + secrets.token_hex(8)
    headers = {'X-API-Key': key}
    for _ in range(5):
        assert requests.get(url, headers=headers, timeout=2).status_code == 200
    assert requests.get(url, headers=headers, timeout=2).status_code == 429
    time.sleep(10.5)
    response = requests.get(url, headers=headers, timeout=2)
    assert response.status_code == 200 and response.text == 'API_SUCCESS'


def test_proxy_depends_on_live_node_backend():
    node_pids = listener_pids(3001)
    assert node_pids
    key = 'backend-' + secrets.token_hex(12)
    url = 'http://127.0.0.1:8080/uncached-' + secrets.token_hex(16)
    for pid in node_pids:
        os.kill(pid, signal.SIGSTOP)
    try:
        try:
            response = requests.get(url, headers={'X-API-Key': key}, timeout=1)
        except requests.exceptions.RequestException:
            response = None
        if response is not None:
            assert not (response.status_code == 200 and response.text == 'API_SUCCESS'), 'Proxy returned a fabricated backend response while Node was stopped'
    finally:
        for pid in node_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
    time.sleep(0.5)
    response = requests.get(url + '-live', headers={'X-API-Key': 'live-' + secrets.token_hex(8)}, timeout=3)
    assert response.status_code == 200 and response.text == 'API_SUCCESS'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
