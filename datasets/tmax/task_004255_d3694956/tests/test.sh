#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import secrets
import subprocess
import tempfile
import time
from datetime import datetime, timedelta

import pandas as pd
import pytest


def run_and_time(cmd):
    start = time.time()
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    duration = time.time() - start
    assert result.returncode == 0, f"Command failed: {cmd}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    return duration


def run_and_capture(args):
    start = time.time()
    result = subprocess.run(args, capture_output=True, text=True)
    duration = time.time() - start
    assert result.returncode == 0, (
        f"Command failed: {args}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    return duration, result


def make_novel_log(path):
    rng = random.Random(secrets.randbits(128))
    endpoints = [
        "/internal/alpha",
        "/internal/beta",
        "/v2/search",
        "/metrics/query",
        "/checkout/retry",
        "/users/profile",
        "/orders/archive",
    ]
    statuses = [200, 200, 201, 204, 399, 400, 401, 404, 429, 500, 503]
    base = datetime(2024, 2, 17, 8, 0, 0)
    timestamps = [
        (base + timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
        for i in range(10801)
    ]

    with open(path, "w", encoding="utf-8") as f:
        for i in range(1_000_000):
            if i % 10007 == 0:
                f.write("this is not json\n")
                continue
            timestamp = timestamps[rng.randrange(len(timestamps))]
            endpoint = endpoints[rng.randrange(len(endpoints))]
            response_time = rng.randrange(1, 5001)
            status = statuses[rng.randrange(len(statuses))]
            f.write(
                '{"timestamp":"%s","ip":"10.7.%d.%d",'
                '"response_time_ms":%d,"endpoint":"%s","status":%d}\n'
                % (timestamp, (i // 251) % 256, i % 251 + 1,
                   response_time, endpoint, status)
            )


def test_00_novel_input_correctness_speed_and_logging():
    go_script = "/home/user/parallel_processor.go"
    oracle_bin = "/app/bucket_oracle"

    assert os.path.isfile(go_script), f"Agent's Go program {go_script} does not exist or is not a file."
    assert os.path.isfile(oracle_bin), f"Legacy tool {oracle_bin} does not exist."

    workspace = tempfile.mkdtemp(prefix="bucket-verifier-")
    os.chmod(workspace, 0o700)
    novel_log = os.path.join(workspace, "novel_requests.log")
    oracle_out = os.path.join(workspace, "expected.csv")
    agent_out = os.path.join(workspace, "actual.csv")
    make_novel_log(novel_log)
    os.chmod(novel_log, 0o600)

    t_oracle, _ = run_and_capture([oracle_bin, novel_log, oracle_out])
    assert os.path.exists(oracle_out), f"Oracle output {oracle_out} was not created."
    df_oracle = pd.read_csv(oracle_out)
    os.remove(oracle_out)

    t_agent, result = run_and_capture(["go", "run", go_script, novel_log, agent_out])
    assert os.path.exists(agent_out), f"Agent output {agent_out} was not created."
    assert result.stdout.strip(), "Agent program did not emit basic pipeline logging to stdout."

    df_agent = pd.read_csv(agent_out)
    try:
        pd.testing.assert_frame_equal(df_oracle, df_agent, check_dtype=False, check_exact=True)
    except AssertionError as e:
        pytest.fail(f"Agent's output for a novel log does not match the oracle.\nDetails: {e}")

    speedup = t_oracle / t_agent
    assert speedup >= 3.0, (
        f"Novel-input speedup {speedup:.2f}x is below the 3.0x threshold "
        f"(Oracle: {t_oracle:.2f}s, Agent: {t_agent:.2f}s)"
    )


def test_parallel_processor_speedup_and_correctness():
    go_script = "/home/user/parallel_processor.go"
    log_file = "/home/user/requests.log"
    oracle_bin = "/app/bucket_oracle"

    oracle_out = "/tmp/oracle_out.csv"
    agent_out = "/tmp/agent_out.csv"

    assert os.path.exists(go_script), f"Agent's Go program {go_script} does not exist."
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    assert os.path.exists(oracle_bin), f"Legacy tool {oracle_bin} does not exist."

    # Remove previous outputs if they exist
    for f in [oracle_out, agent_out]:
        if os.path.exists(f):
            os.remove(f)

    # Run oracle
    t_oracle = run_and_time(f"{oracle_bin} {log_file} {oracle_out}")
    assert os.path.exists(oracle_out), f"Oracle output {oracle_out} was not created."

    # Run agent
    t_agent = run_and_time(f"go run {go_script} {log_file} {agent_out}")
    assert os.path.exists(agent_out), f"Agent output {agent_out} was not created."

    # Verify outputs match
    df_oracle = pd.read_csv(oracle_out)
    df_agent = pd.read_csv(agent_out)

    try:
        pd.testing.assert_frame_equal(df_oracle, df_agent, check_dtype=False, check_exact=True)
    except AssertionError as e:
        pytest.fail(f"Agent's output CSV does not match the oracle's output exactly.\nDetails: {e}")

    # Metric Threshold
    speedup = t_oracle / t_agent
    assert speedup >= 3.0, f"Speedup {speedup:.2f}x is below the 3.0x threshold (Oracle: {t_oracle:.2f}s, Agent: {t_agent:.2f}s)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
