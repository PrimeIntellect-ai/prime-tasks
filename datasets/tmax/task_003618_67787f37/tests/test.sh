#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import re
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.request

import numpy as np
import pytest


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(os.path.join(procdir, "fd")):
                try:
                    target = os.readlink(os.path.join(procdir, "fd", fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(os.path.basename(procdir)))
                    break
        except OSError:
            pass
    return pids


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def wait_for_port(port, present=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if bool(listener_pids(port)) == present:
            return
        time.sleep(0.05)
    state = "open" if present else "closed"
    raise AssertionError(f"Port {port} did not become {state}")


def request(url, timeout=2):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode(errors="replace")


def test_multi_service_end_to_end():
    # Clear the redis list first to ensure a clean slate
    subprocess.run(["redis-cli", "DEL", "latency_metrics"], capture_output=True)

    # Send 10 requests to the load balancer
    success_count = 0
    for _ in range(10):
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/ping")
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status == 200:
                    success_count += 1
        except Exception:
            pass
        time.sleep(0.1)

    assert success_count == 10, f"Expected 10 successful requests to Nginx, got {success_count}"

    # Check redis list length
    result = subprocess.run(["redis-cli", "LLEN", "latency_metrics"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to execute redis-cli"

    llen = int(result.stdout.strip())
    assert llen >= 10, f"Expected at least 10 items in 'latency_metrics' Redis list, found {llen}"


def test_effective_nginx_and_backend_processes():
    nginx_pids = listener_pids(8080)
    assert nginx_pids, "Nothing is listening on port 8080"
    assert any("nginx" in cmdline(pid) for pid in nginx_pids), "Port 8080 is not served by Nginx"

    for port in (5001, 5002):
        pids = listener_pids(port)
        assert pids, f"No backend is listening on port {port}"
        assert any("/home/user/app/api.py" in cmdline(pid) and str(port) in cmdline(pid) for pid in pids), \
            f"Port {port} is not served by the submitted Flask API"

    checked = subprocess.run(
        ["nginx", "-T", "-c", "/home/user/app/nginx.conf"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert checked.returncode == 0, f"Submitted Nginx configuration is invalid: {checked.stderr}"
    effective = checked.stdout + "\n" + checked.stderr
    effective = "\n".join(line.split("#", 1)[0] for line in effective.splitlines())
    assert re.search(r"\blisten\s+[^;\n]*\b8080\b[^;\n]*;", effective), "Nginx does not listen on port 8080"

    upstreams = {}
    for name, body in re.findall(r"\bupstream\s+([^\s{]+)\s*\{([^}]*)\}", effective, re.S):
        declarations = re.findall(r"\bserver\s+([^;]+);", body)
        endpoints = [declaration.split()[0] for declaration in declarations]
        upstreams[name] = (endpoints, declarations)

    proxy_targets = re.findall(r"\bproxy_pass\s+http://([^/;\s]+)", effective)
    valid = []
    for target in proxy_targets:
        if target not in upstreams:
            continue
        endpoints, declarations = upstreams[target]
        if sorted(endpoints) == ["127.0.0.1:5001", "127.0.0.1:5002"]:
            assert not any(re.search(r"\b(weight|backup|down)\b", item) for item in declarations), \
                "The two backends must use ordinary round-robin balancing"
            valid.append(target)
    assert valid, "proxy_pass does not use an upstream containing exactly ports 5001 and 5002"


def test_submitted_api_records_a_float_in_local_redis():
    assert not listener_pids(5099), "Unexpected process already listening on verifier port 5099"
    subprocess.run(["redis-cli", "DEL", "latency_metrics"], capture_output=True)
    proc = subprocess.Popen(
        ["python3", "/home/user/app/api.py", "5099"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_port(5099)
        status, body = request("http://127.0.0.1:5099/ping")
        assert status == 200 and "pong" in body.lower(), "Submitted API's /ping endpoint did not return pong"
        result = subprocess.run(
            ["redis-cli", "LRANGE", "latency_metrics", "0", "-1"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        assert result.returncode == 0, "Failed to read latency_metrics from Redis"
        values = [line for line in result.stdout.splitlines() if line.strip()]
        assert values, "The submitted API did not push a latency to latency_metrics"
        parsed = [float(value) for value in values]
        assert all(math.isfinite(value) and value >= 0 for value in parsed), "Redis latency entries must be nonnegative floats"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_nginx_routes_to_both_backends():
    # Replace the two otherwise indistinguishable Flask responses with temporary
    # labeled HTTP backends, while retaining the submitted, running Nginx config.
    old_pids = listener_pids(5001) | listener_pids(5002)
    for pid in old_pids:
        os.kill(pid, signal.SIGTERM)
    wait_for_port(5001, present=False)
    wait_for_port(5002, present=False)

    server_code = r'''
import http.server, sys
port, label = int(sys.argv[1]), sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/ping':
            self.send_error(404); return
        body = label.encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass
http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
'''
    servers = [
        subprocess.Popen(["python3", "-c", server_code, "5001", "backend-5001"]),
        subprocess.Popen(["python3", "-c", server_code, "5002", "backend-5002"]),
    ]
    try:
        wait_for_port(5001)
        wait_for_port(5002)
        bodies = []
        for _ in range(20):
            status, body = request("http://127.0.0.1:8080/ping")
            assert status == 200
            bodies.append(body)
        assert set(bodies) == {"backend-5001", "backend-5002"}, \
            f"Nginx did not route requests to both configured backends: {bodies}"
        assert bodies.count("backend-5001") >= 3 and bodies.count("backend-5002") >= 3, \
            f"Requests were not reasonably balanced between the two backends: {bodies}"
    finally:
        for proc in servers:
            proc.terminate()
        for proc in servers:
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def run_classifier(script_path, path):
    try:
        return subprocess.run(
            ["python3", script_path, path],
            capture_output=True,
            timeout=2,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_adversarial_corpus_classifier():
    script_path = "/home/user/profile_classifier.py"
    assert os.path.isfile(script_path), f"Classifier script {script_path} does not exist"

    clean_dir = "/home/user/data/clean"
    evil_dir = "/home/user/data/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    failed_clean = []
    for cf in clean_files:
        if run_classifier(script_path, cf) != 0:
            failed_clean.append(os.path.basename(cf))

    failed_evil = []
    for ef in evil_files:
        if run_classifier(script_path, ef) != 1:
            failed_evil.append(os.path.basename(ef))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified (expected exit 0, got otherwise): {', '.join(failed_clean[:5])}...")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed (expected exit 1, got otherwise): {', '.join(failed_evil[:5])}...")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

    # Re-test randomly selected supplied profiles under neutral, unpredictable names,
    # then add freshly generated profiles whose labels are derived here.
    cases = []
    chooser = secrets.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="profiles_") as tempdir:
        for source, expected in (
            *[(p, 0) for p in chooser.sample(clean_files, min(12, len(clean_files)))],
            *[(p, 1) for p in chooser.sample(evil_files, min(12, len(evil_files)))],
        ):
            destination = os.path.join(tempdir, secrets.token_hex(12) + ".json")
            with open(source, "rb") as src, open(destination, "wb") as dst:
                dst.write(src.read())
            cases.append((destination, expected))

        for _ in range(10):
            rng = np.random.default_rng(secrets.randbits(128))
            clean = rng.exponential(scale=0.05, size=1000).tolist()
            evil = np.concatenate([
                rng.exponential(scale=0.05, size=900),
                rng.normal(loc=0.5, scale=0.1, size=100),
            ])
            rng.shuffle(evil)
            for values, expected in ((clean, 0), (evil.tolist(), 1)):
                destination = os.path.join(tempdir, secrets.token_hex(12) + ".json")
                with open(destination, "w") as f:
                    json.dump(values, f)
                cases.append((destination, expected))

        chooser.shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_classifier(script_path, path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Classifier failed neutral-path or fresh profiles: {failures[:5]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
