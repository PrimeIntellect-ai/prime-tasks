#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import random
import string
import hashlib
import urllib.request
import json
import pytest
import redis

def test_files_exist():
    assert os.path.exists("/home/user/app/v2/main.py"), "Python 3 service file is missing"
    assert os.path.exists("/home/user/app/nginx.conf"), "Nginx config file is missing"
    assert os.path.exists("/home/user/app/ci_test.sh"), "CI test script is missing"

def test_ci_test_script_execution():
    log_path = "/home/user/app/test_status.log"
    assert os.path.exists(log_path), "test_status.log is missing, did the ci_test.sh script run?"
    with open(log_path, "r") as f:
        status = f.read().strip()
    assert status.isdigit(), f"test_status.log does not contain a valid numeric HTTP status code, found: {status}"

def test_speedup_and_correctness():
    random.seed(42)
    # Generate a set of unique payloads
    unique_payloads = [''.join(random.choices(string.ascii_letters, k=10)) for _ in range(50)]

    def get_sig(p):
        return hashlib.sha256(p.encode('utf-8')).hexdigest()

    requests_data = []
    # Create 200 requests with many duplicates to test caching
    for _ in range(200):
        p = random.choice(unique_payloads)
        # Mix of correct and incorrect signatures
        if random.random() > 0.5:
            sig = get_sig(p)
        else:
            sig = "invalid_sig"
        requests_data.append((p, sig))

    expected_results = [sig == get_sig(p) for p, sig in requests_data]

    # 1. Measure Legacy App
    legacy_results = []
    start_legacy = time.time()
    for p, sig in requests_data:
        url = f"http://127.0.0.1:8080/legacy/verify?payload={p}&sig={sig}"
        try:
            req = urllib.request.urlopen(url)
            res = json.loads(req.read().decode('utf-8'))
            legacy_results.append(res.get("valid"))
        except Exception as e:
            pytest.fail(f"Legacy request failed via Nginx proxy on port 8080: {e}")
    time_legacy = time.time() - start_legacy

    # Clear DB 0 so cache entries checked below must be produced by the V2 requests.
    try:
        cache = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
        assert cache.ping(), "Redis on localhost:6379 DB 0 is unavailable"
        cache.flushdb()
    except Exception as e:
        pytest.fail(f"Unable to prepare Redis DB 0 for cache validation: {e}")

    # 2. Measure V2 App
    v2_results = []
    start_v2 = time.time()
    for p, sig in requests_data:
        url = f"http://127.0.0.1:8080/v2/verify?payload={p}&sig={sig}"
        try:
            req = urllib.request.urlopen(url)
            res = json.loads(req.read().decode('utf-8'))
            v2_results.append(res.get("valid"))
        except Exception as e:
            pytest.fail(f"V2 request failed via Nginx proxy on port 8080: {e}")
    time_v2 = time.time() - start_v2

    # Verify each service against independently computed SHA-256 truth, while
    # retaining the original cross-service equivalence assertion.
    assert legacy_results == expected_results, "Legacy service results do not match independently computed SHA-256 results."
    assert v2_results == expected_results, "V2 service results do not match independently computed SHA-256 results."
    assert legacy_results == v2_results, "V2 service results do not match the legacy service results."

    # Verify that V2 populated Redis DB 0 using each payload as the key and its
    # independently computed valid signature as the value.
    for p in set(p for p, _ in requests_data):
        cached_sig = cache.get(p)
        assert cached_sig == get_sig(p), f"Redis cache entry for payload {p!r} is missing or incorrect"

    # Verify Speedup Metric
    speedup = time_legacy / max(time_v2, 0.001)
    assert speedup >= 4.0, f"Speedup metric failed: ratio is {speedup:.2f} (Threshold >= 4.0). Legacy took {time_legacy:.2f}s, V2 took {time_v2:.2f}s. Ensure Redis caching is implemented correctly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
