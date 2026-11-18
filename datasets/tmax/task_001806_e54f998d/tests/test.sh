#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import stat
import subprocess
import time

import pytest
import requests

PORT = 8080
SERVER = "/app/server"
SOURCE = "/app/server.c"


def listener_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    state = fields[3]
                    if local_port == port and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def stop_existing_listener():
    owners = {pid for pid in listener_owners(PORT) if pid > 1}
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and listener_owners(PORT):
        time.sleep(0.05)

    for pid in listener_owners(PORT):
        if pid > 1:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    deadline = time.time() + 2
    while time.time() < deadline:
        if not listener_owners(PORT):
            return
        time.sleep(0.05)
    pytest.fail("Could not stop the pre-existing listener on port 8080")


@pytest.fixture(scope="session", autouse=True)
def run_submitted_server():
    assert os.path.isfile(SERVER), "/app/server was not created"
    mode = os.stat(SERVER).st_mode
    assert mode & stat.S_IXUSR, "/app/server is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/server is not an ELF executable"

    assert os.path.isfile(SOURCE), "/app/server.c is missing"
    with open(SOURCE, errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*<assert\.h>", source), "server.c must include assert.h"
    assert re.search(r"\bassert\s*\(", source), "server.c must contain an active assertion"

    linked = subprocess.run(
        ["ldd", SERVER], text=True, capture_output=True, timeout=5
    )
    linkage = linked.stdout + linked.stderr
    assert linked.returncode == 0, f"Unable to inspect /app/server linkage: {linkage}"
    jansson_lines = [line for line in linkage.splitlines() if "libjansson" in line]
    assert jansson_lines, "/app/server is not linked against libjansson"
    assert all("/opt/legacy" not in line for line in jansson_lines), (
        f"/app/server is linked against the conflicting legacy libjansson: {jansson_lines}"
    )

    stop_existing_listener()
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = subprocess.Popen(
        [SERVER],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        start_new_session=True,
    )

    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"/app/server exited with status {proc.returncode}")
        owners = listener_owners(PORT)
        if proc.pid in owners:
            break
        time.sleep(0.05)
    else:
        pytest.fail("The executed /app/server did not become the listener on port 8080")

    yield
    # Intentionally leave the submitted server running, as required by the task.


def request_hash(sn, key):
    url = f"http://127.0.0.1:8080/process?sn={sn}&key={key}"
    try:
        return requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at 127.0.0.1:8080: {e}")


def test_server_running_and_processing_overflow_case():
    response = request_hash(2147483, 1500)
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    body = response.text.strip()
    expected_hash = "3221224500"
    assert body == expected_hash, f"Expected body to be '{expected_hash}', but got '{body}'. Integer overflow might not be fixed."


def test_server_running_and_processing_normal_case():
    response = request_hash(1000, 1000)
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    body = response.text.strip()
    expected_hash = "1000000"
    assert body == expected_hash, f"Expected body to be '{expected_hash}', but got '{body}'."


def test_runtime_generated_64_bit_products():
    rng = secrets.SystemRandom()
    cases = [(2147483647, 1500)]
    cases.extend((rng.randrange(1_000_000, 2_000_000_000), rng.randrange(3_000, 1_000_000)) for _ in range(6))

    for sn, key in cases:
        expected = str(sn * key)
        response = request_hash(sn, key)
        assert response.status_code == 200, (
            f"Expected HTTP 200 OK for sn={sn}, key={key}; got {response.status_code}"
        )
        assert response.text.strip() == expected, (
            f"Incorrect 64-bit hash for sn={sn}, key={key}: expected {expected}, "
            f"got {response.text.strip()!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
