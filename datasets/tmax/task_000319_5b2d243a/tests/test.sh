#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import json
import pytest

ORACLE_PATH = "/tests/log_parser_oracle"
AGENT_PATH = "/app/log_parser/target/release/log_parser"

def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []
    for _ in range(n):
        ts = f"2023-10-12T{random.randint(10,23)}:{random.randint(10,59)}:{random.randint(10,59)}Z"
        metric = f"{random.uniform(0, 1000):.{random.randint(1, 15)}f}"

        tags = ""
        num_tags = random.randint(0, 3)
        for _ in range(num_tags):
            tag_content = "".join(random.choices(string.ascii_letters, k=random.randint(2, 8)))
            if random.random() < 0.1:
                tags += f"[{tag_content} "
            elif random.random() < 0.1:
                tags += f"{tag_content}] "
            else:
                tags += f"[{tag_content}] "

        msg_len = random.randint(5, 50)
        msg = "".join(random.choices(string.ascii_letters + string.digits + " ", k=msg_len))
        log_line = f"{ts} {metric} {tags}{msg}"
        inputs.append(log_line)
    return inputs

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

    inputs = generate_fuzz_inputs(n=1000)

    for i, log_line in enumerate(inputs):
        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH, "--stdin"],
                input=log_line,
                text=True,
                capture_output=True,
                timeout=2
            )
            oracle_out = oracle_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail("Oracle timed out. This should not happen.")

        try:
            agent_res = subprocess.run(
                [AGENT_PATH, "--stdin"],
                input=log_line,
                text=True,
                capture_output=True,
                timeout=2
            )
            agent_out = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent binary timed out on input: {log_line!r}\nLikely infinite loop.")

        assert agent_out == oracle_out, (
            f"Mismatch on fuzz input {i}:\n"
            f"Input: {log_line!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output:  {agent_out!r}"
        )

def test_end_to_end_redis_data():
    try:
        res = subprocess.run(
            ["redis-cli", "LLEN", "parsed_logs"],
            text=True, capture_output=True, check=True
        )
        llen = int(res.stdout.strip())
        assert llen >= 5, f"Expected at least 5 entries in 'parsed_logs' list in Redis, found {llen}. Did you run the services and log_generator.py?"

        res_pop = subprocess.run(
            ["redis-cli", "LINDEX", "parsed_logs", "0"],
            text=True, capture_output=True, check=True
        )
        item = res_pop.stdout.strip()
        assert item, "Expected to find an item in Redis 'parsed_logs'"
        try:
            parsed = json.loads(item)
            assert "metric" in parsed, "Parsed JSON missing 'metric' field"
        except json.JSONDecodeError:
            pytest.fail(f"Redis item is not valid JSON: {item}")

    except FileNotFoundError:
        pytest.fail("redis-cli not found, cannot verify Redis state.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query Redis: {e.stderr}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
