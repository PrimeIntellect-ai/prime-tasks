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
import ctypes
import os
import random
import re
import socket
import subprocess

import pytest
import requests

LIB_PATH = "/home/user/app/lib/libtransform.so"
NGINX_CONF = "/home/user/app/nginx/nginx.conf"
PROXY_URL = "http://127.0.0.1:8080/api/process"
BACKEND_URL = "http://127.0.0.1:9000/process"


def oracle(data):
    lib = ctypes.CDLL(LIB_PATH)
    fn = lib.transform_data_v2
    fn.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p]
    fn.restype = ctypes.c_int
    output = ctypes.create_string_buffer(len(data) + 1)
    result = fn(data, len(data), output)
    assert result == len(data)
    return output.raw[:result]


def post(url, data):
    try:
        response = requests.post(url, data=data, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Connection refused to {url}.")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out.")
    assert response.status_code == 200, (
        f"Expected status 200 from {url}, got {response.status_code}. "
        f"Response: {response.content!r}"
    )
    return response.content


def listeners(port):
    found = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state != "0A":
                continue
            address_hex, port_hex = local.split(":")
            if int(port_hex, 16) != port:
                continue
            inode = fields[9]
            if table.endswith("tcp"):
                address = socket.inet_ntoa(bytes.fromhex(address_hex)[::-1])
            else:
                address = address_hex
            pids = set()
            for name in os.listdir("/proc"):
                if not name.isdigit():
                    continue
                fd_dir = f"/proc/{name}/fd"
                try:
                    for fd in os.listdir(fd_dir):
                        try:
                            if os.readlink(f"{fd_dir}/{fd}") == f"socket:[{inode}]":
                                pids.add(int(name))
                                break
                        except OSError:
                            pass
                except OSError:
                    pass
            found.append((address, inode, pids))
    return found


def descendants(pid):
    result = {pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit() or int(name) in result:
                continue
            try:
                status = open(f"/proc/{name}/status").read()
                parent = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
            except (OSError, AttributeError):
                continue
            if parent in result:
                result.add(int(name))
                changed = True
    return result


def test_tcp_health_check():
    host = "127.0.0.1"
    port = 9001
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(b"PING\n")
            data = s.recv(1024)
            assert data == b"PONG\n", f"Expected b'PONG\\n', got {data!r}"
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused to {host}:{port}. Is the TCP health check service running?")
    except socket.timeout:
        pytest.fail(f"Connection to {host}:{port} timed out.")
    except Exception as e:
        pytest.fail(f"Failed to connect and communicate with TCP health check: {e}")


def test_http_process_hello():
    data = b"hello"
    expected = b"ifmmp"
    assert post(PROXY_URL, data) == expected


def test_http_process_data_processing():
    data = b"data processing"
    expected = b"ebub!qspdfttjoh"
    assert post(PROXY_URL, data) == expected


def test_backend_and_proxy_on_unpredictable_inputs():
    rng = random.SystemRandom()
    alphabet = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !?_-"
    samples = []
    for _ in range(8):
        length = rng.randint(1, 96)
        samples.append(bytes(rng.choice(alphabet) for _ in range(length)))

    for data in samples:
        expected = oracle(data)
        assert post(BACKEND_URL, data) == expected
        assert post(PROXY_URL, data) == expected


def test_required_listeners_and_nginx_process():
    backend = listeners(9000)
    health = listeners(9001)
    proxy = listeners(8080)
    assert any(address == "127.0.0.1" for address, _, _ in backend), "Backend is not listening on 127.0.0.1:9000"
    assert any(address == "127.0.0.1" for address, _, _ in health), "Health service is not listening on 127.0.0.1:9001"
    assert any(address == "0.0.0.0" for address, _, _ in proxy), "Proxy is not listening on 0.0.0.0:8080"

    proxy_pids = set().union(*(pids for _, _, pids in proxy))
    assert proxy_pids, "Could not identify the process listening on port 8080"
    nginx_pids = []
    for pid in proxy_pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
        except OSError:
            continue
        if os.path.basename(exe) == "nginx":
            nginx_pids.append(pid)
    assert nginx_pids, "Port 8080 is not being served by Nginx"


def test_nginx_configuration_is_valid_and_contains_proxy_route():
    assert os.path.isfile(NGINX_CONF), f"Missing {NGINX_CONF}"
    result = subprocess.run(
        ["nginx", "-T", "-c", NGINX_CONF],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Nginx configuration is invalid:\n{result.stdout}"
    effective = result.stdout
    assert re.search(r"listen\s+(?:0\.0\.0\.0:)?8080\b", effective), "Nginx config does not listen on port 8080"
    assert re.search(r"location\s+(?:=\s*)?/api(?:/process|/)", effective), "Nginx config has no /api processing location"
    assert "proxy_pass" in effective and "9000" in effective, "Nginx config does not proxy the API route to the backend on port 9000"


def test_backend_has_loaded_the_supplied_library():
    backend = listeners(9000)
    owner_pids = set().union(*(pids for _, _, pids in backend))
    assert owner_pids, "Could not identify the backend process listening on port 9000"
    candidate_pids = set()
    for pid in owner_pids:
        candidate_pids.update(descendants(pid))

    loaded = False
    for pid in candidate_pids:
        try:
            maps = open(f"/proc/{pid}/maps").read()
        except OSError:
            continue
        if LIB_PATH in maps:
            loaded = True
            break
    assert loaded, f"The backend serving port 9000 has not loaded {LIB_PATH}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
