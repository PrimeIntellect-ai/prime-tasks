#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import threading
import time
from pathlib import Path

import pytest

DEPLOY_DIR = Path("/home/user/deploy")
DEPLOY_SCRIPT = DEPLOY_DIR / "deploy.py"
WORKER_SCRIPT = DEPLOY_DIR / "worker.py"
EVENT_LOG = DEPLOY_DIR / ".verifier-worker-events"

EXPECTED_WORKER = b'''import sys
import time
import socket
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

def check_dep(prev_id, prev_port):
    # Check filesystem dependency
    if not os.path.exists(f"/home/user/deploy/w{prev_id}.ready"):
        print(f"Worker {prev_id} readiness file not found. Crashing.")
        sys.exit(1)
    # Check network dependency
    try:
        with socket.create_connection(("127.0.0.1", prev_port), timeout=1):
            pass
    except OSError:
        print(f"Worker {prev_id} port {prev_port} not reachable. Crashing.")
        sys.exit(1)

worker_id = int(sys.argv[1])
port = 8080 + worker_id

if worker_id > 1:
    check_dep(worker_id - 1, port - 1)

# Simulate startup delay
time.sleep(2)

# Start server
class DummyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()

server = HTTPServer(('127.0.0.1', port), DummyHandler)

# Write readiness file
with open(f"/home/user/deploy/w{worker_id}.ready", "w") as f:
    f.write("ready")

# Serve forever
server.serve_forever()
'''

INSTRUMENTED_WORKER = r'''import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

BASE = "/home/user/deploy"
EVENTS = os.path.join(BASE, ".verifier-worker-events")

def record(event, worker_id):
    line = f"{time.monotonic():.9f} {event} {worker_id}\n".encode()
    fd = os.open(EVENTS, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, line)
    finally:
        os.close(fd)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"instrumented-worker")
    def log_message(self, fmt, *args):
        pass

def ready(worker_id):
    with open(os.path.join(BASE, f"w{worker_id}.ready"), "w") as f:
        f.write("ready")
    record("ready", worker_id)

def make_server(worker_id):
    server = HTTPServer(("127.0.0.1", 8080 + worker_id), Handler)
    record("listen", worker_id)
    return server

if len(sys.argv) != 2 or sys.argv[1] not in {"1", "2", "3"}:
    sys.exit(64)
worker_id = int(sys.argv[1])
record("start", worker_id)

# Deliberately expose the two readiness conditions in opposite orders. This
# catches deployers that check only a file, only a port, or launch all workers.
if worker_id == 1:
    ready(worker_id)
    time.sleep(1.2)
    server = make_server(worker_id)
elif worker_id == 2:
    server = make_server(worker_id)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    time.sleep(1.2)
    ready(worker_id)
    thread.join()
    sys.exit(0)
else:
    ready(worker_id)
    time.sleep(1.2)
    server = make_server(worker_id)

server.serve_forever()
'''

STATE_FILES = [
    DEPLOY_DIR / "w1.ready",
    DEPLOY_DIR / "w2.ready",
    DEPLOY_DIR / "w3.ready",
    DEPLOY_DIR / "status.log",
    EVENT_LOG,
]


