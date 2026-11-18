#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import time
import urllib.request
import subprocess
import random
import pytest

def test_config_updated():
    config_path = "/home/user/app/config.json"
    assert os.path.isfile(config_path), f"File {config_path} is missing."

    with open(config_path, "r") as f:
        config = json.load(f)

    assert "api_port" in config, "api_port key missing in config.json."
    assert config["api_port"] == 8080, f"Expected api_port to be 8080, got {config['api_port']}."

def test_services_connectivity():
    start_sh_path = "/home/user/app/start.sh"
    assert os.path.isfile(start_sh_path), f"File {start_sh_path} is missing."

    proc = subprocess.Popen([start_sh_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        time.sleep(2)
        req = urllib.request.Request("http://127.0.0.1:8000/status")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = response.read().decode('utf-8')
            result = json.loads(data)

        assert result.get("status") == "ok", f"Expected status 'ok', got {result.get('status')}"
        assert result.get("api_connected") is True, f"Expected api_connected to be true, got {result.get('api_connected')}"
    finally:
        proc.terminate()

def generate_fuzz_inputs(n=1000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        r = random.random()
        if r < 0.10:
            length = random.randint(0, 13)
            inputs.append(''.join(random.choices("0123456789ABCDEF", k=length)))
        elif r < 0.30:
            version = random.randint(0, 255)
            ts = random.randint(0, 0xFFFFFFFF)
            actual_payload_len = random.randint(0, 40)
            payload = [random.randint(0, 255) for _ in range(actual_payload_len)]

            wrong_len = actual_payload_len + 7 + random.choice([-1, 1, 2, 5])
            if wrong_len < 0: wrong_len = 0

            hex_str = f"{version:02X}{wrong_len:04X}{ts:08X}" + "".join(f"{b:02X}" for b in payload)
            inputs.append(hex_str)
        else:
            version = random.randint(0, 255)
            ts = random.randint(0, 0xFFFFFFFF)
            actual_payload_len = random.randint(0, 40)
            payload = [random.randint(0, 255) for _ in range(actual_payload_len)]

            total_len = actual_payload_len + 7
            hex_str = f"{version:02X}{total_len:04X}{ts:08X}" + "".join(f"{b:02X}" for b in payload)
            inputs.append(hex_str)

    return inputs

def test_packet_parser_fuzz_equivalence():
    agent_script = "/home/user/packet_parser.py"
    oracle_script = "/tests/oracle_packet_parser.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."

    inputs = generate_fuzz_inputs(100)

    for hex_input in inputs:
        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=hex_input,
            text=True,
            capture_output=True
        )
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=hex_input,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input: {hex_input}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
