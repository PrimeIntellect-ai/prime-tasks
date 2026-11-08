#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.client
import importlib.util
import os
import queue
import random
import socket
import string
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def test_build_system():
    harness_dir = "/home/user/legacy_harness"
    tester_path = os.path.join(harness_dir, "tester")

    cmake_result = subprocess.run(["cmake", "."], cwd=harness_dir, capture_output=True, text=True)
    assert cmake_result.returncode == 0, f"cmake failed:\n{cmake_result.stderr}"

    subprocess.run(["make", "clean"], cwd=harness_dir, capture_output=True, text=True)
    if os.path.lexists(tester_path):
        os.unlink(tester_path)

    make_result = subprocess.run(["make", "VERBOSE=1"], cwd=harness_dir, capture_output=True, text=True)
    assert make_result.returncode == 0, f"make failed:\n{make_result.stderr}"

    assert os.path.isfile(tester_path), f"tester executable not found at {tester_path}"
    assert os.access(tester_path, os.X_OK), f"tester at {tester_path} is not executable"
    with open(tester_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "tester is not a compiled ELF executable"

    link_evidence = make_result.stdout + make_result.stderr
    for path in glob.glob(os.path.join(harness_dir, "CMakeFiles", "**", "link.txt"), recursive=True):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            link_evidence += "\n" + f.read()
    assert "qa_utils" in link_evidence, "tester link command does not link qa_utils"
    assert "/opt/qa_libs" in link_evidence, "tester link command does not use /opt/qa_libs"

    cases = [
        ("ordinary-" + uuid.uuid4().hex, "1"),
        ("prefix <script>" + uuid.uuid4().hex, "0"),
        (uuid.uuid4().hex + " DROP TABLE records", "0"),
        ("UNION SELECT " + uuid.uuid4().hex, "0"),
        ("Z" * 11 + uuid.uuid4().hex, "0"),
        ("Z" * 10 + "Y" + uuid.uuid4().hex, "1"),
    ]
    with tempfile.TemporaryDirectory(prefix="harness-runtime-") as td:
        for content, expected in cases:
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, "w", encoding="ascii") as f:
                f.write(content)
            result = subprocess.run([tester_path, path], capture_output=True, text=True, timeout=5)
            assert result.returncode == 0, f"tester failed at runtime: {result.stderr}"
            assert result.stdout.strip() == expected, f"tester produced the wrong result for {content!r}"


def load_sanitizer():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Missing sanitizer script: {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer is not executable: {sanitizer_path}"

    spec = importlib.util.spec_from_file_location("sanitizer", sanitizer_path)
    sanitizer = importlib.util.module_from_spec(spec)
    sys.modules["sanitizer"] = sanitizer
    try:
        spec.loader.exec_module(sanitizer)
    except Exception as e:
        pytest.fail(f"Failed to load {sanitizer_path}: {e}")
    assert hasattr(sanitizer, "analyze_payload"), "analyze_payload function is missing"
    return sanitizer


def test_adversarial_corpus():
    sanitizer = load_sanitizer()

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    for f in evil_files:
        try:
            if sanitizer.analyze_payload(f) is not False:
                evil_bypassed.append(os.path.basename(f))
        except Exception as e:
            evil_bypassed.append(f"{os.path.basename(f)} (error: {e})")

    clean_modified = []
    for f in clean_files:
        try:
            if sanitizer.analyze_payload(f) is not True:
                clean_modified.append(os.path.basename(f))
        except Exception as e:
            clean_modified.append(f"{os.path.basename(f)} (error: {e})")

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " _-.,:/"

    def token(n=40):
        return "".join(rng.choice(alphabet) for _ in range(n)) + uuid.uuid4().hex

    dynamic_cases = [
        ("", True),
        (token(), True),
        ("<SCRIPT>" + token(), True),
        ("drop table " + token(), True),
        ("union select " + token(), True),
        ("q" * 10 + "r" + token(), True),
        (token() + "<script>" + token(), False),
        (token() + "DROP TABLE" + token(), False),
        (token() + "UNION SELECT" + token(), False),
    ]
    for _ in range(12):
        ch = rng.choice(string.ascii_letters + string.digits)
        dynamic_cases.append((token() + ch * rng.randint(11, 25) + token(), False))
        dynamic_cases.append((token() + rng.choice(["<script>", "DROP TABLE", "UNION SELECT"]) + token(), False))

    with tempfile.TemporaryDirectory(prefix="hidden-payloads-") as td:
        rng.shuffle(dynamic_cases)
        for content, expected in dynamic_cases:
            path = os.path.join(td, uuid.uuid4().hex + ".dat")
            with open(path, "w", encoding="ascii") as f:
                f.write(content)
            result = sanitizer.analyze_payload(path)
            assert result is expected, f"wrong sanitizer result for generated payload {content!r}"

        missing = os.path.join(td, uuid.uuid4().hex)
        assert sanitizer.analyze_payload(missing) is False, "unreadable/missing payloads must be rejected"


class CaptureBackend(BaseHTTPRequestHandler):
    events = None

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.events.put((self.path, body, self.headers.get("X-QA-Auth")))
        response = b"backend-response-" + uuid.uuid4().hex.encode("ascii")
        self.send_response(201)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *args):
        pass


