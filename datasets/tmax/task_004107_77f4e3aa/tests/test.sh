#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import hashlib
import heapq
import json
import os
import random
import signal
import socket
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest
import redis

APP = "/home/user/app"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
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
            pass
    return pids


def stop_listener(port):
    for pid in listener_pids(port):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.15)


def wait_port(port, proc=None, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail(f"process exited while starting on port {port} (status {proc.returncode})")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"nothing listened on port {port}")


def start_solver():
    stop_listener(8081)
    log = open("/tmp/verified_solver.log", "ab", buffering=0)
    proc = subprocess.Popen(
        [os.path.join(APP, "solver")], cwd=APP,
        stdin=subprocess.DEVNULL, stdout=log, stderr=log,
        start_new_session=True,
    )
    wait_port(8081, proc)
    return proc


def recv_exact(sock, count):
    result = bytearray()
    while len(result) < count:
        chunk = sock.recv(count - len(result))
        if not chunk:
            raise AssertionError(f"short TCP response: wanted {count}, got {len(result)}")
        result.extend(chunk)
    return bytes(result)


def solver_request(jobs, dependencies):
    words = [jobs, len(dependencies)]
    for u, v in dependencies:
        words.extend((u, v))
    payload = struct.pack("<" + "I" * len(words), *words)
    with socket.create_connection(("127.0.0.1", 8081), timeout=5) as sock:
        sock.sendall(payload)
        count = struct.unpack("<I", recv_exact(sock, 4))[0]
        assert count <= jobs
        return list(struct.unpack("<" + "I" * count, recv_exact(sock, count * 4)))


def generate_dag(num_jobs, num_edges):
    edges = set()
    num_edges = min(num_edges, num_jobs * (num_jobs - 1) // 2)
    while len(edges) < num_edges:
        u = random.randint(0, num_jobs - 2)
        v = random.randint(u + 1, num_jobs - 1)
        edges.add((u, v))
    perm = list(range(num_jobs))
    random.shuffle(perm)
    return num_jobs, [[perm[u], perm[v]] for u, v in edges]


def oracle_topological_sort(num_jobs, edges):
    adj = [[] for _ in range(num_jobs)]
    indegree = [0] * num_jobs
    for u, v in edges:
        adj[u].append(v)
        indegree[v] += 1
    queue = [i for i in range(num_jobs) if indegree[i] == 0]
    heapq.heapify(queue)
    result = []
    while queue:
        node = heapq.heappop(queue)
        result.append(node)
        for neighbor in adj[node]:
            indegree[neighbor] -= 1
            if indegree[neighbor] == 0:
                heapq.heappush(queue, neighbor)
    return result


def send_request(payload):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/schedule",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            assert response.status == 200
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        pytest.fail(f"Request to gateway failed: {exc}")


class RecordingSolver(threading.Thread):
    def __init__(self, response):
        super().__init__(daemon=True)
        self.response = response
        self.requests = []
        self.ready = threading.Event()
        self.stop_event = threading.Event()
        self.error = None

    def run(self):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 8081))
                server.listen(5)
                server.settimeout(0.2)
                self.ready.set()
                while not self.stop_event.is_set():
                    try:
                        conn, _ = server.accept()
                    except socket.timeout:
                        continue
                    with conn:
                        header = recv_exact(conn, 8)
                        jobs, edge_count = struct.unpack("<II", header)
                        body = recv_exact(conn, edge_count * 8)
                        self.requests.append(header + body)
                        encoded = struct.pack("<I", len(self.response)) + struct.pack(
                            "<" + "I" * len(self.response), *self.response
                        )
                        # Deliberately fragment the response to verify stream-safe reads.
                        conn.sendall(encoded[:2])
                        time.sleep(0.02)
                        conn.sendall(encoded[2:])
        except Exception as exc:
            self.error = exc
            self.ready.set()


