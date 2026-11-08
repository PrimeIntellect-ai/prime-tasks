#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.request

APP = "/home/user/app"
LIB = os.path.join(APP, "clib", "libscheduler.so")
INTEGRATION = os.path.join(APP, "integration_test.py")
PERF = os.path.join(APP, "perf.log")


def wait_for_api(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("api.py exited before the integration test ran")
        try:
            urllib.request.urlopen("http://127.0.0.1:5000/", timeout=0.2)
            return
        except Exception:
            time.sleep(0.05)
    raise AssertionError("Flask API did not start on port 5000")


def redis_tokens(line):
    quoted = re.findall(r'"(?:\\.|[^"\\])*"', line)
    result = []
    for token in quoted:
        try:
            result.append(json.loads(token))
        except Exception:
            pass
    return result


def redis_job_activity(path):
    enqueued = 0
    dequeued = 0
    with open(path, "r", errors="replace") as f:
        for line in f:
            tokens = redis_tokens(line)
            if not tokens:
                continue
            command = tokens[0].upper()
            args = tokens[1:]
            if command in ("LPUSH", "RPUSH", "LPUSHX", "RPUSHX") and len(args) >= 2:
                enqueued += len(args) - 1
            elif command in ("LPOP", "RPOP") and args:
                if len(args) >= 2:
                    try:
                        dequeued += int(args[1])
                    except ValueError:
                        dequeued += 1
                else:
                    dequeued += 1
            elif command in ("BLPOP", "BRPOP", "RPOPLPUSH", "BRPOPLPUSH", "LMOVE", "BLMOVE"):
                dequeued += 1
    return enqueued, dequeued


def check_library():
    assert os.path.isfile(LIB), f"File {LIB} does not exist. Did you compile the C library?"
    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libscheduler.so is not an ELF shared library"

    symbols = subprocess.run(
        ["nm", "-D", LIB], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"\bschedule$", symbols, re.MULTILINE), "schedule is not exported by libscheduler.so"

    # Exercise the required ABI in a child process so a broken struct mapping or
    # crashing implementation becomes a normal verifier failure.
    probe = r'''
import ctypes
lib = ctypes.CDLL("/home/user/app/clib/libscheduler.so")
class Node(ctypes.Structure):
    _fields_ = [("id", ctypes.c_int), ("dep", ctypes.c_int)]
class Graph(ctypes.Structure):
    _fields_ = [("nodes", ctypes.POINTER(Node)), ("count", ctypes.c_int)]
nodes = (Node * 4)(Node(0, -1), Node(1, 0), Node(2, 0), Node(3, 2))
graph = Graph(nodes, 4)
lib.schedule.argtypes = [Graph]
lib.schedule.restype = ctypes.c_int
result = lib.schedule(graph)
assert isinstance(result, int)
'''
    subprocess.run(["python3", "-c", probe], check=True, timeout=5)


def check_redis_lists_empty():
    result = subprocess.run(["redis-cli", "keys", "*"], capture_output=True, text=True, check=True)
    for key in result.stdout.split():
        key_type = subprocess.run(
            ["redis-cli", "type", key], capture_output=True, text=True, check=True
        ).stdout.strip()
        if key_type == "list":
            length = int(subprocess.run(
                ["redis-cli", "llen", key], capture_output=True, text=True, check=True
            ).stdout.strip())
            assert length == 0, f"Redis list '{key}' is not empty (length {length}). Jobs were not fully processed."


def test_complete_system():
    check_library()
    assert os.path.isfile(INTEGRATION), f"File {INTEGRATION} does not exist. You must create the integration test script."

    subprocess.run(["redis-cli", "flushall"], check=True, stdout=subprocess.DEVNULL)
    for path in (PERF, "/tmp/api_request_count.json", "/tmp/redis-monitor.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    launcher = r'''
import json, os, signal, sys, threading
sys.path.insert(0, "/home/user/app")
import api
app = api.app
lock = threading.Lock()
state = {"successful_submits": 0}
@app.after_request
def verifier_count(response):
    from flask import request
    if request.path == "/submit" and request.method == "POST" and 200 <= response.status_code < 300:
        with lock:
            state["successful_submits"] += 1
    return response
def dump(signum=None, frame=None):
    with lock:
        data = dict(state)
    tmp = "/tmp/api_request_count.json.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, "/tmp/api_request_count.json")
signal.signal(signal.SIGUSR1, dump)
app.run(host="127.0.0.1", port=5000, threaded=True, use_reloader=False)
'''
    with open("/tmp/api_verifier_launcher.py", "w") as f:
        f.write(launcher)

    monitor_file = open("/tmp/redis-monitor.log", "w")
    monitor = subprocess.Popen(
        ["redis-cli", "monitor"], stdout=monitor_file, stderr=subprocess.STDOUT, text=True
    )
    worker_log = open("/tmp/worker-verifier.log", "w")
    api_log = open("/tmp/api-verifier.log", "w")
    worker = subprocess.Popen(
        ["python3", os.path.join(APP, "worker.py")], cwd=APP,
        stdout=worker_log, stderr=subprocess.STDOUT
    )
    api_proc = subprocess.Popen(
        ["python3", "/tmp/api_verifier_launcher.py"], cwd=APP,
        stdout=api_log, stderr=subprocess.STDOUT
    )

    try:
        wait_for_api(api_proc)
        time.sleep(0.2)  # Ensure Redis MONITOR is subscribed before submissions.
        assert worker.poll() is None, "worker.py is not running as a worker service"

        start = time.monotonic()
        try:
            subprocess.run(["python3", INTEGRATION], cwd=APP, check=True, timeout=30)
        except subprocess.TimeoutExpired:
            raise AssertionError("integration_test.py timed out. The system is too slow or hung.")
        elapsed = time.monotonic() - start

        assert elapsed <= 1.5, (
            f"Independently measured integration time was {elapsed:.6f} seconds, "
            "which is greater than 1.5 seconds."
        )
        assert worker.poll() is None, "worker.py exited while processing jobs"

        assert os.path.isfile(PERF), f"File {PERF} was not created by integration_test.py."
        content = open(PERF).read().strip()
        try:
            reported = float(content)
        except ValueError:
            raise AssertionError(f"Could not parse '{content}' in {PERF} as a float.")
        assert reported <= 1.5, (
            f"Execution time was {reported} seconds, which is strictly greater than the threshold of 1.5 seconds."
        )

        os.kill(api_proc.pid, signal.SIGUSR1)
        deadline = time.time() + 2
        while not os.path.exists("/tmp/api_request_count.json") and time.time() < deadline:
            time.sleep(0.02)
        assert os.path.isfile("/tmp/api_request_count.json"), "Could not obtain the API request count"
        with open("/tmp/api_request_count.json") as f:
            count = json.load(f)["successful_submits"]
        assert count == 5000, f"integration_test.py made {count} successful POST /submit requests, not 5000"

        time.sleep(0.1)
        monitor.terminate()
        monitor.wait(timeout=2)
        monitor_file.flush()
        enqueued, dequeued = redis_job_activity("/tmp/redis-monitor.log")
        assert enqueued >= 5000, f"Only {enqueued} jobs were observed being enqueued in Redis"
        assert dequeued >= 5000, f"Only {dequeued} jobs were observed being popped for processing"

        check_redis_lists_empty()
    finally:
        for proc in (monitor, api_proc, worker):
            if proc.poll() is None:
                proc.terminate()
        for proc in (monitor, api_proc, worker):
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        monitor_file.close()
        worker_log.close()
        api_log.close()
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
