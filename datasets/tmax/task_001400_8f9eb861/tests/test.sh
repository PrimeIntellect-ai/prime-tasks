#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/dashboard_probe.py
import fcntl
import http.server
import os
import socketserver
import time

EVENTS = "/tmp/dashboard_probe_events"
COUNTER = "/tmp/dashboard_probe_counter"

with open(COUNTER, "a+") as counter_file:
    fcntl.flock(counter_file, fcntl.LOCK_EX)
    counter_file.seek(0)
    text = counter_file.read().strip()
    instance = (int(text) if text else 0) + 1
    counter_file.seek(0)
    counter_file.truncate()
    counter_file.write(str(instance))
    counter_file.flush()
    os.fsync(counter_file.fileno())
    fcntl.flock(counter_file, fcntl.LOCK_UN)

requests = 0

def record(kind):
    with open(EVENTS, "a") as event_file:
        event_file.write(f"{kind} {instance} {os.getpid()} {time.monotonic()}\n")
        event_file.flush()
        os.fsync(event_file.fileno())

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global requests
        if self.path != "/health":
            self.send_response(404)
            self.end_headers()
            return

        requests += 1
        record("HEALTH")
        # The first process is the pre-existing dashboard. The first process
        # launched by the supervisor becomes unhealthy on its third check.
        status = 503 if instance == 2 and requests >= 3 else 200
        self.send_response(status)
        self.end_headers()
        self.wfile.write(b"OK" if status == 200 else b"UNHEALTHY")

    def log_message(self, *args):
        pass

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

server = ReusableTCPServer(("127.0.0.1", 8080), Handler)
record("START")
server.serve_forever()
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import stat
import subprocess
import time

DASHBOARD = "/home/user/dash_app/dashboard.py"
EVENTS = "/tmp/dashboard_probe_events"
COUNTER = "/tmp/dashboard_probe_counter"
PROBE = "/tmp/dashboard_probe.py"


def test_symlink_created_correctly():
    symlink_path = "/home/user/dash_app/current_metrics"
    target_path = "/home/user/metrics_data"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    assert os.readlink(symlink_path) == target_path, f"{symlink_path} does not point to {target_path}."


def test_supervisor_script_executable():
    script_path = "/home/user/supervisor.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def read_events():
    result = []
    if not os.path.exists(EVENTS):
        return result
    with open(EVENTS) as f:
        for line in f:
            fields = line.strip().split()
            if len(fields) == 4:
                result.append((fields[0], int(fields[1]), int(fields[2]), float(fields[3])))
    return result


def process_is_running(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError):
        return False


def wait_until(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError(message)


def test_supervisor_script_behavior():
    script_path = "/home/user/supervisor.sh"
    log_path = "/home/user/dash_app/supervision.log"
    original_data = open(DASHBOARD, "rb").read()
    original_mode = stat.S_IMODE(os.stat(DASHBOARD).st_mode)
    old_process = None
    supervisor = None

    subprocess.run(["pkill", "-f", "python3 /home/user/dash_app/dashboard.py"], capture_output=True)
    time.sleep(0.2)

    try:
        for path in (EVENTS, COUNTER, log_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        with open(PROBE, "rb") as source, open(DASHBOARD, "wb") as target:
            target.write(source.read())
        os.chmod(DASHBOARD, 0o755)

        # Start a real pre-existing instance on port 8080. The supervisor must
        # terminate it before launching the instance it will track.
        old_process = subprocess.Popen(
            ["python3", DASHBOARD],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid,
        )
        wait_until(
            lambda: any(e[0] == "START" and e[1] == 1 for e in read_events()),
            3,
            "The pre-existing dashboard failed to start on port 8080.",
        )

        supervisor = subprocess.Popen(
            [script_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid,
        )

        wait_until(
            lambda: any(e[0] == "START" and e[1] == 3 for e in read_events()),
            10,
            "Supervisor did not health-check, kill, and restart the unhealthy dashboard.",
        )

        events = read_events()
        starts = {instance: pid for kind, instance, pid, stamp in events if kind == "START"}
        assert 1 in starts and 2 in starts and 3 in starts, (
            f"Expected the existing process plus two supervisor launches; events were {events}"
        )

        wait_until(
            lambda: not process_is_running(starts[1]),
            2,
            "Supervisor did not kill the dashboard already occupying port 8080.",
        )
        wait_until(
            lambda: not process_is_running(starts[2]),
            2,
            "Supervisor restarted without killing the previously tracked dashboard process.",
        )
        assert process_is_running(starts[3]), "Restarted dashboard process is not running."

        health_times = [
            stamp for kind, instance, pid, stamp in events
            if kind == "HEALTH" and instance == 2 and pid == starts[2]
        ]
        assert len(health_times) >= 3, (
            f"Expected at least three real /health requests to the tracked process; events were {events}"
        )
        intervals = [b - a for a, b in zip(health_times, health_times[1:])]
        assert all(0.7 <= interval <= 2.5 for interval in intervals[:2]), (
            f"Health checks were not performed at approximately one-second intervals: {intervals}"
        )

        assert os.path.isfile(log_path), f"Log file {log_path} was not created by the supervisor."
        with open(log_path) as f:
            lines = [line.rstrip("\n") for line in f]

        assert "RESTART_EVENT | TOTAL_CRASHES: 1" in lines, (
            f"Expected 'RESTART_EVENT | TOTAL_CRASHES: 1' in log, but got:\n{lines}"
        )
        assert lines == ["RESTART_EVENT | TOTAL_CRASHES: 1"], (
            f"Expected exactly one correctly formatted restart record, but got: {lines}"
        )
        assert all(re.fullmatch(r"RESTART_EVENT \| TOTAL_CRASHES: [1-9][0-9]*", line) for line in lines)
    finally:
        if supervisor is not None and supervisor.poll() is None:
            try:
                os.killpg(os.getpgid(supervisor.pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        if old_process is not None and old_process.poll() is None:
            try:
                os.killpg(os.getpgid(old_process.pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        subprocess.run(["pkill", "-f", "python3 /home/user/dash_app/dashboard.py"], capture_output=True)
        with open(DASHBOARD, "wb") as f:
            f.write(original_data)
        os.chmod(DASHBOARD, original_mode)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
