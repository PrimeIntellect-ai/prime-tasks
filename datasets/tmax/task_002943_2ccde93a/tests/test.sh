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
import secrets
import subprocess
import time

import pytest
import requests

LIB_PATH = "/app/pow_shield/libpow_shield.so"
PROXY_URL = "http://127.0.0.1:8000/submit"


def load_library():
    lib = ctypes.CDLL(LIB_PATH)
    lib.verify_pow.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.c_uint64,
        ctypes.c_uint32,
    ]
    lib.verify_pow.restype = ctypes.c_bool
    return lib


def native_verify(lib, raw, nonce, target):
    if raw:
        buf = (ctypes.c_uint8 * len(raw)).from_buffer_copy(raw)
    else:
        buf = (ctypes.c_uint8 * 1)()
    return bool(lib.verify_pow(buf, len(raw), nonce, target))


def post(payload):
    try:
        return requests.post(PROXY_URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the proxy server: {exc}")


def response_json(resp):
    try:
        return resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")


def test_vendored_project_builds_shared_library():
    # Rebuild from the submitted vendored source so a pre-created dummy file is
    # not sufficient to pass the existence check.
    subprocess.run(["cargo", "clean"], cwd="/app/pow_shield", check=True, timeout=30)
    if os.path.exists(LIB_PATH):
        os.unlink(LIB_PATH)
    result = subprocess.run(
        ["make"], cwd="/app/pow_shield", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert result.returncode == 0, f"Vendored library failed to build:\n{result.stdout}"


def test_shared_library_exists():
    assert os.path.isfile(LIB_PATH), "Shared library libpow_shield.so was not built in /app/pow_shield/"
    assert open(LIB_PATH, "rb").read(4) == b"\x7fELF", "libpow_shield.so is not an ELF shared library"
    load_library()


def test_native_verify_pow_on_derived_inputs():
    lib = load_library()

    # Exercise the exported native function on verifier-selected data. Expected
    # answers are derived from the specified algorithm.
    for _ in range(64):
        raw = secrets.token_bytes(secrets.randbelow(96))
        nonce = secrets.randbits(40)
        target = secrets.randbelow(10000) + 2
        expected = (sum(raw) + nonce) % target == 0
        assert native_verify(lib, raw, nonce, target) is expected

    raw = secrets.token_bytes(12)
    assert native_verify(lib, raw, secrets.randbits(32), 0) is False


def test_proxy_and_virtualenv_files():
    assert os.path.isfile("/home/user/proxy.py"), "/home/user/proxy.py is missing"
    venv_python = "/home/user/venv/bin/python"
    assert os.path.isfile(venv_python), "/home/user/venv was not created"
    subprocess.run(
        [venv_python, "-c", "import flask"], check=True, timeout=10,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    source = open("/home/user/proxy.py", "r", encoding="utf-8").read()
    assert "ctypes" in source, "proxy.py does not use ctypes"
    assert LIB_PATH in source, "proxy.py does not load the required vendored library path"


def test_proxy_valid_pow():
    # UTF-8 byte sum for 'test' is 448, so nonce 2 is valid for target 10.
    time.sleep(0.5)
    resp = post({"data": "test", "nonce": 2, "target": 10})
    assert resp.status_code == 200, f"Expected 200 OK for valid PoW, got {resp.status_code}: {resp.text}"
    data = response_json(resp)
    assert data.get("status") == "Accepted", f"Expected JSON {{'status': 'Accepted'}}, got {data}"


def test_proxy_invalid_pow():
    time.sleep(0.5)
    resp = post({"data": "test", "nonce": 3, "target": 10})
    assert resp.status_code == 403, f"Expected 403 Forbidden for invalid PoW, got {resp.status_code}: {resp.text}"
    data = response_json(resp)
    assert data.get("error") == "Invalid PoW", f"Expected JSON {{'error': 'Invalid PoW'}}, got {data}"


def test_proxy_on_verifier_selected_inputs():
    # Keep intervals comfortably above the threshold while checking inputs that
    # are not fixed in the verifier. Include non-ASCII text to require UTF-8 bytes.
    alphabet = "abcXYZ019éλ雪"
    for _ in range(8):
        text = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(20) + 1))
        raw = text.encode("utf-8")
        target = secrets.randbelow(5000) + 2
        valid_nonce = (-sum(raw)) % target

        time.sleep(0.4)
        resp = post({"data": text, "nonce": valid_nonce, "target": target})
        assert resp.status_code == 200, f"Derived valid PoW was rejected: {resp.status_code}: {resp.text}"
        assert response_json(resp).get("status") == "Accepted"

        time.sleep(0.4)
        resp = post({"data": text, "nonce": valid_nonce + 1, "target": target})
        assert resp.status_code == 403, f"Derived invalid PoW was accepted: {resp.status_code}: {resp.text}"
        assert response_json(resp).get("error") == "Invalid PoW"


def test_listening_proxy_process_loaded_native_library():
    # Find processes owning the listening socket for 127.0.0.1:8000 and require
    # the vendored shared object to be mapped into at least one of them.
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table, "r", encoding="ascii").read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F40") and fields[3] == "0A":
                socket_inodes.add(fields[9])
    assert socket_inodes, "No process is listening on port 8000"

    owners = set()
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                link = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if link.startswith("socket:[") and link[8:-1] in socket_inodes:
                owners.add(pid)
                break

    assert owners, "Could not identify the process listening on port 8000"
    mapped = False
    for pid in owners:
        try:
            maps = open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if LIB_PATH in maps:
            mapped = True
            break
    assert mapped, "The proxy process has not loaded /app/pow_shield/libpow_shield.so"


def test_proxy_rate_limiting():
    rate_limited = False
    payload = {"data": "test", "nonce": 2, "target": 10}

    for _ in range(15):
        resp = post(payload)
        if resp.status_code == 429:
            rate_limited = True
            data = response_json(resp)
            assert data.get("error") == "Too Fast", f"Expected JSON {{'error': 'Too Fast'}}, got {data}"
            break

    assert rate_limited, "Expected rate limit (HTTP 429) to trigger after rapid consecutive requests, but it did not."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
