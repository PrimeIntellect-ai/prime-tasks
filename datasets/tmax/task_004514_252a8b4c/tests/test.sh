#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import re
import string
import subprocess
import threading
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import redis


def normalize(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9]", " ", text)
    tokens = [token for token in text.split() if token][:10]
    return tokens, " ".join(tokens)


def generate_fuzz_input(n=1000):
    rng = random.SystemRandom()
    lines = [
        {"id": "empty123", "text": ""},
        {"id": "punct123", "text": "!@#$%^&*()"},
        {"id": "long1234", "text": "a b c d e f g h i j k l m n o p"},
        {"id": "repeat12", "text": "repeat this text"},
        {"id": "repeat34", "text": "repeat this text"},
    ]

    for _ in range(n - len(lines)):
        id_str = "".join(rng.choices(string.ascii_letters + string.digits, k=8))
        text_chars = []
        for _ in range(rng.randint(10, 200)):
            if rng.random() < 0.8:
                text_chars.append(rng.choice(string.printable))
            else:
                text_chars.append(chr(rng.randint(0x00A0, 0x02AF)))
        lines.append({"id": id_str, "text": "".join(text_chars)})
    return lines


def test_fuzz_equivalence():
    agent_bin = "/home/user/rust_worker/target/release/process_data"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}. Did you build the release binary?"
    assert os.access(agent_bin, os.X_OK), f"Agent artifact is not executable: {agent_bin}"
    with open(agent_bin, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", "process_data must be a compiled release binary"

    cache = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    cache.ping()
    cache.flushall()

    inputs = generate_fuzz_input(1000)
    normalized = [normalize(item["text"]) for item in inputs]

    # Exercise genuine cache hits with valid integer arrays that cannot be
    # reproduced by merely computing the mock API's usual MD5 embedding.
    cache_overrides = {
        normalized[0][1]: [901, 0, 17],
        normalized[2][1]: [902, 10, 20, 30],
        normalized[3][1]: [903, 44],
    }
    for text, embedding in cache_overrides.items():
        cache.set(f"embed:{text}", json.dumps(embedding))

    secret = os.urandom(32)
    requests_seen = Counter()
    request_lock = threading.Lock()

    def api_embedding(text):
        return list(hashlib.md5(secret + text.encode("utf-8")).digest())

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/embed":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length).decode("utf-8"))
                if set(body) != {"text"} or not isinstance(body["text"], str):
                    raise ValueError("payload must contain only a string text field")
                text = body["text"]
            except Exception:
                self.send_error(400)
                return

            with request_lock:
                requests_seen[text] += 1
            response = json.dumps({"embedding": api_embedding(text)}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)

        def log_message(self, format, *args):
            pass

    class Server(ThreadingHTTPServer):
        allow_reuse_address = True

    server = Server(("127.0.0.1", 8000), Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    input_data = "".join(json.dumps(item) + "\n" for item in inputs)
    try:
        agent_proc = subprocess.run(
            [agent_bin], input=input_data, text=True, capture_output=True, timeout=180
        )
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)

    assert agent_proc.returncode == 0, (
        f"Agent binary failed with return code {agent_proc.returncode}.\n"
        f"Stderr: {agent_proc.stderr}"
    )

    agent_lines = agent_proc.stdout.strip().split("\n")
    assert len(agent_lines) == len(inputs), (
        f"Output line count mismatch. Expected {len(inputs)} lines, "
        f"Agent produced {len(agent_lines)} lines."
    )

    expected_by_text = {}
    for tokens, normalized_text in normalized:
        expected_by_text[normalized_text] = cache_overrides.get(
            normalized_text, api_embedding(normalized_text)
        )

    for index, (line, item, normalized_item) in enumerate(zip(agent_lines, inputs, normalized)):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(
                f"Agent output is not valid JSON at line {index + 1}.\n"
                f"Input: {json.dumps(item)}\nAgent output: {line}"
            )

        tokens, normalized_text = normalized_item
        expected = {
            "id": item["id"],
            "tokens": tokens,
            "embedding": expected_by_text[normalized_text],
        }
        assert actual == expected, (
            f"Mismatch at line {index + 1}.\n"
            f"Input: {json.dumps(item)}\n"
            f"Expected: {json.dumps(expected)}\n"
            f"Agent Produced: {line}"
        )

    unique_texts = {normalized_text for _, normalized_text in normalized}
    misses = unique_texts - set(cache_overrides)
    assert set(requests_seen) == misses, (
        "The worker did not use the embedding API exactly for the normalized cache misses. "
        f"Missing requests: {sorted(misses - set(requests_seen))[:10]}; "
        f"unexpected requests: {sorted(set(requests_seen) - misses)[:10]}"
    )

    for normalized_text in unique_texts:
        cached = cache.get(f"embed:{normalized_text}")
        assert cached is not None, f"Embedding was not cached for {normalized_text!r}"
        assert json.loads(cached) == expected_by_text[normalized_text], (
            f"Incorrect cached embedding for {normalized_text!r}"
        )
TEST_EOF

# Replace any stale agent-started services with clean verifier-owned services.
redis-cli shutdown nosave >/dev/null 2>&1 || true
pkill -f '[u]vicorn.*mock_api:app' >/dev/null 2>&1 || true
sleep 1
redis-server --daemonize yes >/dev/null 2>&1
redis_started=$?

if [ "$redis_started" -eq 0 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
