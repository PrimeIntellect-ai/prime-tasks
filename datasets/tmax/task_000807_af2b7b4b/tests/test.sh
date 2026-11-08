#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import ipaddress
import json
import os
import random
import secrets
import socket
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse

import networkx as nx
import pytest
import requests
from redis import Redis
from rq.job import Job


def load_setting(path, name):
    spec = importlib.util.spec_from_file_location("checked_" + name.lower(), path)
    assert spec is not None and spec.loader is not None, f"Cannot load {path}"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    value = getattr(module, name, None)
    assert isinstance(value, str) and value, f"{name} must be a non-empty string in {path}"
    return value


def redis_endpoint(url):
    parsed = urlparse(url)
    assert parsed.scheme == "redis", f"Expected a redis:// URL, got {url!r}"
    assert parsed.hostname, f"Redis URL has no hostname: {url!r}"
    port = parsed.port or 6379
    path = parsed.path.strip("/")
    db = int(path) if path else 0

    addresses = socket.getaddrinfo(parsed.hostname, port, type=socket.SOCK_STREAM)
    assert addresses, f"Redis hostname does not resolve: {parsed.hostname}"
    assert all(ipaddress.ip_address(item[4][0]).is_loopback for item in addresses), \
        f"Redis must point to the local service, got {parsed.hostname!r}"
    return port, db


def running_command_contains(fragment):
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            command = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except (OSError, PermissionError):
            continue
        if fragment in command:
            return True
    return False


