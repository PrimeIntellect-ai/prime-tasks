#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import socket
import pytest
import os

def read_ground_truth():
    truth_file = "/tests/ground_truth.txt"
    assert os.path.exists(truth_file), "Ground truth file missing"

    truth = []
    with open(truth_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            frame_id, node_id, cost = line.split(",")
            truth.append((int(frame_id), int(cost)))
    return truth

def test_tcp_server_single_connection():
    truth = read_ground_truth()
    assert len(truth) > 0, "Ground truth is empty"

    try:
        s = socket.create_connection(("127.0.0.1", 8888), timeout=5)
    except Exception as e:
        pytest.fail(f"Could not connect to TCP server on 127.0.0.1:8888: {e}")

    with s:
        s.settimeout(2.0)
        for frame_id, expected_cost in truth:
            req = f"QUERY {frame_id}\n".encode("utf-8")
            s.sendall(req)

            resp_bytes = b""
            while not resp_bytes.endswith(b"\n"):
                try:
                    chunk = s.recv(1024)
                    if not chunk:
                        break
                    resp_bytes += chunk
                except socket.timeout:
                    pytest.fail(f"Timeout waiting for response for frame {frame_id}")

            resp_str = resp_bytes.decode("utf-8")
            expected_resp = f"PATH_COST: {expected_cost}\n"
            assert resp_str == expected_resp, f"For frame {frame_id}, expected '{expected_resp.strip()}', got '{resp_str.strip()}'"

def test_tcp_server_multiple_connections():
    truth = read_ground_truth()
    assert len(truth) > 0, "Ground truth is empty"

    # Test fresh connection for the first few frames
    for frame_id, expected_cost in truth[:5]:
        try:
            s = socket.create_connection(("127.0.0.1", 8888), timeout=5)
        except Exception as e:
            pytest.fail(f"Could not connect to TCP server on 127.0.0.1:8888 for frame {frame_id}: {e}")

        with s:
            s.settimeout(2.0)
            req = f"QUERY {frame_id}\n".encode("utf-8")
            s.sendall(req)

            resp_bytes = b""
            while not resp_bytes.endswith(b"\n"):
                try:
                    chunk = s.recv(1024)
                    if not chunk:
                        break
                    resp_bytes += chunk
                except socket.timeout:
                    pytest.fail(f"Timeout waiting for response for frame {frame_id} on fresh connection")

            resp_str = resp_bytes.decode("utf-8")
            expected_resp = f"PATH_COST: {expected_cost}\n"
            assert resp_str == expected_resp, f"For frame {frame_id} on fresh connection, expected '{expected_resp.strip()}', got '{resp_str.strip()}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
