#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/verify_capacity.py
import http.client
import json
import os
import random
import socket
import socketserver
import stat
import subprocess
import threading
import time

BASHRC = "/home/user/.bashrc"
PLANNER = "/home/user/capacity_planner.py"
REPORT = "/home/user/capacity_report.json"
TARGET = "/home/user/target_app.py"


def target_processes():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if any(arg == TARGET for arg in args):
            found.append((int(entry), args))
    return found


def assert_port_free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", port))


def rss_bytes(pid):
    try:
        with open(f"/proc/{pid}/statm") as f:
            fields = f.read().split()
        return int(fields[1]) * os.sysconf("SC_PAGE_SIZE")
    except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
        return 0


# Preserve the original final-state assertions before creating verifier-owned processes.
assert os.path.exists(BASHRC), f"{BASHRC} does not exist"
with open(BASHRC) as f:
    bashrc_content = f.read()
assert "CAPACITY_TARGET_PORT=8080" in bashrc_content, "CAPACITY_TARGET_PORT=8080 not found in .bashrc"
assert not target_processes(), f"target_app.py is still running: {target_processes()}"
assert_port_free(8080)
assert_port_free(9090)

# The demanded artifact must exist, be a real nonempty Python file, and execute.
assert os.path.isfile(PLANNER), f"{PLANNER} not found or is not a regular file"
assert os.path.getsize(PLANNER) > 0, f"{PLANNER} is empty"
with open(PLANNER, "rb") as f:
    compile(f.read(), PLANNER, "exec")

try:
    os.unlink(REPORT)
except FileNotFoundError:
    pass

state_lock = threading.Lock()
state = {
    "requests": 0,
    "successful": 0,
    "active": 0,
    "max_active": 0,
    "durations_ms": [],
    "peak_rss": 0,
}
target_proc = None
# A verifier-selected delay makes the expected latency unavailable to a fabricated report.
forward_delay = random.SystemRandom().uniform(0.075, 0.325)


class ForwardHandler(socketserver.BaseRequestHandler):
    def handle(self):
        started = time.perf_counter()
        counted = False
        try:
            self.request.settimeout(10)
            request = b""
            while b"\r\n\r\n" not in request and len(request) < 65536:
                chunk = self.request.recv(4096)
                if not chunk:
                    break
                request += chunk
            first_line = request.split(b"\r\n", 1)[0]
            assert first_line.startswith(b"GET /compute "), f"unexpected forwarded request: {first_line!r}"

            with state_lock:
                state["requests"] += 1
                state["active"] += 1
                state["max_active"] = max(state["max_active"], state["active"])
                counted = True

            time.sleep(forward_delay)
            response = b""
            with socket.create_connection(("127.0.0.1", 9090), timeout=10) as upstream:
                upstream.sendall(request)
                while True:
                    chunk = upstream.recv(65536)
                    if not chunk:
                        break
                    response += chunk
                    self.request.sendall(chunk)

            assert response.startswith(b"HTTP/1.0 200") or response.startswith(b"HTTP/1.1 200"), "target did not return HTTP 200"
            assert b"Computation complete" in response, "unexpected target response body"
            elapsed = (time.perf_counter() - started) * 1000.0
            with state_lock:
                state["successful"] += 1
                state["durations_ms"].append(elapsed)
                if target_proc is not None:
                    state["peak_rss"] = max(state["peak_rss"], rss_bytes(target_proc.pid))
        finally:
            if counted:
                with state_lock:
                    state["active"] -= 1


class ForwardServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


server = None
monitor_stop = threading.Event()
monitor_thread = None
try:
    target_proc = subprocess.Popen(
        ["python3", TARGET],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.time() + 8
    while True:
        if target_proc.poll() is not None:
            raise AssertionError("target_app.py exited before testing")
        try:
            conn = http.client.HTTPConnection("127.0.0.1", 9090, timeout=0.5)
            conn.request("GET", "/")
            conn.getresponse().read()
            conn.close()
            break
        except OSError:
            if time.time() >= deadline:
                raise AssertionError("target_app.py did not start on port 9090")
            time.sleep(0.05)

    def monitor():
        while not monitor_stop.is_set():
            value = rss_bytes(target_proc.pid)
            with state_lock:
                state["peak_rss"] = max(state["peak_rss"], value)
            monitor_stop.wait(0.005)

    monitor_thread = threading.Thread(target=monitor, daemon=True)
    monitor_thread.start()

    server = ForwardServer(("127.0.0.1", 8080), ForwardHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    env = os.environ.copy()
    env["CAPACITY_TARGET_PORT"] = "8080"
    run = subprocess.run(
        ["python3", PLANNER],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, f"capacity_planner.py failed\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"

    # Give proxy handlers a moment to finish their bookkeeping.
    deadline = time.time() + 2
    while time.time() < deadline:
        with state_lock:
            if state["active"] == 0:
                break
        time.sleep(0.01)

    assert os.path.exists(REPORT), f"{REPORT} not found after executing planner"
    with open(REPORT) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{REPORT} is not valid JSON: {exc}")

    # Preserve the original report assertions.
    assert "total_requests" in data, "Missing 'total_requests' key in report"
    assert data["total_requests"] == 20, f"total_requests must be exactly 20, got {data['total_requests']}"
    assert "avg_latency_ms" in data, "Missing 'avg_latency_ms' key in report"
    assert isinstance(data["avg_latency_ms"], (int, float)) and not isinstance(data["avg_latency_ms"], bool), "avg_latency_ms must be a number"
    assert data["avg_latency_ms"] > 0, f"avg_latency_ms must be positive, got {data['avg_latency_ms']}"
    assert "peak_rss_bytes" in data, "Missing 'peak_rss_bytes' key in report"
    assert type(data["peak_rss_bytes"]) is int, "peak_rss_bytes must be an integer"
    assert data["peak_rss_bytes"] > 10 * 1024 * 1024, f"peak_rss_bytes should exceed 10MB, got {data['peak_rss_bytes']}"

    with state_lock:
        observed = dict(state)
    assert observed["requests"] == 20, f"expected exactly 20 requests through port 8080, observed {observed['requests']}"
    assert observed["successful"] == 20, f"only {observed['successful']} forwarded requests completed successfully"
    assert observed["max_active"] == 1, f"requests were not sequential (maximum concurrent requests: {observed['max_active']})"

    observed_latency = sum(observed["durations_ms"]) / len(observed["durations_ms"])
    latency_tolerance = max(40.0, observed_latency * 0.25)
    assert abs(float(data["avg_latency_ms"]) - observed_latency) <= latency_tolerance, (
        f"reported average latency {data['avg_latency_ms']}ms does not match observed {observed_latency:.2f}ms"
    )

    measured_peak = observed["peak_rss"]
    assert measured_peak > 10 * 1024 * 1024, "verifier could not measure target RSS"
    assert abs(data["peak_rss_bytes"] - measured_peak) <= 4 * 1024 * 1024, (
        f"reported peak RSS {data['peak_rss_bytes']} does not match observed {measured_peak}"
    )
finally:
    monitor_stop.set()
    if monitor_thread is not None:
        monitor_thread.join(timeout=1)
    if server is not None:
        server.shutdown()
        server.server_close()
    if target_proc is not None and target_proc.poll() is None:
        target_proc.terminate()
        try:
            target_proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            target_proc.kill()
            target_proc.wait(timeout=3)

# Verifier-owned processes must also have released the requested resources.
assert not target_processes(), f"target_app.py remains running: {target_processes()}"
assert_port_free(8080)
assert_port_free(9090)
PYTEST

if python3 /tmp/verify_capacity.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
