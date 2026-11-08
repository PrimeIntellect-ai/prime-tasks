#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests

HOME = "/home/user"
APP = "/home/user/app"
LIB = "/home/user/app/lib/libtaskqueue.so"
BINARY = "/home/user/app/task-broker"


@pytest.fixture(scope="session", autouse=True)
def build_artifacts():
    path = "/home/user/build.sh"
    assert os.path.isfile(path), f"Build script {path} is missing."
    assert os.access(path, os.X_OK), f"Build script {path} is not executable."

    # Remove stale artifacts so the build script must actually produce them.
    for artifact in (LIB, BINARY):
        try:
            os.remove(artifact)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [path], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180
    )
    assert result.returncode == 0, f"build.sh failed:\n{result.stdout}"
    assert os.path.isfile(LIB), f"The shared library {LIB} was not produced."
    assert os.path.isfile(BINARY), f"The compiled Go binary {BINARY} is missing. Ensure the build script produces it."
    assert os.access(BINARY, os.X_OK), f"The compiled Go binary {BINARY} is not executable."

    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB} is not an ELF shared library."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.dirname(LIB)
    linked = subprocess.run(
        ["ldd", BINARY], env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20
    )
    assert linked.returncode == 0, f"ldd failed for task-broker:\n{linked.stdout}"
    assert "libtaskqueue.so" in linked.stdout and "not found" not in linked.stdout, (
        f"task-broker is not dynamically linked to an available libtaskqueue.so:\n{linked.stdout}"
    )


def test_task_queue_cpp_lock():
    path = "/home/user/app/cpp/TaskQueue.cpp"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "std::lock_guard" in content, "std::lock_guard is missing in TaskQueue.cpp. The pop_task method must be thread-safe."

    # Ensure lock_guard is used inside pop_task
    match = re.search(r'Task\*\s+TaskQueue::pop_task\s*\([^)]*\)\s*\{([^}]*std::lock_guard[^}]*)\}', content, re.DOTALL)
    if not match:
        # Fallback check in case the regex doesn't match perfectly due to nested braces
        assert re.search(r'pop_task\s*\([^)]*\)\s*\{.*std::lock_guard', content, re.DOTALL), "std::lock_guard must be inside the pop_task method."


def test_shared_library_priority_and_concurrency():
    lib = ctypes.CDLL(LIB)
    lib.create_queue.restype = ctypes.c_void_p
    lib.push_queue.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    lib.pop_queue.argtypes = [ctypes.c_void_p]
    lib.pop_queue.restype = ctypes.c_void_p
    lib.destroy_queue.argtypes = [ctypes.c_void_p]

    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]

    def pop(q):
        ptr = lib.pop_queue(q)
        if not ptr:
            return None
        try:
            return ctypes.string_at(ptr).decode("utf-8")
        finally:
            libc.free(ptr)

    q = lib.create_queue()
    assert q, "create_queue returned null"
    try:
        assert pop(q) is None, "Popping an empty queue must return nullptr."

        values = [(f"lib-{uuid.uuid4().hex}", priority) for priority in range(-80, 120)]
        # Concurrent calls exercise the mutex rather than merely searching source text.
        with ThreadPoolExecutor(max_workers=16) as pool:
            futures = [pool.submit(lib.push_queue, q, task_id.encode(), priority)
                       for task_id, priority in values]
            for future in futures:
                future.result(timeout=10)

        expected = [task_id for task_id, _ in sorted(values, key=lambda x: x[1], reverse=True)]
        actual = [pop(q) for _ in values]
        assert actual == expected, "The shared library did not pop tasks in descending priority order."
        assert pop(q) is None, "The queue was not empty after all tasks were popped."

        more_ids = [f"pop-{uuid.uuid4().hex}" for _ in range(240)]
        for priority, task_id in enumerate(more_ids):
            lib.push_queue(q, task_id.encode(), priority)
        with ThreadPoolExecutor(max_workers=16) as pool:
            popped = list(pool.map(lambda _: pop(q), range(len(more_ids))))
        assert None not in popped
        assert sorted(popped) == sorted(more_ids), "Concurrent pop_queue calls lost or duplicated tasks."
        assert pop(q) is None
    finally:
        lib.destroy_queue(q)


