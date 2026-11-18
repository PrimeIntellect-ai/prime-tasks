#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import re
import socket
import string
import struct
import subprocess
import time
import urllib.request

import pytest


def rot13(data):
    out = bytearray(data)
    for i, value in enumerate(out):
        if ord('a') <= value <= ord('z'):
            out[i] = (value - ord('a') + 13) % 26 + ord('a')
        elif ord('A') <= value <= ord('Z'):
            out[i] = (value - ord('A') + 13) % 26 + ord('A')
    return bytes(out)


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def wait_for_port(port, proc, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"{proc.args!r} exited early with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"process did not listen on TCP port {port}")


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def daemon_request(data):
    with socket.create_connection(("127.0.0.1", 9000), timeout=2) as sock:
        sock.settimeout(2)
        sock.sendall(struct.pack("<I", len(data)) + data)
        chunks = []
        remaining = len(data)
        while remaining:
            chunk = sock.recv(remaining)
            assert chunk, "worker daemon closed the connection before returning the full result"
            chunks.append(chunk)
            remaining -= len(chunk)
        assert sock.recv(1) == b"", "worker daemon returned extra bytes"
        return b"".join(chunks)


def test_gateway_env():
    """Verify that the gateway .env file is correctly and unambiguously configured."""
    env_path = "/app/gateway/.env"
    assert os.path.isfile(env_path), f"Gateway .env file missing at {env_path}"

    with open(env_path, "r") as f:
        content = f.read()

    assert "GATEWAY_PORT=8080" in content, "GATEWAY_PORT is not correctly set in .env"
    assert "WORKER_ADDR=127.0.0.1:9000" in content, "WORKER_ADDR is not correctly set in .env"

    assignments = {}
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", line)
        if not match:
            continue
        key, value = match.groups()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        else:
            value = re.split(r"\s+#", value, maxsplit=1)[0].rstrip()
        assignments.setdefault(key, []).append(value)

    assert assignments.get("GATEWAY_PORT") == ["8080"], \
        "GATEWAY_PORT must have exactly one effective assignment, to 8080"
    assert assignments.get("WORKER_ADDR") == ["127.0.0.1:9000"], \
        "WORKER_ADDR must have exactly one effective assignment, to 127.0.0.1:9000"


def test_worker_daemon_compiled():
    """Verify that worker_daemon is compiled, executable, and implements its TCP protocol."""
    daemon_path = "/app/c_worker/worker_daemon"
    assert os.path.isfile(daemon_path), f"worker_daemon not found at {daemon_path}"
    assert os.access(daemon_path, os.X_OK), f"worker_daemon at {daemon_path} is not executable"
    assert_elf(daemon_path)

    proc = subprocess.Popen(
        [daemon_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_port(9000, proc)
        samples = [b"Hello, World!", b"ABCDEFGHIJKLMNOPQRSTUVWXYZ", b"n0-punctuation_123"]
        rng = random.Random(314159)
        alphabet = (string.ascii_letters + string.digits + string.punctuation + " ").encode("ascii")
        for _ in range(25):
            samples.append(bytes(rng.choice(alphabet) for _ in range(rng.randint(1, 2048))))
        for data in samples:
            assert daemon_request(data) == rot13(data)
        assert proc.poll() is None, "worker daemon exited while processing requests"
    finally:
        stop_process(proc)


def test_gateway_worker_end_to_end():
    """Boot the supplied services and verify the configured HTTP-to-TCP workflow."""
    daemon_path = "/app/c_worker/worker_daemon"
    gateway_path = "/app/gateway/gateway_service"
    assert os.path.isfile(gateway_path), f"gateway_service not found at {gateway_path}"
    assert os.access(gateway_path, os.X_OK), f"gateway_service at {gateway_path} is not executable"

    daemon = subprocess.Popen(
        [daemon_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    gateway = None
    try:
        wait_for_port(9000, daemon)
        clean_env = os.environ.copy()
        clean_env.pop("GATEWAY_PORT", None)
        clean_env.pop("WORKER_ADDR", None)
        gateway = subprocess.Popen(
            [gateway_path],
            cwd="/app/gateway",
            env=clean_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_for_port(8080, gateway)

        for text in ["GatewayToWorker", "Hello, World! 123", "AbCdEfGhIjKlMnOpQrStUvWxYz"]:
            body = json.dumps({"payload": text}).encode("utf-8")
            request = urllib.request.Request(
                "http://127.0.0.1:8080/process",
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=3) as response:
                assert response.status == 200
                result = json.loads(response.read().decode("utf-8"))
            assert result == {"result": rot13(text.encode("ascii")).decode("ascii")}
    finally:
        if gateway is not None:
            stop_process(gateway)
        stop_process(daemon)


def test_transformer_fuzz_equivalence():
    """Verify that the transformer binary perfectly matches the oracle on 1000 random inputs."""
    agent_bin = "/app/c_worker/transformer"
    oracle_bin = "/app/reference/transformer_oracle"

    assert os.path.isfile(agent_bin), f"transformer binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"transformer at {agent_bin} is not executable"

    assert os.path.isfile(oracle_bin), f"oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"oracle at {oracle_bin} is not executable"
    assert not filecmp.cmp(agent_bin, oracle_bin, shallow=False), \
        "transformer must not be a byte-identical copy of the reference binary"

    random.seed(42)
    printable_chars = string.ascii_letters + string.digits + string.punctuation + " "

    for i in range(1000):
        L = random.randint(1, 4096)
        ascii_data = "".join(random.choices(printable_chars, k=L)).encode("ascii")
        payload = struct.pack("<I", L) + ascii_data

        try:
            oracle_proc = subprocess.run([oracle_bin], input=payload, capture_output=True, timeout=2)
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on iteration {i} with input length {L}")

        try:
            agent_proc = subprocess.run([agent_bin], input=payload, capture_output=True, timeout=2)
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent binary timed out on iteration {i} with input length {L}")

        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch on iteration {i} (input length {L}).\n"
                f"Input payload (first 50 bytes): {payload[:50]!r}...\n"
                f"Expected output (first 50 bytes): {oracle_out[:50]!r}...\n"
                f"Agent output (first 50 bytes): {agent_out[:50]!r}..."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
