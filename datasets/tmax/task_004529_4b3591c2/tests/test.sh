#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import psycopg2
import pytest
import redis
from dotenv import dotenv_values


def get_health(expect_success=True):
    req = urllib.request.Request("http://localhost:8080/api/health")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode("utf-8")
            if expect_success:
                assert response.status == 200, f"Expected HTTP status 200, got {response.status}"
                try:
                    data = json.loads(body)
                except json.JSONDecodeError:
                    pytest.fail(f"Expected JSON response, got: {body}")
                assert data.get("status") == "healthy", f"Expected {{'status': 'healthy'}}, got {data}"
            return response.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        if expect_success:
            pytest.fail(f"Health endpoint returned HTTP {e.code}: {body}")
        return e.code, body
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to health endpoint: {e}. Check nginx.conf and backend/.env configuration.")


def test_service_topology_health():
    """Verify the requested configuration and the original end-to-end health behavior."""
    env_path = "/app/backend/.env"
    assert os.path.isfile(env_path), f"Missing {env_path}"
    env = dotenv_values(env_path)
    assert env.get("DB_USER") == "backup_user"
    assert env.get("DB_PASS") == "secret"
    assert env.get("DB_NAME") == "backups"
    assert env.get("REDIS_HOST") == "127.0.0.1"
    assert env.get("REDIS_PORT") == "6379"
    assert env.get("DB_HOST") in ("localhost", "127.0.0.1")

    nginx_conf = "/app/nginx.conf"
    assert os.path.isfile(nginx_conf), f"Missing {nginx_conf}"
    checked = subprocess.run(
        ["nginx", "-T", "-c", nginx_conf],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, f"Invalid nginx configuration:\n{checked.stdout}"
    effective = re.sub(r"#.*", "", checked.stdout)
    location = re.search(r"location\s+/api/\s*\{([^}]*)\}", effective, re.S)
    assert location, "nginx.conf must contain a location /api/ block"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8000/\s*;", location.group(1)), \
        "location /api/ must proxy to http://127.0.0.1:8000/"

    conn = psycopg2.connect(
        host=env.get("DB_HOST"), user=env.get("DB_USER"), password=env.get("DB_PASS"),
        dbname=env.get("DB_NAME"), connect_timeout=5,
    )
    conn.close()
    queue = redis.Redis(host=env.get("REDIS_HOST"), port=int(env.get("REDIS_PORT")), socket_timeout=5)
    assert queue.ping() is True

    # Preserve the original end-to-end assertion.
    get_health(expect_success=True)

    # Ensure this is the supplied dependency-checking health endpoint, rather than
    # an unconditional fabricated response.
    try:
        subprocess.run(["service", "redis-server", "stop"], check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1)
        status, _ = get_health(expect_success=False)
        assert status == 500, "Health endpoint remained healthy while Redis was unavailable"
    finally:
        subprocess.run(["service", "redis-server", "start"], check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1)

    try:
        subprocess.run(["service", "postgresql", "stop"], check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1)
        status, _ = get_health(expect_success=False)
        assert status == 500, "Health endpoint remained healthy while PostgreSQL was unavailable"
    finally:
        subprocess.run(["service", "postgresql", "start"], check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1)

    get_health(expect_success=True)


def run_sanitizer(path, payload, exact=False):
    try:
        result = subprocess.run(
            [path], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out for payload {payload!r}")
    assert result.returncode == 0, f"Sanitizer exited {result.returncode}; stderr={result.stderr!r}"
    if exact:
        assert result.stdout in (b"ACCEPT\n", b"REJECT\n"), \
            f"Output must be exactly ACCEPT\\n or REJECT\\n, got {result.stdout!r}"
    return result.stdout


def oracle(payload):
    try:
        text = payload.decode("utf-8")
        def reject_constant(value):
            raise ValueError(value)
        pairs = json.loads(text, object_pairs_hook=lambda p: p, parse_constant=reject_constant)
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError):
        return False

    if not isinstance(pairs, list) or len(pairs) != 3:
        return False
    if any(not isinstance(item, tuple) or len(item) != 2 for item in pairs):
        return False
    keys = [key for key, _ in pairs]
    if len(set(keys)) != 3 or set(keys) != {"backup_id", "query", "deps"}:
        return False
    obj = dict(pairs)
    if isinstance(obj["backup_id"], bool) or not isinstance(obj["backup_id"], int):
        return False
    if not isinstance(obj["query"], str) or "'" in obj["query"]:
        return False
    if not isinstance(obj["deps"], list):
        return False

    edges = []
    for edge in obj["deps"]:
        if not isinstance(edge, list) or len(edge) != 2:
            return False
        if any(isinstance(node, bool) or not isinstance(node, int) for node in edge):
            return False
        edges.append((edge[0], edge[1]))

    graph = {}
    nodes = set()
    for source, target in edges:
        graph.setdefault(source, []).append(target)
        nodes.add(source)
        nodes.add(target)
    state = {}
    def visit(node):
        if state.get(node) == 1:
            return False
        if state.get(node) == 2:
            return True
        state[node] = 1
        for target in graph.get(node, []):
            if not visit(target):
                return False
        state[node] = 2
        return True
    return all(visit(node) for node in nodes if state.get(node, 0) == 0)


def hidden_payloads():
    rng = random.SystemRandom()
    cases = [
        b"", b"null", b"[]", b"{}", b"not json",
        b'{"backup_id":1,"query":"SELECT ?","deps":[]} trailing',
        b'{"backup_id":true,"query":"SELECT ?","deps":[]}',
        b'{"backup_id":"1","query":"SELECT ?","deps":[]}',
        b'{"backup_id":1,"query":7,"deps":[]}',
        b'{"backup_id":1,"query":"SELECT \'x\'","deps":[]}',
        b'{"backup_id":1,"query":"SELECT ?","deps":{},"extra":0}',
        b'{"backup_id":1,"query":"SELECT ?","deps":[[1]]}',
        b'{"backup_id":1,"query":"SELECT ?","deps":[[1,2,3]]}',
        b'{"backup_id":1,"query":"SELECT ?","deps":[[1,"2"]]}',
        b'{"backup_id":1,"query":"SELECT ?","deps":[[9,9]]}',
        b'{"backup_id":1,"backup_id":2,"query":"SELECT ?","deps":[]}',
    ]

    for _ in range(20):
        count = rng.randint(1, 10)
        nodes = rng.sample(range(-50000, 50001), count)
        order = nodes[:]
        rng.shuffle(order)
        edges = []
        for i in range(count):
            for j in range(i + 1, count):
                if rng.random() < 0.22:
                    edges.append([order[i], order[j]])
        payload = {
            "backup_id": rng.randint(-1000000, 1000000),
            "query": f"SELECT col FROM table_{rng.randint(100, 9999)} WHERE id = $1",
            "deps": edges,
        }
        items = list(payload.items())
        rng.shuffle(items)
        cases.append(json.dumps(dict(items), separators=(",", ":")).encode())

        bad = dict(payload)
        mutation = rng.randrange(5)
        if mutation == 0:
            bad["query"] += " OR name = 'root'"
        elif mutation == 1:
            node = nodes[0]
            bad["deps"] = list(edges) + [[node, node]]
        elif mutation == 2:
            a, b = rng.sample(nodes, 2) if len(nodes) > 1 else (nodes[0], nodes[0] + 1)
            bad["deps"] = list(edges) + [[a, b], [b, a]]
        elif mutation == 3:
            bad["unexpected"] = rng.randint(1, 1000)
        else:
            bad["deps"] = list(edges) + [[nodes[0], False]]
        cases.append(json.dumps(bad, separators=(",", ":")).encode())
    return cases


def test_sanitizer_adversarial_corpus():
    """Preserve the visible corpus assertions and exercise fresh hidden cases."""
    sanitizer_bin = "/home/user/sanitizer"
    sanitizer_src = "/home/user/sanitizer.c"
    assert os.path.isfile(sanitizer_bin), f"Sanitizer binary not found at {sanitizer_bin}. Did you compile it?"
    assert os.access(sanitizer_bin, os.X_OK), f"Sanitizer binary at {sanitizer_bin} is not executable."
    assert stat.S_ISREG(os.lstat(sanitizer_bin).st_mode), "Sanitizer must be a regular compiled file"
    with open(sanitizer_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled native executable"
    assert os.path.isfile(sanitizer_src), f"C source not found at {sanitizer_src}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    clean_files = sorted(os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json"))
    evil_files = sorted(os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json"))

    clean_modified = []
    evil_bypassed = []
    for cf in clean_files:
        with open(cf, "rb") as f:
            result = subprocess.run([sanitizer_bin], stdin=f, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0 or result.stdout.decode("utf-8").strip() != "ACCEPT":
            clean_modified.append(os.path.basename(cf))
    for ef in evil_files:
        with open(ef, "rb") as f:
            result = subprocess.run([sanitizer_bin], stdin=f, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0 or result.stdout.decode("utf-8").strip() != "REJECT":
            evil_bypassed.append(os.path.basename(ef))
    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    rebuilt = tempfile.mktemp(prefix="sanitizer-rebuilt-")
    compile_result = subprocess.run([
        "gcc", sanitizer_src, "/home/user/cJSON/cJSON.c", "-o", rebuilt, "-I/home/user/cJSON"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert compile_result.returncode == 0, f"sanitizer.c does not compile:\n{compile_result.stderr}"

    try:
        for payload in hidden_payloads():
            expected = b"ACCEPT\n" if oracle(payload) else b"REJECT\n"
            for executable in (sanitizer_bin, rebuilt):
                actual = run_sanitizer(executable, payload, exact=True)
                assert actual == expected, \
                    f"Wrong result for {payload!r}: expected {expected!r}, got {actual!r}"
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
