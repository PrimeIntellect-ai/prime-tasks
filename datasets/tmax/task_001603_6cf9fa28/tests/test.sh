#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import random
import subprocess
import pytest

try:
    import redis
except ImportError:
    pytest.fail("redis package is not installed but required for testing.")

def test_fuzz_equivalence():
    oracle_path = '/tests/oracle.py'
    agent_path = '/home/user/solve.py'

    assert os.path.exists(agent_path), f"Agent script not found at {agent_path}"
    assert os.path.exists(oracle_path), f"Oracle script not found at {oracle_path}"

    r = redis.Redis(host='127.0.0.1', port=6379, db=0, decode_responses=True)

    # Use a fixed seed for reproducible fuzzing
    random.seed(1337)

    for i in range(200):
        node_id = random.randint(1, 100)
        limit = random.randint(1, 25)
        offset = random.randint(0, 50)

        args = [str(node_id), str(limit), str(offset)]
        key = f"graph:{node_id}:{limit}:{offset}"

        # Run oracle with empty cache
        r.flushdb()
        oracle_cmd = [sys.executable, oracle_path] + args
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Clear redis cache again so agent must compute and populate it
        r.flushdb()

        # Run agent
        agent_cmd = [sys.executable, agent_path] + args
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent failed on input {args}:\n{agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        # Assert identical stdout
        assert agent_out == oracle_out, f"Output mismatch on input {args}:\nExpected: {oracle_out}\nGot: {agent_out}"

        # Verify Redis was populated correctly
        cached_val = r.get(key)
        assert cached_val is not None, f"Agent did not populate Redis cache for key {key}"
        assert cached_val.strip() == oracle_out, f"Redis cache mismatch for key {key}:\nExpected: {oracle_out}\nGot: {cached_val}"

        # Verify agent uses the cache on subsequent runs
        dummy_cache_val = '["cached_dummy_value"]'
        r.set(key, dummy_cache_val)
        agent_res_cached = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res_cached.returncode == 0, f"Agent failed on cached run for input {args}:\n{agent_res_cached.stderr}"
        assert agent_res_cached.stdout.strip() == dummy_cache_val, f"Agent did not read from Redis cache for key {key}. Expected: {dummy_cache_val}, Got: {agent_res_cached.stdout.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
