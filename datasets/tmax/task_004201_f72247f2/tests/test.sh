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
import math
import os
import random
import secrets
import signal
import subprocess
import threading
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests


def get_embedding(text):
    length = len(text)
    v1 = sum(ord(c) for c in text) % 100 / 100.0
    v2 = sum(ord(c) * i for i, c in enumerate(text)) % 100 / 100.0
    v3 = length % 10 / 10.0
    return [v1, v2, v3]


def pearson_corr(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return 0.0
    return num / math.sqrt(den_x * den_y)


def correlation_matrix(sentences):
    embeddings = [get_embedding(s) for s in sentences]
    result = []
    for i in range(3):
        row = []
        for j in range(3):
            row.append(pearson_corr([e[i] for e in embeddings],
                                    [e[j] for e in embeddings]))
        result.append(row)
    return result


def test_embedding_api():
    url = "http://127.0.0.1:8080/embed"
    payload = {"text": "The quick brown fox"}
    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to embedding API on port 8080: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Embedding API did not return valid JSON. Response: {response.text}")

    assert "embedding" in data, f"Response JSON is missing 'embedding' key. Got: {data}"
    emb = data["embedding"]
    assert isinstance(emb, list) and len(emb) == 3, f"Expected embedding to be a list of 3 floats, got {emb}"

    expected_emb = [0.63, 0.44, 0.9]
    for actual, expected in zip(emb, expected_emb):
        assert math.isclose(actual, expected, abs_tol=1e-5), f"Expected embedding {expected_emb}, got {emb}"


def test_embedding_api_on_unannounced_inputs():
    url = "http://127.0.0.1:8080/embed"
    rng = random.Random(secrets.randbits(64))
    alphabet = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?-_"
    texts = [
        "hidden-" + ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 70)))
        for _ in range(12)
    ]
    texts.extend(["", "a", "Symbols !? 927 and spaces"])

    for text in texts:
        response = requests.post(url, json={"text": text}, timeout=5)
        assert response.status_code == 200, response.text
        data = response.json()
        assert set(data) == {"embedding"}, f"Unexpected response schema: {data}"
        emb = data["embedding"]
        expected = get_embedding(text)
        assert isinstance(emb, list) and len(emb) == 3
        assert all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in emb)
        for actual, wanted in zip(emb, expected):
            assert math.isclose(actual, wanted, abs_tol=1e-9), \
                f"Wrong embedding for hidden input {text!r}: expected {expected}, got {emb}"


