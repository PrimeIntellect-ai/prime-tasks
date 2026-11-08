#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import socket
import time
import pytest

def test_evidence_server_protocol():
    """
    Connects to the evidence server on 127.0.0.1:8080 and verifies the custom protocol
    and the correctness of the extracted evidence.
    """
    host = '127.0.0.1'
    port = 8080
    expected_evidence = "EVIDENCE_FLAG{TH3_QU1CK_BR0WN_F0X_JUMPS_0V3R_TH3_L4ZY_D0G_99321}"

    # Attempt to connect to the server with retries to allow for slow startup
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)

    connected = False
    for _ in range(3):
        try:
            s.connect((host, port))
            connected = True
            break
        except ConnectionRefusedError:
            time.sleep(1)

    assert connected, f"Failed to connect to the evidence server at {host}:{port}. Ensure your Bash server is running in the background."

    try:
        # Step 1: Send HELO
        s.sendall(b"HELO\n")

        # Receive ACK
        resp1 = s.recv(1024).decode('utf-8', errors='replace').strip()
        assert resp1 == "ACK", f"Protocol error: Expected 'ACK' after sending 'HELO', but received '{resp1}'"

        # Step 2: Send GET_EVIDENCE
        s.sendall(b"GET_EVIDENCE\n")

        # Receive Evidence
        resp2 = s.recv(1024).decode('utf-8', errors='replace').strip()
        assert resp2 == expected_evidence, (
            f"Evidence mismatch.\n"
            f"Expected: {expected_evidence}\n"
            f"Received: {resp2}\n"
            f"Check your log parsing order and decoding logic."
        )

        # Verify connection is closed by the server (optional but good practice based on instructions)
        # The server should close the connection after sending the evidence.
        try:
            extra_data = s.recv(1024)
            assert not extra_data, "Server did not close the connection after sending the evidence as required."
        except socket.timeout:
            pytest.fail("Server did not close the connection after sending the evidence (timed out waiting for EOF).")

    except socket.timeout:
        pytest.fail("Socket operation timed out. The server did not respond within 5 seconds.")
    except Exception as e:
        pytest.fail(f"An unexpected error occurred during communication: {e}")
    finally:
        s.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
