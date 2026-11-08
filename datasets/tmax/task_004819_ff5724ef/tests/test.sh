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
import pathlib
import secrets
import socket
import subprocess
import time
from collections import deque

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
SOURCE = pathlib.Path("/home/user/config_server.c")
VENDOR = pathlib.Path("/app/vendored/tinyhttp")


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


@pytest.fixture(scope="session", autouse=True)
def validate_artifacts_and_wait_for_server():
    assert SOURCE.is_file(), "/home/user/config_server.c does not exist"
    source = SOURCE.read_text(errors="replace")
    assert "tinyhttp.h" in source and "http_serve" in source, "Service source does not use tinyhttp"
    assert "regex.h" in source and "regcomp" in source and "regexec" in source, "Service source does not use POSIX regex"

    build = subprocess.run(
        ["make", "-B"], cwd=VENDOR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"Vendored tinyhttp still fails to build:\n{build.stdout}"

    libraries = [p for p in (VENDOR / "libtinyhttp.a", VENDOR / "libtinyhttp.so") if p.is_file()]
    assert libraries, "tinyhttp build did not produce libtinyhttp.a or libtinyhttp.so"
    assert any(p.read_bytes()[:8] in (b"!<arch>\n", b"\x7fELF\x02\x01\x01\x00", b"\x7fELF\x01\x01\x01\x00") for p in libraries), \
        "tinyhttp output is not a static archive or ELF shared library"

    compile_result = subprocess.run(
        ["gcc", str(SOURCE), "-I", str(VENDOR), "-L", str(VENDOR), "-ltinyhttp", "-o", "/tmp/verifier_config_server"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert compile_result.returncode == 0, f"config_server.c does not compile and link with tinyhttp:\n{compile_result.stdout}"
    linked_symbols = subprocess.run(
        ["nm", "/tmp/verifier_config_server"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert linked_symbols.returncode == 0 and "http_serve" in linked_symbols.stdout, \
        "Compiled service is not linked to tinyhttp's http_serve"

    max_retries = 10
    for _ in range(max_retries):
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=1):
                break
        except OSError:
            time.sleep(0.5)
    else:
        pytest.fail("Service is not listening on 127.0.0.1:8080. Is the C application running?")

    pids = listening_pids(8080)
    assert pids, "Could not identify the process listening on port 8080"
    assert any(pathlib.Path(f"/proc/{pid}/exe").read_bytes()[:4] == b"\x7fELF" for pid in pids), \
        "The running service is not a compiled native executable"


def assert_stats(values):
    expected = f"Average: {sum(values) / len(values):.2f}\n"
    res = requests.get(f"{BASE_URL}/stats", timeout=3)
    assert res.status_code == 200, f"Expected 200 OK for GET /stats, got {res.status_code}"
    assert res.text == expected, f"Expected {expected!r}, got {res.text!r}"


def test_service_workflow():
    # Preserve the original fixed workflow and assertions.
    res = requests.post(f"{BASE_URL}/config", data="[TXN:T01] SET a=1 SIZE=10", timeout=3)
    assert res.status_code == 200, f"Expected 200 OK for POST /config, got {res.status_code}"

    res = requests.post(f"{BASE_URL}/config", data="[TXN:T02] SET b=2 SIZE=20", timeout=3)
    assert res.status_code == 200, f"Expected 200 OK for POST /config, got {res.status_code}"

    res = requests.get(f"{BASE_URL}/stats", timeout=3)
    assert res.status_code == 200, f"Expected 200 OK for GET /stats, got {res.status_code}"
    assert res.text == "Average: 15.00\n", f"Expected 'Average: 15.00\\n', got {res.text!r}"

    res = requests.post(f"{BASE_URL}/config", data="[TXN:T01] SET a=1 SIZE=500", timeout=3)
    assert res.status_code == 200, f"Expected 200 OK for POST /config (duplicate), got {res.status_code}"

    res = requests.get(f"{BASE_URL}/stats", timeout=3)
    assert res.status_code == 200
    assert res.text == "Average: 15.00\n", f"Deduplication failed. Expected 'Average: 15.00\\n', got {res.text!r}"

    requests.post(f"{BASE_URL}/config", data="[TXN:T03] SET c=3 SIZE=30", timeout=3)
    requests.post(f"{BASE_URL}/config", data="[TXN:T04] SET d=4 SIZE=40", timeout=3)
    requests.post(f"{BASE_URL}/config", data="[TXN:T05] SET e=5 SIZE=50", timeout=3)
    requests.post(f"{BASE_URL}/config", data="[TXN:T06] SET f=6 SIZE=60", timeout=3)

    res = requests.get(f"{BASE_URL}/stats", timeout=3)
    assert res.status_code == 200
    assert res.text == "Average: 40.00\n", f"Rolling window failed. Expected 'Average: 40.00\\n', got {res.text!r}"

    # Exercise unpredictable IDs and sizes, deriving every expected response.
    window = deque([20, 30, 40, 50, 60], maxlen=5)
    generated = []
    for index in range(9):
        txn = "R" + secrets.token_hex(8)
        size = 101 + secrets.randbelow(8900)
        generated.append((txn, size))
        body = f"[TXN:{txn}] SET key{index}=value{index} SIZE={size}"
        res = requests.post(f"{BASE_URL}/config", data=body, timeout=3)
        assert res.status_code == 200
        window.append(size)
        assert_stats(window)

    # A duplicate still must be ignored after its original value has rolled out.
    old_txn, old_size = generated[0]
    res = requests.post(
        f"{BASE_URL}/config",
        data=f"[TXN:{old_txn}] SET retry=changed SIZE={old_size + 7777}", timeout=3
    )
    assert res.status_code == 200
    assert_stats(window)

    # Also verify deduplication for a transaction currently represented in the window.
    recent_txn, recent_size = generated[-1]
    res = requests.post(
        f"{BASE_URL}/config",
        data=f"[TXN:{recent_txn}] SET retry=again SIZE={recent_size + 3333}", timeout=3
    )
    assert res.status_code == 200
    assert_stats(window)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
