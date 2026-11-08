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
import re
import time
import base64
import ctypes
import shutil
import tempfile
import subprocess
import requests
import pytest

URL = "http://127.0.0.1:9090/api/v1/release/check"
AUTH_HEADER = {"Authorization": "Bearer secr3t-d3pl0y-t0k3n"}
LIBDIR = "/app/libmathcheck-1.2.4"
SO_PATH = os.path.join(LIBDIR, "libmathcheck.so")
SERVICE_DIR = "/home/user/release-manager"


def oracle_parity(data: bytes) -> int:
    value = 0
    for byte in data:
        value ^= byte
    return value


@pytest.fixture(scope="session", autouse=True)
def wait_for_ready():
    """Wait for the ready.txt file to be created and contain READY."""
    ready_file = "/home/user/ready.txt"
    timeout = 10
    start = time.time()
    while time.time() - start < timeout:
        if os.path.exists(ready_file):
            with open(ready_file, "r") as f:
                if "READY" in f.read():
                    return
        time.sleep(0.5)
    pytest.fail(f"Service not ready: {ready_file} not found or does not contain 'READY'.")


@pytest.fixture(scope="session")
def mathcheck_lib():
    """Load the compiled shared library and independently validate its behavior."""
    assert os.path.exists(SO_PATH), f"Shared library {SO_PATH} not found. Ensure Makefile builds it."
    try:
        lib = ctypes.CDLL(SO_PATH)
        lib.calculate_parity.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        lib.calculate_parity.restype = ctypes.c_uint32
    except Exception as e:
        pytest.fail(f"Failed to load {SO_PATH}: {e}")

    assert lib.calculate_parity(None, 0) == 0
    cases = [
        b"\x01",
        b"Hello World\n",
        bytes(range(1, 33)),
        b"A very long string that is greater than 16 bytes to trigger UB",
    ]
    for data in cases:
        # The nonzero sentinel immediately after len detects an inclusive
        # upper bound without relying on whatever happens to follow a buffer.
        buf = ctypes.create_string_buffer(data + b"\xa5")
        actual = lib.calculate_parity(ctypes.cast(buf, ctypes.c_void_p), len(data))
        assert actual == oracle_parity(data), (
            f"calculate_parity returned {actual}, expected {oracle_parity(data)} for {data!r}"
        )
    return lib


def get_parity(lib, data_bytes: bytes) -> int:
    buf = ctypes.create_string_buffer(data_bytes + b"\xa5")
    actual = lib.calculate_parity(ctypes.cast(buf, ctypes.c_void_p), len(data_bytes))
    expected = oracle_parity(data_bytes)
    assert actual == expected, f"Vendored library parity {actual} differs from independent oracle {expected}"
    return expected


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    if state == "0A" and local.endswith(":2382"):
                        if table.endswith("tcp") and local != "0100007F:2382":
                            continue
                        inodes.add(inode)
        except FileNotFoundError:
            pass
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError):
            continue
    pytest.fail("Could not identify the process listening on 127.0.0.1:9090")


