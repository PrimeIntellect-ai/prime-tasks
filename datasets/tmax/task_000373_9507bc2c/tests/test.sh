#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import time

import numpy as np
import pytest

HOST = "127.0.0.1"
PORT = 8080
SOURCE = "/home/user/data_server.c"
BINARY = "/tmp/verified_data_server"


def expected_responses():
    data = np.loadtxt("/app/dataset.csv", delimiter=",", dtype=np.int64)
    assert data.shape == (100, 3)
    clean_data = np.delete(data, [15, 42, 78], axis=0)
    cov = np.cov(clean_data, rowvar=False, bias=True)
    cov_text = " ".join(f"{x:.3f}" for x in cov.flatten())
    trace_text = f"{np.trace(cov):.3f}"
    return cov_text, trace_text


def kill_port_listeners(port):
    inodes = set()
    target = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == target and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(victims):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                victims.discard(pid)
        if victims:
            time.sleep(0.25)


def receive_response(command):
    with socket.create_connection((HOST, PORT), timeout=5) as s:
        s.settimeout(5)
        s.sendall(command)
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
        return b"".join(chunks)


@pytest.fixture(scope="session", autouse=True)
def compiled_c_server():
    assert os.path.isfile(SOURCE), f"Required C source {SOURCE} is missing."
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Failed to compile {SOURCE}:\n{result.stderr}"

    kill_port_listeners(PORT)
    proc = subprocess.Popen(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        stderr = ""
        if proc.poll() is not None and proc.stderr is not None:
            stderr = proc.stderr.read().decode("utf-8", errors="replace")
        proc.kill()
        pytest.fail(f"Compiled C server did not listen on {HOST}:{PORT}. {stderr}")

    yield

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
    kill_port_listeners(PORT)


def test_server_cov_response():
    expected_cov, _ = expected_responses()
    try:
        raw = receive_response(b"COV\n")
        response = raw.decode("ascii").strip()
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}")
    except socket.timeout:
        pytest.fail(f"Server at {HOST}:{PORT} timed out waiting for COV response.")

    assert response == expected_cov, f"Expected COV response '{expected_cov}', got '{response}'"
    assert raw == (expected_cov + "\n").encode("ascii"), "COV response must have exact formatting and one trailing newline."


def test_server_trace_response():
    _, expected_trace = expected_responses()
    try:
        raw = receive_response(b"TRACE\n")
        response = raw.decode("ascii").strip()
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}")
    except socket.timeout:
        pytest.fail(f"Server at {HOST}:{PORT} timed out waiting for TRACE response.")

    assert response == expected_trace, f"Expected TRACE response '{expected_trace}', got '{response}'"
    assert raw == (expected_trace + "\n").encode("ascii"), "TRACE response must have exact formatting and one trailing newline."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
