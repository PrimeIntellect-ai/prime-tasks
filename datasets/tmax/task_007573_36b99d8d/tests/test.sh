#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

HOME = "/home/user"
BINARY = f"{HOME}/metrics_service"
SOURCE = f"{HOME}/metrics_service.c"
DEPLOY = f"{HOME}/deploy.sh"
CONFIG = f"{HOME}/nginx.conf"
EXPECTED = {"status": "ok", "active_connections": 42}


def executable_file(path):
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.stat(path).st_mode & stat.S_IXUSR, f"{path} is not executable."


def clean_services():
    subprocess.run(["pkill", "-TERM", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-TERM", "-f", "^/home/user/metrics_service( |$)"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.5)
    subprocess.run(["pkill", "-KILL", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-KILL", "-f", "^/home/user/metrics_service( |$)"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try:
        os.unlink(f"{HOME}/nginx.pid")
    except FileNotFoundError:
        pass


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def fetch_json(port, path="/"):
    url = f"http://127.0.0.1:{port}{path}"
    with urllib.request.urlopen(url, timeout=3) as response:
        status = response.getcode()
        body = response.read().decode("utf-8")
        content_type = response.headers.get("Content-Type", "")
    assert status == 200, f"Expected HTTP 200 from {url}, got {status}"
    assert "application/json" in content_type.lower(), f"Wrong Content-Type from {url}: {content_type}"
    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Response from {url} is not valid JSON: {body}") from exc
    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
    assert data.get("active_connections") == 42, (
        f"Expected 42 active_connections, got {data.get('active_connections')}"
    )
    return data


def wait_for_json(port, path="/", timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return fetch_json(port, path)
        except Exception as exc:
            last = exc
            time.sleep(0.15)
    raise AssertionError(f"Endpoint on port {port}{path} did not become ready: {last}")


def exercise_service(program):
    port = free_port()
    proc = subprocess.Popen([program, str(port)], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    try:
        wait_for_json(port, "/", timeout=5)
        assert proc.poll() is None, f"{program} exited while serving requests"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
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
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def wait_for_listener_pids(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.1)
    raise AssertionError(f"No process is listening on port {port}")


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except FileNotFoundError:
        return ""


def assert_deployed_processes():
    backend = wait_for_listener_pids(9090)
    frontend = wait_for_listener_pids(8080)

    assert backend, "Nothing listens on backend port 9090"
    for pid in backend:
        assert os.path.samefile(f"/proc/{pid}/exe", BINARY), (
            f"Port 9090 is served by {process_exe(pid)}, not {BINARY}"
        )

    assert frontend, "Nothing listens on proxy port 8080"
    assert all(os.path.basename(process_exe(pid)) == "nginx" for pid in frontend), (
        f"Port 8080 is not exclusively served by nginx: "
        f"{[(pid, process_exe(pid)) for pid in frontend]}"
    )

    pid_path = f"{HOME}/nginx.pid"
    assert os.path.isfile(pid_path), "nginx did not create /home/user/nginx.pid"
    with open(pid_path) as f:
        master_pid = int(f.read().strip())
    assert os.path.basename(process_exe(master_pid)) == "nginx", "nginx.pid does not identify nginx"
    assert CONFIG in process_cmdline(master_pid), "Running nginx master was not started with the custom config"
    return backend | frontend


def run_deploy():
    result = subprocess.run([DEPLOY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            timeout=15)
    assert result.returncode == 0, f"deploy.sh exited with status {result.returncode}"


def test_metrics_service_compiled_and_fixed():
    executable_file(BINARY)
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "metrics_service is not a compiled ELF executable"
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    with open(SOURCE) as f:
        source = f.read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\.sin_port\s*=\s*htons\s*\(\s*port\s*\)\s*;", source_without_comments), (
        "The source does not fix sin_port using htons(port)"
    )

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "metrics_service")
        result = subprocess.run(["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True)
        assert result.returncode == 0, f"metrics_service.c does not compile with gcc: {result.stderr}"
        exercise_service(rebuilt)
    exercise_service(BINARY)


def test_deploy_script_exists_and_executable():
    executable_file(DEPLOY)


def test_nginx_config_exists_and_is_valid():
    assert os.path.isfile(CONFIG), f"{CONFIG} does not exist."
    with open(CONFIG) as f:
        content = f.read()
    assert "8080" in content, "Nginx config does not seem to contain port 8080."
    assert "9090" in content, "Nginx config does not seem to contain upstream port 9090."

    text = re.sub(r"#[^\n]*", "", content)
    required = {
        "worker_processes": "1",
        "pid": "/home/user/nginx.pid",
        "access_log": "/home/user/access.log",
        "error_log": "/home/user/error.log",
        "client_body_temp_path": "/home/user/tmp/",
        "proxy_temp_path": "/home/user/tmp/",
        "fastcgi_temp_path": "/home/user/tmp/",
        "uwsgi_temp_path": "/home/user/tmp/",
        "scgi_temp_path": "/home/user/tmp/",
    }
    for directive, value in required.items():
        assert re.search(rf"\b{directive}\s+{re.escape(value)}\s*;", text), (
            f"Missing required directive: {directive} {value};"
        )
    assert re.search(r"\blisten\s+8080\s*;", text), "Nginx must listen on port 8080"
    location = re.search(r"location\s+(?:=\s+|\^~\s+)?/api/metrics\s*\{(.*?)\}", text, re.S)
    assert location, "Missing an Nginx location for /api/metrics"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9090\s*;", location.group(1)), (
        "/api/metrics must proxy to http://127.0.0.1:9090"
    )
    assert os.path.isdir(f"{HOME}/tmp"), "/home/user/tmp/ was not created"

    result = subprocess.run(["nginx", "-t", "-c", CONFIG], capture_output=True, text=True)
    assert result.returncode == 0, f"nginx.conf is not a valid Nginx configuration: {result.stderr}"


def test_deploy_is_idempotent_and_uses_required_services():
    run_deploy()
    wait_for_json(9090, "/")
    wait_for_json(8080, "/api/metrics")
    first_pids = assert_deployed_processes()

    run_deploy()
    wait_for_json(9090, "/")
    wait_for_json(8080, "/api/metrics")
    second_pids = assert_deployed_processes()

    deadline = time.time() + 4
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in first_pids):
        time.sleep(0.1)
    assert first_pids.isdisjoint(second_pids), "Second deployment reused services instead of restarting them"
    assert not any(os.path.exists(f"/proc/{pid}") for pid in first_pids), (
        "The second deployment left old service processes running"
    )
    assert os.path.isfile(f"{HOME}/access.log"), "Nginx access log was not created at the required path"
    assert os.path.isfile(f"{HOME}/error.log"), "Nginx error log was not created at the required path"


def setup_module(module):
    clean_services()


def teardown_module(module):
    clean_services()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
