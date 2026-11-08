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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pwd
import random
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

SERVER_FILE = "/app/vendor/metrics_server-1.0.0/server.py"
GATHER_FILE = "/home/user/gather_stats.py"
STATS_FILE = "/home/user/stats.json"
AGGREGATOR_FILE = "/home/user/aggregator.py"


def read_stats():
    with open(STATS_FILE, "r") as f:
        return json.load(f)


def write_stats(value):
    tmp = STATS_FILE + ".verifier.tmp"
    with open(tmp, "w") as f:
        json.dump({"process_count": value}, f)
    os.replace(tmp, STATS_FILE)


def run_gather():
    subprocess.run(
        ["python3", GATHER_FILE],
        check=True,
        timeout=10,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    data = read_stats()
    assert set(data) == {"process_count"}, "stats.json must contain only process_count"
    assert isinstance(data["process_count"], int), "process_count is not an integer"
    return data["process_count"]


def ps_count():
    output = subprocess.check_output(["ps", "-e", "--no-headers"], timeout=5)
    return len(output.splitlines())


def aggregator_request(payload):
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(payload)
        chunks = []
        while True:
            part = sock.recv(1024)
            if not part:
                break
            chunks.append(part)
    return b"".join(chunks).decode("ascii")


def wait_http(port, expected=None, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(f"http://127.0.0.1:{port}/", timeout=0.5)
            if response.status_code == 200:
                data = response.json()
                if expected is None or data == {"process_count": expected}:
                    return response
        except Exception as exc:
            last_error = exc
        time.sleep(0.05)
    pytest.fail(f"HTTP server on port {port} did not become ready: {last_error}")


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(procdir + "/fd"):
                try:
                    target = os.readlink(procdir + "/fd/" + fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(procdir.rsplit("/", 1)[1]))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_port_free(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not listening_pids(port):
            return
        time.sleep(0.05)
    pytest.fail(f"Port {port} did not become free")


def start_vendored_server(port=9090):
    env = os.environ.copy()
    env["METRICS_PORT"] = str(port)
    proc = subprocess.Popen(
        ["python3", SERVER_FILE],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return proc


def test_server_py_fixed_and_executable():
    assert os.path.isfile(SERVER_FILE), f"File {SERVER_FILE} is missing"
    with open(SERVER_FILE, "r") as f:
        content = f.read()
    assert "METRICS_PORT" in content, "server.py was not fixed to use METRICS_PORT"

    challenge = random.randint(200000, 900000)
    write_stats(challenge)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]

    proc = start_vendored_server(port)
    try:
        response = wait_http(port, challenge)
        assert response.json() == {"process_count": challenge}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_gather_stats_script_exists_and_counts_processes():
    assert os.path.isfile(GATHER_FILE), f"File {GATHER_FILE} is missing"

    before_actual = ps_count()
    baseline = run_gather()
    after_actual = ps_count()
    assert min(before_actual, after_actual) - 1 <= baseline <= max(before_actual, after_actual) + 2, (
        f"gathered count {baseline} does not match the actual process count near "
        f"execution ({before_actual}, {after_actual})"
    )

    extra_count = random.randint(7, 12)
    children = [subprocess.Popen(["sleep", "30"]) for _ in range(extra_count)]
    try:
        augmented = run_gather()
        assert augmented - baseline == extra_count, (
            f"process_count did not increase by {extra_count} after starting "
            f"{extra_count} processes: {baseline} -> {augmented}"
        )
    finally:
        for child in children:
            child.terminate()
        for child in children:
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=2)
        run_gather()


def test_stats_json_exists_and_valid():
    assert os.path.isfile(STATS_FILE), f"File {STATS_FILE} is missing"
    try:
        data = read_stats()
    except json.JSONDecodeError:
        pytest.fail("stats.json does not contain valid JSON")
    assert "process_count" in data, "stats.json is missing the process_count key"
    assert isinstance(data["process_count"], int), "process_count is not an integer"


def test_cron_job_configured():
    try:
        output = subprocess.check_output(
            ["crontab", "-l", "-u", "user"], stderr=subprocess.STDOUT
        ).decode()
    except subprocess.CalledProcessError:
        try:
            output = subprocess.check_output(
                ["crontab", "-l"], stderr=subprocess.STDOUT
            ).decode()
        except subprocess.CalledProcessError:
            pytest.fail("Failed to read crontab")

    assert "gather_stats.py" in output, "Cron job for gather_stats.py is not configured"
    active_lines = [line.strip() for line in output.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+.*(?:python3\s+)?/home/user/gather_stats\.py(?:\s|$)", line) for line in active_lines), (
        "gather_stats.py is not scheduled every minute"
    )


def test_http_metrics_server_serves_current_file():
    challenge = random.randint(1000000, 2000000)
    write_stats(challenge)
    try:
        response = requests.get("http://127.0.0.1:9090/", timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to metrics server on port 9090: {exc}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from metrics server is not valid JSON: {response.text}")
    assert "process_count" in data, "JSON response missing process_count key"
    assert isinstance(data["process_count"], int), "process_count in JSON response is not an integer"
    assert data == {"process_count": challenge}, "HTTP server did not serve the current stats.json value"


def test_tcp_aggregator_matches_http_metric():
    assert os.path.isfile(AGGREGATOR_FILE), f"File {AGGREGATOR_FILE} is missing"
    challenge = random.randint(2100000, 3000000)
    write_stats(challenge)
    http_data = requests.get("http://127.0.0.1:9090/", timeout=2).json()
    assert http_data == {"process_count": challenge}

    for payload in (b"FETCH_CAPACITY\n", b"FETCH_CAPACITY"):
        response = aggregator_request(payload)
        assert re.match(r"^CAPACITY_OK: \d+\n$", response), f"Invalid aggregator response: {response!r}"
        assert response == f"CAPACITY_OK: {http_data['process_count']}\n"


def test_aggregator_actually_fetches_http():
    old_pids = listening_pids(9090)
    assert old_pids, "No metrics server is listening on port 9090"
    for pid in old_pids:
        os.kill(pid, signal.SIGTERM)
    wait_port_free(9090)

    challenge = random.randint(3100000, 4000000)
    write_stats(challenge + 1)
    marker = f"/tmp/verifier_http_requests_{os.getpid()}"
    challenge_code = r'''
import http.server, json, os, socketserver
value = int(os.environ["CHALLENGE_VALUE"])
marker = os.environ["CHALLENGE_MARKER"]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(marker, "a") as f:
            f.write("GET\n")
        body = json.dumps({"process_count": value}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
class Server(socketserver.TCPServer):
    allow_reuse_address = True
with Server(("127.0.0.1", 9090), Handler) as server:
    server.serve_forever()
'''
    env = os.environ.copy()
    env["CHALLENGE_VALUE"] = str(challenge)
    env["CHALLENGE_MARKER"] = marker
    challenge_server = subprocess.Popen(
        ["python3", "-u", "-c", challenge_code],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    replacement = None
    try:
        wait_http(9090, challenge)
        before = 0
        if os.path.exists(marker):
            before = len(open(marker).readlines())
        response = aggregator_request(b"FETCH_CAPACITY\n")
        assert response == f"CAPACITY_OK: {challenge}\n", (
            "Aggregator did not use the JSON supplied by the HTTP metrics endpoint"
        )
        after = len(open(marker).readlines()) if os.path.exists(marker) else 0
        assert after > before, "Aggregator did not make an HTTP GET request"
    finally:
        challenge_server.terminate()
        try:
            challenge_server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            challenge_server.kill()
            challenge_server.wait(timeout=3)
        wait_port_free(9090)
        replacement = start_vendored_server(9090)
        run_gather()
        wait_http(9090)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
