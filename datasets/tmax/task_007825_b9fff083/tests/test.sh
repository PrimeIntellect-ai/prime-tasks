#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import base64
import json
import os
import secrets
import stat
import subprocess
import time
import uuid

import pytest


def test_runner_executable():
    runner_path = "/home/user/auto_provision_runner"
    assert os.path.isfile(runner_path), f"{runner_path} does not exist."
    assert os.access(runner_path, os.X_OK), f"{runner_path} is not executable."


def test_daemon_executable():
    daemon_path = "/home/user/provision_daemon.sh"
    assert os.path.isfile(daemon_path), f"{daemon_path} does not exist."
    assert os.access(daemon_path, os.X_OK), f"{daemon_path} is not executable."


def test_daemon_running():
    output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    assert "provision_daemon.sh" in output, "provision_daemon.sh is not running in the background."


def test_runner_and_daemon_execute_legacy_utility():
    legacy_path = "/home/user/legacy_net_setup.py"
    runner_path = "/home/user/auto_provision_runner"
    job_file = "/home/user/job_queue.txt"
    log_file = "/home/user/processed_tokens.log"

    assert os.path.isfile(legacy_path), f"{legacy_path} does not exist."
    assert os.access(legacy_path, os.X_OK), f"{legacy_path} is not executable."

    with open(legacy_path, "rb") as f:
        original_legacy = f.read()
    original_mode = stat.S_IMODE(os.stat(legacy_path).st_mode)

    challenge_token = base64.b64encode(secrets.token_bytes(24)).decode("ascii")
    marker_path = f"/tmp/legacy_probe_{uuid.uuid4().hex}.jsonl"
    direct_cluster = f"direct-{uuid.uuid4().hex}"
    direct_port = str(12000 + secrets.randbelow(20000))
    daemon_cluster = f"daemon-{uuid.uuid4().hex}"
    daemon_port = str(35000 + secrets.randbelow(20000))

    probe = f'''#!/usr/bin/env python3
import json
import sys

sys.stdout.write("Enter cluster name: ")
sys.stdout.flush()
cluster = input().strip()
sys.stdout.write("Enter base port (1024-65535): ")
sys.stdout.flush()
port = input().strip()
sys.stdout.write("Enable IPv6? (y/n): ")
sys.stdout.flush()
ipv6 = input().strip()
with open({marker_path!r}, "a") as marker:
    marker.write(json.dumps({{"cluster": cluster, "port": port, "ipv6": ipv6}}) + "\\n")
print("\\nProbe processing complete")
print("SUCCESS: Node configured. token=" + {challenge_token!r} + " endpoint=127.0.0.1:" + port)
'''

    def marker_records():
        if not os.path.exists(marker_path):
            return []
        with open(marker_path, "r") as f:
            return [json.loads(line) for line in f if line.strip()]

    def log_lines():
        if not os.path.exists(log_file):
            return []
        with open(log_file, "r") as f:
            return f.read().splitlines()

    try:
        with open(legacy_path, "w") as f:
            f.write(probe)
        os.chmod(legacy_path, 0o755)

        env = os.environ.copy()
        env["CLUSTER_NAME"] = direct_cluster
        env["BASE_PORT"] = direct_port
        result = subprocess.run(
            [runner_path],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, f"Runner failed: {result.stderr}"
        assert result.stdout.splitlines() == [challenge_token], \
            "Runner must output only the token extracted from the legacy SUCCESS line."
        assert {"cluster": direct_cluster, "port": direct_port, "ipv6": "n"} in marker_records(), \
            "Runner did not execute and correctly answer the legacy utility."

        if os.path.exists(job_file):
            os.unlink(job_file)
        baseline_log_count = len(log_lines())
        baseline_marker_count = len(marker_records())

        temporary_job = job_file + f".{uuid.uuid4().hex}.tmp"
        with open(temporary_job, "w") as f:
            f.write(f"export CLUSTER_NAME={daemon_cluster}\n")
            f.write(f"export BASE_PORT={daemon_port}\n")
        os.replace(temporary_job, job_file)

        deadline = time.time() + 12
        while time.time() < deadline:
            records = marker_records()
            lines = log_lines()
            if (not os.path.exists(job_file)
                    and len(records) > baseline_marker_count
                    and len(lines) > baseline_log_count):
                break
            time.sleep(0.25)

        assert not os.path.exists(job_file), f"{job_file} was not deleted by the daemon."
        records = marker_records()
        assert {"cluster": daemon_cluster, "port": daemon_port, "ipv6": "n"} in records[baseline_marker_count:], \
            "Daemon did not execute the runner against the legacy utility with the queued values."
        lines = log_lines()
        assert len(lines) > baseline_log_count, "Daemon did not append a token to the log."
        assert lines[-1].strip() == challenge_token, \
            "Daemon did not append the token returned through the runner/legacy pipeline."
    finally:
        with open(legacy_path, "wb") as f:
            f.write(original_legacy)
        os.chmod(legacy_path, original_mode)
        if os.path.exists(marker_path):
            os.unlink(marker_path)


def test_processing_pipeline():
    job_file = "/home/user/job_queue.txt"
    log_file = "/home/user/processed_tokens.log"

    # Test case 1
    cluster1 = "prod-eu-central"
    port1 = "8443"
    expected_token1 = base64.b64encode(f"{cluster1}:{port1}:n".encode('utf-8')).decode('utf-8')

    with open(job_file, "w") as f:
        f.write(f"export CLUSTER_NAME={cluster1}\n")
        f.write(f"export BASE_PORT={port1}\n")

    # Wait up to 10 seconds for the file to be processed
    for _ in range(10):
        if not os.path.exists(job_file):
            break
        time.sleep(1)

    assert not os.path.exists(job_file), f"{job_file} was not deleted by the daemon. Polling might not be working."
    assert os.path.exists(log_file), f"{log_file} was not created."

    with open(log_file, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) >= 1, f"{log_file} is empty."
    assert lines[-1].strip() == expected_token1, f"Expected token {expected_token1} not found at the end of {log_file}."

    # Test case 2
    cluster2 = "dev-us-east"
    port2 = "9090"
    expected_token2 = base64.b64encode(f"{cluster2}:{port2}:n".encode('utf-8')).decode('utf-8')

    with open(job_file, "w") as f:
        f.write(f"export CLUSTER_NAME={cluster2}\n")
        f.write(f"export BASE_PORT={port2}\n")

    # Wait up to 10 seconds for the second file to be processed
    for _ in range(10):
        if not os.path.exists(job_file):
            break
        time.sleep(1)

    assert not os.path.exists(job_file), f"{job_file} was not deleted by the daemon on the second run."

    with open(log_file, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) >= 2, f"{log_file} does not have enough lines appended."
    assert lines[-1].strip() == expected_token2, f"Expected token {expected_token2} not found at the end of {log_file}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
