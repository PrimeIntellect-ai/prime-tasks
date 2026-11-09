#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import random
import signal
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

NGINX_URL = "http://127.0.0.1:8080/analyze"
RNG = random.SystemRandom()


def expected_status(sequence):
    n = len(sequence) // 20
    if n < 2:
        return "clean"
    ys = []
    for i in range(n):
        window = sequence[i * 20:(i + 1) * 20]
        ys.append(sum(base in "GC" for base in window) / 20.0)
    xs = list(range(n))
    xbar = sum(xs) / n
    ybar = sum(ys) / n
    sxx = sum((x - xbar) ** 2 for x in xs)
    slope = sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / sxx
    intercept = ybar - slope * xbar
    ss_tot = sum((y - ybar) ** 2 for y in ys)
    if ss_tot == 0:
        r_squared = 0.0
    else:
        ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
        r_squared = 1.0 - ss_res / ss_tot
    return "evil" if r_squared >= 0.60 else "clean"


def send_request(sequence, url=NGINX_URL, timeout=8):
    data = json.dumps({"sequence": sequence}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "Connection": "close"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200
        body = json.loads(response.read().decode("utf-8"))
    assert isinstance(body, dict) and isinstance(body.get("status"), str)
    return body["status"]


def make_sequence(gc_counts, remainder=0):
    chunks = []
    for count in gc_counts:
        chars = [RNG.choice("GC") for _ in range(count)]
        chars += [RNG.choice("AT") for _ in range(20 - count)]
        RNG.shuffle(chars)
        chunks.append("".join(chars))
    if remainder:
        chunks.append("".join(RNG.choice("ACGT") for _ in range(remainder)))
    return "".join(chunks)


def build_dynamic_cases():
    cases = []
    seen = set()
    wanted = {"clean": 28, "evil": 28}
    while wanted["clean"] or wanted["evil"]:
        windows = RNG.randint(3, 16)
        if wanted["evil"] and RNG.random() < 0.55:
            start = RNG.randint(1, 5)
            end = RNG.randint(15, 19)
            counts = [round(start + (end - start) * i / (windows - 1)) for i in range(windows)]
            counts = [max(0, min(20, c + RNG.choice([-1, 0, 0, 0, 1]))) for c in counts]
            if RNG.random() < 0.5:
                counts.reverse()
        else:
            counts = [RNG.randint(5, 15) for _ in range(windows)]
        sequence = make_sequence(counts, RNG.randint(0, 19))
        label = expected_status(sequence)
        if wanted[label] and sequence not in seen:
            seen.add(sequence)
            cases.append((sequence, label))
            wanted[label] -= 1
    RNG.shuffle(cases)
    return cases


DYNAMIC_CASES = build_dynamic_cases()


def test_1_adversarial_corpus():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, "No files found in evil corpus"
    assert clean_files, "No files found in clean corpus"

    evil_bypassed = []
    clean_modified = []
    for filename in evil_files:
        with open(os.path.join(evil_dir, filename), "r") as f:
            sequence = f.read().strip()
        if send_request(sequence) != "evil":
            evil_bypassed.append(filename)
    for filename in clean_files:
        with open(os.path.join(clean_dir, filename), "r") as f:
            sequence = f.read().strip()
        if send_request(sequence) != "clean":
            clean_modified.append(filename)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified. Offending files: {', '.join(clean_modified)}")
    assert not errors, "\n".join(errors)


def test_2_generated_regression_and_concurrency():
    # Inputs are generated at verification time, and expected answers are derived
    # independently from the regression specification.
    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as pool:
        futures = {pool.submit(send_request, sequence): (sequence, expected)
                   for sequence, expected in DYNAMIC_CASES}
        for future in concurrent.futures.as_completed(futures):
            sequence, expected = futures[future]
            assert future.result() == expected, f"Incorrect classification for generated sequence {sequence}"


def redis_cli(*args):
    return subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "--raw", *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).stdout.rstrip("\n")


def test_3_redis_cache_is_populated():
    # Use a fresh unpredictable key so a preloaded corpus or hardcoded lookup cannot pass.
    sequence = make_sequence([2, 4, 6, 8, 10, 12, 14, 16, 18], RNG.randint(1, 19))
    expected = expected_status(sequence)
    redis_cli("DEL", sequence)
    assert redis_cli("EXISTS", sequence) == "0"
    assert send_request(sequence) == expected
    cached = None
    for _ in range(20):
        cached = redis_cli("GET", sequence)
        if cached == expected:
            break
        time.sleep(0.05)
    assert cached == expected, "Worker did not cache the result in Redis under the sequence key"


def test_4_all_three_workers_serve_analysis():
    sample = DYNAMIC_CASES[:8]
    for port in (8081, 8082, 8083):
        url = f"http://127.0.0.1:{port}/analyze"
        for sequence, expected in sample:
            assert send_request(sequence, url=url) == expected, f"Worker on port {port} failed"


def listener_pids(ports):
    wanted_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    port = int(fields[1].split(":")[1], 16)
                    state = fields[3]
                    if port in ports and state == "0A":
                        wanted_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    found = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted_inodes:
                    found.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return found


def test_9_nginx_reaches_every_upstream_worker():
    # Replace the already-validated workers with port-identifying probes. This
    # makes Nginx's actual upstream choices observable rather than trusting text
    # in nginx.conf or indistinguishable worker responses.
    ports = (8081, 8082, 8083)
    pids = listener_pids(set(ports))
    assert len(pids) >= 3, "Expected a listening worker on each of the three ports"
    for pid in pids:
        os.kill(pid, signal.SIGKILL)

    deadline = time.time() + 5
    while listener_pids(set(ports)) and time.time() < deadline:
        time.sleep(0.05)

    token = os.urandom(12).hex()
    servers = []
    threads = []

    def handler_for(port):
        class ProbeHandler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                body = json.dumps({"status": f"probe-{port}-{token}"}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                pass
        return ProbeHandler

    try:
        for port in ports:
            server = ThreadingHTTPServer(("127.0.0.1", port), handler_for(port))
            servers.append(server)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            threads.append(thread)

        seen = set()
        for _ in range(36):
            probe_sequence = "".join(RNG.choice("ACGT") for _ in range(137))
            status = send_request(probe_sequence)
            for port in ports:
                if status == f"probe-{port}-{token}":
                    seen.add(port)
            if seen == set(ports):
                break
        assert seen == set(ports), f"Nginx did not load-balance requests across all three workers; reached {sorted(seen)}"
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