def test_system_script_makes_required_requests():
    script = "/home/user/test_system.py"
    assert os.path.isfile(script), f"Python integration script {script} is missing."

    expected_posts = {
        ("task1", 10),
        ("task2", 30),
        ("task3", 20),
    }
    state = {
        "posts": [],
        "queue": [],
        "gets": 0,
        "barrier_passes": 0,
    }
    lock = threading.Lock()
    barrier = threading.Barrier(3)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            if self.path != "/enqueue":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                item = (body["id"], body["priority"])
            except Exception:
                self.send_error(400)
                return

            with lock:
                state["posts"].append(item)
                state["queue"].append(item)
            try:
                # A sequential implementation cannot get all three handlers here together.
                barrier.wait(timeout=5)
                with lock:
                    state["barrier_passes"] += 1
            except threading.BrokenBarrierError:
                self.send_error(409)
                return
            self.send_response(200)
            self.end_headers()

        def do_GET(self):
            if self.path != "/dequeue":
                self.send_error(404)
                return
            with lock:
                state["gets"] += 1
                if not state["queue"]:
                    self.send_error(404)
                    return
                index = max(range(len(state["queue"])), key=lambda i: state["queue"][i][1])
                task_id, _ = state["queue"].pop(index)
            data = json.dumps({"id": task_id}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    subprocess.run(["pkill", "-f", "/home/user/app/task-broker"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    server = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        try:
            os.remove("/home/user/api_output.txt")
        except FileNotFoundError:
            pass
        result = subprocess.run(
            ["python3", script], cwd=HOME, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=30
        )
        assert result.returncode == 0, f"test_system.py failed:\n{result.stdout}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert set(state["posts"]) == expected_posts and len(state["posts"]) == 3, (
        f"test_system.py sent incorrect enqueue requests: {state['posts']}"
    )
    assert state["barrier_passes"] == 3, "The three POST requests were not sent concurrently."
    assert state["gets"] == 3, f"Expected three dequeue requests, got {state['gets']}."
    assert state["queue"] == [], "test_system.py did not dequeue all three enqueued tasks."


def test_api_output_content():
    path = "/home/user/api_output.txt"
    assert os.path.isfile(path), f"File {path} is missing. The test script did not produce the expected output file."

    with open(path, "r") as f:
        content = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    expected = ["task2", "task3", "task1"]
    assert content == expected, f"The contents of {path} are incorrect. Expected {expected}, but got {content}."


def test_running_service_with_unpredictable_inputs():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.dirname(LIB)
    subprocess.run(["pkill", "-f", "/home/user/app/task-broker"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    proc = subprocess.Popen(
        [BINARY], cwd=APP, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True
    )
    try:
        deadline = time.time() + 12
        while time.time() < deadline:
            if proc.poll() is not None:
                output = proc.stdout.read() if proc.stdout else ""
                pytest.fail(f"task-broker exited before serving requests:\n{output}")
            try:
                response = requests.get("http://127.0.0.1:8080/dequeue", timeout=0.4)
                if response.status_code == 404:
                    break
            except requests.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail("task-broker did not begin listening on port 8080")

        priorities = [137, -41, 902, 0, 56, 411, -300, 78, 1001, 12]
        items = [(f"verify-{uuid.uuid4().hex}", p) for p in priorities]

        def enqueue(item):
            task_id, priority = item
            return requests.post(
                "http://127.0.0.1:8080/enqueue",
                json={"id": task_id, "priority": priority}, timeout=5
            )

        with ThreadPoolExecutor(max_workers=len(items)) as pool:
            responses = list(pool.map(enqueue, items))
        assert all(r.status_code == 200 for r in responses), (
            f"Some enqueue requests failed: {[r.status_code for r in responses]}"
        )

        actual = []
        for _ in items:
            response = requests.get("http://127.0.0.1:8080/dequeue", timeout=5)
            assert response.status_code == 200, f"dequeue returned HTTP {response.status_code}: {response.text}"
            actual.append(response.json()["id"])

        expected = [task_id for task_id, _ in sorted(items, key=lambda x: x[1], reverse=True)]
        assert actual == expected, f"REST API priority order was incorrect: expected {expected}, got {actual}"
        assert requests.get("http://127.0.0.1:8080/dequeue", timeout=5).status_code == 404
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def test_build_script_exists_and_executable():
    path = "/home/user/build.sh"
    assert os.path.isfile(path), f"Build script {path} is missing."
    assert os.access(path, os.X_OK), f"Build script {path} is not executable."


def test_task_broker_binary_exists():
    path = "/home/user/app/task-broker"
    assert os.path.isfile(path), f"The compiled Go binary {path} is missing. Ensure the build script produces it."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