def test_complete_polyglot_scheduler():
    makefile = os.path.join(APP, "Makefile")
    source_path = os.path.join(APP, "solver.cpp")
    binary = os.path.join(APP, "solver")
    gateway = os.path.join(APP, "gateway.py")
    assert os.path.isfile(makefile), "Makefile is missing"
    assert os.path.isfile(source_path), "solver.cpp is missing"
    assert os.path.isfile(gateway), "gateway.py is missing"

    make_text = open(makefile, encoding="utf-8").read()
    assert "g++" in make_text
    assert "-std=c++17" in make_text
    assert "-pthread" in make_text
    source = open(source_path, encoding="utf-8").read()
    assert "in_degree[100]" not in source, "the fixed-size indegree overflow remains"
    assert "bool visited[N]" not in source, "the uninitialized variable-length visited array remains"

    stop_listener(8081)
    try:
        os.unlink(binary)
    except FileNotFoundError:
        pass
    built = subprocess.run(
        ["make"], cwd=APP, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=45
    )
    assert built.returncode == 0, f"default make target failed:\n{built.stdout}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "make did not produce executable solver"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "solver is not a compiled ELF executable"

    solver_proc = start_solver()

    # Exercise the compiled service directly, including an input far beyond the old 100-entry buffer.
    direct_cases = [
        (5, [[0, 1], [2, 3]]),
        (1200, [[i, i + 1] for i in range(1199)]),
        (1000, [[i, i + 7] for i in range(993)]),
    ]
    for jobs, deps in direct_cases:
        assert solver_request(jobs, deps) == oracle_topological_sort(jobs, deps)
    assert solver_proc.poll() is None, "compiled solver crashed during direct tests"

    try:
        cache = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
        cache.ping()
        cache.flushdb()
    except redis.ConnectionError:
        pytest.fail("Redis server is not running on 127.0.0.1:6379")

    # Preserve the original end-to-end randomized equivalence assertion.
    random.seed(42)
    for index in range(50):
        jobs = random.randint(10, 1000)
        edge_count = random.randint(0, 5000)
        jobs, deps = generate_dag(jobs, edge_count)
        payload = {"jobs": jobs, "dependencies": deps}
        expected = oracle_topological_sort(jobs, deps)
        response = send_request(payload)
        assert "schedule" in response
        assert response["schedule"] == expected, f"end-to-end mismatch on fuzz request {index}"

    # Replace port 8081 with a recording protocol peer. The non-oracle response proves
    # that the gateway actually serialized to and consumed a response from that port.
    stop_listener(8081)
    cache.flushdb()
    fake_schedule = [2, 1, 0, 3]
    recorder = RecordingSolver(fake_schedule)
    recorder.start()
    assert recorder.ready.wait(2), "recording solver did not start"
    assert recorder.error is None

    payload = {"jobs": 4, "dependencies": [[0, 3]]}
    first = send_request(payload)
    assert first == {"schedule": fake_schedule}, "gateway did not use the solver response from port 8081"

    expected_wire = struct.pack("<IIII", 4, 1, 0, 3)
    deadline = time.time() + 2
    while not recorder.requests and time.time() < deadline:
        time.sleep(0.02)
    assert recorder.requests == [expected_wire], "gateway did not use the specified little-endian protocol"

    keys = cache.keys("*")
    assert len(keys) == 1, "a cache miss did not create exactly one Redis entry"
    key = keys[0]
    assert len(key) == 64
    int(key, 16)
    assert json.loads(cache.get(key)) == {"schedule": fake_schedule}

    # Overwrite the cached JSON with a distinct result. A repeat request must return it
    # without making another solver connection.
    cached_schedule = [3, 2, 1, 0]
    cache.set(key, json.dumps({"schedule": cached_schedule}))
    second = send_request(payload)
    assert second == {"schedule": cached_schedule}, "gateway did not read the Redis cache"
    time.sleep(0.25)
    assert len(recorder.requests) == 1, "gateway contacted the solver again on a cache hit"

    recorder.stop_event.set()
    recorder.join(timeout=2)
    assert recorder.error is None

    # Leave the required compiled solver service running after verification.
    final_solver = start_solver()
    assert final_solver.poll() is None
    assert listener_pids(8080), "Python gateway is not running on port 8080"
PYTEST

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
