#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import http.server
import os
import random
import re
import socket
import subprocess
import threading
import time

import pytest
import requests


def is_port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        return s.connect_ex(("127.0.0.1", port)) == 0


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and is_port_open(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def start_services():
    stop_port(8080)
    stop_port(9000)
    subprocess.Popen(
        ["bash", "/app/start_services.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if all(is_port_open(p) for p in (6379, 9000, 8080)):
            return
        time.sleep(0.1)
    pytest.fail("Redis, compute_engine, and frontend_api did not all start")


def test_wal_corruption_fixed():
    wal_path = "/app/data/engine.wal"
    assert os.path.isfile(wal_path), f"{wal_path} is missing"
    size = os.path.getsize(wal_path)
    assert size >= 16, "WAL file is too small to contain the 16-byte header."
    assert (size - 16) % 32 == 0, (
        f"WAL file size {size} is invalid. It should have a 16-byte header "
        "and exactly 32-byte records."
    )
    assert size == 16 + 100 * 32, "Complete WAL records were removed or corrupt bytes remain"
    with open(wal_path, "rb") as f:
        assert f.read(16) == b"WAL_v1.0" + b"\0" * 8, "The WAL header was modified"


def test_compute_engine_build():
    repo = "/app/compute_engine"
    result = subprocess.run(
        ["make", "-B", "engine"], cwd=repo,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert result.returncode == 0, f"compute_engine does not rebuild:\n{result.stdout}"

    engine_path = os.path.join(repo, "engine")
    assert os.path.isfile(engine_path), f"Compiled binary {engine_path} is missing"
    assert os.access(engine_path, os.X_OK), f"{engine_path} is not executable"
    with open(engine_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "engine must be the compiled native executable, not a script"

    queue_path = os.path.join(repo, "queue.c")
    assert os.path.isfile(queue_path), "queue.c is missing"
    source = open(queue_path, encoding="utf-8", errors="replace").read()
    assert not re.search(r"%\s*q->capacity\s*<=\s*q->head", source), (
        "queue.c still contains the original off-by-one full-queue boundary comparison"
    )


def test_services_and_real_load():
    start_services()
    pong = subprocess.check_output(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"], timeout=3)
    assert pong.strip() == b"PONG"

    direct = requests.get("http://127.0.0.1:9000/process", timeout=2)
    assert direct.status_code == 200, "compute_engine does not process requests on port 9000"
    assert direct.content, "compute_engine returned an empty response"

    nonce = random.getrandbits(64)
    workers = 128
    per_worker = [10000 // workers] * workers
    for i in range(10000 % workers):
        per_worker[i] += 1

    def send_batch(pair):
        worker_id, count = pair
        session = requests.Session()
        ok = 0
        errors = []
        for n in range(count):
            try:
                response = session.get(
                    f"http://127.0.0.1:8080/process?v={nonce}-{worker_id}-{n}",
                    headers={"Cache-Control": "no-cache"}, timeout=2
                )
                if response.status_code == 200 and response.text.strip() == "OK":
                    ok += 1
                else:
                    errors.append((response.status_code, response.text[:80]))
            except Exception as exc:
                errors.append(repr(exc))
        session.close()
        return ok, errors

    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(send_batch, enumerate(per_worker)))
    runtime = time.perf_counter() - started

    successes = sum(item[0] for item in results)
    errors = [error for item in results for error in item[1]]
    assert successes == 10000, f"Only {successes}/10000 requests succeeded; examples: {errors[:5]}"
    assert runtime < 3.0, f"Real 10,000-request runtime was {runtime:.3f}s, not less than 3.0s"


def test_frontend_actually_routes_to_engine():
    stop_port(9000)
    generated = []
    lock = threading.Lock()
    secret = os.urandom(16).hex()

    class Backend(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                token = f"BACKEND-{secret}-{len(generated)}"
                generated.append(token)
            body = token.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 9000), Backend)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for i in range(25):
            before = len(generated)
            response = requests.get(
                f"http://127.0.0.1:8080/process?probe={secret}-{i}", timeout=2
            )
            assert response.status_code == 200
            assert len(generated) == before + 1, "frontend returned without sending this request to port 9000"
            assert response.text.strip() == generated[-1], "frontend did not return the compute_engine response"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_original_load_test_metric_still_valid():
    try:
        out = subprocess.check_output(
            ["python3", "/app/load_test.py"], stderr=subprocess.STDOUT, timeout=45
        ).decode("utf-8")
    except subprocess.TimeoutExpired:
        pytest.fail("Load test timed out after 45 seconds")
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Load test failed with exit code {exc.returncode}:\n{exc.output.decode('utf-8')}")

    match = re.search(r"RESULT_RUNTIME_SECONDS:\s*([0-9.]+)", out)
    assert match is not None, f"Metric not found in output:\n{out}"
    assert float(match.group(1)) < 3.0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
