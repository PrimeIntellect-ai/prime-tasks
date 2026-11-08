#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import signal
import socket
import subprocess
import time
import urllib.request

WRAPPER = "/home/user/run_monitor.sh"
MONITOR = "/home/user/monitor_uptime.py"
HELPER = "/home/user/bin/get_disk_usage"
LOG = "/home/user/logs/uptime.log"
URL = "http://127.0.0.1:8000"


def test_wrapper_script_modifications():
    assert os.path.isfile(WRAPPER), f"Wrapper script {WRAPPER} is missing."
    assert os.access(WRAPPER, os.X_OK), f"Wrapper script {WRAPPER} is not executable."

    with open(WRAPPER, "r") as f:
        content = f.read()

    assert "MONITOR_LOG_DIR=/home/user/logs" in content or "MONITOR_LOG_DIR=\"/home/user/logs\"" in content or "MONITOR_LOG_DIR='/home/user/logs'" in content, \
        "Wrapper script does not properly set MONITOR_LOG_DIR to /home/user/logs."
    assert "/home/user/bin" in content and "PATH" in content, \
        "Wrapper script does not append /home/user/bin to PATH."
    assert "monitor_uptime.py" in content, "Wrapper does not invoke monitor_uptime.py."


def test_python_script_no_absolute_path_and_required_operations():
    assert os.path.isfile(MONITOR), f"Python script {MONITOR} is missing."

    with open(MONITOR, "r") as f:
        content = f.read()

    assert "/home/user/bin/get_disk_usage" not in content, \
        "Python script should not use the absolute path for get_disk_usage."

    tree = ast.parse(content, filename=MONITOR)
    subprocess_call = False
    environment_read = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
                if node.func.value.id == "subprocess":
                    subprocess_call = True
                if node.func.value.id == "os" and node.func.attr == "getenv":
                    environment_read = True
        if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute):
            if isinstance(node.value.value, ast.Name) and node.value.value.id == "os" and node.value.attr == "environ":
                environment_read = True

    assert subprocess_call, "Python monitor must execute get_disk_usage using the subprocess module."
    assert "get_disk_usage" in content, "Python monitor does not invoke get_disk_usage by name."
    assert environment_read, "Python monitor does not read MONITOR_LOG_DIR from the environment."
    assert "MONITOR_LOG_DIR" in content, "Python monitor does not reference MONITOR_LOG_DIR."
    assert URL in content, f"Python monitor does not request {URL}."


def test_log_file_created_and_accurate():
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."

    with open(LOG, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, "Log file is empty."
    expected_log = "STATUS: UP, DISK: 42%"
    found = any(expected_log in line for line in lines)
    assert found, f"Expected log line containing '{expected_log}' not found in {LOG}."


def test_webserver_running():
    try:
        response = urllib.request.urlopen(URL, timeout=2)
        assert response.getcode() == 200, "Webserver is running but did not return HTTP 200."
        assert response.read() == b"OK\n", "Webserver is not serving /home/user/www."
    except Exception as e:
        assert False, f"Could not connect to the dummy webserver on 127.0.0.1:8000: {e}"


def listener_pids(port):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[1].upper() == wanted_port and state == "0A":
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_port(expected_open, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.2)
        try:
            is_open = sock.connect_ex(("127.0.0.1", 8000)) == 0
        finally:
            sock.close()
        if is_open == expected_open:
            return
        time.sleep(0.05)
    raise AssertionError(f"Port 8000 did not become {'open' if expected_open else 'closed'}")


def run_and_require_one_line(expected):
    before = open(LOG, "rb").read() if os.path.exists(LOG) else b""
    result = subprocess.run([WRAPPER], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, (
        f"Wrapper failed with exit code {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    after = open(LOG, "rb").read() if os.path.exists(LOG) else b""
    addition = (expected + "\n").encode()
    assert after == before + addition, (
        "Each wrapper invocation must append exactly one correctly formatted line; "
        f"expected appended bytes {addition!r}, got {after[len(before):]!r}."
    )


def test_execute_wrapper_and_monitor_for_up_and_down():
    with open(HELPER, "rb") as f:
        original_helper = f.read()
    original_mode = os.stat(HELPER).st_mode
    usage = str(100 + secrets.randbelow(800))
    replacement = f"#!/bin/bash\nprintf '%s' '{usage}'\n".encode()
    down_server = None
    restored_server = None

    try:
        with open(HELPER, "wb") as f:
            f.write(replacement)
        os.chmod(HELPER, 0o755)

        # Exercise the actual wrapper and monitor against the required live service.
        run_and_require_one_line(f"STATUS: UP, DISK: {usage}%")

        # Replace the live HTTP-200 service with a deterministic HTTP-503 service
        # so the monitor's failure branch is also executed.
        for pid in listener_pids(8000):
            os.kill(pid, signal.SIGTERM)
        wait_for_port(False)

        down_code = (
            "from http.server import BaseHTTPRequestHandler,HTTPServer\n"
            "class H(BaseHTTPRequestHandler):\n"
            " def do_GET(self):\n"
            "  self.send_response(503); self.end_headers()\n"
            " def log_message(self,*args): pass\n"
            "HTTPServer(('127.0.0.1',8000),H).serve_forever()\n"
        )
        down_server = subprocess.Popen(
            ["python3", "-c", down_code],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        wait_for_port(True)
        run_and_require_one_line(f"STATUS: DOWN, DISK: {usage}%")
    finally:
        with open(HELPER, "wb") as f:
            f.write(original_helper)
        os.chmod(HELPER, original_mode)

        if down_server is not None and down_server.poll() is None:
            down_server.terminate()
            try:
                down_server.wait(timeout=2)
            except subprocess.TimeoutExpired:
                down_server.kill()
        for pid in listener_pids(8000):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            wait_for_port(False, timeout=3)
        except AssertionError:
            pass

        # Leave the required service running after verification.
        restored_server = subprocess.Popen(
            ["python3", "-m", "http.server", "8000", "--bind", "127.0.0.1", "--directory", "/home/user/www"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        wait_for_port(True)

    response = urllib.request.urlopen(URL, timeout=2)
    assert response.getcode() == 200
    assert response.read() == b"OK\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
