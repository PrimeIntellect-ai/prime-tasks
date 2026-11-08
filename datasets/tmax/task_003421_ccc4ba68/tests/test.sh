#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import secrets
import socket
import struct

import pytest
import requests


def get_expected_signature():
    seed = 1
    vals = [4294967295, 1, 2, 3]
    for v in vals:
        seed = (seed * v) & 0xFFFFFFFFFFFFFFFF

    while seed % 10007 != 0:
        seed = (seed * 1337 + 1) & 0xFFFFFFFFFFFFFFFF
    return str(seed)


PAYLOAD = b'\xFF\xFF\xFF\xFF\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00'


def expected_for_payload(payload, iteration_limit=None):
    vals = struct.unpack('<IIII', payload)
    seed = 1
    for value in vals:
        seed = (seed * value) & 0xFFFFFFFFFFFFFFFF

    iterations = 0
    while seed % 10007 != 0:
        seed = (seed * 1337 + 1) & 0xFFFFFFFFFFFFFFFF
        iterations += 1
        if iteration_limit is not None and iterations > iteration_limit:
            return None
    return str(seed)


def make_random_cases(count=4):
    cases = []
    seen = {PAYLOAD}
    while len(cases) < count:
        payload = bytearray(secrets.token_bytes(16))
        # Every case contains an unsigned word above INT32_MAX.
        payload[3] |= 0x80
        payload = bytes(payload)
        if payload in seen:
            continue
        expected = expected_for_payload(payload, iteration_limit=30000)
        if expected is not None:
            seen.add(payload)
            cases.append((payload, expected))
    return cases


RANDOM_CASES = make_random_cases()


def backend_request(payload):
    try:
        with socket.create_connection(('127.0.0.1', 8081), timeout=3.0) as sock:
            sock.sendall(payload)
            return sock.recv(1024)
    except ConnectionRefusedError:
        pytest.fail('Backend crypto node is not listening on 127.0.0.1:8081')
    except socket.timeout:
        pytest.fail('Backend crypto node timed out. The signed integer bug might still exist.')


def frontend_request(payload):
    try:
        return requests.post(
            'http://127.0.0.1:8080/analyze',
            data=payload,
            timeout=3.0,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail('Frontend gateway is not listening on 127.0.0.1:8080')
    except requests.exceptions.Timeout:
        pytest.fail('Frontend gateway timed out. It might be misconfigured or blocked.')


def test_backend_tcp_service():
    expected_sig = get_expected_signature().encode()
    res = backend_request(PAYLOAD)
    assert res != b'ERROR', 'Backend returned ERROR. The unpacking logic might still be failing.'
    assert res == expected_sig, f'Backend returned incorrect signature: {res} (expected {expected_sig})'


def test_frontend_http_service():
    expected_sig = get_expected_signature()
    response = frontend_request(PAYLOAD)
    assert response.status_code == 200, f'Expected HTTP 200 OK, got {response.status_code}. The gateway port bug might still exist.'

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f'Gateway did not return valid JSON. Response body: {response.text}')

    assert data.get('status') == 'success', f"Expected status 'success', got {data.get('status')}"
    assert data.get('signature') == expected_sig, f"Gateway returned incorrect signature: {data.get('signature')} (expected {expected_sig})"


@pytest.mark.parametrize('payload,expected', RANDOM_CASES)
def test_backend_on_unpredictable_payloads(payload, expected):
    res = backend_request(payload)
    assert res != b'ERROR', 'Backend returned ERROR for a randomized high-bit payload.'
    assert res == expected.encode(), f'Backend returned incorrect signature for {payload.hex()}: {res!r}'


@pytest.mark.parametrize('payload,expected', RANDOM_CASES)
def test_frontend_on_unpredictable_payloads(payload, expected):
    response = frontend_request(payload)
    assert response.status_code == 200, f'Expected HTTP 200 OK, got {response.status_code}'
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f'Gateway did not return valid JSON. Response body: {response.text}')
    assert data.get('status') == 'success', f"Expected status 'success', got {data.get('status')}"
    assert data.get('signature') == expected, f"Gateway returned incorrect signature for {payload.hex()}: {data.get('signature')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
