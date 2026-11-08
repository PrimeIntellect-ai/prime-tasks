#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
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

APP_CONF = "/home/user/app/nginx.conf"
START_SCRIPT = "/home/user/app/start.sh"
BINARY = "/home/user/etl_filter/target/release/etl_filter"
PROJECT = "/home/user/etl_filter"


def stop_services():
    subprocess.run(
        ["nginx", "-c", APP_CONF, "-s", "stop"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["pkill", "-f", "/home/user/app/mock_listener.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.5)


def fetch(req, timeout=2):
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.headers, response.read()


def wait_for_request(req, attempts=30):
    last_error = None
    for _ in range(attempts):
        try:
            return fetch(req)
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Service did not become ready: {last_error}")


def test_nginx_proxy_configuration():
    assert os.path.isfile(START_SCRIPT), "Startup script missing."

    stop_services()
    starter = subprocess.Popen(
        [START_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        req = urllib.request.Request("http://localhost:8080/api/health")
        status, _, body = wait_for_request(req)
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert "ok" in body.decode("utf-8").lower(), \
            "Expected 'ok' in response body from mock listener"
    finally:
        starter.terminate()
        try:
            starter.wait(timeout=2)
        except subprocess.TimeoutExpired:
            starter.kill()
        stop_services()

    # Use an unpredictable endpoint and response so a static Nginx response or
    # health-only special case cannot satisfy the proxy requirement.
    token = secrets.token_hex(24)
    path_token = secrets.token_hex(12)
    query_token = secrets.token_hex(8)
    request_body = secrets.token_bytes(37)
    expected_path = f"/api/{path_token}?probe={query_token}"

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    class ChallengeHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            received = self.rfile.read(length)
            valid = (
                self.path == expected_path
                and received == request_body
                and self.headers.get("X-Proxy-Challenge") == token
            )
            payload = json.dumps({
                "backend_token": token if valid else "invalid",
                "path": self.path,
            }).encode()
            self.send_response(200 if valid else 418)
            self.send_header("Content-Type", "application/json")
            self.send_header("X-Backend-Token", token if valid else "invalid")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, fmt, *args):
            pass

    backend = ReusableHTTPServer(("127.0.0.1", 9000), ChallengeHandler)
    backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
    backend_thread.start()
    nginx = subprocess.Popen(
        ["nginx", "-c", APP_CONF, "-g", "daemon off;"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        req = urllib.request.Request(
            f"http://localhost:8080{expected_path}",
            data=request_body,
            method="POST",
            headers={"X-Proxy-Challenge": token, "Content-Type": "application/octet-stream"},
        )
        status, headers, body = wait_for_request(req)
        assert status == 200
        decoded = json.loads(body)
        assert decoded["backend_token"] == token
        assert decoded["path"] == expected_path
        assert headers.get("X-Backend-Token") == token
    finally:
        nginx.terminate()
        try:
            nginx.wait(timeout=2)
        except subprocess.TimeoutExpired:
            nginx.kill()
        backend.shutdown()
        backend.server_close()
        backend_thread.join(timeout=2)
        stop_services()


def test_etl_filter_adversarial_corpus():
    assert os.path.isfile(BINARY), f"Rust release binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable"

    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean JSON files found to test."
    assert len(evil_files) > 0, "No evil JSON files found to test."

    clean_failed = []
    for cf in clean_files:
        res = subprocess.run([BINARY, cf], capture_output=True, timeout=5)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        res = subprocess.run([BINARY, ef], capture_output=True, timeout=5)
        if res.returncode == 0:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def metadata_has_dollar(value):
    if isinstance(value, dict):
        return any(
            key.startswith("$") or metadata_has_dollar(child)
            for key, child in value.items()
        )
    if isinstance(value, list):
        return any(metadata_has_dollar(child) for child in value)
    return False


def graph_has_cycle(edges):
    adjacency = {}
    vertices = set()
    for edge in edges:
        source = edge["from"]
        target = edge["to"]
        vertices.add(source)
        vertices.add(target)
        adjacency.setdefault(source, []).append(target)

    state = {}
    def visit(vertex):
        if state.get(vertex) == 1:
            return True
        if state.get(vertex) == 2:
            return False
        state[vertex] = 1
        if any(visit(neighbor) for neighbor in adjacency.get(vertex, [])):
            return True
        state[vertex] = 2
        return False

    return any(visit(vertex) for vertex in vertices if state.get(vertex, 0) == 0)


def oracle(payload):
    return metadata_has_dollar(payload.get("metadata", {})) or graph_has_cycle(payload.get("edges", []))


def random_label(rng):
    alphabet = string.ascii_letters + string.digits
    return "n_" + ''.join(rng.choice(alphabet) for _ in range(18))


def test_etl_filter_generated_payloads_and_cli_contract():
    assert os.path.isfile(BINARY), f"Rust release binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable"
    with open(BINARY, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "Release deliverable must be a compiled executable"

    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
    build_env = os.environ.copy()
    build_env["CARGO_NET_OFFLINE"] = "true"
    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        env=build_env,
        capture_output=True,
        timeout=120,
    )
    assert build.returncode == 0, build.stderr.decode(errors="replace")

    assert subprocess.run([BINARY], capture_output=True, timeout=5).returncode != 0

    rng = secrets.SystemRandom()
    cases = []
    for index in range(32):
        count = rng.randrange(3, 9)
        nodes = [random_label(rng) for _ in range(count)]
        edges = []

        # Begin with a randomly thinned DAG whose ordering is itself random.
        for source_index in range(count):
            for target_index in range(source_index + 1, count):
                if rng.random() < 0.28:
                    edges.append({"from": nodes[source_index], "to": nodes[target_index]})

        metadata = {
            "source": secrets.token_hex(7),
            "priority": rng.randrange(-100, 101),
            "nested": {"value": secrets.token_hex(5), "items": [1, 2, {"safe": True}]},
        }

        if index % 4 == 1:
            cycle_size = rng.randrange(2, count + 1)
            selected = nodes[:cycle_size]
            for pos, source in enumerate(selected):
                edges.append({"from": source, "to": selected[(pos + 1) % cycle_size]})
        elif index % 4 == 2:
            metadata["nested"]["deeper"] = {
                "$" + secrets.token_hex(6): secrets.token_hex(8)
            }
        elif index % 4 == 3:
            # Mix arbitrary additional edges; the independent oracle derives
            # whether the resulting graph happens to contain a cycle.
            for _ in range(rng.randrange(1, count + 2)):
                edges.append({"from": rng.choice(nodes), "to": rng.choice(nodes)})

        rng.shuffle(edges)
        payload = {"nodes": nodes, "edges": edges, "metadata": metadata}
        cases.append((payload, oracle(payload)))

    assert any(expected for _, expected in cases)
    assert any(not expected for _, expected in cases)

    with tempfile.TemporaryDirectory(prefix="payload_probe_") as directory:
        probe_paths = []
        for payload, expected_evil in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8") as output:
                json.dump(payload, output, separators=(",", ":"))
            probe_paths.append(path)
            result = subprocess.run([BINARY, os.path.abspath(path)], capture_output=True, timeout=5)
            if expected_evil:
                assert result.returncode != 0, f"Generated evil payload was accepted: {payload}"
            else:
                assert result.returncode == 0, f"Generated clean payload was rejected: {payload}"

        assert subprocess.run(
            [BINARY, probe_paths[0], probe_paths[1]], capture_output=True, timeout=5
        ).returncode != 0, "The binary must accept exactly one argument"

        malformed = os.path.join(directory, secrets.token_hex(16))
        with open(malformed, "w", encoding="utf-8") as output:
            output.write('{"nodes": ["unterminated"]')
        assert subprocess.run([BINARY, malformed], capture_output=True, timeout=5).returncode != 0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
