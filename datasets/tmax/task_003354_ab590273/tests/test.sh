#!/bin/bash
set -e
mkdir -p /logs/verifier
service nginx start >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from types import SimpleNamespace

import pytest

BACKEND_SCRIPT = "/home/user/start_backend.py"
VERIFY_SCRIPT = "/home/user/verify_deployment.py"
RATE_FILE = "/home/user/success_rate.txt"
WRAPPER = "/app/data_service-1.2.0/bin/start_service.sh"
MONITOR_DIR = "/app/data_service-1.2.0"
MARKER = "/tmp/verifier_wrapper_answer.txt"
URL = "http://127.0.0.1:8080/api/data"


def read_rate():
    assert os.path.isfile(RATE_FILE), f"File {RATE_FILE} does not exist. Did the agent run verify_deployment.py?"
    with open(RATE_FILE, "r") as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Content of {RATE_FILE} is not a valid float: '{content}'")
    assert 0.0 <= value <= 1.0, f"Success rate in {RATE_FILE} must be between 0.0 and 1.0, got {value}"
    return value


def kill_port_9000():
    """Kill whichever process owns a listening TCP socket on port 9000."""
    for _ in range(4):
        inodes = set()
        for table in ("/proc/net/tcp", "/proc/net/tcp6"):
            try:
                with open(table) as f:
                    next(f, None)
                    for line in f:
                        fields = line.split()
                        if len(fields) > 9 and fields[1].endswith(":2328") and fields[3] == "0A":
                            inodes.add(fields[9])
            except FileNotFoundError:
                pass
        if not inodes:
            return
        for pid in os.listdir("/proc"):
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            fd_dir = f"/proc/{pid}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(os.path.join(fd_dir, fd))
                    except OSError:
                        continue
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        try:
                            os.kill(int(pid), signal.SIGKILL)
                        except (ProcessLookupError, PermissionError):
                            pass
                        break
            except (FileNotFoundError, PermissionError):
                pass
        time.sleep(0.25)


