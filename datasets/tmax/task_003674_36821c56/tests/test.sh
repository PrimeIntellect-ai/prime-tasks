#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
WRAPPER_SCRIPT = "/home/user/test_waf.sh"
SOURCE_FILE = "/home/user/waf_service.cpp"
SERVICE_BINARY = "/home/user/waf_service"
RULE = re.compile(r"<script>|eval\(", re.IGNORECASE)


def kill_service_processes():
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == SERVICE_BINARY:
                victims.append(int(entry))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        if not any(os.path.exists(f"/proc/{pid}") for pid in victims):
            return
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def port_has_listener():
    sock = socket.socket()
    sock.settimeout(0.2)
    try:
        return sock.connect_ex(("127.0.0.1", 8080)) == 0
    finally:
        sock.close()


def post_raw(body):
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=3)
    try:
        conn.request(
            "POST",
            "/api/v1/evaluate",
            body=body,
            headers={"Content-Type": "application/json"},
        )
        response = conn.getresponse()
        response.read()
        return response.status
    finally:
        conn.close()


def expected_status(payload):
    value = payload.get("user", {}).get("input")
    return 403 if isinstance(value, str) and RULE.search(value) else 200


@pytest.fixture(scope="session")
def service_controller():
    kill_service_processes()
    assert not port_has_listener(), "Port 8080 is occupied by a process other than the submitted service."

    process = subprocess.Popen(
        [SERVICE_BINARY],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            if post_raw(b'{"user":{"input":"startup probe"}}') == 200:
                break
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    else:
        if process.poll() is not None:
            pytest.fail(f"Submitted service exited during startup with code {process.returncode}.")
        pytest.fail(f"Submitted service did not become ready on localhost:8080: {last_error}")

    controller = {"process": process, "stopped": False}

    def stop():
        if controller["stopped"]:
            return
        controller["stopped"] = True
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        kill_service_processes()

    controller["stop"] = stop
    yield controller
    stop()


def test_cpp_source_and_compiled_service_exist():
    assert os.path.isfile(SOURCE_FILE), f"C++ source {SOURCE_FILE} does not exist."
    assert os.path.getsize(SOURCE_FILE) > 0, f"C++ source {SOURCE_FILE} is empty."
    assert os.path.isfile(SERVICE_BINARY), f"Compiled service {SERVICE_BINARY} does not exist."
    assert os.access(SERVICE_BINARY, os.X_OK), f"Compiled service {SERVICE_BINARY} is not executable."
    with open(SERVICE_BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "waf_service is not a compiled ELF executable."


def test_wrapper_script_exists_and_executable():
    assert os.path.isfile(WRAPPER_SCRIPT), f"Wrapper script {WRAPPER_SCRIPT} does not exist."
    assert os.access(WRAPPER_SCRIPT, os.X_OK), f"Wrapper script {WRAPPER_SCRIPT} is not executable."


def test_service_on_generated_payloads(service_controller):
    token = uuid.uuid4().hex
    payloads = [
        {"user": {"input": f"ordinary-{token}"}},
        {"user": {"input": f"prefix <ScRiPt> suffix-{token}"}},
        {"user": {"input": f"prefix EVAL({token}) suffix"}},
        {"user": {"input": f"evaluation({token}) is harmless"}},
        {"user": {"input": f"eval ({token}) has a space"}},
        {"user": {"input": f"safe-{token}"}, "other": {"input": "<script>"}},
        {"metadata": {"value": f"eval({token})"}},
    ]
    for payload in payloads:
        body = json.dumps(payload).encode()
        assert post_raw(body) == expected_status(payload), f"Wrong status for generated payload: {payload}"


def test_malformed_json_returns_400_and_service_survives(service_controller):
    for malformed in (b'{"user":', b'not-json', b'{]'):
        assert post_raw(malformed) == 400, f"Malformed JSON did not return 400: {malformed!r}"
    valid = {"user": {"input": "still alive " + uuid.uuid4().hex}}
    assert post_raw(json.dumps(valid).encode()) == 200, "Service failed after malformed JSON requests."


def test_wrapper_on_generated_files(service_controller):
    token = uuid.uuid4().hex
    payloads = [
        {"user": {"input": f"clean-{token}"}},
        {"user": {"input": f"before <SCRIPT> after-{token}"}},
        {"user": {"input": f"before eVaL({token})"}},
        {"user": {"input": f"evaluate({token})"}},
    ]
    with tempfile.TemporaryDirectory(prefix="waf-generated-") as directory:
        for index, payload in enumerate(payloads):
            path = os.path.join(directory, f"case-{uuid.uuid4().hex}-{index}.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle)
            result = subprocess.run([WRAPPER_SCRIPT, path], capture_output=True, timeout=10)
            expected_exit = 1 if expected_status(payload) == 403 else 0
            assert result.returncode == expected_exit, f"Wrapper returned {result.returncode} for {payload}"


def test_clean_corpus_accepted(service_controller):
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No JSON files found in clean corpus."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run([WRAPPER_SCRIPT, filepath], capture_output=True, timeout=10)
        if result.returncode != 0:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (or script failed): {failed_files}"


def test_evil_corpus_rejected(service_controller):
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No JSON files found in evil corpus."

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run([WRAPPER_SCRIPT, filepath], capture_output=True, timeout=10)
        if result.returncode != 1:
            bypassed_files.append((filename, result.returncode))

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil payloads bypassed the WAF (expected exit code 1): {[f[0] for f in bypassed_files]}"


def run_wrapper_against_mock(path, response_status):
    records = []

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            records.append((self.path, self.rfile.read(length)))
            self.send_response(response_status)
            self.end_headers()

        def do_GET(self):
            self.send_response(404)
            self.end_headers()

        def log_message(self, format, *args):
            pass

    server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run([WRAPPER_SCRIPT, path], capture_output=True, timeout=10)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
        kill_service_processes()
    return result, records


def test_wrapper_posts_file_and_maps_actual_http_status(service_controller):
    service_controller["stop"]()
    assert not port_has_listener(), "Submitted service did not stop before wrapper transport test."

    with tempfile.TemporaryDirectory(prefix="waf-wrapper-transport-") as directory:
        cases = [
            ({"user": {"input": "<script>mock says allow"}}, 200, 0),
            ({"user": {"input": "clean but mock says deny"}}, 403, 1),
        ]
        for payload, response_status, expected_exit in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".json")
            body = json.dumps(payload).encode()
            with open(path, "wb") as handle:
                handle.write(body)
            result, records = run_wrapper_against_mock(path, response_status)
            assert result.returncode == expected_exit, (
                f"Wrapper did not map HTTP {response_status} to exit code {expected_exit}."
            )
            assert any(request_path == "/api/v1/evaluate" and request_body == body
                       for request_path, request_body in records), (
                "Wrapper did not POST the supplied JSON file to /api/v1/evaluate."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
