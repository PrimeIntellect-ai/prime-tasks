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
import os
import re
import json
import math
import hashlib
import secrets
import socket
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlencode

import pytest
import requests


def deterministic_embedding(text):
    h = hashlib.md5(text.encode('utf-8')).digest()
    vec = [(b / 255.0) - 0.5 for b in h[:10]]
    norm = math.sqrt(sum(x*x for x in vec))
    return [x/norm for x in vec] if norm > 0 else vec


def cosine_similarity(v1, v2):
    return sum(x*y for x, y in zip(v1, v2))


@pytest.fixture(scope="module")
def expected_results():
    datasets = [
        {"id": "ds1", "description": "Global climate and weather patterns"},
        {"id": "ds2", "description": "Financial stock market historical data"},
        {"id": "ds3", "description": "Images of cats and dogs for classification"},
        {"id": "ds4", "description": "Text corpus of ancient Greek literature"},
        {"id": "ds5", "description": "Daily temperature and precipitation records"}
    ]

    query_vec = deterministic_embedding("climate")
    results = []
    for ds in datasets:
        ds_vec = deterministic_embedding(ds["description"])
        score = cosine_similarity(query_vec, ds_vec)
        results.append({"id": ds["id"], "score": score})

    results.sort(key=lambda x: x["score"], reverse=True)
    return results


