#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import struct
import subprocess
import tempfile
import time

import pytest
import requests
from scapy.all import IP, TCP, Raw, rdpcap

MODULUS = 104729


def read_exact(sock, count):
    data = b''
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            break
        data += chunk
    return data


def backend_request(val):
    start_time = time.time()
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        s.connect(('127.0.0.1', 9090))
        s.sendall(struct.pack('<q', val))
        response = read_exact(s, 8)
    return response, time.time() - start_time


def test_http_gateway():
    """Verify the HTTP Gateway correctly processes requests and responds quickly."""
    url = "http://127.0.0.1:8080/compute?val=1000"
    start_time = time.time()
    try:
        response = requests.get(url, timeout=2.0)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP Gateway request failed or timed out: {e}")

    elapsed = time.time() - start_time
    assert elapsed < 0.2, f"HTTP Gateway is too slow ({elapsed:.3f}s). The performance bug might not be fixed."
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")

    assert "result" in data, f"Response JSON missing 'result' key. Got: {data}"
    assert data["result"] == 57429, f"Expected result 57429 (1000^2 % 104729), got {data['result']}"


def test_tcp_backend():
    """Verify the raw TCP Backend conforms to the binary protocol and responds quickly."""
    start_time = time.time()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(('127.0.0.1', 9090))
        req_data = struct.pack('<q', 32)
        s.sendall(req_data)
        resp_data = read_exact(s, 8)
        s.close()
    except Exception as e:
        pytest.fail(f"TCP Backend request failed or timed out: {e}")

    elapsed = time.time() - start_time
    assert elapsed < 0.2, f"TCP Backend is too slow ({elapsed:.3f}s). The performance bug might not be fixed."
    assert len(resp_data) == 8, f"Expected 8 bytes from backend, got {len(resp_data)} bytes: {resp_data!r}"

    result = struct.unpack('<q', resp_data)[0]
    assert result == 1024, f"Expected result 1024 (32^2 % 104729), got {result}"


def test_runtime_generated_inputs():
    """Exercise both interfaces on values selected only when verification runs."""
    rng = secrets.SystemRandom()
    values = []
    while len(values) < 8:
        value = rng.randrange(-(2**40), 2**40)
        if value not in values and value not in (32, 1000):
            values.append(value)

    for value in values:
        expected = pow(value, 2, MODULUS)

        resp_data, elapsed = backend_request(value)
        assert elapsed < 0.2, f"TCP Backend is too slow for {value} ({elapsed:.3f}s)"
        assert len(resp_data) == 8, f"Expected 8 bytes from backend for {value}, got {len(resp_data)}"
        assert struct.unpack('<q', resp_data)[0] == expected, f"Wrong backend result for runtime value {value}"

        start_time = time.time()
        try:
            response = requests.get('http://127.0.0.1:8080/compute', params={'val': str(value)}, timeout=2.0)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"HTTP Gateway failed for runtime value {value}: {e}")
        elapsed = time.time() - start_time
        assert elapsed < 0.2, f"HTTP Gateway is too slow for {value} ({elapsed:.3f}s)"
        assert response.status_code == 200, f"Expected HTTP 200 for {value}, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Expected JSON response for {value}, got: {response.text}")
        assert "result" in data, f"Response JSON missing 'result' for {value}: {data}"
        assert data["result"] == expected, f"Wrong gateway result for runtime value {value}"


def test_gateway_forwards_to_backend():
    """Observe a fresh gateway request traversing the required TCP backend protocol."""
    rng = secrets.SystemRandom()
    value = rng.randrange(-(2**48), 2**48)
    expected = pow(value, 2, MODULUS)
    request_bytes = struct.pack('<q', value)
    response_bytes = struct.pack('<q', expected)

    fd, capture_path = tempfile.mkstemp(suffix='.pcap')
    os.close(fd)
    os.unlink(capture_path)
    capture = subprocess.Popen(
        ['tcpdump', '-i', 'lo', '-n', '-s', '0', '-U', '-w', capture_path, 'tcp port 9090'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(0.3)
        assert capture.poll() is None, "tcpdump could not start to observe backend traffic"
        response = requests.get(
            'http://127.0.0.1:8080/compute', params={'val': str(value)}, timeout=2.0
        )
        assert response.status_code == 200
        assert response.json().get('result') == expected
        time.sleep(0.2)
    finally:
        if capture.poll() is None:
            capture.terminate()
        try:
            capture.communicate(timeout=2.0)
        except subprocess.TimeoutExpired:
            capture.kill()
            capture.communicate()

    assert os.path.exists(capture_path), "No backend traffic capture was produced"
    packets = rdpcap(capture_path)
    os.unlink(capture_path)

    client_payloads = []
    backend_payloads = []
    for packet in packets:
        if IP not in packet or TCP not in packet or Raw not in packet:
            continue
        payload = bytes(packet[Raw].load)
        if packet[TCP].dport == 9090:
            client_payloads.append(payload)
        if packet[TCP].sport == 9090:
            backend_payloads.append(payload)

    assert any(request_bytes in payload for payload in client_payloads), (
        "The gateway did not forward the runtime-selected value to TCP port 9090 "
        "as a little-endian 64-bit integer"
    )
    assert any(response_bytes in payload for payload in backend_payloads), (
        "The gateway request did not receive the expected little-endian 64-bit response from the backend"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
