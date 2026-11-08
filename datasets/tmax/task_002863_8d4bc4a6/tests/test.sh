#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import urllib.request
import time
import pytest

def test_filter_exists():
    assert os.path.isfile("/home/user/loc_filter.py"), "The filter script /home/user/loc_filter.py is missing."

def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/start_pipeline.sh"), "The pipeline script /home/user/start_pipeline.sh is missing."

def test_fuzz_equivalence():
    oracle_path = "/tests/loc_filter_oracle"
    agent_path = "/home/user/loc_filter.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing at {agent_path}"

    random.seed(42)

    # We run 250 streams to balance thoroughness and test execution time
    for stream_idx in range(250):
        num_lines = random.randint(50, 500)
        lines = []
        ts = random.uniform(0.0, 100.0)
        for _ in range(num_lines):
            ts += random.uniform(0.1, 5.0)
            slen = random.randint(1, 50)
            tlen = random.randint(1, 150)
            lang = random.choice(["fr", "de", "es", "ja"])
            lines.append(json.dumps({
                "timestamp": ts,
                "source_len": slen,
                "target_len": tlen,
                "lang": lang
            }))

        input_data = "\n".join(lines) + "\n"

        oracle_proc = subprocess.run(["/usr/bin/python3", oracle_path], input=input_data, text=True, capture_output=True)
        agent_proc = subprocess.run(["/usr/bin/python3", agent_path], input=input_data, text=True, capture_output=True)

        oracle_out = [line for line in oracle_proc.stdout.strip().split("\n") if line]
        agent_out = [line for line in agent_proc.stdout.strip().split("\n") if line]

        if len(oracle_out) != len(agent_out):
            assert False, (
                f"Stream {stream_idx}: Line count mismatch.\n"
                f"Oracle generated {len(oracle_out)} lines, Agent generated {len(agent_out)} lines.\n"
                f"First few input lines: {lines[:3]}"
            )

        for line_idx, (o_line, a_line) in enumerate(zip(oracle_out, agent_out)):
            try:
                o_json = json.loads(o_line)
            except json.JSONDecodeError:
                continue # Skip if oracle output is somehow malformed

            try:
                a_json = json.loads(a_line)
            except json.JSONDecodeError:
                assert False, f"Stream {stream_idx}, Line {line_idx}: Agent output is not valid JSON: {a_line}"

            assert o_json == a_json, (
                f"Stream {stream_idx}, Line {line_idx}: Mismatch found!\n"
                f"Oracle: {o_json}\n"
                f"Agent:  {a_json}\n"
            )

def test_dashboard_running():
    # Wait for the multi-service compose to be up and running
    max_retries = 10
    success = False
    for _ in range(max_retries):
        try:
            req = urllib.request.Request("http://localhost:8080/metrics")
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status == 200:
                    data = response.read().decode('utf-8')
                    # Just verify we can read it and it's up
                    success = True
                    break
        except Exception:
            pass
        time.sleep(1)

    assert success, "Dashboard is not reachable at http://localhost:8080/metrics after waiting. Ensure start_pipeline.sh runs all services in the background."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