def valid_response(timeout=2):
    try:
        req = urllib.request.Request(URL, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as response:
            if response.getcode() != 200:
                return False
            data = json.loads(response.read().decode("utf-8"))
            return data.get("status") == "ok" and data.get("data") == "vendored_app_active"
    except Exception:
        return False


def wait_for_response(seconds=12):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if valid_response():
            return True
        time.sleep(0.2)
    return False


def assert_pexpect_implementation(path):
    with open(path, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        pytest.fail(f"{path} is not valid Python: {exc}")

    imports_pexpect = False
    imported_names = set()
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    imports_pexpect = True
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            imports_pexpect = True
            imported_names.update(alias.asname or alias.name for alias in node.names)
        elif isinstance(node, ast.Call):
            calls.append(node.func)

    def has_call(names):
        for func in calls:
            if isinstance(func, ast.Attribute) and func.attr in names:
                return True
            if isinstance(func, ast.Name) and func.id in names:
                return True
        return False

    assert imports_pexpect, f"{path} must use Python's pexpect module"
    assert has_call({"spawn"}) or "spawn" in imported_names, f"{path} does not spawn the legacy wrapper with pexpect"
    assert has_call({"expect", "expect_exact"}), f"{path} does not wait for the interactive prompt"
    assert has_call({"send", "sendline"}), f"{path} does not send an answer to the interactive prompt"


def test_full_deployment():
    # Preserve the original existence and pre-existing success-rate assertions.
    assert os.path.isfile(BACKEND_SCRIPT), f"File {BACKEND_SCRIPT} does not exist. The agent was required to create it."
    assert os.path.isfile(VERIFY_SCRIPT), f"File {VERIFY_SCRIPT} does not exist. The agent was required to create it."
    read_rate()

    # Verify the disk monitor's intended 500 MiB boundary behavior, rather than
    # merely checking that the currently available disk happens to pass.
    original_disk_usage = shutil.disk_usage
    sys.path.insert(0, MONITOR_DIR)
    sys.modules.pop("disk_monitor", None)
    try:
        shutil.disk_usage = lambda path: SimpleNamespace(total=10**12, used=0, free=500 * 1024**2)
        import disk_monitor
        disk_monitor.check_space()
        disk_monitor.shutil.disk_usage = lambda path: SimpleNamespace(total=10**12, used=0, free=500 * 1024**2 - 1)
        with pytest.raises(Exception):
            disk_monitor.check_space()
    finally:
        shutil.disk_usage = original_disk_usage
        sys.modules.pop("disk_monitor", None)
        if sys.path and sys.path[0] == MONITOR_DIR:
            sys.path.pop(0)

    assert_pexpect_implementation(BACKEND_SCRIPT)

    # Replace the wrapper temporarily with an equivalent instrumented wrapper.
    # Requiring a TTY ensures that piping "y" to it is insufficient; pexpect's
    # interactive PTY path must actually work.
    with open(WRAPPER, "rb") as f:
        wrapper_original = f.read()
    wrapper_mode = stat.S_IMODE(os.stat(WRAPPER).st_mode)
    instrumented = f'''#!/bin/bash
if [ ! -t 0 ]; then
    exit 71
fi
read -p "Do you want to start the service? (y/n): " answer
printf '%s' "$answer" > {MARKER}
if [ "$answer" = "y" ]; then
    exec python3 /app/data_service-1.2.0/server.py
fi
'''

    launcher = None
    counter = None
    try:
        kill_port_9000()
        try:
            os.unlink(MARKER)
        except FileNotFoundError:
            pass
        with open(WRAPPER, "w") as f:
            f.write(instrumented)
        os.chmod(WRAPPER, 0o755)

        launcher = subprocess.Popen(
            ["python3", BACKEND_SCRIPT],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.time() + 12
        while time.time() < deadline and not os.path.exists(MARKER):
            time.sleep(0.1)
        assert os.path.isfile(MARKER), "start_backend.py did not execute the required legacy wrapper"
        with open(MARKER) as f:
            assert f.read() == "y", "start_backend.py did not answer the wrapper prompt with 'y'"
        assert wait_for_response(), "The backend launched through the wrapper did not become available through Nginx"

        # Preserve the original fixed-endpoint assertion: 100 requests and >=95% correct responses.
        successful = sum(1 for _ in range(100) if valid_response())
        success_rate = successful / 100
        assert success_rate >= 0.95, (
            f"Success rate {success_rate} is below the threshold of 0.95. "
            "Expected 200 OK with correct JSON payload."
        )

        # Stop the launched backend and exercise verify_deployment.py against a
        # network failure. It must terminate gracefully and derive a zero rate.
        kill_port_9000()
        try:
            os.unlink(RATE_FILE)
        except FileNotFoundError:
            pass
        result = subprocess.run(
            ["python3", VERIFY_SCRIPT],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"verify_deployment.py did not handle network errors gracefully: {result.stderr}"
        assert read_rate() == 0.0, "verify_deployment.py did not calculate the failed-request rate"

        # Use a counting backend whose expected answer is generated by the test.
        counter_source = r'''
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

state_path = sys.argv[1]
lock = threading.Lock()
state = {"count": 0, "active": 0, "max_active": 0}

def save():
    tmp = state_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    __import__("os").replace(tmp, state_path)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with lock:
            state["count"] += 1
            state["active"] += 1
            state["max_active"] = max(state["max_active"], state["active"])
            save()
        time.sleep(0.03)
        body = json.dumps({"status": "ok", "data": "vendored_app_active"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        with lock:
            state["active"] -= 1
            save()
    def log_message(self, *args):
        pass

save()
ThreadingHTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
'''
        counter_path = "/tmp/verifier_counting_server.py"
        state_path = "/tmp/verifier_request_state.json"
        with open(counter_path, "w") as f:
            f.write(counter_source)
        for path in (state_path, state_path + ".tmp", RATE_FILE):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        counter = subprocess.Popen(["python3", counter_path, state_path], start_new_session=True)
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(state_path):
            time.sleep(0.05)
        assert os.path.exists(state_path), "Verifier counting backend failed to start"

        result = subprocess.run(
            ["python3", VERIFY_SCRIPT],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"verify_deployment.py failed: {result.stderr}"
        value = read_rate()
        assert value == 1.0, f"Expected a derived success rate of 1.0, got {value}"
        time.sleep(0.2)
        with open(state_path) as f:
            state = json.load(f)
        assert state["count"] == 50, f"verify_deployment.py sent {state['count']} requests instead of 50"
        assert state["max_active"] == 1, "verify_deployment.py did not send the 50 requests sequentially"
    finally:
        with open(WRAPPER, "wb") as f:
            f.write(wrapper_original)
        os.chmod(WRAPPER, wrapper_mode)
        for proc in (counter, launcher):
            if proc is not None and proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        kill_port_9000()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
