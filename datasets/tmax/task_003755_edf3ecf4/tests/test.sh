#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import hashlib
import hmac
import json
import os
import random
import secrets
import string
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

RNG = random.SystemRandom()


def random_key():
    return "k_" + secrets.token_hex(8)


def nested_object(value, depth):
    result = value
    for _ in range(depth):
        result = {random_key(): result}
    return result


def mixed_case_drop_table():
    return "".join(c.upper() if RNG.randrange(2) else c.lower() for c in "DROP TABLE")


def make_detector_cases():
    evil = [
        {"a": {"b": {"c": {"d": {"execute": "something"}}}}},
        {"query": "SELECT * FROM users; DROP TABLE admin;"},
        {"nested": {"test": "drop table users"}},
    ]
    clean = [
        {"execute": "safe"},
        {"a": {"b": {"c": {"execute": "safe"}}}},
        {"query": "SELECT * FROM users;"},
        {"message": "Please drop the table at the restaurant"},
    ]

    for _ in range(RNG.randint(24, 34)):
        marker = secrets.token_hex(12)
        depth = RNG.randint(4, 9)
        evil.append(nested_object({"execute": marker}, depth))

        drop_value = "prefix-" + mixed_case_drop_table() + "-" + marker
        evil.append(nested_object({random_key(): [marker, {random_key(): drop_value}]}, RNG.randint(0, 7)))

    for _ in range(RNG.randint(28, 38)):
        marker = secrets.token_hex(12)
        clean.append(nested_object({"execute": marker}, RNG.randint(0, 3)))
        clean.append(nested_object({random_key(): [marker, "DROP  TABLE", "drop the table"]}, RNG.randint(0, 7)))

    return evil, clean


def test_detector_adversarial_corpus():
    detector_path = "/home/user/detector"
    assert os.path.exists(detector_path), f"Detector not found at {detector_path}"
    assert os.path.isfile(detector_path), f"Detector at {detector_path} is not a regular file"
    assert os.access(detector_path, os.X_OK), f"Detector at {detector_path} is not executable"

    evil_payloads, clean_payloads = make_detector_cases()

    with tempfile.TemporaryDirectory(prefix="json_detector_cases_") as corpus_dir:
        evil_files = []
        clean_files = []

        for payload in evil_payloads:
            path = os.path.join(corpus_dir, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f, separators=(",", ":"))
            evil_files.append(path)

        for payload in clean_payloads:
            path = os.path.join(corpus_dir, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f, separators=(",", ":"))
            clean_files.append(path)

        assert len(evil_files) > 0, "No evil corpus files found."
        assert len(clean_files) > 0, "No clean corpus files found."

        cases = [(path, 1) for path in evil_files] + [(path, 0) for path in clean_files]
        RNG.shuffle(cases)

        evil_bypassed = []
        clean_modified = []
        for filepath, expected in cases:
            try:
                result = subprocess.run([detector_path, filepath], capture_output=True, timeout=4)
            except subprocess.TimeoutExpired:
                pytest.fail(f"Detector timed out on {os.path.basename(filepath)}")
            if expected == 1 and result.returncode != 1:
                evil_bypassed.append(os.path.basename(filepath))
            if expected == 0 and result.returncode != 0:
                clean_modified.append(os.path.basename(filepath))

        error_msgs = []
        if evil_bypassed:
            error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

        assert not error_msgs, " | ".join(error_msgs)


class DummyBackendHandler(BaseHTTPRequestHandler):
    secret = b""
    received = []

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        type(self).received.append((self.path, body))
        signature = hmac.new(type(self).secret, body, hashlib.sha256).hexdigest().encode("ascii")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK:" + signature)

    def log_message(self, format, *args):
        pass


def backend_response(body):
    signature = hmac.new(DummyBackendHandler.secret, body, hashlib.sha256).hexdigest().encode("ascii")
    return b"OK:" + signature


