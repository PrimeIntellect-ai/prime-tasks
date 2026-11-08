#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import secrets
import subprocess
import urllib.error
import urllib.request

import pytest

PROJECT = "/home/user/project"
LIB = os.path.join(PROJECT, "libmathops.so")
SERVER = os.path.join(PROJECT, "server.py")
NGINX_CONF = os.path.join(PROJECT, "nginx.conf")


def expected_hash(data):
    value = 0
    power = 1
    for byte in data.split(b"\x00", 1)[0]:
        value = (value + byte * power) % 1000000009
        power = (power * 31) % 1000000009
    return value


def request(path):
    url = "http://127.0.0.1:9090" + path
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.headers, response.read()
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to Nginx proxy at {url}: {exc}")


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as stream:
                next(stream)
                for line in stream:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def process_description(pid):
    try:
        with open(f"/proc/{pid}/comm") as stream:
            comm = stream.read().strip()
        with open(f"/proc/{pid}/cmdline", "rb") as stream:
            cmdline = stream.read().replace(b"\x00", b" ").decode(errors="replace")
        return comm, cmdline
    except OSError:
        return "", ""


def test_libmathops_so_exists():
    assert os.path.isfile(LIB), f"Expected shared library {LIB} does not exist."


def test_libmathops_is_loadable_shared_library_with_real_function():
    with open(LIB, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", "libmathops.so is not an ELF library."

    header = subprocess.run(
        ["readelf", "-h", LIB], text=True, capture_output=True, check=True
    ).stdout
    assert "DYN (Shared object file)" in header, "libmathops.so is not a shared object."

    symbols = subprocess.run(
        ["readelf", "-Ws", LIB], text=True, capture_output=True, check=True
    ).stdout
    assert "compute_hash" in symbols, "libmathops.so does not export compute_hash."

    library = ctypes.CDLL(LIB)
    function = library.compute_hash
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_long

    samples = [b"world", b"Hello", b"prefix\x00ignored"]
    samples.extend(
        bytes(secrets.randbelow(95) + 32 for _ in range(secrets.randbelow(31) + 1))
        for _ in range(6)
    )
    for sample in samples:
        assert function(sample) == expected_hash(sample)


def test_server_source_uses_ctypes_compute_hash_abi():
    assert os.path.isfile(SERVER), f"Expected Python server {SERVER} does not exist."
    with open(SERVER, encoding="utf-8") as stream:
        source = stream.read()
    tree = ast.parse(source, filename=SERVER)

    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "server.py must import ctypes."

    def called_name(call):
        if isinstance(call.func, ast.Name):
            return call.func.id
        if isinstance(call.func, ast.Attribute):
            return call.func.attr
        return None

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(called_name(node) in ("CDLL", "LoadLibrary") for node in calls), \
        "server.py must load libmathops.so through ctypes."
    assert "libmathops.so" in source, "server.py does not reference libmathops.so."
    assert any(called_name(node) == "compute_hash" for node in calls), \
        "server.py does not call compute_hash."

    assigned_attributes = {
        target.attr
        for node in ast.walk(tree)
        if isinstance(node, (ast.Assign, ast.AnnAssign))
        for target in (node.targets if isinstance(node, ast.Assign) else [node.target])
        if isinstance(target, ast.Attribute)
    }
    assert "argtypes" in assigned_attributes, "server.py does not define compute_hash argtypes."
    assert "restype" in assigned_attributes, "server.py does not define compute_hash restype."


def test_output_log_content():
    path = os.path.join(PROJECT, "output.log")
    assert os.path.isfile(path), f"Expected output log {path} does not exist."
    with open(path, "r") as stream:
        content = stream.read().strip()
    assert content == "95682642", \
        f"Output log content is incorrect. Expected '95682642', got '{content}'."


def test_required_services_own_the_listening_ports():
    backend_owners = listener_pids(8080)
    assert backend_owners, "Nothing is listening on backend port 8080."
    assert any(SERVER in process_description(pid)[1] for pid in backend_owners), \
        "Port 8080 is not owned by the required server.py process."

    proxy_owners = listener_pids(9090)
    assert proxy_owners, "Nothing is listening on proxy port 9090."
    assert any("nginx" in process_description(pid)[0].lower() for pid in proxy_owners), \
        "Port 9090 is not owned by Nginx."


def test_nginx_configuration_is_valid():
    assert os.path.isfile(NGINX_CONF), f"Expected Nginx configuration {NGINX_CONF} does not exist."
    result = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF, "-p", PROJECT],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, f"Invalid Nginx configuration: {result.stderr}"


def test_nginx_proxy_and_python_server():
    status, _, body = request("/api/hash?data=776f726c64")
    assert status == 200, f"Expected HTTP status 200, got {status}."
    decoded = body.decode("utf-8").strip()
    assert decoded == "95682642", f"Expected response body '95682642', got '{decoded}'."


def test_nginx_proxy_and_python_server_dynamic():
    status, _, body = request("/api/hash?data=48656c6c6f")
    assert status == 200, f"Expected HTTP status 200, got {status}."
    decoded = body.decode("utf-8").strip()
    assert decoded == "105835250", f"Expected response body '105835250', got '{decoded}'."


def test_dynamic_unpredictable_inputs_through_backend_and_proxy():
    samples = [b"abc\x00this-part-must-not-be-hashed"]
    samples.extend(
        bytes(secrets.randbelow(95) + 32 for _ in range(secrets.randbelow(40) + 1))
        for _ in range(10)
    )

    for sample in samples:
        wanted = str(expected_hash(sample)).encode()
        query = "/hash?data=" + sample.hex()

        try:
            with urllib.request.urlopen("http://127.0.0.1:8080" + query, timeout=5) as response:
                direct_status = response.status
                direct_body = response.read().strip()
        except urllib.error.URLError as exc:
            pytest.fail(f"Failed to connect directly to Python backend: {exc}")

        proxy_status, headers, proxy_body = request("/api" + query)
        assert direct_status == 200
        assert proxy_status == 200
        assert direct_body == wanted, f"Backend returned {direct_body!r}, expected {wanted!r}."
        assert proxy_body.strip() == wanted, f"Proxy returned {proxy_body!r}, expected {wanted!r}."
        assert headers.get_content_type() == "text/plain", "Hash response must be plain text."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
