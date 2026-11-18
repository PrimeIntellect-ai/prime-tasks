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

# Replace the deterministic mock process with a verifier-controlled API whose
# reads can be changed between endpoint requests.
pkill -f '^python3 /home/user/app/mock_api.py$' 2>/dev/null || true
sleep 0.5

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import random
import socket
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
import requests


BASELINE_READS = [
    "ATGCGTA", "TGCGTAC", "CGTACGA", "AAAAAAT",
    "TTTTTTT", "ATGCGGG", "GGGGGGG", "AAAAAAG",
    "ATGC", "CGTA"
]


class MutableReadsHandler(BaseHTTPRequestHandler):
    reads = BASELINE_READS
    request_count = 0

    def do_GET(self):
        if self.path != "/api/reads":
            self.send_response(404)
            self.end_headers()
            return

        type(self).request_count += 1
        body = json.dumps(type(self).reads).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def redis_command(*parts):
    payload = f"*{len(parts)}\r\n".encode()
    for part in parts:
        raw = str(part).encode()
        payload += f"${len(raw)}\r\n".encode() + raw + b"\r\n"

    with socket.create_connection(("127.0.0.1", 6379), timeout=2) as sock:
        sock.sendall(payload)
        stream = sock.makefile("rb")
        header = stream.readline()
        assert header, "Redis returned an empty response"
        if header.startswith(b"$"):
            length = int(header[1:-2])
            if length == -1:
                return None
            data = stream.read(length)
            assert stream.read(2) == b"\r\n"
            return data.decode("utf-8")
        if header.startswith(b":"):
            return int(header[1:-2])
        if header.startswith(b"+"):
            return header[1:-2].decode("utf-8")
        pytest.fail(f"Unexpected Redis response: {header!r}")


def expected_stats(reads):
    kmer_sets = [
        {read[i:i + 4] for i in range(max(0, len(read) - 3))}
        for read in reads
    ]
    degrees = [0] * len(reads)
    for i in range(len(reads)):
        for j in range(i + 1, len(reads)):
            if kmer_sets[i].intersection(kmer_sets[j]):
                degrees[i] += 1
                degrees[j] += 1

    y = sorted(degrees, reverse=True)
    x_mean = (len(y) - 1) / 2.0
    y_mean = sum(y) / len(y)
    denominator = sum((x - x_mean) ** 2 for x in range(len(y)))
    slope = sum((x - x_mean) * (degree - y_mean) for x, degree in enumerate(y)) / denominator
    intercept = y_mean - slope * x_mean
    return {
        "slope": round(float(slope), 4),
        "intercept": round(float(intercept), 4),
        "max_degree": max(degrees),
    }


def random_reads(rng):
    alphabet = "ACGT"
    randseq = lambda n: "".join(rng.choice(alphabet) for _ in range(n))
    n = rng.randint(9, 16)
    motif1 = randseq(4)
    motif2 = randseq(4)
    while motif2 == motif1:
        motif2 = randseq(4)

    first_group = rng.randint(3, n - 4)
    second_group = rng.randint(2, n - first_group - 1)
    reads = []
    for i in range(n):
        if i < first_group:
            reads.append(randseq(rng.randint(1, 3)) + motif1 + randseq(rng.randint(1, 3)))
        elif i < first_group + second_group:
            reads.append(randseq(rng.randint(1, 3)) + motif2 + randseq(rng.randint(1, 3)))
        else:
            reads.append(randseq(rng.randint(7, 11)))
    rng.shuffle(reads)
    return reads


def exercise(reads, baseline=False):
    MutableReadsHandler.reads = list(reads)
    before = MutableReadsHandler.request_count
    redis_command("DEL", "dna_raw_reads")

    url = "http://127.0.0.1:8080/api/v1/network-stats"
    try:
        response = requests.get(url, timeout=8)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the agent's service at {url}. Error: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert type(data) is dict
    assert set(data) == {"slope", "intercept", "max_degree"}, (
        f"Response must contain exactly slope, intercept, and max_degree; got {data}"
    )
    assert type(data["slope"]) is float
    assert type(data["intercept"]) is float
    assert type(data["max_degree"]) is int

    expected = expected_stats(reads)
    assert math.isclose(data["slope"], expected["slope"], abs_tol=0.00005)
    assert math.isclose(data["intercept"], expected["intercept"], abs_tol=0.00005)
    assert data["slope"] == round(data["slope"], 4)
    assert data["intercept"] == round(data["intercept"], 4)
    assert data["max_degree"] == expected["max_degree"]

    # Retain the original verifier's fixed baseline assertions.
    if baseline:
        assert math.isclose(data["slope"], -0.5333, abs_tol=0.001)
        assert math.isclose(data["intercept"], 4.6, abs_tol=0.001)
        assert data["max_degree"] == 5

    assert MutableReadsHandler.request_count > before, (
        "The endpoint did not fetch /api/reads during this request"
    )
    cached = redis_command("GET", "dna_raw_reads")
    assert cached is not None, "Key 'dna_raw_reads' does not exist in Redis"
    try:
        cached_reads = json.loads(cached)
    except json.JSONDecodeError:
        pytest.fail(f"Data in Redis is not valid JSON. Data: {cached}")
    assert cached_reads == reads, f"Cached reads do not match fetched reads: {cached_reads}"


def test_network_stats_workflow():
    server = HTTPServer(("127.0.0.1", 8001), MutableReadsHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        exercise(BASELINE_READS, baseline=True)
        rng = random.SystemRandom()
        exercise(random_reads(rng))
        exercise(random_reads(rng))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