def test_services_integration():
    """Retain the supplied service check, then independently verify the real integration."""
    verify_script = "/app/verify_services.py"
    assert os.path.isfile(verify_script), f"{verify_script} not found."

    result = subprocess.run(
        ["python3", verify_script], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, \
        f"Service verification failed. Output:\n{result.stdout}\n{result.stderr}"

    api_config = "/app/services/api/config.py"
    worker_config = "/app/services/worker/settings.py"
    assert os.path.isfile(api_config), f"{api_config} not found."
    assert os.path.isfile(worker_config), f"{worker_config} not found."

    api_url = load_setting(api_config, "REDIS_URL")
    worker_url = load_setting(worker_config, "BROKER_URL")
    api_endpoint = redis_endpoint(api_url)
    worker_endpoint = redis_endpoint(worker_url)
    assert api_endpoint == worker_endpoint, \
        f"API and worker use different Redis endpoints: {api_url!r} vs {worker_url!r}"

    redis_conn = Redis.from_url(api_url)
    assert redis_conn.ping() is True, "Configured Redis service is not reachable"
    assert running_command_contains("/app/services/api/app.py"), "Flask API process is not running"
    assert running_command_contains("/app/services/worker/worker.py"), "Worker process is not running"

    nonce = secrets.token_hex(8)
    payloads = [
        [{"source": nonce + "-a", "target": nonce + "-b"}],
        [
            {"source": nonce + "-x", "target": nonce + "-y"},
            {"source": nonce + "-y", "target": nonce + "-z"},
            {"source": nonce + "-z", "target": nonce + "-w"},
        ],
    ]

    for payload in payloads:
        response = requests.post(
            "http://localhost:5000/process", json=payload, timeout=5
        )
        assert response.status_code == 202, \
            f"POST /process returned {response.status_code}: {response.text}"
        body = response.json()
        job_id = body.get("job_id")
        assert isinstance(job_id, str) and job_id, f"Invalid job ID response: {body!r}"

        rq_job = Job.fetch(job_id, connection=redis_conn)
        assert rq_job.id == job_id, "Submitted job was not placed in the configured Redis queue"

        final = None
        for _ in range(40):
            status_response = requests.get(
                f"http://localhost:5000/status/{job_id}", timeout=5
            )
            if status_response.status_code == 200:
                final = status_response.json()
                break
            assert status_response.status_code == 202, \
                f"Unexpected job status response: {status_response.status_code} {status_response.text}"
            time.sleep(0.25)

        assert final is not None, f"Job {job_id} did not finish in time"
        assert final.get("status") == "finished", f"Job did not finish successfully: {final!r}"
        assert final.get("result") == {"status": "success", "nodes": len(payload)}, \
            f"Incorrect analytics result for submitted graph: {final!r}"

        rq_job.refresh()
        assert rq_job.is_finished, "Redis queue job is not marked finished"
        assert rq_job.result == {"status": "success", "nodes": len(payload)}, \
            "Worker did not store the expected result in Redis"


def expected_exit(edges):
    graph = nx.Graph()
    graph.add_edges_from((edge["source"], edge["target"]) for edge in edges)
    anomalous = any(
        graph.degree(node) >= 5 and nx.clustering(graph, node) == 0.0
        for node in graph.nodes
    )
    return 1 if anomalous else 0


def run_sanitizer(script, path):
    result = subprocess.run(
        ["python3", script, str(path)], capture_output=True, text=True, timeout=5
    )
    assert result.returncode in (0, 1), \
        f"Sanitizer returned unexpected status {result.returncode} for {path}: {result.stderr.decode(errors='replace')}"
    return result.returncode


def test_sanitizer_adversarial_corpus():
    """Retain classification checks for every provided corpus file."""
    sanitizer_script = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_script), f"{sanitizer_script} is missing."

    evil_dir = "/home/user/corpus/evil"
    clean_dir = "/home/user/corpus/clean"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []
    for path in evil_files:
        if run_sanitizer(sanitizer_script, path) != 1:
            evil_bypassed.append(os.path.basename(path))
    for path in clean_files:
        if run_sanitizer(sanitizer_script, path) != 0:
            clean_modified.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_sanitizer_generated_graphs():
    """Exercise independently generated graphs at paths unrelated to the public corpora."""
    sanitizer_script = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_script), f"{sanitizer_script} is missing."

    cases = []
    cases.append([{"source": "hub", "target": f"leaf-{i}"} for i in range(5)])
    cases.append([{"source": "hub", "target": f"leaf-{i}"} for i in range(4)])

    clustered_hub = [{"source": "hub", "target": f"n-{i}"} for i in range(5)]
    clustered_hub.append({"source": "n-0", "target": "n-1"})
    cases.append(clustered_hub)

    clique = []
    for i in range(7):
        for j in range(i + 1, 7):
            clique.append({"source": f"c-{i}", "target": f"c-{j}"})
    cases.append(clique)

    disconnected = [
        {"source": "p0", "target": "p1"},
        {"source": "p1", "target": "p2"},
    ] + [{"source": "hidden-hub", "target": f"hidden-leaf-{i}"} for i in range(6)]
    cases.append(disconnected)

    rng = random.Random(secrets.randbits(128))
    for case_number in range(30):
        count = rng.randint(6, 15)
        probability = rng.uniform(0.05, 0.75)
        labels = [f"g{case_number}-{secrets.token_hex(3)}-{i}" for i in range(count)]
        edges = []
        for i in range(count):
            for j in range(i + 1, count):
                if rng.random() < probability:
                    edges.append({"source": labels[i], "target": labels[j]})
        rng.shuffle(edges)
        cases.append(edges)

    expectations = [expected_exit(edges) for edges in cases]
    assert 0 in expectations and 1 in expectations, "Generated suite must contain both classes"

    with tempfile.TemporaryDirectory(prefix="graph-check-") as directory:
        for index, (edges, expected) in enumerate(zip(cases, expectations)):
            path = Path(directory) / f"sample-{secrets.token_hex(6)}-{index}.json"
            path.write_text(json.dumps(edges), encoding="utf-8")
            actual = run_sanitizer(sanitizer_script, path)
            assert actual == expected, \
                f"Wrong classification for generated graph {index}: expected {expected}, got {actual}; edges={edges!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
