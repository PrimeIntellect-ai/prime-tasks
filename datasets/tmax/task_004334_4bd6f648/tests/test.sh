#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import socket
import subprocess
import threading
import pytest

def test_git_deployment_setup():
    """Verify the Git bare repository, post-receive hook, and deployment log."""
    repo_dir = "/home/user/device-repo.git"
    assert os.path.isdir(repo_dir), f"Bare Git repository directory {repo_dir} does not exist."
    assert os.path.isfile(os.path.join(repo_dir, "HEAD")), f"{repo_dir} does not appear to be a valid Git repository."

    hook_path = os.path.join(repo_dir, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook not found at {hook_path}."
    assert os.access(hook_path, os.X_OK), f"post-receive hook at {hook_path} is not executable."

    log_path = "/home/user/deploy/deploy.log"
    assert os.path.isfile(log_path), f"Deployment log not found at {log_path}."

    with open(log_path, "r") as f:
        log_content = f.read().strip()

    assert log_content == "DEPLOYMENT_SUCCESS", f"deploy.log content is incorrect. Expected 'DEPLOYMENT_SUCCESS', got '{log_content}'."

def test_fuzz_equivalence():
    """Verify that the deployed telemetry processor exactly matches the oracle binary output on random inputs."""
    oracle_bin = "/tests/oracle_telemetry_processor"
    agent_bin = "/home/user/deploy/telemetry_processor"

    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}."
    assert os.path.isfile(agent_bin), f"Agent deployed binary not found at {agent_bin}."
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable."

    random.seed(42)
    num_tests = 500

    for i in range(num_tests):
        length = random.randint(50, 5000)
        input_data = bytes(random.getrandbits(8) for _ in range(length))

        proc_oracle = subprocess.run([oracle_bin], input=input_data, capture_output=True)
        proc_agent = subprocess.run([agent_bin], input=input_data, capture_output=True)

        assert proc_oracle.returncode == 0, f"Oracle binary failed on input {i}."

        if proc_oracle.stdout != proc_agent.stdout:
            oracle_out = proc_oracle.stdout[:100] + (b'...' if len(proc_oracle.stdout) > 100 else b'')
            agent_out = proc_agent.stdout[:100] + (b'...' if len(proc_agent.stdout) > 100 else b'')
            pytest.fail(
                f"Fuzz test {i} failed (input length {length}).\n"
                f"Oracle output (prefix): {oracle_out}\n"
                f"Agent output (prefix): {agent_out}"
            )

def test_ssh_tunnel_active():
    """Verify that a local port forward is tunneling 127.0.0.1:7070 to 127.0.0.1:8080."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(('127.0.0.1', 8080))
        server.listen(1)
    except Exception as e:
        pytest.fail(f"Could not bind to 8080 to test tunnel. Is something else running? Error: {e}")

    received_data = []

    def accept_and_read():
        try:
            server.settimeout(3.0)
            conn, _ = server.accept()
            conn.settimeout(2.0)
            data = conn.recv(1024)
            received_data.append(data)
            conn.close()
        except:
            pass

    t = threading.Thread(target=accept_and_read)
    t.start()

    test_payload = b"TELEMETRY_TUNNEL_TEST_DATA"
    try:
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.settimeout(2.0)
        client.connect(('127.0.0.1', 7070))
        client.sendall(test_payload)
        client.close()
    except Exception as e:
        server.close()
        pytest.fail(f"Failed to connect to local port 7070 or send data. Is the SSH tunnel running? Error: {e}")

    t.join(timeout=4.0)
    server.close()

    assert len(received_data) > 0, "No data received on port 8080. The SSH tunnel from 7070 to 8080 is not active or not forwarding traffic."
    assert received_data[0] == test_payload, f"Data mismatch through tunnel. Expected {test_payload}, got {received_data[0]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
