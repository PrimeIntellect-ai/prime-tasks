#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import signal
import socket
import subprocess
import time
import urllib.request
import pytest

BASE = "/home/user/capacity_planner"
USER_UID = pwd.getpwnam("user").pw_uid


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return []


def proc_uid(pid):
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except (FileNotFoundError, ProcessLookupError):
        return None


def listener_inodes(port, address="127.0.0.1"):
    wanted_port = f"{port:04X}"
    wanted_addr = "0100007F" if address == "127.0.0.1" else None
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_addr, local_port = fields[1].split(":")
                    if fields[3] != "0A" or local_port.upper() != wanted_port:
                        continue
                    if wanted_addr is not None and table.endswith("tcp") and local_addr.upper() != wanted_addr:
                        continue
                    result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listener_inodes(port)
    found = set()
    if not inodes:
        return found
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    found.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def wait_for_listener(port, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def terminate_pids(pids):
    pids = {int(pid) for pid in pids if int(pid) != os.getpid()}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        alive = {pid for pid in pids if os.path.exists(f"/proc/{pid}")}
        if not alive:
            return
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def is_python_http_server(pid, port):
    args = proc_cmdline(pid)
    joined = " ".join(args)
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return False
    return (
        exe.startswith("python")
        and re.search(r"(?:^|\s)-m\s+http\.server(?:\s|$)", joined)
        and re.search(rf"(?:^|\s){port}(?:\s|$)", joined)
        and re.search(r"--bind\s+127\.0\.0\.1(?:\s|$)", joined)
    )


def is_haproxy(pid):
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe")) == "haproxy"
    except OSError:
        return False


def haproxy_uses_cfg(pid, cfg_path):
    args = proc_cmdline(pid)
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return False
    for index, arg in enumerate(args[:-1]):
        if arg == "-f":
            supplied = args[index + 1]
            resolved = supplied if os.path.isabs(supplied) else os.path.join(cwd, supplied)
            if os.path.realpath(resolved) == os.path.realpath(cfg_path):
                return True
    return False


def kill_all_haproxy():
    targets = set(listener_pids(8080))
    for name in os.listdir("/proc"):
        if name.isdigit() and is_haproxy(int(name)):
            targets.add(int(name))
    terminate_pids(targets)


def start_haproxy_from_cfg():
    subprocess.Popen(
        ["runuser", "-u", "user", "--", "haproxy", "-f", os.path.join(BASE, "haproxy.cfg")],
        cwd=BASE,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    pids = wait_for_listener(8080)
    assert pids, "HAProxy did not start from the submitted configuration"
    assert any(is_haproxy(pid) and proc_uid(pid) == USER_UID for pid in pids), \
        "Port 8080 was not reopened by HAProxy as user"


def test_start_backends_script_fixed():
    """Test that start_backends.sh is fixed to use the correct ports and bind addresses."""
    script_path = os.path.join(BASE, "start_backends.sh")
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert re.search(r'8081\s+--bind\s+127\.0\.0\.1', content), "Port 8081 not bound to 127.0.0.1 in start_backends.sh"
    assert re.search(r'8082\s+--bind\s+127\.0\.0\.1', content), "Port 8082 not bound to 127.0.0.1 in start_backends.sh"
    assert re.search(r'8083\s+--bind\s+127\.0\.0\.1', content), "Port 8083 not bound to 127.0.0.1 in start_backends.sh"

    # Clear the submitted processes and execute the submitted artifact itself.
    old = set()
    for port in (8081, 8082, 8083):
        old.update(listener_pids(port))
    terminate_pids(old)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", script_path],
        cwd=BASE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
        text=True,
    )
    assert result.returncode == 0, f"start_backends.sh failed: {result.stderr}"

    for port in (8081, 8082, 8083):
        pids = wait_for_listener(port)
        assert pids, f"Executing start_backends.sh did not open port {port}"
        assert any(
            pid not in old and proc_uid(pid) == USER_UID and is_python_http_server(pid, port)
            for pid in pids
        ), f"Port {port} was not opened by a new python3 -m http.server process launched by start_backends.sh"


def test_python_servers_running():
    """Test that python HTTP servers are listening on 8081, 8082, 8083."""
    for port in [8081, 8082, 8083]:
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{port}/")
            with urllib.request.urlopen(req, timeout=2) as response:
                assert response.status == 200, f"Server on port {port} returned status {response.status}"
                body = response.read().decode('utf-8')
                assert "Directory listing" in body or "Directory" in body, f"Server on port {port} not serving directory listing"
        except Exception as e:
            pytest.fail(f"Could not connect to python server on 127.0.0.1:{port}: {e}")


def test_haproxy_cfg_fixed():
    """Test that haproxy.cfg is fixed to listen on 8080 and point to correct backends."""
    cfg_path = os.path.join(BASE, "haproxy.cfg")
    assert os.path.isfile(cfg_path), f"Config file {cfg_path} does not exist."

    with open(cfg_path, "r") as f:
        content = f.read()

    assert re.search(r'bind\s+127\.0\.0\.1:8080', content), "HAProxy frontend not bound to 127.0.0.1:8080"
    assert re.search(r'127\.0\.0\.1:8081', content), "HAProxy backend missing 127.0.0.1:8081"
    assert re.search(r'127\.0\.0\.1:8082', content), "HAProxy backend missing 127.0.0.1:8082"
    assert re.search(r'127\.0\.0\.1:8083', content), "HAProxy backend missing 127.0.0.1:8083"

    checked = subprocess.run(
        ["haproxy", "-c", "-f", cfg_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert checked.returncode == 0, f"HAProxy rejects haproxy.cfg: {checked.stdout}"

    # Parse active directives, excluding comments, so inert text cannot satisfy the test.
    sections = []
    current = None
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.match(r"^(frontend|backend)\s+(\S+)", line, re.I)
        if match:
            current = {"kind": match.group(1).lower(), "name": match.group(2), "lines": []}
            sections.append(current)
        elif re.match(r"^(global|defaults|listen)\b", line, re.I):
            current = None
        elif current is not None:
            current["lines"].append(line)

    frontends = [s for s in sections if s["kind"] == "frontend" and any(
        re.match(r"^bind\s+127\.0\.0\.1:8080(?:\s|$)", line, re.I) for line in s["lines"]
    )]
    assert frontends, "No active frontend binds 127.0.0.1:8080"
    backend_names = []
    for frontend in frontends:
        for line in frontend["lines"]:
            match = re.match(r"^default_backend\s+(\S+)", line, re.I)
            if match:
                backend_names.append(match.group(1))
    assert backend_names, "The 8080 frontend has no active default_backend"

    addresses = set()
    for section in sections:
        if section["kind"] == "backend" and section["name"] in backend_names:
            for line in section["lines"]:
                match = re.match(r"^server\s+\S+\s+(127\.0\.0\.1:\d+)(?:\s|$)", line, re.I)
                if match:
                    addresses.add(match.group(1))
    assert addresses == {"127.0.0.1:8081", "127.0.0.1:8082", "127.0.0.1:8083"}, \
        f"Active HAProxy backend pool is incorrect: {sorted(addresses)}"


def test_haproxy_running():
    """Test that HAProxy is running and listening on 127.0.0.1:8080."""
    pids = listener_pids(8080)
    assert pids, "Nothing is listening on 127.0.0.1:8080"
    assert any(
        is_haproxy(pid) and proc_uid(pid) == USER_UID and haproxy_uses_cfg(pid, os.path.join(BASE, "haproxy.cfg"))
        for pid in pids
    ), "Port 8080 is not served by HAProxy running as user with the submitted haproxy.cfg"
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"HAProxy on port 8080 returned status {response.status}"
            body = response.read().decode('utf-8')
            assert "Directory" in body, "HAProxy did not return the backend directory listing"
    except Exception as e:
        pytest.fail(f"Could not connect to HAProxy on 127.0.0.1:8080: {e}")


def test_check_capacity_script():
    """Test that check_capacity.sh exists, is executable, and contains the correct commands."""
    script_path = os.path.join(BASE, "check_capacity.sh")
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "curl" in content and "-s" in content, "check_capacity.sh must use curl in silent mode"
    assert "127.0.0.1:8080" in content, "check_capacity.sh must curl 127.0.0.1:8080"
    assert "capacity_log.txt" in content, "check_capacity.sh must append to capacity_log.txt"


def test_capacity_log():
    """Test that capacity_log.txt exists and contains exactly one seeded HTML response."""
    log_path = os.path.join(BASE, "capacity_log.txt")
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the script?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "<html" in content.lower() or "directory" in content.lower(), f"Log file {log_path} does not contain the expected HTML response."
    assert content.lower().count("<html") == 1, "capacity_log.txt must contain exactly one manually seeded response"
    assert content.endswith("\n"), "The seeded response must be followed by a newline"


def test_check_capacity_runtime_append_behavior():
    """Execute the monitor against a controlled endpoint and verify its exact append behavior."""
    script_path = os.path.join(BASE, "check_capacity.sh")
    log_path = os.path.join(BASE, "capacity_log.txt")
    marker_path = "/tmp/capacity_monitor_requests"
    server_path = "/tmp/capacity_test_server.py"
    expected = b"verifier-capacity-response\nline-two"

    with open(log_path, "rb") as f:
        before = f.read()
    try:
        os.unlink(marker_path)
    except FileNotFoundError:
        pass

    server_source = r'''import http.server
MARKER = "/tmp/capacity_monitor_requests"
BODY = b"verifier-capacity-response\nline-two"
class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(MARKER, "ab") as f:
            f.write((self.command + " " + self.path + "\n").encode())
        self.send_response(200)
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *args):
        pass
Server(("127.0.0.1", 8080), Handler).serve_forever()
'''
    with open(server_path, "w") as f:
        f.write(server_source)

    server = None
    kill_all_haproxy()
    try:
        server = subprocess.Popen(
            ["python3", server_path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        assert wait_for_listener(8080), "Controlled HTTP endpoint could not bind port 8080"
        result = subprocess.run(
            ["runuser", "-u", "user", "--", script_path],
            cwd=BASE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
        )
        assert result.returncode == 0, f"check_capacity.sh failed when executed: {result.stderr.decode(errors='replace')}"
    finally:
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        start_haproxy_from_cfg()

    with open(log_path, "rb") as f:
        after = f.read()
    assert after.startswith(before), "check_capacity.sh overwrote or modified existing log data"
    assert after[len(before):] == expected + b"\n", \
        "check_capacity.sh must append exactly the raw response body followed by one newline"
    with open(marker_path, "rb") as f:
        requests = f.read().splitlines()
    assert requests == [b"GET /"], "check_capacity.sh must make exactly one GET request to the root URL"


def test_crontab_txt():
    """Test that crontab.txt contains the correct cron schedule."""
    crontab_path = os.path.join(BASE, "crontab.txt")
    assert os.path.isfile(crontab_path), f"File {crontab_path} does not exist."

    with open(crontab_path, "r") as f:
        content = f.read().strip()

    assert re.search(r'\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/capacity_planner/check_capacity\.sh', content), \
        f"crontab.txt does not contain the correct schedule. Found: {content}"
    active = [line.strip() for line in content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert len(active) == 1, "crontab.txt must contain exactly one active crontab line"
    assert re.fullmatch(r'\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/capacity_planner/check_capacity\.sh', active[0]), \
        f"Invalid or non-exact five-minute schedule: {active[0]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
