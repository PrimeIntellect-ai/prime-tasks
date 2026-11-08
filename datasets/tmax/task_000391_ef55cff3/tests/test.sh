#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SITE_EOF' > /tmp/sitecustomize.py
import base64
import json
import os
import socket

_log_path = os.environ.get("CLIENT_TRACE_LOG")
_replacement = os.environ.get("COOKIE_REPLACEMENT", "").encode("ascii")
_original_cookie = b"b4ckd00r_t0k3n_991"
_original_socket = socket.socket

def _log(kind, value):
    if not _log_path:
        return
    try:
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"kind": kind, "value": value}) + "\n")
    except Exception:
        pass

def _rewrite(data):
    if _replacement and len(_replacement) == len(_original_cookie):
        return data.replace(_original_cookie, _replacement)
    return data

class TracedSocket(_original_socket):
    def connect(self, address):
        _log("connect", address)
        return super().connect(address)

    def connect_ex(self, address):
        _log("connect", address)
        return super().connect_ex(address)

    def send(self, data, *args, **kwargs):
        _log("send", base64.b64encode(bytes(data)).decode("ascii"))
        return super().send(data, *args, **kwargs)

    def sendall(self, data, *args, **kwargs):
        _log("send", base64.b64encode(bytes(data)).decode("ascii"))
        return super().sendall(data, *args, **kwargs)

    def recv(self, bufsize, *args, **kwargs):
        return _rewrite(super().recv(bufsize, *args, **kwargs))

    def recv_into(self, buffer, nbytes=0, flags=0):
        if nbytes:
            count = super().recv_into(buffer, nbytes, flags)
        else:
            count = super().recv_into(buffer, len(buffer), flags)
        if count:
            view = memoryview(buffer)
            data = _rewrite(bytes(view[:count]))
            view[:count] = data
        return count

socket.socket = TracedSocket
SITE_EOF
chmod 755 /tmp/sitecustomize.py

cat << 'HARNESS_EOF' > /tmp/verify_client.py
import base64
import hashlib
import json
import os
import secrets
import stat
import subprocess

REPORT_FILE = "/home/user/report.txt"
SERVICE_FILE = "/home/user/suspicious_service.py"
TRACE_FILE = "/tmp/client_http_trace.jsonl"
EXPECTED_SHA256 = "a7f998ccb05ab64d99815a5105a2eab4d516d26732ea952eeeb4918e7e2c9438"

def service_ports():
    socket_inodes = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ")
            if SERVICE_FILE.encode() not in cmdline:
                continue
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target.endswith("]"):
                    socket_inodes.add(target[8:-1])
        except (OSError, PermissionError):
            continue

    ports = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) < 10 or fields[3] != "0A" or fields[9] not in socket_inodes:
                continue
            ports.add(int(fields[1].rsplit(":", 1)[1], 16))
    return ports

def candidates():
    found = []
    excluded = {SERVICE_FILE, "/tmp/sitecustomize.py", "/tmp/verify_client.py", "/tmp/test_final_state.py"}
    for root in ("/home/user", "/tmp"):
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".git"}]
            for name in files:
                path = os.path.abspath(os.path.join(directory, name))
                if not name.endswith(".py") or path in excluded:
                    continue
                try:
                    mode = os.stat(path).st_mode
                except OSError:
                    continue
                if stat.S_ISREG(mode):
                    found.append(path)
    return sorted(set(found))

def trace_proves_request(valid_ports):
    connects = []
    sent = bytearray()
    try:
        with open(TRACE_FILE, "r", encoding="utf-8") as f:
            for line in f:
                event = json.loads(line)
                if event.get("kind") == "connect":
                    connects.append(event.get("value"))
                elif event.get("kind") == "send":
                    sent.extend(base64.b64decode(event.get("value", "")))
    except (OSError, ValueError, json.JSONDecodeError):
        return False

    connected = False
    for address in connects:
        if isinstance(address, list) and len(address) >= 2:
            if address[0] == "127.0.0.1" and isinstance(address[1], int) and address[1] in valid_ports:
                connected = True
                break
    return connected and b"GET /admin " in bytes(sent)

def report_lines():
    try:
        with open(REPORT_FILE, "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]
    except OSError:
        return []

def run_client(path, valid_ports, replacement=None):
    for target in (REPORT_FILE, TRACE_FILE):
        try:
            os.remove(target)
        except FileNotFoundError:
            pass
    open(TRACE_FILE, "a").close()
    os.chmod(TRACE_FILE, 0o666)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp"
    env["CLIENT_TRACE_LOG"] = TRACE_FILE
    if replacement is not None:
        env["COOKIE_REPLACEMENT"] = replacement
    else:
        env.pop("COOKIE_REPLACEMENT", None)

    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "env"] +
            [f"{key}={value}" for key, value in env.items()] +
            ["python3", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and trace_proves_request(valid_ports)

ports = service_ports()
assert ports, "The suspicious_service.py process has no discoverable listening socket."
with open(SERVICE_FILE, "rb") as f:
    expected_md5 = hashlib.md5(f.read()).hexdigest()

accepted_report = None
accepted_path = None
for candidate in candidates():
    if not run_client(candidate, ports):
        continue
    lines = report_lines()
    if len(lines) < 2 or lines[0] != EXPECTED_SHA256 or lines[1] != expected_md5:
        continue
    with open(REPORT_FILE, "rb") as f:
        original_report = f.read()

    dynamic_cookie = secrets.token_hex(9)
    if not run_client(candidate, ports, dynamic_cookie):
        continue
    dynamic_lines = report_lines()
    dynamic_hash = hashlib.sha256(dynamic_cookie.encode("ascii")).hexdigest()
    if len(dynamic_lines) < 2 or dynamic_lines[0] != dynamic_hash or dynamic_lines[1] != expected_md5:
        continue

    accepted_report = original_report
    accepted_path = candidate
    break

assert accepted_path is not None, (
    "No submitted Python client was successfully executed making GET /admin to the "
    "suspicious service and correctly parsing both the real and verifier-varied cookies."
)
with open(REPORT_FILE, "wb") as f:
    f.write(accepted_report)
HARNESS_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
import pytest

REPORT_FILE = "/home/user/report.txt"
SCRIPT_FILE = "/home/user/suspicious_service.py"
EXPECTED_SHA256 = "a7f998ccb05ab64d99815a5105a2eab4d516d26732ea952eeeb4918e7e2c9438"

def test_report_file_exists():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."
    assert os.path.isfile(SCRIPT_FILE), f"The script file {SCRIPT_FILE} does not exist."

    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"The report file {REPORT_FILE} must contain at least two lines."

    # Verify Line 1 (SHA256 of the cookie)
    assert lines[0] == EXPECTED_SHA256, (
        f"Line 1 of {REPORT_FILE} is incorrect. "
        f"Expected {EXPECTED_SHA256}, but got {lines[0]}."
    )

    # Compute MD5 of the script file
    with open(SCRIPT_FILE, "rb") as f:
        file_content = f.read()
    expected_md5 = hashlib.md5(file_content).hexdigest()

    # Verify Line 2 (MD5 of the script file)
    assert lines[1] == expected_md5, (
        f"Line 2 of {REPORT_FILE} is incorrect. "
        f"Expected {expected_md5}, but got {lines[1]}."
    )
TEST_EOF

if python3 /tmp/verify_client.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
