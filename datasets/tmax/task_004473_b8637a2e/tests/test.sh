#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import os
import random
import re
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

PROJECT_DIR = "/home/user/artifact_server"
SCRIPT_PATH = "/home/user/benchmark.py"
RESULT_PATH = "/home/user/p95_result.txt"


def test_rust_server_compiles():
    """Check that the Rust server passes the original check and builds in release mode."""
    assert os.path.isdir(PROJECT_DIR), f"Directory {PROJECT_DIR} does not exist."

    try:
        result = subprocess.run(
            ["cargo", "check", "--release"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Rust project failed to compile. Error:\n{result.stderr}"

        build = subprocess.run(
            ["cargo", "build", "--release"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"cargo build --release failed. Error:\n{build.stderr}"
        binary = os.path.join(PROJECT_DIR, "target", "release", "artifact_server")
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Release server binary was not produced."
    except FileNotFoundError:
        pytest.fail("cargo command not found. Is Rust installed?")
    except subprocess.TimeoutExpired:
        pytest.fail("Cargo compilation timed out.")


def _fetch(url):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        return response.read().decode("utf-8")


def test_rust_server_running_and_correct():
    """Exercise the running server with unpredictable IDs and repeated cache lookups."""
    ids = [f"audit_{uuid.uuid4().hex}" for _ in range(8)]
    try:
        for artifact_id in ids:
            url = f"http://127.0.0.1:8080/artifact/v2/linux?id={artifact_id}"
            expected = f"ArtifactData_{artifact_id}"
            assert _fetch(url) == expected
            assert _fetch(url) == expected
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the Rust server on port 8080. Is it running? Error: {e}")
    except Exception as e:
        pytest.fail(f"Unexpected error when communicating with the Rust server: {e}")


def test_benchmark_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as e:
        pytest.fail(f"benchmark.py is not valid Python: {e}")

    forbidden = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            forbidden.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            forbidden.add(node.module.split(".")[0])
    assert "numpy" not in forbidden and "statistics" not in forbidden, \
        "benchmark.py must use only a custom standard-library percentile calculation, not numpy/statistics."


def test_p95_result_exists_and_format():
    assert os.path.isfile(RESULT_PATH), f"The result file {RESULT_PATH} does not exist."
    with open(RESULT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content, f"The file {RESULT_PATH} is empty."
    try:
        float(content)
    except ValueError:
        pytest.fail(f"The content of {RESULT_PATH} ('{content}') is not a valid float.")
    assert re.fullmatch(r"\d+\.\d{2}", content), \
        f"The value '{content}' is not rounded to exactly 2 decimal places."


def _kill_port_8080_listener():
    """Terminate the already-validated agent server so a controlled benchmark server can bind."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
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
                    victims.add(int(pid))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def test_benchmark_executes_500_requests_and_computes_p95():
    """Run benchmark.py against controlled timings and derive the expected percentile independently."""
    _kill_port_8080_listener()

    high_delay_ms = random.SystemRandom().randint(90, 230)
    high_ids = set(random.SystemRandom().sample(range(1, 501), 25))
    received = []
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                received.append(self.path)

            match = re.fullmatch(r"/artifact/v2/linux\?id=(\d+)", self.path)
            if not match:
                self.send_response(404)
                self.end_headers()
                return

            artifact_id = int(match.group(1))
            delay_ms = high_delay_ms if artifact_id in high_ids else 1
            time.sleep(delay_ms / 1000.0)
            body = f"ArtifactData_{artifact_id}".encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        run = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=40,
        )
        assert run.returncode == 0, \
            f"benchmark.py failed. stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    expected_paths = [f"/artifact/v2/linux?id={n}" for n in range(1, 501)]
    assert len(received) == 500, f"Expected exactly 500 HTTP requests, received {len(received)}."
    assert collections.Counter(received) == collections.Counter(expected_paths), \
        "benchmark.py must request every id from 1 through 500 exactly once at the required URL."

    assert os.path.isfile(RESULT_PATH), "benchmark.py did not create p95_result.txt."
    with open(RESULT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert re.fullmatch(r"\d+\.\d{2}", content), \
        f"The generated value '{content}' is not a nonnegative float with exactly two decimals."

    measured_p95 = float(content)
    # There are exactly 475 low-latency and 25 secret high-latency requests. Thus
    # sorted_latencies[int(0.95 * 500)] is the first high-latency measurement.
    assert high_delay_ms - 5 <= measured_p95 <= high_delay_ms + 20, \
        f"Reported p95 {measured_p95:.2f} ms does not match the controlled p95 near {high_delay_ms} ms."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