def test_search_endpoint(expected_results):
    try:
        response = requests.get("http://127.0.0.1:9000/search?q=climate&k=2", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the C++ service on port 9000: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from C++ service is not valid JSON")

    assert "results" in data, "'results' key missing in the JSON response"
    results = data["results"]
    assert isinstance(results, list), "'results' should be a list"
    assert len(results) == 2, f"Expected 2 results, got {len(results)}"

    for i in range(2):
        assert "id" in results[i], f"Result {i} missing 'id'"
        assert "score" in results[i], f"Result {i} missing 'score'"

        expected_id = expected_results[i]["id"]
        expected_score = expected_results[i]["score"]

        assert results[i]["id"] == expected_id, f"Expected id {expected_id} at rank {i+1}, got {results[i]['id']}"
        assert math.isclose(results[i]["score"], expected_score, abs_tol=1e-2), \
            f"Expected score ~{expected_score} at rank {i+1}, got {results[i]['score']}"


def test_benchmark_log():
    log_path = "/home/user/benchmark.log"
    assert os.path.isfile(log_path), f"Benchmark log file {log_path} is missing"

    with open(log_path, 'r') as f:
        content = f.read()

    pattern = r"\[climate\] time_ms:\s*([0-9]*\.?[0-9]+)"
    match = re.search(pattern, content)
    assert match is not None, f"Could not find the expected benchmark log pattern for 'climate' in {log_path}. Content: {content}"

    try:
        float(match.group(1))
    except ValueError:
        pytest.fail(f"Logged time_ms value '{match.group(1)}' is not a valid float")


def _kill_port(port):
    wanted = []
    port_hex = format(port, '04X')
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[-1].upper() == port_hex and fields[3] == '0A':
                        wanted.append(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if any(target == f'socket:[{inode}]' for inode in wanted):
                    pids.add(int(name))
        except OSError:
            pass

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def test_recompiled_service_with_dynamic_backends():
    source = '/home/user/recommender.cpp'
    assert os.path.isfile(source), f"Missing required C++ source file {source}"
    assert os.path.isfile('/home/user/include/httplib.h'), "Missing downloaded httplib.h"
    assert os.path.isfile('/home/user/include/json.hpp'), "Missing downloaded json.hpp"

    binary = '/tmp/recommender_under_test'
    build = subprocess.run(
        ['g++', '-std=c++17', '-O2', '-pthread', source,
         '-I/home/user/include', '-lcurl', '-o', binary],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45
    )
    assert build.returncode == 0, f"Failed to compile recommender.cpp:\n{build.stdout}"

    token = secrets.token_hex(16)
    salt = secrets.token_bytes(24)
    datasets = [
        {"id": f"item-{token[:6]}-{i}",
         "description": f"dynamic dataset {i} {secrets.token_hex(10)}"}
        for i in range(7)
    ]
    state = {"metadata_calls": 0, "embedded_texts": []}
    lock = threading.Lock()

    def dynamic_embedding(text):
        digest = hashlib.sha256(salt + text.encode('utf-8')).digest()
        vec = [(digest[i] / 255.0) - 0.5 for i in range(12)]
        norm = math.sqrt(sum(x*x for x in vec))
        return [x / norm for x in vec]

    class MetadataHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != '/datasets':
                self.send_response(404)
                self.end_headers()
                return
            with lock:
                state["metadata_calls"] += 1
            body = json.dumps(datasets).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    class EmbeddingHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != '/embed':
                self.send_response(404)
                self.end_headers()
                return
            length = int(self.headers.get('Content-Length', '0'))
            request = json.loads(self.rfile.read(length))
            text = request.get('text', '')
            with lock:
                state["embedded_texts"].append(text)
            body = json.dumps({"embedding": dynamic_embedding(text)}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    process = None
    metadata_server = None
    embedding_server = None
    try:
        for port in (9000, 8080, 8081):
            _kill_port(port)

        metadata_server = ReusableHTTPServer(('127.0.0.1', 8080), MetadataHandler)
        embedding_server = ReusableHTTPServer(('127.0.0.1', 8081), EmbeddingHandler)
        threading.Thread(target=metadata_server.serve_forever, daemon=True).start()
        threading.Thread(target=embedding_server.serve_forever, daemon=True).start()

        process = subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 12
        while time.time() < deadline:
            if process.poll() is not None:
                pytest.fail(f"Recompiled service exited early with status {process.returncode}")
            try:
                with socket.create_connection(('127.0.0.1', 9000), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            pytest.fail("Recompiled service did not listen on 127.0.0.1:9000")

        with lock:
            assert state["metadata_calls"] >= 1, "Service did not fetch GET /datasets on startup"
            embedded_at_startup = list(state["embedded_texts"])
        for ds in datasets:
            assert ds["description"] in embedded_at_startup, \
                f"Service did not request an embedding for dataset {ds['id']}"

        queries = [
            (f"query alpha {secrets.token_hex(6)}", 1),
            (f"query beta {secrets.token_hex(6)}", 3),
            (f"query gamma {secrets.token_hex(6)}", 5),
        ]

        for query, k in queries:
            expected = []
            qvec = dynamic_embedding(query)
            for ds in datasets:
                expected.append({
                    "id": ds["id"],
                    "score": cosine_similarity(qvec, dynamic_embedding(ds["description"]))
                })
            expected.sort(key=lambda item: item["score"], reverse=True)

            log_path = '/home/user/benchmark.log'
            before = os.path.getsize(log_path) if os.path.exists(log_path) else 0
            with lock:
                calls_before = len(state["embedded_texts"])

            response = requests.get(
                'http://127.0.0.1:9000/search?' + urlencode({'q': query, 'k': k}),
                timeout=5
            )
            assert response.status_code == 200
            data = response.json()
            assert "results" in data
            results = data["results"]
            assert isinstance(results, list)
            assert len(results) == k, f"Query with k={k} returned {len(results)} results"

            for i in range(k):
                assert "id" in results[i]
                assert "score" in results[i]
                assert isinstance(results[i]["score"], (int, float)) and not isinstance(results[i]["score"], bool)
                assert results[i]["id"] == expected[i]["id"], \
                    f"Wrong result at rank {i+1} for dynamic query {query!r}"
                assert math.isclose(results[i]["score"], expected[i]["score"], abs_tol=1e-4), \
                    f"Wrong score at rank {i+1} for dynamic query {query!r}"

            with lock:
                new_calls = state["embedded_texts"][calls_before:]
            assert query in new_calls, f"Embedding service was not called for query {query!r}"

            assert os.path.isfile(log_path), "Benchmark log is missing after search"
            with open(log_path, 'rb') as f:
                f.seek(before)
                appended = f.read().decode('utf-8', errors='replace')
            line_pattern = rf"(?m)^\[{re.escape(query)}\] time_ms: ([0-9]*\.?[0-9]+)$"
            match = re.search(line_pattern, appended)
            assert match is not None, f"No newly appended benchmark line for {query!r}"
            float(match.group(1))
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
        if metadata_server is not None:
            metadata_server.shutdown()
            metadata_server.server_close()
        if embedding_server is not None:
            embedding_server.shutdown()
            embedding_server.server_close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