def encode_payload(payload):
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def test_reverse_proxy_filtering():
    DummyBackendHandler.secret = secrets.token_bytes(32)
    DummyBackendHandler.received = []

    server = HTTPServer(("127.0.0.1", 9090), DummyBackendHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    time.sleep(1)

    evil_payloads = [
        b'{"a": {"b": {"c": {"d": {"execute": "something"}}}}}',
        b'{"query": "SELECT * FROM users; DROP TABLE admin;"}',
        b'{"nested": {"test": "drop table users"}}',
    ]

    clean_payloads = [
        b'{"execute": "safe"}',
        b'{"a": {"b": {"c": {"execute": "safe"}}}}',
        b'{"query": "SELECT * FROM users;"}',
        b'{"message": "Please drop the table at the restaurant"}',
    ]

    all_clean_bodies = list(clean_payloads)
    all_evil_bodies = list(evil_payloads)

    try:
        evil_bypassed = 0
        for i, payload in enumerate(evil_payloads):
            req = urllib.request.Request("http://127.0.0.1:8080", data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            try:
                urllib.request.urlopen(req, timeout=3)
                evil_bypassed += 1
            except urllib.error.HTTPError as e:
                assert e.code == 403, f"Evil payload {i} got HTTP {e.code} instead of 403"
            except urllib.error.URLError as e:
                pytest.fail(f"Proxy not reachable or connection error: {e}")

        clean_blocked = 0
        for i, payload in enumerate(clean_payloads):
            req = urllib.request.Request("http://127.0.0.1:8080", data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            try:
                resp = urllib.request.urlopen(req, timeout=3)
                assert resp.getcode() == 200, f"Clean payload {i} got HTTP {resp.getcode()} instead of 200"
                assert resp.read() == backend_response(payload), f"Clean payload {i} was not transparently forwarded"
            except urllib.error.HTTPError:
                clean_blocked += 1
            except urllib.error.URLError as e:
                pytest.fail(f"Proxy not reachable or connection error: {e}")

        assert evil_bypassed == 0, f"{evil_bypassed} of {len(evil_payloads)} evil payloads bypassed the proxy"
        assert clean_blocked == 0, f"{clean_blocked} of {len(clean_payloads)} clean payloads were blocked by the proxy"

        randomized_cases = []
        for _ in range(RNG.randint(18, 26)):
            marker = secrets.token_hex(12)
            if RNG.randrange(2):
                payload = nested_object({"execute": marker}, RNG.randint(4, 10))
            else:
                payload = nested_object({random_key(): [marker, mixed_case_drop_table() + marker]}, RNG.randint(0, 8))
            body = encode_payload(payload)
            randomized_cases.append((body, True, "/" + secrets.token_hex(8)))
            all_evil_bodies.append(body)

        for _ in range(RNG.randint(18, 26)):
            marker = secrets.token_hex(12)
            if RNG.randrange(2):
                payload = nested_object({"execute": marker}, RNG.randint(0, 3))
            else:
                payload = nested_object({random_key(): [marker, "drop the table", "DROP  TABLE"]}, RNG.randint(0, 8))
            body = encode_payload(payload)
            randomized_cases.append((body, False, "/" + secrets.token_hex(8)))
            all_clean_bodies.append(body)

        RNG.shuffle(randomized_cases)
        random_evil_bypassed = 0
        random_clean_blocked = 0

        for i, (payload, is_evil, path) in enumerate(randomized_cases):
            req = urllib.request.Request("http://127.0.0.1:8080" + path, data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            try:
                resp = urllib.request.urlopen(req, timeout=3)
                if is_evil:
                    random_evil_bypassed += 1
                else:
                    assert resp.getcode() == 200, f"Random clean payload {i} got HTTP {resp.getcode()} instead of 200"
                    assert resp.read() == backend_response(payload), f"Random clean payload {i} was not forwarded to the backend"
            except urllib.error.HTTPError as e:
                if is_evil:
                    assert e.code == 403, f"Random evil payload {i} got HTTP {e.code} instead of 403"
                else:
                    random_clean_blocked += 1
            except urllib.error.URLError as e:
                pytest.fail(f"Proxy not reachable or connection error: {e}")

        assert random_evil_bypassed == 0, f"{random_evil_bypassed} randomized evil payloads bypassed the proxy"
        assert random_clean_blocked == 0, f"{random_clean_blocked} randomized clean payloads were blocked by the proxy"

        received_bodies = [body for _, body in DummyBackendHandler.received]
        evil_forwarded = [body for body in received_bodies if body in set(all_evil_bodies)]
        assert not evil_forwarded, f"Proxy forwarded {len(evil_forwarded)} malicious requests to the backend"
        assert collections.Counter(received_bodies) == collections.Counter(all_clean_bodies), "Proxy did not forward exactly the clean requests"
    finally:
        server.shutdown()
        server.server_close()
        t.join(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
