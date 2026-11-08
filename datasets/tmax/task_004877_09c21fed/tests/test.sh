#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import itertools
import json
import math
import os
import random
import subprocess
import threading
import time
import urllib.request
from urllib.parse import urlparse

import pytest
import redis
from celery import Celery


def expected_distance(seq1, seq2):
    kmers = [''.join(p) for p in itertools.product('ACGT', repeat=3)]

    def distribution(seq):
        counts = {k: 1 for k in kmers}
        for i in range(len(seq) - 2):
            counts[seq[i:i + 3]] += 1
        total = sum(counts.values())
        return [counts[k] / total for k in kmers]

    d1 = distribution(seq1)
    d2 = distribution(seq2)
    value = math.sqrt(sum((a - b) ** 2 for a, b in zip(d1, d2)))
    return float(f"{value:.6f}")


def post_analyze(seq1, seq2, timeout=20):
    payload = json.dumps({"seq1": seq1, "seq2": seq2}).encode('utf-8')
    req = urllib.request.Request(
        "http://127.0.0.1:8000/analyze",
        data=payload,
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        return json.loads(response.read().decode('utf-8'))


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_redis_url(value, label):
    assert value, f"{label} is not configured"
    parsed = urlparse(str(value))
    assert parsed.scheme == 'redis', f"{label} must use Redis, got {value}"
    assert parsed.hostname in {'redis', 'localhost', '127.0.0.1'}, \
        f"{label} has the wrong Redis host: {value}"
    assert parsed.port == 6379, f"{label} must use Redis port 6379: {value}"


def test_fuzz_equivalence_kmer_dist():
    oracle_path = "/app/legacy_kmer_dist"
    agent_path = "/home/user/kmer_dist.py"

    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"
    assert os.path.exists(oracle_path), f"Oracle script missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent path is not a regular script: {agent_path}"
    with open(agent_path, 'rb') as agent_file, open(oracle_path, 'rb') as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent script must not be a byte-for-byte copy of the legacy implementation"

    random.seed(42)
    chars = ['A', 'C', 'G', 'T']

    for i in range(100):
        len1 = random.randint(10, 100)
        len2 = random.randint(10, 100)
        seq1 = "".join(random.choices(chars, k=len1))
        seq2 = "".join(random.choices(chars, k=len2))

        try:
            oracle_proc = subprocess.run(
                [oracle_path, seq1, seq2],
                capture_output=True, text=True, check=True
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on inputs {seq1}, {seq2}: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                ["python3", agent_path, seq1, seq2],
                capture_output=True, text=True, check=True
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on inputs {seq1}, {seq2}: {e.stderr}")

        assert agent_out == oracle_out, f"Mismatch on inputs:\nSeq1: {seq1}\nSeq2: {seq2}\nOracle: {oracle_out}\nAgent: {agent_out}"


def test_service_files_and_celery_configuration():
    gateway_path = "/app/services/gateway/app.py"
    worker_path = "/app/services/worker/tasks.py"
    assert os.path.isfile(gateway_path), f"Gateway missing at {gateway_path}"
    assert os.path.isfile(worker_path), f"Worker tasks missing at {worker_path}"

    gateway_source = open(gateway_path, encoding='utf-8').read()
    worker_source = open(worker_path, encoding='utf-8').read()
    ast.parse(gateway_source)
    ast.parse(worker_source)

    assert 'invalid_host' not in gateway_source, "Gateway still uses the invalid broker host"
    assert '/home/user/kmer_dist.py' in worker_source, "Worker task does not call the required metric script"
    assert 'subprocess' in worker_source, "Worker task must execute the metric script"
    assert 'tasks.compute_kmer_dist' in worker_source, "Required Celery task name is missing"

    dispatch_markers = ('.delay(', '.apply_async(', '.send_task(', '.signature(')
    assert any(marker in gateway_source for marker in dispatch_markers), \
        "Gateway does not dispatch work through Celery"
    assert '.get(' in gateway_source, "Gateway does not wait for and use the Celery task result"

    gateway_module = load_module(gateway_path, 'verified_gateway_app')
    worker_module = load_module(worker_path, 'verified_worker_tasks')
    assert hasattr(gateway_module, 'celery_app'), "Gateway Celery application is missing"
    assert hasattr(worker_module, 'app'), "Worker Celery application is missing"

    assert_redis_url(gateway_module.celery_app.conf.broker_url, 'Gateway broker')
    assert_redis_url(gateway_module.celery_app.conf.result_backend, 'Gateway result backend')
    assert_redis_url(worker_module.app.conf.broker_url, 'Worker broker')
    assert_redis_url(worker_module.app.conf.result_backend, 'Worker result backend')


def test_redis_and_worker_task_end_to_end():
    client = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=3)
    assert client.ping() is True, "Redis is not running on port 6379"
    info = client.info(section='server')
    assert info.get('redis_version'), "Port 6379 is not reporting a Redis server"

    probe = Celery(
        'verifier_probe',
        broker='redis://127.0.0.1:6379/0',
        backend='redis://127.0.0.1:6379/0',
    )
    rng = random.SystemRandom()
    for _ in range(3):
        seq1 = ''.join(rng.choice('ACGT') for _ in range(rng.randint(13, 80)))
        seq2 = ''.join(rng.choice('ACGT') for _ in range(rng.randint(13, 80)))
        result = probe.send_task('tasks.compute_kmer_dist', args=[seq1, seq2])
        try:
            actual = float(result.get(timeout=20))
        except Exception as exc:
            pytest.fail(f"Celery worker did not execute tasks.compute_kmer_dist through Redis: {exc}")
        assert abs(actual - expected_distance(seq1, seq2)) < 1e-9


def test_gateway_api():
    url = "http://127.0.0.1:8000/analyze"
    seq1 = "ATGCATGCAT"
    seq2 = "GCATGCATGC"

    payload = json.dumps({"seq1": seq1, "seq2": seq2}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to connect to or read from gateway API at {url}: {e}")

    assert "distance" in data, f"Response JSON missing 'distance' key: {data}"
    assert isinstance(data["distance"], float), f"Expected 'distance' to be a float, got {type(data['distance'])}"

    oracle_path = "/app/legacy_kmer_dist"
    oracle_proc = subprocess.run(
        [oracle_path, seq1, seq2],
        capture_output=True, text=True, check=True
    )
    oracle_out = float(oracle_proc.stdout.strip())

    assert abs(data["distance"] - oracle_out) < 1e-5, f"API returned distance {data['distance']}, expected {oracle_out}"


def test_gateway_dynamic_requests_are_enqueued_in_redis():
    client = redis.Redis(host='127.0.0.1', port=6379, db=0, decode_responses=True)
    monitor = client.monitor()
    monitor.__enter__()
    commands = []

    def collect_commands():
        try:
            for item in monitor.listen():
                commands.append(item.get('command', ''))
        except Exception:
            pass

    thread = threading.Thread(target=collect_commands, daemon=True)
    thread.start()
    time.sleep(0.2)

    rng = random.SystemRandom()
    try:
        for _ in range(5):
            seq1 = ''.join(rng.choice('ACGT') for _ in range(rng.randint(11, 95)))
            seq2 = ''.join(rng.choice('ACGT') for _ in range(rng.randint(11, 95)))
            data = post_analyze(seq1, seq2)
            assert set(data) == {'distance'}, f"Unexpected gateway response: {data}"
            assert isinstance(data['distance'], float), f"Expected float distance, got {data}"
            assert abs(data['distance'] - expected_distance(seq1, seq2)) < 1e-5
        time.sleep(0.5)
    finally:
        monitor.__exit__(None, None, None)
        thread.join(timeout=1)

    celery_enqueues = [
        command for command in commands
        if command.upper().startswith(('LPUSH ', 'RPUSH '))
        and 'tasks.compute_kmer_dist' in command
    ]
    assert len(celery_enqueues) >= 5, \
        "Gateway requests did not enqueue tasks.compute_kmer_dist through Redis"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
