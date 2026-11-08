#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import secrets
import random
import urllib.request
import time
import subprocess
import pytest
import numpy as np


def test_nginx_running():
    """Verify Nginx is running and listening on port 8080."""
    try:
        output = subprocess.check_output(["netstat", "-tuln"]).decode("utf-8")
        assert ":8080 " in output, "Nginx is not listening on port 8080."
    except FileNotFoundError:
        pass


def test_worker_running():
    """Verify the C++ worker is compiled and running."""
    worker_path = "/home/user/filter_worker"
    assert os.path.isfile(worker_path), f"Worker executable not found at {worker_path}"
    assert os.access(worker_path, os.X_OK), f"Worker at {worker_path} is not executable."

    output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    assert "filter_worker" in output, "The filter_worker process is not running."


def joint_log_likelihood(a, b, c):
    def normal_logpdf(x, mean, std):
        z = (x - mean) / std
        return -0.5 * z * z - math.log(std * math.sqrt(2.0 * math.pi))

    expected_c = 0.5 * a + 0.8 * b
    return (
        normal_logpdf(a, 50.0, 5.0)
        + normal_logpdf(b, 100.0, 10.0)
        + normal_logpdf(c, expected_c, 2.0)
    )


def original_corpus_likelihood_bounds():
    """Recreate the shipped corpus independently to obtain valid threshold bounds."""
    rng = np.random.RandomState(42)
    clean_ll = []
    evil_ll = []

    for _ in range(100):
        a = float(rng.normal(50.0, 5.0))
        b = float(rng.normal(100.0, 10.0))
        c = float(0.5 * a + 0.8 * b + rng.normal(0.0, 2.0))
        clean_ll.append(joint_log_likelihood(a, b, c))

    for _ in range(100):
        a = float(rng.normal(50.0, 5.0))
        b = float(rng.normal(100.0, 10.0))
        c = float(0.5 * a + 0.8 * b + rng.normal(50.0, 5.0))
        evil_ll.append(joint_log_likelihood(a, b, c))

    clean_floor = min(clean_ll)
    evil_ceiling = max(evil_ll)
    assert evil_ceiling < clean_floor, "Reference corpus is not separable"
    return clean_floor, evil_ceiling


def make_hidden_probes():
    """Create unpredictable cases with misleading IDs and model-derived labels."""
    clean_floor, evil_ceiling = original_corpus_likelihood_bounds()
    rng = random.SystemRandom()
    probes = []

    # High-likelihood samples use an evil-looking ID and must be CLEAN.
    for _ in range(6):
        a = 50.0 + rng.uniform(-1.0, 1.0)
        b = 100.0 + rng.uniform(-2.0, 2.0)
        c = 0.5 * a + 0.8 * b + rng.uniform(-0.4, 0.4)
        payload = {"id": "evil_hidden_" + secrets.token_hex(12), "a": a, "b": b, "c": c}
        ll = joint_log_likelihood(a, b, c)
        assert ll >= clean_floor
        probes.append((payload, "CLEAN"))

    # Low likelihood caused independently by a, b, or conditional c. These use
    # clean-looking IDs so classification by ID prefix cannot pass.
    for feature in ("a", "b", "c"):
        for _ in range(3):
            a = 50.0 + rng.uniform(-0.5, 0.5)
            b = 100.0 + rng.uniform(-1.0, 1.0)
            noise = rng.uniform(-0.2, 0.2)
            if feature == "a":
                a = 50.0 + rng.choice((-1.0, 1.0)) * rng.uniform(120.0, 130.0)
            elif feature == "b":
                b = 100.0 + rng.choice((-1.0, 1.0)) * rng.uniform(240.0, 260.0)
            else:
                noise = rng.choice((-1.0, 1.0)) * rng.uniform(48.0, 52.0)
            c = 0.5 * a + 0.8 * b + noise
            payload = {"id": "clean_hidden_" + secrets.token_hex(12), "a": a, "b": b, "c": c}
            ll = joint_log_likelihood(a, b, c)
            assert ll < evil_ceiling
            probes.append((payload, "REJECT"))

    return probes


def test_pipeline_adversarial_corpus():
    """Test the visible corpus plus unpredictable likelihood-derived probes."""
    import redis

    r = redis.Redis(host='127.0.0.1', port=6379, db=0)
    r.delete('incoming_queue')
    r.delete('processed_queue')

    clean_dir = "/app/data/clean/"
    evil_dir = "/app/data/evil/"
    assert os.path.isdir(clean_dir), f"Clean dir missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil dir missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_ids = set()
    evil_ids = set()
    submissions = []

    for filepath in clean_files:
        with open(filepath, 'r') as f:
            data = f.read()
        parsed = json.loads(data)
        clean_ids.add(parsed['id'])
        submissions.append((data, parsed['id'], "CLEAN"))

    for filepath in evil_files:
        with open(filepath, 'r') as f:
            data = f.read()
        parsed = json.loads(data)
        evil_ids.add(parsed['id'])
        submissions.append((data, parsed['id'], "REJECT"))

    hidden_expected = {}
    for payload, status in make_hidden_probes():
        hidden_expected[payload['id']] = status
        submissions.append((json.dumps(payload), payload['id'], status))

    random.SystemRandom().shuffle(submissions)

    for data, item_id, _ in submissions:
        req = urllib.request.Request(
            "http://127.0.0.1:8080/api/ingest",
            data=data.encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                assert response.status == 200
        except Exception as e:
            pytest.fail(f"Failed to POST item {item_id} to Nginx: {e}")

    expected_total = len(clean_ids) + len(evil_ids) + len(hidden_expected)
    results = {}
    timeout = 20
    start_time = time.time()

    while time.time() - start_time < timeout:
        item = r.lpop('processed_queue')
        if item:
            try:
                parsed = json.loads(item)
                results[parsed['id']] = parsed['status']
            except Exception:
                pass
        else:
            if len(results) >= expected_total:
                break
            time.sleep(0.1)

    clean_modified = [cid for cid in clean_ids if results.get(cid) != "CLEAN"]
    evil_bypassed = [eid for eid in evil_ids if results.get(eid) != "REJECT"]
    hidden_wrong = [
        item_id for item_id, expected in hidden_expected.items()
        if results.get(item_id) != expected
    ]

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_ids)} evil bypassed (e.g., {evil_bypassed[:3]})")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_ids)} clean modified/rejected (e.g., {clean_modified[:3]})")
    if hidden_wrong:
        error_msgs.append(f"{len(hidden_wrong)} of {len(hidden_expected)} hidden likelihood probes misclassified (e.g., {hidden_wrong[:3]})")

    if error_msgs:
        pytest.fail("; ".join(error_msgs))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
