#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import signal
import socket
import socketserver
import stat
import subprocess
import tempfile
import threading
import time
import urllib.request
import pytest

DEPLOY = "/home/user/deploy"
MONITOR = DEPLOY + "/disk_monitor.py"
WRAPPER = DEPLOY + "/job_wrapper.sh"
SETTINGS = DEPLOY + "/settings.env"
BACKEND_LOG = "/tmp/verifier_backend_requests.jsonl"
BACKEND_TOKEN = os.urandom(16).hex()


def _listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].split(":")[-1], 16) == port:
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            pass
    return pids


def _stop_backend_on_9999():
    pids = _listener_pids(9999)
    try:
        with open("/tmp/dummy_server.pid") as f:
            pids.add(int(f.read().strip()))
    except (OSError, ValueError):
        pass
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 3
    while time.time() < deadline and _listener_pids(9999):
        time.sleep(0.05)
    for pid in _listener_pids(9999):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def controlled_backend():
    _stop_backend_on_9999()
    try:
        os.unlink(BACKEND_LOG)
    except FileNotFoundError:
        pass

    code = r'''
import http.server, json, sys
log_path, token = sys.argv[1], sys.argv[2]
class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log_path, "a") as f:
            f.write(json.dumps({"path": self.path}) + "\\n")
        body = ("PONG:" + token).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
Server(("127.0.0.1", 9999), Handler).serve_forever()
'''
    proc = subprocess.Popen(
        ["/usr/bin/python3", "-c", code, BACKEND_LOG, BACKEND_TOKEN],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    deadline = time.time() + 4
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Could not start controlled backend: {proc.stderr.read()}")
        try:
            with socket.create_connection(("127.0.0.1", 9999), timeout=0.1):
                break
        except OSError:
            time.sleep(0.05)
    else:
        proc.terminate()
        pytest.fail("Controlled backend did not listen on port 9999")

    yield
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()


def _read_backend_paths():
    try:
        with open(BACKEND_LOG) as f:
            return [json.loads(line)["path"] for line in f if line.strip()]
    except FileNotFoundError:
        return []


def _run_monitor(env, timeout=8):
    return subprocess.run(
        ["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in env.items()],
         "/usr/bin/python3", MONITOR],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_settings_env_exists_and_content():
    env_path = "/home/user/deploy/settings.env"
    assert os.path.exists(env_path), f"File {env_path} does not exist."
    with open(env_path, "r") as f:
        content = f.read()
    assert "METRICS_OUT_DIR=/home/user/app_data/metrics" in content, "METRICS_OUT_DIR not properly set in settings.env"
    assert "METRICS_PORT=8888" in content, "METRICS_PORT not properly set in settings.env"

    result = subprocess.run(
        ["/usr/bin/env", "-i", "/bin/bash", "-c",
         f"source {SETTINGS}; /usr/bin/env"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    exported = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    assert exported.get("METRICS_OUT_DIR") == "/home/user/app_data/metrics"
    assert exported.get("METRICS_PORT") == "8888"


def test_disk_monitor_py_exists():
    py_path = "/home/user/deploy/disk_monitor.py"
    assert os.path.exists(py_path), f"File {py_path} does not exist."
    assert stat.S_ISREG(os.stat(py_path).st_mode), f"File {py_path} is not a regular file."


def test_job_wrapper_exists_and_executable():
    sh_path = "/home/user/deploy/job_wrapper.sh"
    assert os.path.exists(sh_path), f"File {sh_path} does not exist."
    st = os.stat(sh_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {sh_path} is not executable."


def test_port_forwarding_active():
    url = "http://127.0.0.1:8888/ping"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3) as response:
            body = response.read().decode("utf-8")
            assert "PONG" in body, f"Expected PONG from port 8888, got {body}"
    except Exception as e:
        pytest.fail(f"Port forwarding on 8888 failed or dummy server unreachable: {e}")

    challenge_path = "/forward-check/" + os.urandom(12).hex()
    with urllib.request.urlopen("http://127.0.0.1:8888" + challenge_path, timeout=3) as response:
        body = response.read().decode("utf-8")
    assert BACKEND_TOKEN in body, "Port 8888 did not return the controlled port-9999 backend response"
    deadline = time.time() + 2
    while time.time() < deadline and challenge_path not in _read_backend_paths():
        time.sleep(0.05)
    assert challenge_path in _read_backend_paths(), "The request to port 8888 never reached port 9999"


def test_wrapper_sources_settings_and_executes_monitor():
    marker = "/tmp/wrapper_probe.json"
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass

    with open(SETTINGS, "rb") as f:
        old_settings = f.read()
    with open(MONITOR, "rb") as f:
        old_monitor = f.read()
    old_mode = stat.S_IMODE(os.stat(MONITOR).st_mode)

    random_out = "/tmp/wrapper-out-" + os.urandom(8).hex()
    random_port = str(20000 + int.from_bytes(os.urandom(2), "big") % 20000)
    probe = (
        "import json, os\n"
        f"json.dump({{'out': os.environ.get('METRICS_OUT_DIR'), "
        f"'port': os.environ.get('METRICS_PORT')}}, open({marker!r}, 'w'))\n"
    )
    try:
        with open(SETTINGS, "w") as f:
            f.write(f"export METRICS_OUT_DIR={random_out}\nexport METRICS_PORT={random_port}\n")
        with open(MONITOR, "w") as f:
            f.write(probe)
        result = subprocess.run(
            ["/usr/bin/env", "-i", "/bin/bash", WRAPPER],
            capture_output=True, text=True, timeout=8,
        )
        assert result.returncode == 0, result.stderr
        assert os.path.exists(marker), "The wrapper did not execute /home/user/deploy/disk_monitor.py"
        with open(marker) as f:
            seen = json.load(f)
        assert seen == {"out": random_out, "port": random_port}, "The wrapper did not source settings.env before executing the monitor"
    finally:
        with open(SETTINGS, "wb") as f:
            f.write(old_settings)
        with open(MONITOR, "wb") as f:
            f.write(old_monitor)
        os.chmod(MONITOR, old_mode)


def test_monitor_uses_dynamic_environment_http_and_disk_check(tmp_path):
    requests_seen = []

    class Handler(__import__("http.server").server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests_seen.append(self.path)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        def log_message(self, *args):
            pass

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    server = Server(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    audit_file = tmp_path / "disk_calls.txt"
    sitecustomize = r'''
import os, shutil, subprocess
_log = os.environ.get("DISK_AUDIT_FILE")
def _record(kind, value):
    try:
        with open(_log, "a") as f: f.write(kind + ":" + repr(value) + "\\n")
    except Exception: pass
_orig_du = shutil.disk_usage
_orig_sv = os.statvfs
_orig_po = subprocess.Popen
_orig_sys = os.system
def disk_usage(path):
    _record("shutil.disk_usage", path)
    return _orig_du(path)
def statvfs(path):
    _record("os.statvfs", path)
    return _orig_sv(path)
def popen(*args, **kwargs):
    _record("subprocess", args[0] if args else kwargs.get("args"))
    return _orig_po(*args, **kwargs)
def system(command):
    _record("os.system", command)
    return _orig_sys(command)
shutil.disk_usage = disk_usage
os.statvfs = statvfs
subprocess.Popen = popen
os.system = system
'''
    (hook_dir / "sitecustomize.py").write_text(sitecustomize)
    out_dir = tmp_path / "dynamic-output"
    try:
        result = _run_monitor({
            "METRICS_OUT_DIR": str(out_dir),
            "METRICS_PORT": str(server.server_address[1]),
            "PYTHONPATH": str(hook_dir),
            "DISK_AUDIT_FILE": str(audit_file),
        })
    finally:
        server.shutdown()
        server.server_close()

    assert result.returncode == 0, result.stderr
    report = out_dir / "report.json"
    assert report.exists()
    assert json.loads(report.read_text()) == {"status": "DISK_OK", "directory": str(out_dir)}
    assert requests_seen == ["/ping"], f"Expected one GET to /ping, got {requests_seen}"
    calls = audit_file.read_text() if audit_file.exists() else ""
    assert "/home/user" in calls, "The monitor did not perform a disk-usage check for /home/user"


def test_monitor_fallback_and_connection_failure():
    fallback = "/tmp/fallback_metrics"
    shutil.rmtree(fallback, ignore_errors=True)
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    unused_port = sock.getsockname()[1]
    sock.close()

    result = _run_monitor({"METRICS_PORT": str(unused_port)})
    assert result.returncode == 0, f"Monitor crashed on a connection failure: {result.stderr}"
    report = os.path.join(fallback, "report.json")
    assert os.path.exists(report), "Monitor did not use /tmp/fallback_metrics when METRICS_OUT_DIR was unset"
    with open(report) as f:
        assert json.load(f) == {"status": "DISK_OK", "directory": fallback}


def test_monitor_http_timeout_is_three_seconds(tmp_path):
    class SlowHandler(__import__("http.server").server.BaseHTTPRequestHandler):
        def do_GET(self):
            time.sleep(10)
        def log_message(self, *args):
            pass

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    server = Server(("127.0.0.1", 0), SlowHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    started = time.monotonic()
    try:
        result = _run_monitor({
            "METRICS_OUT_DIR": str(tmp_path / "timeout-output"),
            "METRICS_PORT": str(server.server_address[1]),
        }, timeout=7)
    finally:
        elapsed = time.monotonic() - started
        server.shutdown()
        server.server_close()
    assert result.returncode == 0, f"Monitor did not safely catch the HTTP timeout: {result.stderr}"
    assert 2.4 <= elapsed <= 4.8, f"HTTP request did not use the required approximately 3-second timeout (elapsed {elapsed:.2f}s)"


def test_wrapper_execution_and_report():
    sh_path = "/home/user/deploy/job_wrapper.sh"

    result = subprocess.run(["env", "-i", "/bin/bash", sh_path], capture_output=True, text=True)
    assert result.returncode == 0, f"job_wrapper.sh failed to execute. stderr: {result.stderr}"

    report_path = "/home/user/app_data/metrics/report.json"
    assert os.path.exists(report_path), f"Report file {report_path} was not created. Did the script write to fallback?"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON.")

    assert data.get("status") == "DISK_OK", "JSON status is not DISK_OK."
    assert data.get("directory") == "/home/user/app_data/metrics", "JSON directory path is incorrect."
    assert data == {"status": "DISK_OK", "directory": "/home/user/app_data/metrics"}, "JSON payload contains missing or extra fields."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
