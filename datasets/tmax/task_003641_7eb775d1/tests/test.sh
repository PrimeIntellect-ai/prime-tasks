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
import re
import secrets
import shutil
import socket
import string
import subprocess
import tempfile

import pytest
import requests

LIB_PATH = "/home/user/libchecksum.so"
LOG_PATH = "/home/user/benchmark.log"
TOKEN = "gamma-ray-burst"
BACKEND = "http://127.0.0.1:8443"
PROXY = "http://127.0.0.1:9000"


def xor_checksum(data):
    result = 0
    for byte in data:
        result ^= byte
    return result


def random_body(length=37):
    alphabet = string.ascii_letters + string.digits + " !@#$%^&*()-_=+[]{};:,.?/"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def listening_socket_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(inode)
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(pid))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return inodes, owners


def test_libchecksum_exists():
    """Test that the shared library exists."""
    assert os.path.isfile(LIB_PATH), "The shared library /home/user/libchecksum.so is missing."


def test_libchecksum_function_works_on_derived_inputs():
    """Load the submitted shared object and exercise its exported C function."""
    try:
        library = ctypes.CDLL(LIB_PATH)
        function = library.compute_checksum
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load compute_checksum from {LIB_PATH}: {exc}")

    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_int
    samples = [b"", b"test", os.urandom(31), random_body(73).encode("ascii")]
    for sample in samples:
        assert function(sample) == xor_checksum(sample), (
            f"compute_checksum returned the wrong value for {sample!r}"
        )


def test_benchmark_log_exists():
    """Test that the benchmark log exists and is not empty."""
    assert os.path.isfile(LOG_PATH), f"The benchmark log is missing: {LOG_PATH}"
    assert os.path.getsize(LOG_PATH) > 0, f"The benchmark log is empty: {LOG_PATH}"


def test_benchmark_log_has_evidence_of_fifty_requests():
    data = open(LOG_PATH, "rb").read().decode("utf-8", "replace")
    nonempty_lines = [line for line in data.splitlines() if line.strip()]
    evidence = (
        len(nonempty_lines) >= 50
        or data.count("OK") >= 50
        or len(re.findall(r"\b(?:200|HTTP/[^\s]+\s+200)\b", data)) >= 50
        or re.search(r"Complete requests\s*:\s*50\b", data, re.I)
        or re.search(r"\b50\s+(?:sequential\s+)?requests?\b", data, re.I)
    )
    assert evidence, "benchmark.log does not contain evidence that 50 requests were benchmarked"


def test_backend_and_proxy_are_separate_listeners():
    backend_inodes, backend_owners = listening_socket_owners(8443)
    proxy_inodes, proxy_owners = listening_socket_owners(9000)
    assert backend_inodes, "No listening backend socket was found on fallback port 8443"
    assert proxy_inodes, "No listening reverse-proxy socket was found on port 9000"
    assert backend_owners, "Could not identify the process owning the backend listener"
    assert proxy_owners, "Could not identify the process owning the proxy listener"
    assert backend_owners.isdisjoint(proxy_owners), (
        "Ports 8443 and 9000 must be separate backend and reverse-proxy services"
    )


def test_health_endpoint():
    """Test the /health endpoint via the reverse proxy."""
    try:
        response = requests.get(f"{PROXY}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the reverse proxy or backend for /health: {e}")

    assert response.status_code == 200, f"Expected 200 OK for /health, got {response.status_code}"
    assert response.text.strip() == "OK", f"Expected body 'OK' for /health, got '{response.text}'"


def test_backend_health_endpoint_directly():
    response = requests.get(f"{BACKEND}/health", timeout=5, headers={"Connection": "close"})
    assert response.status_code == 200
    assert response.text.strip() == "OK"


def test_process_endpoint_unauthorized():
    """Test the /process endpoint with an invalid token."""
    headers = {"Authorization": "Bearer invalid-token"}
    try:
        response = requests.post(f"{PROXY}/process", headers=headers, data="test", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the reverse proxy or backend for /process: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {response.status_code}"


def test_process_endpoint_missing_authorization():
    response = requests.post(f"{PROXY}/process", data=random_body(), timeout=5)
    assert response.status_code == 401


def test_process_endpoint_authorized():
    """Test the /process endpoint with the valid token and check the checksum result."""
    headers = {"Authorization": "Bearer gamma-ray-burst"}
    body = "test"
    try:
        response = requests.post(f"{PROXY}/process", headers=headers, data=body, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the reverse proxy or backend for /process: {e}")

    assert response.status_code == 200, f"Expected 200 OK for valid token, got {response.status_code}"
    assert response.text.strip() == "17", f"Expected body '17' for input 'test', got '{response.text}'"


def test_process_random_derived_inputs_direct_and_through_proxy():
    headers = {"Authorization": f"Bearer {TOKEN}", "Connection": "close"}
    for _ in range(4):
        body = random_body(secrets.randbelow(70) + 1)
        expected = str(xor_checksum(body.encode("ascii")))
        direct = requests.post(f"{BACKEND}/process", headers=headers, data=body, timeout=5)
        proxied = requests.post(f"{PROXY}/process", headers=headers, data=body, timeout=5)
        assert direct.status_code == 200
        assert proxied.status_code == 200
        assert direct.text.strip() == expected
        assert proxied.text.strip() == expected
        assert proxied.text.strip() == direct.text.strip()


def test_process_actually_calls_shared_library():
    """Temporarily interpose a compatible library so hardcoded/inlined XOR servers fail."""
    body = random_body(61)
    original_expected = xor_checksum(body.encode("ascii"))
    altered_expected = original_expected ^ 0x5A
    source = r'''
    int compute_checksum(const char *data) {
        unsigned int value = 0;
        const unsigned char *p = (const unsigned char *)data;
        while (*p) value ^= *p++;
        return (int)(value ^ 0x5A);
    }
    '''
    work = tempfile.mkdtemp(prefix="checksum_verify_")
    backup = os.path.join(work, "original.so")
    replacement = os.path.join(work, "replacement.so")
    shutil.copy2(LIB_PATH, backup)
    try:
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-x", "c", "-", "-o", replacement],
            input=source,
            text=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.replace(replacement, LIB_PATH)
        headers = {"Authorization": f"Bearer {TOKEN}", "Connection": "close"}
        direct = requests.post(f"{BACKEND}/process", headers=headers, data=body, timeout=5)
        proxied = requests.post(f"{PROXY}/process", headers=headers, data=body, timeout=5)
        assert direct.status_code == 200
        assert proxied.status_code == 200
        assert direct.text.strip() == str(altered_expected), (
            "The backend did not use compute_checksum from /home/user/libchecksum.so"
        )
        assert proxied.text.strip() == direct.text.strip(), (
            "The reverse proxy did not transparently forward the backend response"
        )
    finally:
        if os.path.exists(backup):
            os.replace(backup, LIB_PATH)
        shutil.rmtree(work, ignore_errors=True)


def test_fifty_sequential_health_requests_through_proxy():
    for index in range(50):
        response = requests.get(
            f"{PROXY}/health",
            headers={"Connection": "close"},
            timeout=5,
        )
        assert response.status_code == 200, f"Health request {index + 1}/50 failed"
        assert response.text.strip() == "OK"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
