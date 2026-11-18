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
import stat
import socket
import shutil
import subprocess
import tempfile
import uuid

import pytest
import requests

EVIDENCE_DIR = "/home/user/evidence"
ATTACKER_IP_FILE = "/home/user/evidence/attacker_ip.txt"
EXPECTED_IP = "198.51.100.42"
BASE_URL = "http://127.0.0.1:8080"
SOURCE_DIR = "/app/darkhttpd-1.14"
SOURCE_FILE = os.path.join(SOURCE_DIR, "darkhttpd.c")
MAKEFILE = os.path.join(SOURCE_DIR, "Makefile")
BINARY = os.path.join(SOURCE_DIR, "darkhttpd")


def test_attacker_ip_file_content():
    assert os.path.isfile(ATTACKER_IP_FILE), f"Evidence file not found: {ATTACKER_IP_FILE}"
    with open(ATTACKER_IP_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_IP, f"Expected IP {EXPECTED_IP}, but found {content} in {ATTACKER_IP_FILE}"


def test_evidence_permissions():
    assert os.path.isdir(EVIDENCE_DIR), f"Evidence directory not found: {EVIDENCE_DIR}"

    dir_stat = os.stat(EVIDENCE_DIR)
    assert stat.S_IMODE(dir_stat.st_mode) == 0o700, f"Evidence directory permissions are {oct(stat.S_IMODE(dir_stat.st_mode))}, expected 0o700"

    for root, dirs, files in os.walk(EVIDENCE_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            file_stat = os.stat(file_path)
            assert stat.S_IMODE(file_stat.st_mode) == 0o600, f"File permissions for {file_path} are {oct(stat.S_IMODE(file_stat.st_mode))}, expected 0o600"


def test_source_backdoor_removed():
    assert os.path.isfile(SOURCE_FILE), f"Missing source file: {SOURCE_FILE}"
    with open(SOURCE_FILE, "r", errors="replace") as f:
        source = f.read()
    assert "X-Attacker-Auth" not in source, "The attacker authentication header remains in darkhttpd.c"
    assert "backdoor" not in source.lower(), "Backdoor logic or markers remain in darkhttpd.c"
    assert "strstr(\"dummy\"" not in source, "The injected attacker code remains in darkhttpd.c"


def test_repaired_makefile_builds_current_binary():
    assert os.path.isfile(MAKEFILE), f"Missing Makefile: {MAKEFILE}"
    with open(MAKEFILE, "r", errors="replace") as f:
        makefile_text = f.read()
    assert "invalid_compiler_name" not in makefile_text, "The broken compiler setting remains in the Makefile"

    assert os.path.isfile(BINARY), f"Compiled darkhttpd binary not found: {BINARY}"
    binary_stat = os.stat(BINARY)
    assert stat.S_ISREG(binary_stat.st_mode), "darkhttpd is not a regular file"
    assert os.access(BINARY, os.X_OK), "darkhttpd is not executable"
    with open(BINARY, "rb") as f:
        submitted_binary = f.read()
    assert submitted_binary.startswith(b"\x7fELF"), "darkhttpd is not an ELF executable"

    with tempfile.TemporaryDirectory(prefix="verify-darkhttpd-") as tmp:
        build_dir = os.path.join(tmp, "darkhttpd-1.14")
        shutil.copytree(SOURCE_DIR, build_dir)
        copied_binary = os.path.join(build_dir, "darkhttpd")
        if os.path.lexists(copied_binary):
            os.unlink(copied_binary)
        for name in os.listdir(build_dir):
            if name.endswith(".o"):
                os.unlink(os.path.join(build_dir, name))

        result = subprocess.run(
            ["make"], cwd=build_dir, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=60
        )
        assert result.returncode == 0, f"Repaired Makefile failed to build with its default compiler:\n{result.stdout}"
        assert os.path.isfile(copied_binary), f"Make did not produce darkhttpd:\n{result.stdout}"
        with open(copied_binary, "rb") as f:
            rebuilt_binary = f.read()
        assert rebuilt_binary.startswith(b"\x7fELF"), "Make did not produce an ELF executable"
        assert submitted_binary == rebuilt_binary, "Installed darkhttpd does not match a fresh build of the repaired source"


def _listener_pids():
    listening_inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            if local_address.upper() == "0100007F:1F90" and state == "0A":
                listening_inodes.add(inode)

    pids = set()
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in listening_inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def test_port_8080_is_served_by_compiled_darkhttpd():
    pids = _listener_pids()
    assert pids, "No process is listening on 127.0.0.1:8080"

    matching = []
    for pid in pids:
        proc_exe = f"/proc/{pid}/exe"
        try:
            if os.path.samefile(proc_exe, BINARY):
                matching.append(pid)
        except (FileNotFoundError, OSError):
            pass
    assert matching, f"The process listening on 127.0.0.1:8080 is not the compiled {BINARY}"


def test_http_service_running_and_serves_evidence():
    url = f"{BASE_URL}/attacker_ip.txt"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK for {url}, got {response.status_code}"
    assert EXPECTED_IP in response.text, f"Expected IP {EXPECTED_IP} in response body, got {response.text}"


def test_http_service_backdoor_removed():
    url = f"{BASE_URL}/../../../../etc/passwd"
    headers = {"X-Attacker-Auth": "backdoor"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}: {e}")

    assert response.status_code != 200, f"Expected HTTP status code to not be 200 OK for {url} with backdoor header. The backdoor is likely still present."
    assert response.status_code in [400, 403, 404], f"Expected HTTP 400, 403, or 404 for {url}, got {response.status_code}"


def _raw_request(target):
    request = (
        f"GET {target} HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        "X-Attacker-Auth: backdoor\r\n"
        "Connection: close\r\n\r\n"
    ).encode("ascii")
    with socket.create_connection(("127.0.0.1", 8080), timeout=5) as sock:
        sock.sendall(request)
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks)


def test_backdoor_cannot_leak_randomized_external_file():
    name = ".verifier-secret-" + uuid.uuid4().hex
    secret_path = os.path.join("/home/user", name)
    secret = ("VERIFIER_SECRET_" + uuid.uuid4().hex).encode("ascii")
    with open(secret_path, "wb") as f:
        f.write(secret)
    os.chmod(secret_path, 0o600)

    targets = [
        f"/../{name}",
        f"/..%2f{name}",
        f"/.%2e/{name}",
        f"/%2e%2e/{name}",
    ]
    try:
        for target in targets:
            response = _raw_request(target)
            assert secret not in response, f"Backdoor header leaked an external file for request target {target}"
            status_line = response.split(b"\r\n", 1)[0]
            assert not re.match(br"HTTP/\d(?:\.\d)? 200(?: |$)", status_line), f"Traversal request unexpectedly succeeded: {target} ({status_line!r})"
    finally:
        try:
            os.unlink(secret_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