def test_results_api():
    url = "http://127.0.0.1:8081/results"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to results API on port 8081: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Results API did not return valid JSON. Response: {response.text}")

    assert "correlation_matrix" in data, f"Missing 'correlation_matrix' in response. Got: {data}"
    assert "benchmark_average_latency_sec" in data, f"Missing 'benchmark_average_latency_sec' in response. Got: {data}"

    latency = data["benchmark_average_latency_sec"]
    assert isinstance(latency, (int, float)), f"Latency must be a number, got {type(latency)}"
    assert latency > 0, f"Latency must be greater than 0, got {latency}"

    sentences = [
        "The quick brown fox",
        "Jumps over the lazy dog",
        "Machine learning is fascinating",
        "Data science requires statistical thinking",
        "Artificial intelligence agents",
        "Building multi-protocol verifiers",
        "Terminal environments for bash"
    ]
    expected_matrix = correlation_matrix(sentences)

    actual_matrix = data["correlation_matrix"]
    assert isinstance(actual_matrix, list) and len(actual_matrix) == 3, f"Matrix must be a list of 3 lists, got {actual_matrix}"
    for i in range(3):
        assert isinstance(actual_matrix[i], list) and len(actual_matrix[i]) == 3, f"Matrix row {i} must have 3 elements"
        for j in range(3):
            assert math.isclose(actual_matrix[i][j], expected_matrix[i][j], abs_tol=0.002), \
                f"Mismatch in correlation matrix at ({i},{j}): expected {expected_matrix[i][j]:.4f}, got {actual_matrix[i][j]}"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(':', 1)[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
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
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue
    return pids


def process_config(pid):
    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        argv = [os.fsdecode(x) for x in f.read().split(b'\0') if x]
    assert argv, f"Could not determine command for results service PID {pid}"
    cwd = os.readlink(f'/proc/{pid}/cwd')
    env = {}
    with open(f'/proc/{pid}/environ', 'rb') as f:
        for entry in f.read().split(b'\0'):
            if b'=' in entry:
                key, value = entry.split(b'=', 1)
                env[os.fsdecode(key)] = os.fsdecode(value)
    return argv, cwd, env


def stop_pids(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f'/proc/{p}') for p in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f'/proc/{pid}'):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def test_results_are_generated_by_querying_and_benchmarking_api():
    result_pids = listener_pids(8081)
    embed_pids = listener_pids(8080)
    assert result_pids, "No process is listening on port 8081"
    assert embed_pids, "No process is listening on port 8080"

    result_pid = min(result_pids)
    argv, cwd, env = process_config(result_pid)

    rng = random.Random(secrets.randbits(64))
    nonce = secrets.token_hex(8)
    sentences = []
    for i in range(9):
        words = [nonce, str(i)] + [
            ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(rng.randint(3, 11)))
            for _ in range(i + 2)
        ]
        sentences.append(' '.join(words))

    corpus_path = '/app/data/corpus.txt'
    with open(corpus_path, 'rb') as f:
        original_corpus = f.read()
    with open(corpus_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sentences) + '\n')

    delay = 0.035 + secrets.randbelow(3000) / 100000.0
    calls = Counter()
    calls_lock = threading.Lock()

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    class InstrumentedEmbeddingHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != '/embed':
                self.send_response(404)
                self.end_headers()
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                body = json.loads(self.rfile.read(length).decode('utf-8'))
                text = body['text']
                assert isinstance(text, str)
            except Exception:
                self.send_response(400)
                self.end_headers()
                return
            with calls_lock:
                calls[text] += 1
            time.sleep(delay)
            payload = json.dumps({'embedding': get_embedding(text)}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    all_old_pids = result_pids | embed_pids
    stop_pids(all_old_pids)
    server = None
    proc = None
    try:
        server = ReusableHTTPServer(('127.0.0.1', 8080), InstrumentedEmbeddingHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)

        response = None
        deadline = time.time() + 25
        last_error = None
        while time.time() < deadline:
            try:
                candidate = requests.get('http://127.0.0.1:8081/results', timeout=15)
                if candidate.status_code == 200:
                    response = candidate
                    break
                last_error = f"HTTP {candidate.status_code}: {candidate.text}"
            except requests.RequestException as exc:
                last_error = str(exc)
            time.sleep(0.1)
        assert response is not None, f"Restarted results artifact did not serve /results: {last_error}"
        data = response.json()

        assert set(data) == {'correlation_matrix', 'benchmark_average_latency_sec'}, \
            f"Unexpected results schema: {data}"
        actual_matrix = data['correlation_matrix']
        expected_matrix = correlation_matrix(sentences)
        assert isinstance(actual_matrix, list) and len(actual_matrix) == 3
        for i in range(3):
            assert isinstance(actual_matrix[i], list) and len(actual_matrix[i]) == 3
            for j in range(3):
                assert math.isclose(actual_matrix[i][j], expected_matrix[i][j], abs_tol=0.002), \
                    f"Results were not recomputed from the hidden corpus at ({i},{j})"

        with calls_lock:
            observed = calls.copy()
        missing = [s for s in sentences if observed[s] < 1]
        assert not missing, f"Results workflow did not request embeddings for corpus lines: {missing}"
        assert observed[sentences[0]] >= 101, \
            f"Expected one corpus request plus 100 benchmark requests for the first line; observed {observed[sentences[0]]}"
        assert sum(observed.values()) >= len(sentences) + 100, \
            f"Expected at least {len(sentences) + 100} embedding requests, observed {sum(observed.values())}"

        latency = data['benchmark_average_latency_sec']
        assert isinstance(latency, (int, float)) and not isinstance(latency, bool)
        assert math.isfinite(latency) and latency > 0
        assert delay * 0.9 <= latency <= delay + 0.03, \
            f"Reported latency {latency} does not reflect the hidden per-request delay {delay}"
    finally:
        with open(corpus_path, 'wb') as f:
            f.write(original_corpus)
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if server is not None:
            server.shutdown()
            server.server_close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
