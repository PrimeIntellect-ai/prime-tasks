#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import socket
import subprocess

import pytest

APP = "/app/artifact_pca"
REDUCER = os.path.join(APP, "reducer")
HOST = "127.0.0.1"
PORT = 8888


@pytest.fixture(scope="session", autouse=True)
def rebuild_reducer():
    """Ensure the submitted Makefile can build the required executable from scratch."""
    dry_run = subprocess.run(
        ["make", "-Bn", "reducer"], cwd=APP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}"
    link_lines = [line for line in dry_run.stdout.splitlines() if "reducer" in line and "-o" in line]
    assert any("-lm" in shlex.split(line) for line in link_lines), \
        f"The reducer link command does not link the math library with -lm:\n{dry_run.stdout}"

    subprocess.run(["make", "clean"], cwd=APP, check=True, timeout=15)
    build = subprocess.run(
        ["make", "reducer"], cwd=APP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"Clean build of reducer failed:\n{build.stdout}"


def run_direct(payload):
    return subprocess.run(
        [REDUCER], input=payload, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )


def query_service(payload):
    with socket.create_connection((HOST, PORT), timeout=5) as s:
        s.settimeout(5)
        s.sendall(payload.encode("ascii"))
        s.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks).decode("utf-8", errors="replace")


def test_reducer_compiled():
    """Verify that the reducer binary has been compiled."""
    assert os.path.isfile(REDUCER), "The reducer binary was not compiled (missing /app/artifact_pca/reducer)"
    assert os.access(REDUCER, os.X_OK), "The reducer file is not executable"
    with open(REDUCER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The reducer is not a compiled ELF executable"


def test_tcp_service_response():
    """Retain the original fixed service check."""
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            payload = b"EMBEDDING:1.5,2.5,3.5,4.5\n"
            s.sendall(payload)
            response = s.recv(1024)
            assert response, "No response received from the service"
            response_str = response.decode("utf-8", errors="replace")
            expected_output = "PROJECTION:4.00,8.00"
            assert expected_output in response_str, \
                f"Expected '{expected_output}' in response, but got: {response_str.strip()}"
    except ConnectionRefusedError:
        assert False, f"Connection refused on {HOST}:{PORT}. Is the TCP service running?"
    except socket.timeout:
        assert False, "Connection timed out. The service did not respond in time."
    except Exception as e:
        assert False, f"An error occurred while communicating with the service: {e}"


def test_reducer_direct_randomized_inputs():
    """Execute the rebuilt artifact on verifier-generated inputs."""
    for _ in range(8):
        values = [secrets.choice(range(-80, 81)) / 4.0 for _ in range(4)]
        payload = "EMBEDDING:" + ",".join(f"{v:.2f}" for v in values) + "\n"
        expected = f"PROJECTION:{values[0] + values[1]:.2f},{values[2] + values[3]:.2f}"
        result = run_direct(payload)
        assert result.returncode == 0, f"Reducer rejected valid input {payload!r}: {result.stdout}{result.stderr}"
        assert result.stdout.strip() == expected, \
            f"For {payload.strip()!r}, expected {expected!r}, got {result.stdout.strip()!r}"


def test_tcp_service_randomized_inputs():
    """Exercise fresh TCP connections with unpredictable projections."""
    for _ in range(8):
        values = [secrets.choice(range(-120, 121)) / 4.0 for _ in range(4)]
        payload = "EMBEDDING:" + ",".join(f"{v:.2f}" for v in values) + "\n"
        expected = f"PROJECTION:{values[0] + values[1]:.2f},{values[2] + values[3]:.2f}"
        response = query_service(payload)
        assert response.strip() == expected, \
            f"For {payload.strip()!r}, expected {expected!r}, got {response.strip()!r}"


def test_invalid_schema_is_rejected():
    for payload in ("VECTOR:1.0,2.0,3.0,4.0\n", "EMBEDDING:1.0,2.0,3.0\n"):
        result = run_direct(payload)
        assert result.returncode != 0, f"Reducer accepted malformed input: {payload!r}"
        assert "ERROR: Invalid input format" in result.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
