#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import json
import random
import string
import urllib.request
import urllib.error
import time
import pytest

def test_nginx_config_fixed():
    conf_path = "/home/user/pipeline/nginx.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:5000;" in content, "nginx.conf does not point to the correct Flask port (5000)"

def test_api_py_fixed():
    api_path = "/home/user/pipeline/api.py"
    assert os.path.isfile(api_path), f"{api_path} is missing"
    with open(api_path, "r") as f:
        content = f.read()
    assert "port=6379" in content, "api.py does not contain the correct Redis port (6379)"

def test_tokenizer_binary_exists():
    binary_path = "/home/user/bin/tokenizer"
    assert os.path.isfile(binary_path), f"Agent binary {binary_path} is missing"
    assert os.access(binary_path, os.X_OK), f"Agent binary {binary_path} is not executable"

def generate_random_string(length):
    charset = string.ascii_letters + string.digits + "!@#$%^&*()_+{}|:\"<>? \n\t"
    unicode_chars = ['😀', '🚀', '你好', '世界', 'مرحبا', 'ñ', 'é', 'ü', 'ç', '<tag>', '</body>']
    res = []
    for _ in range(length):
        if random.random() < 0.1:
            res.append(random.choice(unicode_chars))
        else:
            res.append(random.choice(charset))
    return "".join(res)

def test_fuzz_equivalence():
    oracle_path = "/tests/tokenizer_oracle"
    agent_path = "/home/user/bin/tokenizer"

    assert os.path.isfile(oracle_path), "Oracle binary missing"
    assert os.access(oracle_path, os.X_OK), "Oracle binary is not executable"
    assert os.path.isfile(agent_path), "Agent binary missing"

    random.seed(42)

    for i in range(500):
        length = random.randint(0, 2000)
        test_input = generate_random_string(length)

        oracle_proc = subprocess.run(
            [oracle_path],
            input=test_input.encode('utf-8'),
            capture_output=True
        )

        agent_proc = subprocess.run(
            [agent_path],
            input=test_input.encode('utf-8'),
            capture_output=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, f"Return code mismatch on input length {length}"

        oracle_out = oracle_proc.stdout.decode('utf-8', errors='replace').strip()
        agent_out = agent_proc.stdout.decode('utf-8', errors='replace').strip()

        assert agent_out == oracle_out, f"Output mismatch on iteration {i}.\nInput: {repr(test_input)}\nOracle: {oracle_out}\nAgent:  {agent_out}"

def test_end_to_end_flow():
    time.sleep(2)

    url = "http://127.0.0.1:8080/tokenize"
    payload = json.dumps({"text": "<html><body>Hello World!</body></html>"}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'}, method='POST')

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"HTTP request to Nginx failed: {e}")

    redis_check = subprocess.run(
        ["redis-cli", "rpop", "tokenized_results"],
        capture_output=True, text=True
    )

    output = redis_check.stdout.strip()
    redis_lrange = subprocess.run(
        ["redis-cli", "lrange", "tokenized_results", "0", "-1"],
        capture_output=True, text=True
    )

    all_items = redis_lrange.stdout.strip()
    expected_val = "[4286121820, 2818617300]"

    assert expected_val in all_items or expected_val in output, \
        f"Expected JSON array {expected_val} not found in Redis 'tokenized_results'. Found: {all_items} / {output}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
