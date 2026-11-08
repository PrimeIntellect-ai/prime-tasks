#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import signal
import stat
import subprocess
import time
import urllib.request

import pytest

PORTS = [8001, 8002, 8003, 8004, 8080]


def fetch_url(url):
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.read()
    except Exception:
        return None


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def listener_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        found.add(fields[9])
        except OSError:
            pass
    return found


def pids_for_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def listener_pids(port):
    return pids_for_inodes(listener_inodes(port))


def stop_existing_services():
    pids = set()
    for port in PORTS:
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        if not any(listener_inodes(port) for port in PORTS):
            return
        time.sleep(0.1)
    for port in PORTS:
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
    time.sleep(0.5)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile("/home/user/provision.py"), "/home/user/provision.py is missing"
    assert os.path.isfile("/home/user/rotate.py"), "/home/user/rotate.py is missing"

    stop_existing_services()
    try:
        os.remove("/home/user/nginx.conf")
    except FileNotFoundError:
        pass
    subprocess.run(["rm", "-rf", "/home/user/proxy_logs"], check=True)

    try:
        result = subprocess.run(
            ["python3", "/home/user/provision.py"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=25,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"provision.py did not finish in the background: {exc}")
    assert result.returncode == 0, (
        f"provision.py failed with code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    deadline = time.time() + 8
    while time.time() < deadline:
        if all(listener_inodes(port) for port in PORTS):
            break
        time.sleep(0.1)
    assert all(listener_inodes(port) for port in PORTS), "provision.py did not bind all required ports"


def test_files_exist():
    assert os.path.isfile("/home/user/provision.py"), "/home/user/provision.py is missing"
    assert os.path.isfile("/home/user/rotate.py"), "/home/user/rotate.py is missing"
    assert os.path.isfile("/home/user/nginx.conf"), "/home/user/nginx.conf is missing"


def test_permissions():
    log_dir = "/home/user/proxy_logs"
    assert os.path.isdir(log_dir), f"{log_dir} is missing"

    dir_stat = os.stat(log_dir)
    assert oct(dir_stat.st_mode)[-3:] == "700", f"{log_dir} permissions must be 0700"

    log_file = os.path.join(log_dir, "access.log")
    if os.path.exists(log_file):
        file_stat = os.stat(log_file)
        assert oct(file_stat.st_mode)[-3:] == "600", f"{log_file} permissions must be 0600"

    for entry in os.scandir(log_dir):
        if entry.is_file(follow_symlinks=False):
            assert stat.S_IMODE(entry.stat(follow_symlinks=False).st_mode) == 0o600, (
                f"{entry.path} permissions must be 0600"
            )


def test_real_backend_processes_running():
    for port in [8001, 8002, 8003, 8004]:
        owners = listener_pids(port)
        assert owners, f"No process is listening on backend port {port}"
        valid = False
        for pid in owners:
            cmd = process_cmdline(pid)
            if re.search(r"(?:^|\s)python3(?:\s|$)", cmd) and "/app/backend.py" in cmd:
                if re.search(rf"--port(?:\s+|=){port}(?:\s|$)", cmd):
                    valid = True
        assert valid, f"Port {port} is not owned by python3 /app/backend.py --port {port}"

        started = time.monotonic()
        res = fetch_url(f"http://127.0.0.1:{port}/")
        elapsed = time.monotonic() - started
        assert res == b"OK", f"Backend on port {port} is not responding correctly"
        assert elapsed >= 0.04, f"Backend on port {port} does not exhibit the required slow API behavior"


def test_nginx_configuration_and_process():
    result = subprocess.run(
        ["nginx", "-T", "-c", "/home/user/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Generated Nginx configuration is invalid: {result.stderr}"
    rendered = result.stdout + "\n" + result.stderr
    rendered = re.sub(r"#.*", "", rendered)

    assert re.search(r"\blisten\s+[^;\n]*8080(?:\s|;)", rendered), "Nginx must listen on port 8080"
    assert re.search(r"\baccess_log\s+/home/user/proxy_logs/access\.log(?:\s|;)", rendered), (
        "Nginx must write access logs to /home/user/proxy_logs/access.log"
    )

    upstreams = re.findall(r"\bupstream\s+([^\s{]+)\s*\{([^}]]*)\}", rendered, flags=re.S)
    matching_upstream = None
    for name, body in upstreams:
        directives = re.findall(r"\bserver\s+([^;]+);", body)
        targets = []
        balanced = True
        for directive in directives:
            parts = directive.split()
            if not parts:
                continue
            target = parts[0]
            match = re.fullmatch(r"(?:(?:127\.0\.0\.1|localhost):)?(800[1-4])", target)
            if match:
                targets.append(int(match.group(1)))
                if len(parts) != 1:
                    balanced = False
        if sorted(targets) == [8001, 8002, 8003, 8004] and len(directives) == 4 and balanced:
            matching_upstream = name
            break
    assert matching_upstream is not None, "Nginx must evenly balance across exactly ports 8001-8004"
    assert re.search(rf"\bproxy_pass\s+http://{re.escape(matching_upstream)}(?:/)?\s*;", rendered), (
        "Nginx server must proxy requests to the four-backend upstream"
    )

    nginx_owners = listener_pids(8080)
    assert nginx_owners, "Nothing is listening on port 8080"
    assert any("nginx" in process_cmdline(pid).lower() for pid in nginx_owners), (
        "Port 8080 is not served by Nginx"
    )
    all_cmdlines = [process_cmdline(int(pid)) for pid in os.listdir("/proc") if pid.isdigit()]
    assert any(
        "nginx" in cmd.lower() and "master process" in cmd.lower()
        and "-c" in cmd and "/home/user/nginx.conf" in cmd
        for cmd in all_cmdlines
    ), "Running Nginx master was not started with /home/user/nginx.conf"


def test_processes_running():
    # Check if backends are running on the required ports
    for port in [8001, 8002, 8003, 8004]:
        try:
            res = fetch_url(f"http://127.0.0.1:{port}/")
            assert res == b"OK", f"Backend on port {port} is not responding correctly"
        except Exception:
            pytest.fail(f"Backend on port {port} is not reachable")


def test_performance_metric():
    url = "http://127.0.0.1:8080/"

    # Send one request first to ensure Nginx is up and to create the log file if not created
    res = fetch_url(url)
    assert res == b"OK", "Nginx is not serving the backend correctly on port 8080"

    # Check log file permissions after a request
    log_file = "/home/user/proxy_logs/access.log"
    assert os.path.exists(log_file), f"{log_file} was not created after request"
    file_stat = os.stat(log_file)
    assert oct(file_stat.st_mode)[-3:] == "600", f"{log_file} permissions must be 0600"

    # Performance test: 200 concurrent requests
    start_time = time.time()
    success_count = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=200) as executor:
        futures = [executor.submit(fetch_url, url) for _ in range(200)]
        for future in concurrent.futures.as_completed(futures):
            if future.result() == b"OK":
                success_count += 1

    duration = time.time() - start_time
    assert success_count == 200, f"Expected 200 successful requests, got {success_count}"
    assert duration <= 3.5, f"Performance metric failed: took {duration:.2f}s, expected <= 3.5s"


def test_log_rotation_script():
    access = "/home/user/proxy_logs/access.log"
    rotated = "/home/user/proxy_logs/access.log.1"
    assert fetch_url("http://127.0.0.1:8080/") == b"OK"
    assert os.path.isfile(access)
    old_stat = os.stat(access)

    result = subprocess.run(
        ["python3", "/home/user/rotate.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"rotate.py failed: {result.stdout}\n{result.stderr}"
    assert os.path.isfile(rotated), "rotate.py did not rename access.log to access.log.1"
    assert os.stat(rotated).st_ino == old_stat.st_ino, "access.log.1 is not the original access log"

    deadline = time.time() + 5
    while time.time() < deadline and not os.path.isfile(access):
        time.sleep(0.1)
    assert os.path.isfile(access), "Nginx did not reopen access.log after rotation"
    assert os.stat(access).st_ino != os.stat(rotated).st_ino, "Nginx did not open a new access.log"
    assert stat.S_IMODE(os.stat(access).st_mode) == 0o600, "Reopened access.log permissions must be 0600"
    assert stat.S_IMODE(os.stat(rotated).st_mode) == 0o600, "Rotated log permissions must be 0600"

    new_before = os.path.getsize(access)
    rotated_before = os.path.getsize(rotated)
    assert fetch_url("http://127.0.0.1:8080/") == b"OK"
    deadline = time.time() + 2
    while time.time() < deadline and os.path.getsize(access) <= new_before:
        time.sleep(0.05)
    assert os.path.getsize(access) > new_before, "Requests are not being written to the reopened access.log"
    assert os.path.getsize(rotated) == rotated_before, "Nginx is still writing to the rotated log"

    os.remove(access)
    result = subprocess.run(
        ["python3", "/home/user/rotate.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, "rotate.py must gracefully handle a missing access.log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
