#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import base64
import os
import random
import re
import signal
import socket
import string
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.request

PROXY = "/home/user/secure_proxy.py"
WORKER = "/home/user/legacy_worker"
BACKUP = "/tmp/legacy_worker.verifier_backup"
PROBE_LOG = "/tmp/legacy_probe_requests.log"
PROBE_START = "/tmp/legacy_probe_started"
launched = []


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        inode = fields[9]
                        if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                            inodes.add(inode)
        except FileNotFoundError:
            pass

    result = set()
    if not inodes:
        return result
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            data = f.read()
        return int(data[data.rfind(")") + 2:].split()[1])
    except Exception:
        return None


def is_descendant(pid, ancestor):
    seen = set()
    while pid and pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = ppid(pid)
    return False


def kill_ports():
    victims = listener_pids(8080) | listener_pids(9090)
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.35)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.25)


def stop_launched():
    for proc in launched:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
    for proc in launched:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    launched.clear()
    kill_ports()


def launch_proxy():
    proc = subprocess.Popen(
        [sys.executable, PROXY],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    launched.append(proc)
    return proc


def wait_listener(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.05)
    raise AssertionError(f"No process listened on 127.0.0.1:{port} within {timeout} seconds")


def request(path, authorization=None, timeout=3):
    req = urllib.request.Request("http://127.0.0.1:9090" + path)
    if authorization is not None:
        req.add_header("Authorization", authorization)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except urllib.error.URLError as error:
        raise AssertionError(f"Failed to connect to proxy: {error.reason}")


def random_text(n=18):
    alphabet = string.ascii_letters + string.digits
    return "".join(random.SystemRandom().choice(alphabet) for _ in range(n))


def derive_legacy_token():
    with open(WORKER, "rb") as f:
        binary = f.read()
    matches = re.findall(rb"Authorization: Bearer ([A-Za-z0-9._~+/-]+)\x00", binary)
    assert len(set(matches)) == 1, "Could not uniquely derive the legacy bearer token from legacy_worker"
    return matches[0].decode("ascii")


def install_probe(marker):
    probe = r'''#!/usr/bin/env python3
import base64, os, socket, sys
port = int(sys.argv[1])
with open("/tmp/legacy_probe_started", "w") as f:
    f.write(f"{os.getpid()} {os.getppid()} {' '.join(sys.argv)}")
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(20)
while True:
    conn, _ = s.accept()
    data = b""
    conn.settimeout(2)
    try:
        while b"\r\n\r\n" not in data and len(data) < 65536:
            part = conn.recv(4096)
            if not part:
                break
            data += part
    except Exception:
        pass
    with open("/tmp/legacy_probe_requests.log", "ab") as log:
        log.write(base64.b64encode(data) + b"\n")
    body = b"''' + marker.encode("ascii").decode("ascii") + r'''"
    response = (b"HTTP/1.1 201 Created\r\nContent-Type: text/plain\r\nContent-Length: "
                + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
    try:
        conn.sendall(response)
    except Exception:
        pass
    conn.close()
'''
    with open(WORKER, "w") as f:
        f.write(probe)
    os.chmod(WORKER, 0o755)


def read_probe_requests():
    try:
        with open(PROBE_LOG, "rb") as f:
            return [base64.b64decode(line.strip()) for line in f if line.strip()]
    except FileNotFoundError:
        return []


def restore_worker():
    if os.path.exists(BACKUP):
        try:
            if os.path.lexists(WORKER):
                os.unlink(WORKER)
        except FileNotFoundError:
            pass
        os.replace(BACKUP, WORKER)


def main():
    assert os.path.isfile(PROXY), f"Expected proxy script {PROXY} does not exist."
    assert not os.path.islink(PROXY), "secure_proxy.py must be a real script, not a symlink"
    assert os.path.isfile(WORKER), f"Expected legacy worker {WORKER} does not exist."
    legacy_token = derive_legacy_token()

    # Restart from the submitted artifact so pre-existing dummy listeners cannot satisfy the checks.
    kill_ports()
    proxy_proc = launch_proxy()
    proxy_pids = wait_listener(9090)
    worker_pids = wait_listener(8080)
    assert any(is_descendant(pid, proxy_proc.pid) for pid in proxy_pids), \
        "Port 9090 is not owned by the executed secure_proxy.py process"
    child_workers = [pid for pid in worker_pids if is_descendant(pid, proxy_proc.pid)]
    assert child_workers, "The executed secure_proxy.py did not launch the port-8080 worker"
    expected_exe = os.path.realpath(WORKER)
    assert any(os.path.realpath(f"/proc/{pid}/exe") == expected_exe for pid in child_workers), \
        "The port-8080 child is not the supplied /home/user/legacy_worker executable"

    nonce = random_text()
    valid_status, valid_body = request(f"/verify/{nonce}?value={random_text()}", "Bearer ROTATED_TOKEN_2024")
    assert valid_status == 200, f"Expected HTTP 200 OK, got {valid_status}"
    assert b"Success!" in valid_body, "Proxy did not return the expected success message from the legacy worker."

    invalid_status, _ = request(f"/invalid/{random_text()}", "Bearer INVALID_" + random_text())
    assert invalid_status == 403, f"Expected HTTP 403 Forbidden for invalid token, got {invalid_status}"
    missing_status, _ = request(f"/missing/{random_text()}")
    assert missing_status == 403, f"Expected HTTP 403 Forbidden for missing token, got {missing_status}"

    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report {report_path} does not exist."
    expected_report = [
        f"LEGACY_TOKEN={legacy_token}",
        f"PROXY_VALID={valid_status}",
        f"PROXY_INVALID={invalid_status}",
    ]
    with open(report_path) as f:
        report_lines = f.read().splitlines()
    assert report_lines == expected_report, \
        f"Audit report must contain exactly the three observed values; found {report_lines!r}"

    # Replace the worker temporarily with an instrumented executable at the same required path.
    # This proves authorized requests are forwarded and their Authorization header is replaced.
    stop_launched()
    os.replace(WORKER, BACKUP)
    marker = "FORWARDED_" + random_text(24)
    install_probe(marker)
    for path in (PROBE_LOG, PROBE_START):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    probe_proxy = launch_proxy()
    wait_listener(9090)
    probe_pids = wait_listener(8080)
    assert os.path.isfile(PROBE_START), "secure_proxy.py did not execute /home/user/legacy_worker 8080"
    with open(PROBE_START) as f:
        start_record = f.read()
    assert start_record.rstrip().endswith(" 8080"), "legacy_worker was not launched with argument 8080"
    assert any(is_descendant(pid, probe_proxy.pid) for pid in probe_pids), \
        "Instrumented legacy_worker was not a child of secure_proxy.py"

    # Ignore any startup probes, then prove rejected requests never reach the worker.
    open(PROBE_LOG, "wb").close()
    bad_status, _ = request(f"/blocked/{random_text()}", "Bearer WRONG_" + random_text())
    assert bad_status == 403, f"Expected HTTP 403 for randomized invalid credential, got {bad_status}"
    noauth_status, _ = request(f"/blocked-noauth/{random_text()}")
    assert noauth_status == 403, f"Expected HTTP 403 for missing credential, got {noauth_status}"
    time.sleep(0.2)
    assert read_probe_requests() == [], "An unauthorized request was forwarded to legacy_worker"

    forwarded_path = f"/forward/{random_text()}?nonce={random_text()}"
    forwarded_status, forwarded_body = request(forwarded_path, "Bearer ROTATED_TOKEN_2024")
    assert forwarded_status == 201, f"Proxy did not preserve the worker's randomized HTTP status: {forwarded_status}"
    assert forwarded_body == marker.encode(), "Proxy did not return the instrumented worker's response body"
    time.sleep(0.2)
    captured = read_probe_requests()
    assert len(captured) == 1, f"Expected exactly one forwarded request, observed {len(captured)}"
    raw = captured[0]
    header_blob = raw.split(b"\r\n\r\n", 1)[0]
    lines = header_blob.split(b"\r\n")
    assert lines and forwarded_path.encode() in lines[0], "Proxy did not preserve the randomized request target"
    auth_values = []
    for line in lines[1:]:
        if b":" in line:
            name, value = line.split(b":", 1)
            if name.strip().lower() == b"authorization":
                auth_values.append(value.strip().decode("latin1"))
    assert auth_values == ["Bearer " + legacy_token], \
        f"Forwarded Authorization header was not replaced with the derived legacy token: {auth_values!r}"
    assert b"ROTATED_TOKEN_2024" not in raw, "Rotated credential leaked into the request sent to legacy_worker"


if __name__ == "__main__":
    failed = False
    try:
        main()
    except Exception:
        failed = True
        traceback.print_exc()
    finally:
        try:
            stop_launched()
        except Exception:
            traceback.print_exc()
        try:
            restore_worker()
        except Exception:
            failed = True
            traceback.print_exc()
        # Leave the submitted proxy and the genuine worker running, as required.
        try:
            kill_ports()
            launch_proxy()
            wait_listener(9090, 3)
            wait_listener(8080, 3)
        except Exception:
            if not failed:
                traceback.print_exc()
            failed = True
    sys.exit(1 if failed else 0)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