def test_repaired_library_build_and_service_linkage(mathcheck_lib):
    with open(os.path.join(LIBDIR, "mathcheck.c")) as f:
        source = f.read()
    assert re.search(r"if\s*\(\s*data\s*==\s*(?:0|NULL)\s*\|\|\s*len\s*==\s*0\s*\)", source), \
        "The null/empty-input security patch is not present in mathcheck.c"

    with open(os.path.join(LIBDIR, "Makefile")) as f:
        makefile = f.read()
    assert "-fPIC" in makefile, "Makefile does not compile position-independent code with -fPIC"

    # Build from only the submitted source and Makefile, so a stale prebuilt .so
    # cannot satisfy the build requirement.
    with tempfile.TemporaryDirectory() as tmp:
        for name in ("Makefile", "mathcheck.c", "mathcheck.h"):
            shutil.copy2(os.path.join(LIBDIR, name), os.path.join(tmp, name))
        result = subprocess.run(["make"], cwd=tmp, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=30)
        assert result.returncode == 0, f"make failed:\n{result.stdout}"
        built_so = os.path.join(tmp, "libmathcheck.so")
        assert os.path.isfile(built_so), "make did not produce libmathcheck.so"
        elf = subprocess.run(["readelf", "-h", built_so], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert elf.returncode == 0 and re.search(r"Type:\s+DYN", elf.stdout), \
            "libmathcheck.so is not an ELF shared object"
        dynamic = subprocess.run(["readelf", "-d", built_so], text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert dynamic.returncode == 0 and "TEXTREL" not in dynamic.stdout, \
            "libmathcheck.so contains text relocations and is not properly position-independent"
        rebuilt = ctypes.CDLL(built_so)
        rebuilt.calculate_parity.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        rebuilt.calculate_parity.restype = ctypes.c_uint32
        data = bytes(range(1, 65))
        buf = ctypes.create_string_buffer(data + b"\xd7")
        assert rebuilt.calculate_parity(ctypes.cast(buf, ctypes.c_void_p), len(data)) == oracle_parity(data)

    go_mod = os.path.join(SERVICE_DIR, "go.mod")
    assert os.path.isfile(go_mod), "go.mod is missing"
    with open(go_mod) as f:
        assert re.search(r"(?m)^module\s+release-manager\s*$", f.read()), \
            "Go module is not named release-manager"
    go_sources = []
    for root, _, files in os.walk(SERVICE_DIR):
        for name in files:
            if name.endswith(".go"):
                with open(os.path.join(root, name)) as f:
                    go_sources.append(f.read())
    combined = "\n".join(go_sources)
    assert re.search(r'import\s+"C"', combined) or re.search(r'import\s*\([^)]*"C"', combined, re.S), \
        "Service source does not use cgo"
    assert re.search(r"C\s*\.\s*calculate_parity\s*\(", combined), \
        "Service source does not call C.calculate_parity"

    pid = listener_pid()
    with open(f"/proc/{pid}/maps") as f:
        maps = f.read()
    assert SO_PATH in maps, f"Listening service process {pid} is not dynamically linked to {SO_PATH}"


def test_missing_auth():
    resp = requests.post(URL, json={})
    assert resp.status_code == 401, f"Expected 401 for missing auth, got {resp.status_code}"


def test_invalid_auth():
    resp = requests.post(URL, headers={"Authorization": "Bearer wrong-token"}, json={})
    assert resp.status_code == 401, f"Expected 401 for invalid auth, got {resp.status_code}"


def test_version_upgrade_required():
    payload = {"version": "1.9.9", "payload": "SGVsbG8=", "expected_parity": 0}
    resp = requests.post(URL, headers=AUTH_HEADER, json=payload)
    assert resp.status_code == 426, f"Expected 426 for old version, got {resp.status_code}"


def test_valid_request_short_payload(mathcheck_lib):
    data = b"Hello World\n"
    payload = {
        "version": "2.0.0",
        "payload": base64.b64encode(data).decode("utf-8"),
        "expected_parity": get_parity(mathcheck_lib, data),
    }
    resp = requests.post(URL, headers=AUTH_HEADER, json=payload)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    assert resp.json().get("status") == "ok", "Expected status: ok in response"


def test_valid_request_long_payload(mathcheck_lib):
    data = b"A very long string that is greater than 16 bytes to trigger UB"
    payload = {
        "version": "2.1.0",
        "payload": base64.b64encode(data).decode("utf-8"),
        "expected_parity": get_parity(mathcheck_lib, data),
    }
    resp = requests.post(URL, headers=AUTH_HEADER, json=payload)
    assert resp.status_code == 200, f"Expected 200 OK for long payload, got {resp.status_code}. Response: {resp.text}"
    assert resp.json().get("status") == "ok", "Expected status: ok in response"


def test_wrong_parity(mathcheck_lib):
    data = b"Some payload"
    parity = get_parity(mathcheck_lib, data)
    payload = {
        "version": "2.0.0",
        "payload": base64.b64encode(data).decode("utf-8"),
        "expected_parity": parity + 1,
    }
    resp = requests.post(URL, headers=AUTH_HEADER, json=payload)
    assert resp.status_code == 400, f"Expected 400 for wrong parity, got {resp.status_code}. Response: {resp.text}"
    assert resp.json().get("status") == "mismatch", "Expected status: mismatch in response"


def test_invalid_json():
    resp = requests.post(URL, headers=AUTH_HEADER, data="not a json")
    assert resp.status_code == 400, f"Expected 400 for invalid JSON, got {resp.status_code}"


def test_invalid_base64():
    payload = {"version": "2.0.0", "payload": "not-valid-base64!@#", "expected_parity": 0}
    resp = requests.post(URL, headers=AUTH_HEADER, json=payload)
    assert resp.status_code == 400, f"Expected 400 for invalid base64, got {resp.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