def wait_for_port(proc, port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=1)
            pytest.fail(f"proxy exited before listening (code {proc.returncode}):\n{out}\n{err}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"proxy did not listen on port {port}")


def test_proxy_configuration():
    proxy_path = "/home/user/proxy.py"
    assert os.path.isfile(proxy_path), f"Missing proxy script: {proxy_path}"
    assert os.access(proxy_path, os.X_OK), f"Proxy script is not executable: {proxy_path}"

    with open(proxy_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "8080" in content, "Proxy script does not contain the listening port 8080"
    assert "9000" in content, "Proxy script does not contain the upstream port 9000"
    assert "X-QA-Auth" in content, "Proxy script does not contain the required header 'X-QA-Auth'"
    assert "Tango42" in content, "Proxy script does not contain the required header value 'Tango42'"

    events = queue.Queue()
    CaptureBackend.events = events
    try:
        backend = HTTPServer(("127.0.0.1", 9000), CaptureBackend)
    except OSError as e:
        pytest.fail(f"could not reserve required upstream port 9000: {e}")
    backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
    backend_thread.start()

    proc = subprocess.Popen(
        [sys.executable, proxy_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_port(proc, 8080)

        safe_body = ("safe-" + uuid.uuid4().hex).encode("ascii")
        safe_path = "/submit/" + uuid.uuid4().hex
        conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
        conn.request("POST", safe_path, body=safe_body, headers={"Content-Type": "application/octet-stream"})
        response = conn.getresponse()
        response_body = response.read()
        conn.close()
        assert response.status == 201, f"safe request was not forwarded correctly (status {response.status})"
        assert response_body.startswith(b"backend-response-"), "proxy did not relay the backend response"
        forwarded_path, forwarded_body, auth = events.get(timeout=3)
        assert forwarded_path == safe_path, "proxy changed the forwarded request path"
        assert forwarded_body == safe_body, "proxy changed the forwarded request body"
        assert auth == "Tango42", "proxy did not inject X-QA-Auth: Tango42"

        evil_body = ("prefix-" + uuid.uuid4().hex + "-<script>-suffix").encode("ascii")
        conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
        conn.request("POST", "/blocked/" + uuid.uuid4().hex, body=evil_body)
        response = conn.getresponse()
        response.read()
        conn.close()
        assert response.status == 403, f"malicious request returned {response.status}, expected 403"
        time.sleep(0.4)
        assert events.empty(), "malicious request was forwarded to the backend"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        backend.shutdown()
        backend.server_close()
        backend_thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
