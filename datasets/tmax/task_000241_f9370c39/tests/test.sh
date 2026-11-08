#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import socket
import urllib.request
import urllib.error
import pytest
import importlib.util
import secrets
import redis


def load_sanitizer():
    sanitizer_path = '/home/user/sanitizer.py'
    assert os.path.isfile(sanitizer_path), f"Sanitizer module not found at {sanitizer_path}"

    spec = importlib.util.spec_from_file_location("sanitizer", sanitizer_path)
    sanitizer = importlib.util.module_from_spec(spec)
    sys.modules["sanitizer"] = sanitizer
    try:
        spec.loader.exec_module(sanitizer)
    except Exception as e:
        pytest.fail(f"Failed to load sanitizer.py: {e}")

    assert hasattr(sanitizer, 'is_safe'), "sanitizer.py does not define is_safe function"
    return sanitizer.is_safe


def post(url, payload, timeout=3):
    req = urllib.request.Request(url, data=payload, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to POST to {url}: {e}")


def test_sanitizer_adversarial_corpus():
    is_safe = load_sanitizer()

    evil_dir = '/home/user/corpus/evil/'
    clean_dir = '/home/user/corpus/clean/'

    evil_files = sorted([f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))])
    clean_files = sorted([f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))])

    assert len(evil_files) > 0, "Evil corpus is empty"
    assert len(clean_files) > 0, "Clean corpus is empty"

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        with open(os.path.join(evil_dir, f), 'rb') as file:
            content = file.read()
            try:
                if is_safe(content) is not False:
                    evil_bypassed.append(f)
            except Exception:
                evil_bypassed.append(f)

    for f in clean_files:
        with open(os.path.join(clean_dir, f), 'rb') as file:
            content = file.read()
            try:
                if is_safe(content) is not True:
                    clean_modified.append(f)
            except Exception:
                clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {clean_modified}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitizer_generated_cases():
    is_safe = load_sanitizer()

    # These cases are generated at verification time so matching the fixed corpus,
    # the word "Evil", or the two fixed end-to-end bodies is insufficient.
    for _ in range(20):
        nonce = secrets.token_hex(12)
        safe_objects = [
            {"nonce": nonce, "message": f"Evil but ordinary log {nonce}"},
            {"message": f"ud800 is plain text {nonce}", "nested": [1, True, None]},
            {"message": f"near miss \\ud801 {nonce}", "kind": "clean"},
        ]
        for obj in safe_objects:
            raw = json.dumps(obj, separators=(',', ':')).encode('utf-8')
            try:
                result = is_safe(raw)
            except Exception as e:
                pytest.fail(f"is_safe raised on generated safe input: {e}")
            assert result is True, f"Generated safe payload was rejected: {raw!r}"

        # The processor checks the decoded request bytes before JSON parsing, so
        # varied structures containing the crashing escape must all be rejected.
        unsafe_payloads = [
            ('{"nonce":"%s","message":"prefix-%s\\ud800-suffix"}' % (nonce, nonce)).encode(),
            (' { "outer" : { "value" : "\\ud800", "nonce" : "%s" } } ' % nonce).encode(),
            ('["%s", {"different_key":"\\ud800"}]' % nonce).encode(),
            b'{"nonce":"' + nonce.encode() + b'","message":"bad-utf8-\xff"}',
            b'\x80' + nonce.encode(),
        ]
        for raw in unsafe_payloads:
            try:
                result = is_safe(raw)
            except Exception as e:
                pytest.fail(f"is_safe raised on generated unsafe input: {e}")
            assert result is False, f"Generated crashing payload bypassed sanitizer: {raw!r}"


def test_router_config_updated():
    config_path = '/home/user/router_config.json'
    assert os.path.isfile(config_path), f"Router config not found at {config_path}"
    with open(config_path, 'r') as f:
        config = json.load(f)
    assert config.get("downstream_url") == "http://127.0.0.1:8082", "Router config downstream_url not updated to point to the proxy (http://127.0.0.1:8082)"


def test_proxy_running():
    assert os.path.isfile('/home/user/proxy.py'), "Proxy implementation not found at /home/user/proxy.py"
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        try:
            s.connect(('127.0.0.1', 8082))
        except (ConnectionRefusedError, socket.timeout, OSError):
            pytest.fail("Proxy is not listening on 127.0.0.1:8082")


def test_generated_end_to_end_forwarding_and_persistence():
    r = redis.Redis(host='127.0.0.1', port=6379, db=0, socket_timeout=2)
    try:
        assert r.ping()
    except Exception as e:
        pytest.fail(f"Redis is unavailable: {e}")

    r.delete('logs')

    # Unique bodies prove that the proxy handles non-fixed inputs. Their presence
    # in the processor's Redis output proves successful requests reached the
    # downstream processing path rather than receiving a fabricated proxy reply.
    expected = []
    for _ in range(6):
        nonce = secrets.token_hex(16)
        obj = {
            "verification_nonce": nonce,
            "message": f"Evil is harmless text here: {secrets.token_hex(7)}",
            "values": [secrets.randbelow(1000000), True, None],
        }
        payload = json.dumps(obj, separators=(',', ':')).encode('utf-8')
        status, _ = post('http://127.0.0.1:8080', payload)
        assert status in (200, 201, 202, 204), f"Expected success for generated safe payload, got {status}"
        expected.append(obj)

    stored_raw = r.lrange('logs', 0, -1)
    stored = []
    for item in stored_raw:
        try:
            stored.append(json.loads(item.decode('utf-8')))
        except Exception as e:
            pytest.fail(f"Processor stored a malformed Redis entry: {e}")
    for obj in expected:
        assert obj in stored, f"Generated safe payload was not persisted by the processor: {obj!r}"

    before = r.llen('logs')
    for _ in range(5):
        nonce = secrets.token_hex(15)
        payload = ('{"verification_nonce":"%s","data":{"message":"%s\\ud800%s"}}' %
                   (nonce, secrets.token_hex(4), secrets.token_hex(4))).encode('ascii')
        status, _ = post('http://127.0.0.1:8080', payload)
        assert status == 400, f"Expected 400 for generated crashing payload, got {status}"
        assert r.llen('logs') == before, "Rejected payload was unexpectedly persisted in Redis"

    invalid_utf8 = b'{"verification_nonce":"' + secrets.token_hex(12).encode() + b'","message":"\xff"}'
    status, _ = post('http://127.0.0.1:8080', invalid_utf8)
    assert status == 400, f"Expected 400 for invalid UTF-8 payload, got {status}"
    assert r.llen('logs') == before, "Invalid UTF-8 payload was unexpectedly persisted in Redis"


def test_end_to_end_flow():
    # Test safe payload
    safe_payload = b'{"timestamp": "2023-10-01T12:00:00Z", "message": "Normal log message"}'
    req = urllib.request.Request('http://127.0.0.1:8080', data=safe_payload, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status in (200, 201, 202, 204), f"Expected success status for safe payload, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to send safe payload to router: {e}")

    # Test evil payload
    evil_payload = b'{"timestamp": "2023-10-01T12:00:01Z", "message": "Evil log message \\ud800"}'
    req = urllib.request.Request('http://127.0.0.1:8080', data=evil_payload, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            pytest.fail(f"Expected 400 series error for evil payload, but request succeeded with status {response.status}")
    except urllib.error.HTTPError as e:
        assert 400 <= e.code < 500, f"Expected 400 series error for evil payload, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to send evil payload to router: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