def kill_workers():
    subprocess.run(["pkill", "-f", "/home/user/deploy/worker.py"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def clean_state():
    for path in STATE_FILES:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def parse_events():
    events = []
    if EVENT_LOG.exists():
        for line in EVENT_LOG.read_text().splitlines():
            timestamp, event, worker_id = line.split()
            events.append((float(timestamp), event, int(worker_id)))
    return events


def event_time(events, event, worker_id):
    matches = [t for t, e, i in events if e == event and i == worker_id]
    assert len(matches) == 1, f"Expected exactly one {event} event for worker {worker_id}; got {matches}"
    return matches[0]


def run_staging_probe():
    assert WORKER_SCRIPT.read_bytes() == EXPECTED_WORKER, \
        "worker.py was modified even though the task explicitly forbids it"
    original_mode = WORKER_SCRIPT.stat().st_mode
    original = WORKER_SCRIPT.read_bytes()

    kill_workers()
    clean_state()
    WORKER_SCRIPT.write_text(INSTRUMENTED_WORKER)
    os.chmod(WORKER_SCRIPT, original_mode)

    proc = None
    status_seen = None
    try:
        proc = subprocess.Popen(
            ["python3", str(DEPLOY_SCRIPT)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 15
        while proc.poll() is None and time.monotonic() < deadline:
            if status_seen is None and (DEPLOY_DIR / "status.log").is_file():
                status_seen = time.monotonic()
            time.sleep(0.01)

        if proc.poll() is None:
            proc.kill()
            proc.wait()
            pytest.fail("deploy.py timed out during staged-readiness testing")
        stderr = proc.stderr.read().decode(errors="replace")
        assert proc.returncode == 0, f"deploy.py failed during staged-readiness testing: {stderr}"
        if status_seen is None and (DEPLOY_DIR / "status.log").is_file():
            status_seen = time.monotonic()

        events = parse_events()
        for worker_id in (1, 2, 3):
            event_time(events, "start", worker_id)
            event_time(events, "ready", worker_id)
            event_time(events, "listen", worker_id)

        start1 = event_time(events, "start", 1)
        start2 = event_time(events, "start", 2)
        start3 = event_time(events, "start", 3)
        listen1 = event_time(events, "listen", 1)
        listen2 = event_time(events, "listen", 2)
        listen3 = event_time(events, "listen", 3)
        ready1 = event_time(events, "ready", 1)
        ready2 = event_time(events, "ready", 2)
        ready3 = event_time(events, "ready", 3)

        assert start1 < start2 < start3, "Workers were not launched in dependency order"
        assert start2 >= max(ready1, listen1), \
            "Worker 2 was launched before both Worker 1 readiness conditions were satisfied"
        assert start3 >= max(ready2, listen2), \
            "Worker 3 was launched before both Worker 2 readiness conditions were satisfied"
        assert status_seen is not None, "status.log was not created"
        assert status_seen >= max(ready3, listen3), \
            "status.log was created before both Worker 3 readiness conditions were satisfied"
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        kill_workers()
        WORKER_SCRIPT.write_bytes(original)
        os.chmod(WORKER_SCRIPT, original_mode)
        clean_state()


@pytest.fixture(scope="session", autouse=True)
def run_deploy_script():
    assert DEPLOY_SCRIPT.is_file(), f"{DEPLOY_SCRIPT} does not exist."

    # First exercise the deployment against workers whose file and network
    # readiness become true separately, proving each stage waits for both.
    run_staging_probe()

    # Preserve the original verifier's end-to-end run and final-state checks.
    kill_workers()
    clean_state()
    try:
        subprocess.run(
            ["python3", str(DEPLOY_SCRIPT)],
            timeout=20,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.py timed out after 20 seconds. It may be hanging or failing to detect readiness.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"deploy.py exited with an error: {e.stderr.decode(errors='replace')}")

    yield
    kill_workers()


def test_status_log():
    log_path = DEPLOY_DIR / "status.log"
    assert log_path.is_file(), f"{log_path} was not created."
    content = log_path.read_text().strip()
    assert content == "DEPLOYMENT SUCCESSFUL", \
        f"Expected 'DEPLOYMENT SUCCESSFUL' in status.log, got '{content}'"


def test_readiness_files():
    for i in range(1, 4):
        ready_file = DEPLOY_DIR / f"w{i}.ready"
        assert ready_file.is_file(), \
            f"Readiness file {ready_file} is missing. Worker {i} may have crashed or not started."


def test_worker_ports_listening():
    for i, port in enumerate([8081, 8082, 8083], start=1):
        is_listening = False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                is_listening = True
        except OSError:
            pass
        assert is_listening, \
            f"Worker {i} is not listening on port {port}. It may have crashed due to unmet dependencies."


def socket_owner_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_port = int(fields[1].rsplit(":", 1)[1], 16)
            state = fields[3]
            if local_port == port and state == "0A":
                inodes.add(fields[9])

    owners = set()
    for proc_dir in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc_dir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(proc_dir.name))
        except OSError:
            continue
    return owners


def test_ports_are_owned_by_required_workers():
    for worker_id in (1, 2, 3):
        owners = socket_owner_pids(8080 + worker_id)
        assert owners, f"No process owns the listening socket for Worker {worker_id}"
        matching = []
        for pid in owners:
            try:
                args = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
                args = [arg.decode(errors="replace") for arg in args if arg]
            except OSError:
                continue
            if len(args) >= 3 and args[-2:] == [str(WORKER_SCRIPT), str(worker_id)]:
                matching.append(pid)
        assert matching, \
            f"Port {8080 + worker_id} is not owned by 'python3 {WORKER_SCRIPT} {worker_id}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
