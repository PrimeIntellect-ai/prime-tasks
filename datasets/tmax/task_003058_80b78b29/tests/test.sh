#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import random
import re
import secrets
import shutil
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

SCRIPT_PATH = "/home/user/sequence_classifier.sh"
CLEAN_CORPUS = "/app/data/clean"
EVIL_CORPUS = "/app/data/evil"
REJECTED_LOG = "/home/user/rejected.log"
API_PATH = "/app/services/api/app.py"
NGINX_CONF = "/app/services/nginx/nginx.conf"
TEST_CLEAN_OUT = "/home/user/test_clean_out"
TEST_EVIL_OUT = "/home/user/test_evil_out"
DYNAMIC_ROOT = "/tmp/sequence_classifier_dynamic"
DYNAMIC_IN = os.path.join(DYNAMIC_ROOT, "input")
DYNAMIC_OUT = os.path.join(DYNAMIC_ROOT, "output")

STATE = {}


def post_json(url, payload, timeout=5):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, json.loads(response.read().decode())


def wait_port_closed(port):
    deadline = time.time() + 5
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.2)
        try:
            if sock.connect_ex(("127.0.0.1", port)) != 0:
                return
        finally:
            sock.close()
        time.sleep(0.1)
    raise AssertionError(f"Port {port} did not close")


def parse_api_configuration():
    assert os.path.isfile(API_PATH), f"Flask application missing: {API_PATH}"
    with open(API_PATH) as f:
        tree = ast.parse(f.read(), API_PATH)

    redis_host = None
    redis_port = None
    flask_port = None
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and node.func.attr == "Redis":
            values = {kw.arg: kw.value for kw in node.keywords if kw.arg}
            if "host" in values and isinstance(values["host"], ast.Constant):
                redis_host = values["host"].value
            if "port" in values and isinstance(values["port"], ast.Constant):
                redis_port = values["port"].value
        if isinstance(node.func, ast.Attribute) and node.func.attr == "run":
            for kw in node.keywords:
                if kw.arg == "port" and isinstance(kw.value, ast.Constant):
                    flask_port = kw.value.value

    assert redis_host in ("127.0.0.1", "localhost"), \
        f"Flask Redis host must be local, found {redis_host!r}"
    assert redis_port == 6379, f"Flask Redis port must be 6379, found {redis_port!r}"
    assert isinstance(flask_port, int), "Could not determine Flask app.run port"
    return flask_port


def assert_infrastructure():
    flask_port = parse_api_configuration()

    assert os.path.isfile(NGINX_CONF), f"Nginx configuration missing: {NGINX_CONF}"
    with open(NGINX_CONF) as f:
        nginx = re.sub(r"#.*", "", f.read())
    assert re.search(r"\blisten\s+8080\s*;", nginx), "Nginx is not configured to listen on 8080"
    assert re.search(r"\bproxy_pass\s+http://[^;]+;", nginx), "Nginx has no proxy_pass"
    local_backend = re.search(
        rf"\bserver\s+(?:127\.0\.0\.1|localhost):{flask_port}\s*;", nginx
    ) or re.search(
        rf"\bproxy_pass\s+http://(?:127\.0\.0\.1|localhost):{flask_port}(?:/)?\s*;", nginx
    )
    assert local_backend, f"Nginx does not proxy to the local Flask port {flask_port}"

    processes = subprocess.check_output(["ps", "-eo", "args="], text=True).splitlines()
    assert any("redis-server" in line for line in processes), "redis-server is not running"
    assert any(re.search(r"python3(?:\s+|.*\s)app\.py(?:\s|$)", line) for line in processes), \
        "Flask app.py is not running under python3"
    assert any("nginx: master process" in line and "-c /app/services/nginx/nginx.conf" in line
               for line in processes), "Nginx was not started with the required configuration"

    pong = subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "PING"],
                          capture_output=True, text=True)
    assert pong.returncode == 0 and pong.stdout.strip() == "PONG", "Redis is not responding on 127.0.0.1:6379"

    status, clean = post_json(f"http://127.0.0.1:{flask_port}/score", {"sequence": "ACGTACGT"})
    assert status == 200 and clean.get("converged") is True and clean.get("score") >= 0.5, \
        "The Flask scoring service is not working"
    status, evil = post_json("http://127.0.0.1:8080/score", {"sequence": "GCGCGCGC"})
    assert status == 200 and evil.get("converged") is True and evil.get("score") < 0.5, \
        "Nginx is not correctly proxying the scoring API"
    return flask_port


class ScoreHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/score":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode())
            sequence = body["sequence"]
            response = self.server.responses[sequence]
            self.server.seen.append(sequence)
        except Exception:
            self.send_error(400)
            return
        encoded = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        pass


