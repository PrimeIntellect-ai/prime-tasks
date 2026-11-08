#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request

import pytest
import redis

DETECTOR = "/home/user/detector.py"


def run_detector(path):
    try:
        return subprocess.run(
            ["python3", DETECTOR, path],
            capture_output=True,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {path}")


def test_detector_evil_corpus():
    detector_path = "/home/user/detector.py"
    assert os.path.isfile(detector_path), f"Detector script not found at {detector_path}"

    evil_dir = "/verify/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert evil_files, "No JSON files found in evil corpus."

    bypassed = []
    for f in evil_files:
        filepath = os.path.join(evil_dir, f)
        if run_detector(filepath) != 1:
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}")


def test_detector_clean_corpus():
    detector_path = "/home/user/detector.py"
    assert os.path.isfile(detector_path), f"Detector script not found at {detector_path}"

    clean_dir = "/verify/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert clean_files, "No JSON files found in clean corpus."

    modified = []
    for f in clean_files:
        filepath = os.path.join(clean_dir, f)
        if run_detector(filepath) != 0:
            modified.append(f)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified. Offending files: {', '.join(modified)}")


def test_detector_generated_payloads():
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"
    rng = random.SystemRandom()
    payloads = []

    # Exercise both sides of each condition, including the exact threshold.
    for _ in range(18):
        payloads.append({
            "sensor": f"S{rng.randrange(1000000)}",
            "value": 10.0 ** (-rng.uniform(301.0, 320.0)),
            "tz": f"UTC-{rng.randrange(1, 15):02d}",
        })
    for _ in range(18):
        payloads.append({
            "sensor": f"S{rng.randrange(1000000)}",
            "value": 10.0 ** (-rng.uniform(301.0, 320.0)),
            "tz": rng.choice(["UTC", "UTC+00", "UTC+05:30", "GMT-10"]),
        })
    for _ in range(18):
        payloads.append({
            "sensor": f"S{rng.randrange(1000000)}",
            "value": 10.0 ** rng.uniform(-299.0, 3.0),
            "tz": f"UTC-{rng.randrange(1, 15):02d}",
        })
    payloads.extend([
        {"sensor": "boundary", "value": 1e-300, "tz": "UTC-14"},
        {"sensor": "below", "value": math.nextafter(1e-300, 0.0), "tz": "UTC-01"},
        {"sensor": "zero", "value": 0.0, "tz": "UTC-00"},
        {"sensor": "negative", "value": -rng.uniform(0.01, 1000.0), "tz": "UTC-09"},
        {"sensor": "negative-safe-tz", "value": -rng.uniform(0.01, 1000.0), "tz": "UTC+09"},
    ])
    rng.shuffle(payloads)

    with tempfile.TemporaryDirectory(prefix="payload-check-") as directory:
        for payload in payloads:
            filename = f"{rng.randrange(1 << 62):016x}.json"
            path = os.path.join(directory, filename)
            with open(path, "w") as handle:
                json.dump(payload, handle)
            expected = 1 if payload["value"] < 1e-300 and "UTC-" in payload["tz"] else 0
            actual = run_detector(path)
            assert actual == expected, (
                f"Detector returned {actual}, expected {expected}, for generated payload {payload}"
            )


def test_flask_config_updated():
    config_path = "/app/flask_app/config.py"
    assert os.path.isfile(config_path), f"Flask config missing at {config_path}"

    with open(config_path, 'r') as f:
        content = f.read()

    assert re.search(r'REDIS_HOST\s*=\s*["\']127\.0\.0\.1["\']', content), "REDIS_HOST not set to '127.0.0.1' in flask config."
    assert re.search(r'REDIS_PORT\s*=\s*6379', content), "REDIS_PORT not set to 6379 in flask config."


def test_nginx_config_updated():
    config_path = "/app/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config missing at {config_path}"

    with open(config_path, 'r') as f:
        content = f.read()

    assert re.search(r'proxy_pass\s+http://(127\.0\.0\.1|localhost):5000/?\s*;', content), "proxy_pass not updated to point to Flask on port 5000 in nginx config."


def process_info(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            cmd = handle.read().replace(b"\0", b" ").decode(errors="replace")
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            cwd = ""
        return cmd, cwd
    except (OSError, ValueError):
        return "", ""


def kill_matching(predicate):
    own_pid = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == own_pid:
            continue
        pid = int(entry)
        cmd, cwd = process_info(pid)
        if cmd and predicate(cmd, cwd):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def cleanup_services():
    subprocess.run(["nginx", "-s", "stop", "-c", "/app/nginx/nginx.conf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    kill_matching(lambda cmd, cwd: "nginx" in cmd or "gunicorn" in cmd or "redis-server" in cmd or (cwd == "/app/worker_repo" and "worker.py" in cmd))
    time.sleep(0.4)


def port_open(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.25):
            return True
    except OSError:
        return False


def test_started_composition_accepts_and_queues_post():
    assert os.path.isfile("/app/start.sh"), "Missing /app/start.sh"
    cleanup_services()
    proc = None
    try:
        proc = subprocess.Popen(
            ["bash", "/app/start.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + 12
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"/app/start.sh exited prematurely with status {proc.returncode}")
            if all(port_open(port) for port in (6379, 5000, 8080)):
                break
            time.sleep(0.2)
        else:
            pytest.fail("Services did not listen on Redis 6379, Flask 5000, and Nginx 8080")

        # Stop the consumer so the assertion can observe the item Flask enqueues.
        kill_matching(lambda cmd, cwd: cwd == "/app/worker_repo" and "worker.py" in cmd)
        time.sleep(0.3)

        queue = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2)
        assert queue.ping(), "Redis did not respond"
        queue.flushdb()

        payload = {"sensor": "A", "value": 1.0, "tz": "UTC"}
        request = urllib.request.Request(
            "http://127.0.0.1:8080/submit",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            body = response.read()
            assert response.status == 200, f"POST returned HTTP {response.status}: {body!r}"

        queued = queue.brpop("queue", timeout=3)
        assert queued is not None, "POST returned successfully but no job was queued in Redis"
        queued_payload = json.loads(queued[1])
        assert queued_payload == payload, f"Queued payload differs from submitted payload: {queued_payload!r}"
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        cleanup_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
