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
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import stat
import subprocess
import time

import pytest
import requests

ROOT = "/home/user/telemetryd"
BINARY = os.path.join(ROOT, "telemetryd")
SCRIPT = os.path.join(ROOT, "test_regression.sh")
PORT = 8088
TOKEN = "f9a3b2c1-telemetry-token"


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                            result.add(fields[9])
        except OSError:
            pass
    return result


def pid_owns_listener(pid, port):
    inodes = listener_inodes(port)
    if not inodes:
        return False
    try:
        for name in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{name}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                return True
    except OSError:
        return False
    return False


def kill_port_listeners(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            for fd in os.listdir(f"/proc/{entry}/fd"):
                try:
                    target = os.readlink(f"/proc/{entry}/fd/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    victims.append(int(entry))
                    break
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)


def start_binary():
    kill_port_listeners(PORT)
    proc = subprocess.Popen(
        [BINARY], cwd=ROOT, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"telemetryd exited during startup with status {proc.returncode}")
        if pid_owns_listener(proc.pid, PORT):
            return proc
        time.sleep(0.05)
    proc.terminate()
    pytest.fail("The built telemetryd executable did not listen on port 8088")


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    deadline = time.time() + 2
    while listener_inodes(PORT) and time.time() < deadline:
        time.sleep(0.05)


@pytest.fixture(scope="session", autouse=True)
def built_server():
    source = os.path.join(ROOT, "server.c")
    makefile = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(source), "server.c is missing"
    assert os.path.isfile(makefile), "Makefile is missing"

    with open(source, errors="replace") as f:
        source_text = f.read()
    uncommented = re.sub(r"/\*.*?\*/", "", source_text, flags=re.S)
    uncommented = re.sub(r"//.*", "", uncommented)
    assert not re.search(r"bad_ptr\s*=\s*NULL", uncommented), "The deliberate null-pointer crash remains in server.c"
    assert not re.search(r"\*\s*bad_ptr\s*=", uncommented), "The deliberate null-pointer dereference remains in server.c"

    with open(makefile, errors="replace") as f:
        make_text = f.read()
    assert re.search(r"(?:-pthread|-lpthread)", make_text), "The pthread linker flag was not added to the Makefile"

    for path in (BINARY, os.path.join(ROOT, "server.o")):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    clean = subprocess.run(["make", "clean"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"
    build = subprocess.run(["make"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(BINARY), "make did not create telemetryd"
    assert os.access(BINARY, os.X_OK), "telemetryd is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "telemetryd is not a compiled ELF executable"

    holder = [start_binary()]
    yield holder
    # Preserve the required final state: leave the submitted executable running.
    if holder[0].poll() is not None or not pid_owns_listener(holder[0].pid, PORT):
        holder[0] = start_binary()


def test_config_ini_exists_and_correct():
    config_path = "/home/user/telemetryd/config.ini"
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read()
    assert "PORT=8088" in content, "config.ini does not contain the correct PORT."
    assert "AUTH_TOKEN=f9a3b2c1-telemetry-token" in content, "config.ini does not contain the correct AUTH_TOKEN."


def test_regression_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Regression test script {SCRIPT} is missing."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Regression test script {SCRIPT} is not executable."


def test_telemetry_server_running_and_healthy(built_server):
    proc = built_server[0]
    assert proc.poll() is None
    assert pid_owns_listener(proc.pid, PORT), "Port 8088 is not owned by the built telemetryd process"

    url = f"http://127.0.0.1:{PORT}/health"
    headers = {"Authorization": f"Bearer {TOKEN}"}
    response = None
    for _ in range(3):
        try:
            response = requests.get(url, headers=headers, timeout=2)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    else:
        pytest.fail("Failed to connect to the built telemetryd server or did not receive 200 OK")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
        assert data.get("status") == "healthy", f"Expected response body to have status 'healthy', got {data}"
    except ValueError:
        assert "healthy" in response.text.lower(), f"Expected 'healthy' in response body, got {response.text}"

    for bad_headers in ({}, {"Authorization": "Bearer wrong-token"}, {"Authorization": TOKEN}):
        rejected = requests.get(url, headers=bad_headers, timeout=2)
        assert rejected.status_code in (401, 403), f"Invalid or missing authentication was not rejected: {rejected.status_code}"

    wrong_path = requests.get(f"http://127.0.0.1:{PORT}/not-health", headers=headers, timeout=2)
    assert wrong_path.status_code != 200, "telemetryd returned success for a non-health route"

    for _ in range(5):
        again = requests.get(url, headers=headers, timeout=2)
        assert again.status_code == 200
        assert proc.poll() is None, "telemetryd crashed while processing requests"


def run_mock(status, capture_path, ready_path):
    mock_code = r'''
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
status, capture, ready = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(capture, "w") as f:
            json.dump({"path": self.path, "authorization": self.headers.get("Authorization")}, f)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"healthy"}\n')
    def log_message(self, *args):
        pass
server = ReusableHTTPServer(("127.0.0.1", 8088), Handler)
open(ready, "w").close()
server.handle_request()
server.server_close()
'''
    proc = subprocess.Popen(["python3", "-c", mock_code, str(status), capture_path, ready_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 3
    while not os.path.exists(ready_path) and time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("Could not start regression-test capture server")
        time.sleep(0.02)
    assert os.path.exists(ready_path), "Capture server did not become ready"
    return proc


def test_regression_script_really_tests_request_and_status(built_server, tmp_path):
    stop_process(built_server[0])

    capture1 = str(tmp_path / "request200.json")
    ready1 = str(tmp_path / "ready200")
    mock1 = run_mock(200, capture1, ready1)
    try:
        result = subprocess.run([SCRIPT], cwd=ROOT, timeout=8, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    finally:
        try:
            mock1.wait(timeout=2)
        except subprocess.TimeoutExpired:
            mock1.kill()
    assert result.returncode == 0, "test_regression.sh did not return 0 for HTTP 200"
    assert os.path.isfile(capture1), "test_regression.sh did not send an HTTP request"
    with open(capture1) as f:
        request = json.load(f)
    assert request["path"] == "/health", "test_regression.sh did not request /health"
    assert request["authorization"] == f"Bearer {TOKEN}", "test_regression.sh sent the wrong Authorization header"

    capture2 = str(tmp_path / "request401.json")
    ready2 = str(tmp_path / "ready401")
    mock2 = run_mock(401, capture2, ready2)
    try:
        result = subprocess.run([SCRIPT], cwd=ROOT, timeout=8, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    finally:
        try:
            mock2.wait(timeout=2)
        except subprocess.TimeoutExpired:
            mock2.kill()
    assert result.returncode == 1, f"test_regression.sh must return 1 for a non-200 response, got {result.returncode}"
    assert os.path.isfile(capture2), "test_regression.sh did not send its failure-case request"

    built_server[0] = start_binary()
    final = requests.get(
        f"http://127.0.0.1:{PORT}/health",
        headers={"Authorization": f"Bearer {TOKEN}"},
        timeout=2,
    )
    assert final.status_code == 200
    assert pid_owns_listener(built_server[0].pid, PORT)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
