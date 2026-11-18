#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_task.py
import ast
import datetime
import glob
import json
import math
import os
import re
import signal
import statistics
import subprocess
import sys
import time
import urllib.request

REPO = "/app/vendored/log_timeline_api"
BASE = "http://127.0.0.1:9000"
SERVER_LOG = "/tmp/log_timeline_api_verifier_server.log"


def request(path, payload=None, timeout=3):
    data = None
    headers = {}
    method = "GET"
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
        method = "POST"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def wait_for_server():
    last_error = None
    for _ in range(20):
        try:
            status, _ = request("/anomalies", timeout=1)
            if status == 200:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError("Service is not running on 127.0.0.1:9000: %r" % (last_error,))


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == 9000:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = []
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(procdir + "/fd"):
                try:
                    target = os.readlink(procdir + "/fd/" + fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.append(pid)
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def stop_server():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(20):
        if not listener_pids():
            return
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def start_clean_server():
    stop_server()
    env = os.environ.copy()
    env["PYTHONPATH"] = REPO + os.pathsep + env.get("PYTHONPATH", "")
    log = open(SERVER_LOG, "ab", buffering=0)
    subprocess.Popen(
        [sys.executable, "-m", "log_timeline_api.server", "--port", "9000"],
        cwd=REPO,
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )
    wait_for_server()


def find_regression_test():
    candidates = ["/home/user/test_regression.py"]
    candidates += glob.glob("/home/user/**/*regression*.py", recursive=True)
    candidates += glob.glob(REPO + "/**/test*regression*.py", recursive=True)
    seen = set()
    for path in candidates:
        if path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        source = open(path, encoding="utf-8").read()
        try:
            tree = ast.parse(source, filename=path)
        except SyntaxError:
            continue
        has_assertion = any(isinstance(node, ast.Assert) for node in ast.walk(tree))
        has_assertion |= any(
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr.startswith("assert")
            for node in ast.walk(tree)
        )
        lower = source.lower()
        if has_assertion and "latency" in lower and "anomal" in lower and "23:" in source and "00:" in source:
            return path
    raise AssertionError("No assertion-based cross-midnight anomaly regression test was found")


def check_bisect_was_performed():
    culprit_lines = subprocess.check_output(
        ["git", "log", "--all", "--format=%H", "--grep=^Refactor time parsing for performance$"],
        cwd=REPO,
        text=True,
    ).splitlines()
    assert len(culprit_lines) == 1, "The original regression commit is missing or ambiguous"
    culprit = culprit_lines[0]

    messages = subprocess.check_output(
        ["git", "reflog", "--format=%gs"], cwd=REPO, text=True
    ).splitlines()
    checked_out = set()
    for message in messages:
        match = re.match(r"checkout: moving from .+ to ([0-9a-fA-F]{7,40})$", message)
        if not match:
            continue
        try:
            full = subprocess.check_output(
                ["git", "rev-parse", match.group(1) + "^{commit}"], cwd=REPO, text=True
            ).strip()
            checked_out.add(full)
        except subprocess.CalledProcessError:
            pass

    assert culprit in checked_out, "Git reflog does not show the regression commit being tested during bisect"
    assert len(checked_out) >= 4, "Git reflog does not show a substantive git bisect search"


def check_fixed_analyzer():
    code = r'''
import json
from log_timeline_api.analyzer import Analyzer, parse_time
before = parse_time("2023-10-01T23:59:59Z")
after = parse_time("2023-10-02T00:00:01Z")
assert before < after, (before, after)
logs = [
 {"service":"internal","timestamp":"2023-10-01T23:55:00Z","latency_ms":10},
 {"service":"internal","timestamp":"2023-10-01T23:56:00Z","latency_ms":11},
 {"service":"internal","timestamp":"2023-10-01T23:57:00Z","latency_ms":9},
 {"service":"internal","timestamp":"2023-10-01T23:58:00Z","latency_ms":10},
 {"service":"internal","timestamp":"2023-10-01T23:59:00Z","latency_ms":12},
 {"service":"internal","timestamp":"2023-10-02T00:00:00Z","latency_ms":8},
 {"service":"internal","timestamp":"2023-10-02T00:01:00Z","latency_ms":100},
]
a = Analyzer()
a.ingest(logs)
values = [x["latency_ms"] for x in logs]
mean = sum(values) / len(values)
std = (sum((x-mean)**2 for x in values) / len(values)) ** 0.5
expected = [x for x in logs if x["latency_ms"] > mean + 2*std]
assert a.get_anomalies() == expected, (a.get_anomalies(), expected)
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = REPO
    subprocess.run([sys.executable, "-c", code], cwd=REPO, env=env, check=True, timeout=15)


def check_http_behavior():
    payload = [
        {"service": "A", "timestamp": "2023-10-01T23:55:00Z", "latency_ms": 10},
        {"service": "A", "timestamp": "2023-10-01T23:56:00Z", "latency_ms": 11},
        {"service": "A", "timestamp": "2023-10-01T23:57:00Z", "latency_ms": 9},
        {"service": "A", "timestamp": "2023-10-01T23:58:00Z", "latency_ms": 10},
        {"service": "A", "timestamp": "2023-10-01T23:59:00Z", "latency_ms": 12},
        {"service": "A", "timestamp": "2023-10-02T00:00:00Z", "latency_ms": 8},
        {"service": "A", "timestamp": "2023-10-02T00:01:00Z", "latency_ms": 100},
    ]
    values = [entry["latency_ms"] for entry in payload]
    threshold = statistics.mean(values) + 2 * statistics.pstdev(values)
    expected = [entry for entry in payload if entry["latency_ms"] > threshold]
    assert expected, "Verifier fixture must contain a mathematically valid anomaly"

    status, body = request("/ingest", payload, timeout=5)
    assert status in (200, 201, 202, 204), "Failed to ingest data: %s %s" % (status, body)
    status, body = request("/anomalies", timeout=5)
    assert status == 200, "Failed to get anomalies: %s %s" % (status, body)
    try:
        anomalies = json.loads(body)
    except ValueError as exc:
        raise AssertionError("Response is not valid JSON: " + body) from exc
    assert isinstance(anomalies, list), "Expected anomalies to be a JSON array"
    assert anomalies == expected, "Incorrect anomaly result: expected %r, got %r" % (expected, anomalies)
    timestamps = [x.get("timestamp") for x in anomalies if isinstance(x, dict)]
    assert "2023-10-02T00:01:00Z" in timestamps


def main():
    # Confirm the agent actually left the requested service running.
    wait_for_server()
    pids = listener_pids()
    assert pids, "No process is listening on port 9000"
    cmdlines = []
    for pid in pids:
        try:
            cmdlines.append(open("/proc/%d/cmdline" % pid, "rb").read().replace(b"\0", b" ").decode())
        except OSError:
            pass
    assert any("log_timeline_api.server" in cmd for cmd in cmdlines), cmdlines

    check_bisect_was_performed()
    check_fixed_analyzer()

    regression_test = find_regression_test()
    start_clean_server()
    env = os.environ.copy()
    env["PYTHONPATH"] = REPO + os.pathsep + env.get("PYTHONPATH", "")
    subprocess.run([sys.executable, regression_test], cwd=REPO, env=env, check=True, timeout=30)

    # Use a fresh analyzer state for independently derived HTTP expectations.
    start_clean_server()
    check_http_behavior()
    wait_for_server()


if __name__ == "__main__":
    main()
PY

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
