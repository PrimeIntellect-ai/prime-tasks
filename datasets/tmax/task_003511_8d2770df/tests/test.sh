#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from collections import deque

import pytest

EXECUTABLE = "/home/user/backup_sanitizer"
SOURCE = "/home/user/backup_sanitizer.cpp"
CONFIG = "/app/nginx/nginx.conf"
START_SCRIPT = "/app/start_services.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_cli(executable, path):
    try:
        return subprocess.run([executable, path], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=5).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out on {path}")


@pytest.fixture(scope="session")
def rebuilt_executable(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"Required C++ source {SOURCE} does not exist"
    out = str(tmp_path_factory.mktemp("build") / "backup_sanitizer_rebuilt")
    command = [
        "g++", "-std=c++17", "-O2", SOURCE, "-o", out,
        "-I/usr/include/jsoncpp", "-ljsoncpp", "-lhiredis", "-lpq", "-pthread"
    ]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
    assert result.returncode == 0, f"C++ source does not compile:\n{result.stderr}"
    return out


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."


def test_adversarial_corpus():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    clean_failed = [os.path.basename(f) for f in clean_files if run_cli(EXECUTABLE, f) != 0]
    evil_failed = [os.path.basename(f) for f in evil_files if run_cli(EXECUTABLE, f) != 1]
    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}")
    assert not errors, " | ".join(errors)


def graph_is_valid(doc):
    nodes = {n["id"]: n for n in doc["nodes"]}
    backups = [n for n in doc["nodes"] if n.get("type") == "backup"]
    derived = {node_id: [] for node_id in nodes}

    for edge in doc["edges"]:
        if edge.get("type") == "derived_from":
            derived.setdefault(edge["source"], []).append(edge["target"])
        if edge.get("type") == "stored_in":
            source = nodes.get(edge["source"], {})
            target = nodes.get(edge["target"], {})
            if source.get("type") == "backup" and target.get("status") == "compromised":
                return False

    color = {}
    def visit(node_id):
        if color.get(node_id) == 1:
            return False
        if color.get(node_id) == 2:
            return True
        color[node_id] = 1
        for target in derived.get(node_id, []):
            if not visit(target):
                return False
        color[node_id] = 2
        return True

    if any(not visit(node_id) for node_id in list(derived)):
        return False

    for backup in backups:
        if backup.get("backup_type") != "incremental":
            continue
        queue = deque([(backup["id"], 0)])
        seen = {backup["id"]}
        distance = None
        while queue:
            node_id, hops = queue.popleft()
            if hops > 0 and nodes.get(node_id, {}).get("type") == "backup" and nodes[node_id].get("backup_type") == "full":
                distance = hops
                break
            for target in derived.get(node_id, []):
                if target not in seen:
                    seen.add(target)
                    queue.append((target, hops + 1))
        if distance is None or distance > 3:
            return False

    ordered = sorted(backups, key=lambda n: n["timestamp"])
    for i in range(len(ordered) - 2):
        if sum(int(n["bytes"]) for n in ordered[i:i + 3]) > 500000000000:
            return False
    return True


def make_cases():
    rng = random.SystemRandom()
    prefix = secrets.token_hex(6)
    cases = []

    def chain(depth, compromised=False):
        nodes = [{"id": f"{prefix}_full_{secrets.token_hex(3)}", "type": "backup",
                  "backup_type": "full", "timestamp": rng.randint(1, 50), "bytes": rng.randint(1, 1000000)}]
        edges = []
        previous = nodes[0]["id"]
        for index in range(depth):
            current = f"{prefix}_inc_{index}_{secrets.token_hex(3)}"
            nodes.append({"id": current, "type": "backup", "backup_type": "incremental",
                          "timestamp": 100 + index, "bytes": rng.randint(1, 1000000)})
            edges.append({"source": current, "target": previous, "type": "derived_from"})
            previous = current
        zone = f"{prefix}_zone_{secrets.token_hex(3)}"
        nodes.append({"id": zone, "type": "zone", "status": "compromised" if compromised else "ok"})
        edges.append({"source": nodes[0]["id"], "target": zone, "type": "stored_in"})
        return {"nodes": nodes, "edges": edges}

    cases.extend([chain(1), chain(2), chain(3), chain(4), chain(rng.randint(1, 3), True)])

    a, b = (f"{prefix}_cycle_{secrets.token_hex(3)}" for _ in range(2))
    cases.append({"nodes": [
        {"id": a, "type": "backup", "backup_type": "incremental", "timestamp": 2, "bytes": 10},
        {"id": b, "type": "backup", "backup_type": "incremental", "timestamp": 1, "bytes": 10}],
        "edges": [{"source": a, "target": b, "type": "derived_from"},
                  {"source": b, "target": a, "type": "derived_from"}]})

    lone = f"{prefix}_orphan_{secrets.token_hex(3)}"
    cases.append({"nodes": [{"id": lone, "type": "backup", "backup_type": "incremental",
                              "timestamp": 1, "bytes": 1}], "edges": []})

    for total, expected_over in [(500000000000, False), (500000000001, True)]:
        first = rng.randint(100000000000, 200000000000)
        second = rng.randint(100000000000, 200000000000)
        third = total - first - second
        values = [(30, third), (10, first), (20, second)]
        rng.shuffle(values)
        nodes = [{"id": f"{prefix}_agg_{secrets.token_hex(3)}", "type": "backup",
                  "backup_type": "full", "timestamp": ts, "bytes": size} for ts, size in values]
        cases.append({"nodes": nodes, "edges": []})

    for _ in range(6):
        cases.append(chain(rng.randint(1, 4), rng.choice([False, False, True])))
    return cases