def run_script(input_dir, output_dir):
    result = subprocess.run(["bash", SCRIPT_PATH, input_dir, output_dir],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Script failed for {input_dir}:\n{result.stderr}"


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"
    STATE["flask_port"] = assert_infrastructure()

    for path in (TEST_CLEAN_OUT, TEST_EVIL_OUT, DYNAMIC_ROOT):
        shutil.rmtree(path, ignore_errors=True)
    os.makedirs(TEST_CLEAN_OUT)
    os.makedirs(TEST_EVIL_OUT)
    os.makedirs(DYNAMIC_IN)
    os.makedirs(DYNAMIC_OUT)
    if os.path.exists(REJECTED_LOG):
        os.remove(REJECTED_LOG)

    # Replace Nginx only during classifier tests with a recording scoring endpoint.
    # This makes classifications unpredictable from sequence content and proves that
    # every extracted sequence is actually POSTed and the returned fields are used.
    subprocess.run(["nginx", "-c", NGINX_CONF, "-s", "stop"], capture_output=True)
    wait_port_closed(8080)

    responses = {
        "ACGTACGT": {"score": 0.9, "converged": True},
        "GCGCGCGC": {"score": 0.1, "converged": True},
    }
    cases = [
        {"score": 0.5, "converged": True},
        {"score": 0.87, "converged": True},
        {"score": 0.49, "converged": True},
        {"score": 0.99, "converged": False},
        {"score": 0.02, "converged": False},
        {"score": 0.73, "converged": True},
    ]
    random.SystemRandom().shuffle(cases)

    dynamic_expected_clean = {}
    dynamic_expected_rejected = set()
    alphabet = "ACGT"
    for index, result in enumerate(cases):
        while True:
            sequence = "".join(secrets.choice(alphabet) for _ in range(37 + index))
            if sequence not in responses:
                break
        name = f"sample_{secrets.token_hex(6)}.fasta"
        content = f">random_{index}\n{sequence[:7]}\n{sequence[7:19]}\n{sequence[19:]}\n"
        with open(os.path.join(DYNAMIC_IN, name), "w") as f:
            f.write(content)
        responses[sequence] = result
        if result["converged"] is True and result["score"] >= 0.5:
            dynamic_expected_clean[name] = content
        else:
            dynamic_expected_rejected.add(name)

    server = ThreadingHTTPServer(("127.0.0.1", 8080), ScoreHandler)
    server.responses = responses
    server.seen = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        run_script(CLEAN_CORPUS, TEST_CLEAN_OUT)
        run_script(EVIL_CORPUS, TEST_EVIL_OUT)
        run_script(DYNAMIC_IN, DYNAMIC_OUT)
        STATE["seen"] = list(server.seen)
        STATE["expected_sequences"] = list(responses.keys())
        STATE["dynamic_clean"] = dynamic_expected_clean
        STATE["dynamic_rejected"] = dynamic_expected_rejected
        yield
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        subprocess.run(["nginx", "-c", NGINX_CONF], capture_output=True)


def test_clean_corpus_preserved():
    clean_files = [os.path.basename(f) for f in glob.glob(os.path.join(CLEAN_CORPUS, "*.fasta"))]
    out_files = [os.path.basename(f) for f in glob.glob(os.path.join(TEST_CLEAN_OUT, "*.fasta"))]
    missing = set(clean_files) - set(out_files)
    modified = set(out_files) - set(clean_files)
    assert not missing, f"{len(missing)} of {len(clean_files)} clean files were not preserved. Missing: {missing}"
    assert not modified, f"Unexpected files found in clean output: {modified}"
    for name in clean_files:
        with open(os.path.join(CLEAN_CORPUS, name), "rb") as source, \
             open(os.path.join(TEST_CLEAN_OUT, name), "rb") as output:
            assert output.read() == source.read(), f"Clean FASTA was modified: {name}"


def test_evil_corpus_rejected():
    evil_files = [os.path.basename(f) for f in glob.glob(os.path.join(EVIL_CORPUS, "*.fasta"))]
    out_files = [os.path.basename(f) for f in glob.glob(os.path.join(TEST_EVIL_OUT, "*.fasta"))]
    bypassed = set(out_files).intersection(set(evil_files))
    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil files bypassed the filter: {bypassed}"
    assert len(out_files) == 0, f"Evil output directory should be empty, found: {out_files}"


def test_rejected_log():
    assert os.path.isfile(REJECTED_LOG), f"Rejected log not found at {REJECTED_LOG}"
    with open(REJECTED_LOG) as f:
        log_contents = f.read()
    evil_files = [os.path.basename(f) for f in glob.glob(os.path.join(EVIL_CORPUS, "*.fasta"))]
    missing = [name for name in evil_files if name not in log_contents]
    assert not missing, f"The following evil files were not found in {REJECTED_LOG}: {missing}"


def test_dynamic_classification_and_original_contents():
    actual = {os.path.basename(p) for p in glob.glob(os.path.join(DYNAMIC_OUT, "*.fasta"))}
    expected = set(STATE["dynamic_clean"])
    assert actual == expected, f"Dynamic classifications were wrong; expected {expected}, found {actual}"
    for name, original_content in STATE["dynamic_clean"].items():
        with open(os.path.join(DYNAMIC_OUT, name)) as f:
            assert f.read() == original_content, f"Output did not preserve original FASTA contents: {name}"

    with open(REJECTED_LOG) as f:
        lines = {line.strip() for line in f if line.strip()}
    assert STATE["dynamic_rejected"].issubset(lines), \
        f"Dynamic rejected files missing from log: {STATE['dynamic_rejected'] - lines}"


def test_endpoint_called_with_extracted_sequences():
    seen = STATE["seen"]
    for sequence in STATE["expected_sequences"]:
        assert sequence in seen, f"Scoring endpoint was not called with extracted sequence {sequence!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
