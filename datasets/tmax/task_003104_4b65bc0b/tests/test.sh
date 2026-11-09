#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import hashlib
import os
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

MALICIOUS_SEQ = b"\x31\xc0\x50\x68\x2f\x2f\x73\x68"
BACKEND_SECRET = secrets.token_bytes(32)
backend_records = []
backend_lock = threading.Lock()


def backend_proof(test_id):
    return hashlib.sha256(BACKEND_SECRET + test_id.encode("ascii")).hexdigest().encode("ascii")


class DummyBackendHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        test_id = self.headers.get("X-Test-ID", "")
        with backend_lock:
            backend_records.append((test_id, self.path, body))

        response = backend_proof(test_id)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope="module")
def backend_server():
    server = ThreadingHTTPServer(("127.0.0.1", 9000), DummyBackendHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)


@pytest.fixture(scope="module")
def proxy_process():
    proxy_path = "/home/user/proxy"
    assert os.path.exists(proxy_path), f"Proxy executable not found at {proxy_path}"
    assert os.access(proxy_path, os.X_OK), f"Proxy at {proxy_path} is not executable"

    proc = subprocess.Popen([proxy_path])
    time.sleep(2)
    if proc.poll() is not None:
        pytest.fail(f"Proxy process exited prematurely with code {proc.returncode}")

    yield proc
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def send_post(case):
    test_id, path, data, evil, dynamic = case
    req = urllib.request.Request(
        "http://127.0.0.1:8080" + path,
        data=data,
        method="POST",
        headers={"X-Test-ID": test_id, "Content-Type": "application/octet-stream"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return test_id, response.status, response.read(), evil, dynamic
    except urllib.error.HTTPError as exc:
        return test_id, exc.code, exc.read(), evil, dynamic


def clean_random_payload(size):
    while True:
        data = os.urandom(size)
        if MALICIOUS_SEQ not in data:
            return data


def records_for(test_id):
    with backend_lock:
        return [record for record in backend_records if record[0] == test_id]


def test_proxy_behavior(backend_server, proxy_process):
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    cases = []
    corpus_names = {}
    for fpath in clean_files:
        with open(fpath, "rb") as f:
            data = f.read()
        test_id = secrets.token_hex(16)
        cases.append((test_id, "/", data, False, False))
        corpus_names[test_id] = os.path.basename(fpath)

    for fpath in evil_files:
        with open(fpath, "rb") as f:
            data = f.read()
        test_id = secrets.token_hex(16)
        cases.append((test_id, "/", data, True, False))
        corpus_names[test_id] = os.path.basename(fpath)

    # Generate fresh cases at verification time, with random lengths and insertion
    # points, so request position and corpus filenames cannot determine the answer.
    for _ in range(12 + secrets.randbelow(9)):
        data = clean_random_payload(257 + secrets.randbelow(1800))
        test_id = secrets.token_hex(16)
        cases.append((test_id, "/case/" + secrets.token_hex(8), data, False, True))

        prefix = clean_random_payload(secrets.randbelow(900))
        suffix = clean_random_payload(secrets.randbelow(900))
        test_id = secrets.token_hex(16)
        cases.append((test_id, "/case/" + secrets.token_hex(8),
                      prefix + MALICIOUS_SEQ + suffix, True, True))

    secrets.SystemRandom().shuffle(cases)

    # Exercise the proxy concurrently and in a nondeterministic mixture of clean
    # and malicious requests.
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(send_post, cases))

    by_id = {case[0]: case for case in cases}
    clean_modified = []
    evil_bypassed = []
    extra_errors = []

    for test_id, status, response_body, evil, dynamic in results:
        _, path, data, _, _ = by_id[test_id]
        name = corpus_names.get(test_id, test_id)
        if evil:
            if status != 403:
                evil_bypassed.append(f"{name} (HTTP {status})")
        else:
            if status != 200:
                clean_modified.append(f"{name} (HTTP {status})")
            if dynamic and status == 200 and response_body != backend_proof(test_id):
                extra_errors.append(f"clean request {name} did not return the backend response")

    # Allow any improper asynchronous forwarding to reach the backend.
    time.sleep(0.5)

    for test_id, path, data, evil, dynamic in cases:
        seen = records_for(test_id)
        name = corpus_names.get(test_id, test_id)
        if evil:
            if seen:
                extra_errors.append(f"malicious request {name} reached the backend")
        else:
            if len(seen) != 1:
                extra_errors.append(
                    f"clean request {name} reached the backend {len(seen)} times instead of once"
                )
            elif seen[0][1] != path or seen[0][2] != data:
                extra_errors.append(f"clean request {name} was not forwarded intact")

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} clean modified/rejected: {', '.join(clean_modified)}"
        )
    errors.extend(extra_errors)
    assert not errors, " | ".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