def test_generated_graphs_at_unlabeled_paths(rebuilt_executable, tmp_path):
    cases = make_cases()
    expected = []
    paths = []
    for doc in cases:
        answer = 0 if graph_is_valid(doc) else 1
        expected.append(answer)
        path = tmp_path / f"{secrets.token_hex(12)}.dat"
        path.write_text(json.dumps(doc))
        paths.append(str(path))

    assert 0 in expected and 1 in expected
    for executable in (EXECUTABLE, rebuilt_executable):
        failures = []
        for path, answer in zip(paths, expected):
            actual = run_cli(executable, path)
            if actual != answer:
                failures.append(f"{os.path.basename(path)} expected {answer}, got {actual}")
        assert not failures, f"{executable} failed generated tests: " + "; ".join(failures)


def wait_port(port, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    pytest.fail(f"Port {port} did not become available")


def redis(*args):
    result = subprocess.run(["redis-cli", "--raw", *args], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def post(url, doc):
    request = urllib.request.Request(url, data=json.dumps(doc).encode(), method="POST",
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def test_services_nginx_http_and_redis():
    assert os.path.isfile(CONFIG), "Nginx configuration is missing"
    assert os.path.isfile(START_SCRIPT) and os.access(START_SCRIPT, os.X_OK), "Startup script is missing or not executable"
    config_text = open(CONFIG).read()
    assert re.search(r"location\s+(?:=\s*)?/register\b", config_text), "Nginx lacks a /register location"
    assert re.search(r"(?:proxy_pass\s+http://|fastcgi_pass\s+)(?:127\.0\.0\.1|localhost):9000\b", config_text), \
        "/register is not configured for the service on port 9000"

    syntax = subprocess.run(["nginx", "-t", "-c", CONFIG], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert syntax.returncode == 0, syntax.stderr

    subprocess.run(["nginx", "-s", "stop", "-c", CONFIG], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=5)
    started = subprocess.run([START_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, timeout=20)
    assert started.returncode == 0, f"start_services.sh failed:\n{started.stdout}\n{started.stderr}"

    for port in (5432, 6379, 9000, 8080):
        wait_port(port)
    assert redis("PING") == ["PONG"]
    redis("DEL", "valid_backups")

    direct_id = "direct_" + secrets.token_hex(8)
    proxy_id = "proxy_" + secrets.token_hex(8)
    evil_id = "evil_" + secrets.token_hex(8)
    clean_direct = {"nodes": [{"id": direct_id, "type": "backup", "backup_type": "full",
                                "timestamp": 1, "bytes": 123}], "edges": []}
    clean_proxy = {"nodes": [{"id": proxy_id, "type": "backup", "backup_type": "full",
                               "timestamp": 2, "bytes": 456}], "edges": []}
    evil = {"nodes": [
        {"id": evil_id, "type": "backup", "backup_type": "full", "timestamp": 1, "bytes": 1},
        {"id": "zone_" + secrets.token_hex(5), "type": "zone", "status": "compromised"}],
        "edges": []}
    evil["edges"].append({"source": evil_id, "target": evil["nodes"][1]["id"], "type": "stored_in"})

    direct_status, _ = post("http://127.0.0.1:9000/register", clean_direct)
    proxy_status, _ = post("http://127.0.0.1:8080/register", clean_proxy)
    post("http://127.0.0.1:9000/register", evil)
    assert 200 <= direct_status < 300, f"Direct service rejected a valid graph with HTTP {direct_status}"
    assert 200 <= proxy_status < 300, f"Nginx /register failed with HTTP {proxy_status}"

    deadline = time.time() + 5
    entries = []
    while time.time() < deadline:
        entries = redis("LRANGE", "valid_backups", "0", "-1")
        if direct_id in entries and proxy_id in entries:
            break
        time.sleep(0.2)
    assert direct_id in entries, "Directly accepted backup ID was not logged to Redis valid_backups"
    assert proxy_id in entries, "Backup accepted through Nginx was not logged to Redis valid_backups"
    assert evil_id not in entries, "Rejected backup ID was logged as valid"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
