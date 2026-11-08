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
set -u
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

PORT_HEX = "1F90"


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].upper().endswith(":" + PORT_HEX) and fields[3] == "0A":
                found.add(fields[9])
    return found


def processes_for_inodes(inodes):
    result = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.append(int(proc.name))
                    break
        except OSError:
            pass
    return result


def exe_name(pid):
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return ""


def ppid(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("PPid:"):
                return int(line.split()[1])
    except OSError:
        pass
    return 0


def cmdline(pid):
    try:
        return [x.decode(errors="replace") for x in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if x]
    except OSError:
        return []


def find_server(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for pid in processes_for_inodes(listener_inodes()):
            if exe_name(pid) in {"nc", "nc.openbsd", "netcat"}:
                return pid
        time.sleep(0.05)
    return None


def find_bash_script(nc_pid):
    pid = ppid(nc_pid)
    while pid > 1:
        args = cmdline(pid)
        if exe_name(pid) == "bash":
            try:
                cwd = os.readlink(f"/proc/{pid}/cwd")
            except OSError:
                cwd = "/"
            for arg in args[1:]:
                candidate = Path(arg)
                if not candidate.is_absolute():
                    candidate = Path(cwd) / candidate
                try:
                    candidate = candidate.resolve()
                except OSError:
                    continue
                if candidate.is_file():
                    try:
                        first = candidate.read_bytes().splitlines()[0].decode(errors="replace")
                    except (OSError, IndexError):
                        continue
                    if re.fullmatch(r"#!\s*(?:/usr/bin/env\s+)?(?:/bin/)?bash(?:\s+.*)?", first):
                        return pid, candidate, cwd
        pid = ppid(pid)
    return None


def descendants(root):
    result = set()
    changed = True
    while changed:
        changed = False
        for proc in Path("/proc").iterdir():
            if not proc.name.isdigit():
                continue
            pid = int(proc.name)
            if pid != root and pid not in result and ppid(pid) in ({root} | result):
                result.add(pid)
                changed = True
    return result


def stop_tree(root):
    pids = list(descendants(root)) + [root]
    for pid in reversed(pids):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in reversed(pids):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def expected_from_files():
    known = {}
    for line in Path("/home/user/known_hashes.txt").read_text().splitlines():
        digest, relpath = line.split(None, 1)
        known[relpath.strip().lstrip("*")] = digest.lower()

    mismatches = []
    base = Path("/home/user")
    for path in Path("/home/user/webroot").iterdir():
        if path.is_file() and path.suffix in {".js", ".html"}:
            rel = str(path.relative_to(base))
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if known.get(rel) != actual:
                mismatches.append(path.name)

    attackers = []
    for line in Path("/home/user/access.log").read_text().splitlines():
        if "eval(" in line or "base64_decode(" in line:
            attackers.append(line.split()[0])
    return mismatches, attackers


def raw_get():
    with socket.create_connection(("127.0.0.1", 8080), timeout=5) as sock:
        sock.sendall(b"GET /audit HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            part = sock.recv(4096)
            if not part:
                break
            chunks.append(part)
    return b"".join(chunks)


def test_audit_endpoint_and_implementation():
    nc_pid = find_server()
    assert nc_pid is not None, "Port 8080 is not being served by nc/netcat"

    artifact = find_bash_script(nc_pid)
    assert artifact is not None, "The nc listener was not started by a Bash script file"
    bash_pid, script_path, original_cwd = artifact

    source = script_path.read_text(errors="replace")
    assert re.search(r"(^|[;&|()\s])nc(?:\.openbsd)?(?=\s|$)", source), "Bash server script does not invoke nc"
    uncommented = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    assert not re.search(r"(^|[;&|()\s])(?:python(?:2|3)?|node(?:js)?)(?=\s|$)", uncommented), "Python/Node.js is not allowed in the server script"

    # Stop the submitted instance and execute the discovered Bash artifact ourselves.
    stop_tree(bash_pid)
    deadline = time.time() + 3
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), "Submitted server could not be stopped for artifact verification"

    launched = subprocess.Popen(
        ["/bin/bash", str(script_path)],
        cwd=original_cwd if os.path.isdir(original_cwd) else str(script_path.parent),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        restarted_nc = find_server()
        assert restarted_nc is not None, "Executing the submitted Bash script did not start an nc server on 127.0.0.1:8080"

        url = "http://127.0.0.1:8080/audit"
        try:
            response = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the audit server at {url}: {e}")

        assert response.status_code == 200, f"Expected HTTP status 200, got {response.status_code}"
        csp_header = response.headers.get("Content-Security-Policy")
        assert csp_header == "default-src 'none';", f"Expected strict CSP header, got {csp_header}"

        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response body is not valid JSON: {response.text}")

        # Preserve the original assertions.
        assert data.get("status") == "audited"
        assert data.get("tampered_file") == "index.html"
        assert data.get("attacker_ip") == "192.168.1.105"
        expected_secrets = ["delta-tango-seven", "delta tango seven"]
        assert data.get("secret_token") in expected_secrets

        # Independently derive the file and log findings from the supplied evidence.
        mismatches, attackers = expected_from_files()
        assert len(mismatches) == 1, f"Expected one hash mismatch, found {mismatches}"
        assert len(set(attackers)) == 1, f"Expected one attacker IP, found {attackers}"
        assert data.get("tampered_file") == mismatches[0]
        assert data.get("attacker_ip") == attackers[0]

        # A second raw request checks persistence and literal CRLF HTTP formatting.
        raw = raw_get()
        assert b"\r\n\r\n" in raw, "HTTP headers are not terminated with CRLF CRLF"
        header, body = raw.split(b"\r\n\r\n", 1)
        assert header.startswith(b"HTTP/1.1 200") or header.startswith(b"HTTP/1.0 200")
        assert b"Content-Security-Policy: default-src 'none';" in header.split(b"\r\n")
        assert json.loads(body.decode()) == data
    finally:
        try:
            os.killpg(launched.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
