#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import signal
import string
import subprocess
import tempfile
import threading
import time
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def run_sanitizer(path):
    return subprocess.run(
        ["python3", "/home/user/sanitizer.py", path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_part1_sanitizer_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Sanitizer script not found at {sanitizer_path}"

    # Retain the checks against any image-provided corpora.
    evil_corpus = "/app/corpora/evil/"
    clean_corpus = "/app/corpora/clean/"
    evil_files = [os.path.join(evil_corpus, f) for f in os.listdir(evil_corpus)
                  if os.path.isfile(os.path.join(evil_corpus, f))]
    clean_files = [os.path.join(clean_corpus, f) for f in os.listdir(clean_corpus)
                   if os.path.isfile(os.path.join(clean_corpus, f))]

    evil_bypassed = []
    for filename in evil_files:
        result = run_sanitizer(filename)
        if result.stdout.strip() != "":
            evil_bypassed.append(os.path.basename(filename))

    clean_modified = []
    for filename in clean_files:
        result = run_sanitizer(filename)
        with open(filename, "r") as infile:
            expected = infile.read().strip()
        if result.stdout.strip() != expected:
            clean_modified.append(os.path.basename(filename))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not error_msg, " | ".join(error_msg)

    # Exercise the submitted artifact with a freshly generated mixed corpus.
    token = ''.join(random.SystemRandom().choice(string.ascii_letters) for _ in range(18))
    valid_objects = [
        {"service_name": "clean-" + token, "weights": [0.25, 0.75], "nested": {"text": "ordinary"}},
        {"service_name": "ｍodel-" + token, "weights": [0.3333334, 0.6666666], "enabled": True},
        {"id": token, "description": "no weights are also allowed"},
        {"service_name": "edge-" + token, "weights": [0.5000004, 0.5]},
    ]
    valid_lines = [json.dumps(obj, ensure_ascii=False, separators=(",", ":")) for obj in valid_objects]
    invalid_lines = [
        '{"service_name":"broken",',
        '{"service_name":"bad\\ud800","weights":[0.5,0.5]}',
        json.dumps({"service_name": "bad\u202e" + token, "weights": [0.5, 0.5]}, ensure_ascii=False),
        json.dumps({"service_name": "nested", "weights": [0.5, 0.5], "meta": {"label": "x\u2067y"}}, ensure_ascii=False),
        '{"service_name":"nan","weights":[NaN,1.0]}',
        '{"service_name":"inf","weights":[Infinity,-Infinity]}',
        json.dumps({"service_name": "wrong-sum", "weights": [0.2, 0.7]}),
    ]

    mixed = []
    for line in valid_lines + invalid_lines:
        mixed.append(line)
    random.SystemRandom().shuffle(mixed)
    expected = [line for line in mixed if line in valid_lines]

    with tempfile.NamedTemporaryFile("wb", delete=False) as corpus:
        corpus.write(("\n".join(mixed) + "\n").encode("utf-8"))
        corpus_path = corpus.name
    try:
        result = run_sanitizer(corpus_path)
    finally:
        os.unlink(corpus_path)

    assert result.returncode == 0, result.stderr
    actual = result.stdout.splitlines()
    assert actual == expected, f"Sanitizer emitted incorrect lines. Expected {expected!r}, got {actual!r}"


def processes_containing(fragment):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                args = [part.decode("utf-8", "replace") for part in handle.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if any(fragment == arg or arg.endswith(fragment) for arg in args):
            found.append(int(entry))
    return found


class CaptureHandler(BaseHTTPRequestHandler):
    received = []
    lock = threading.Lock()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        try:
            parsed = json.loads(body.decode("utf-8"))
        except Exception:
            parsed = None
        record = {
            "path": self.path,
            "content_type": self.headers.get("Content-Type", ""),
            "json": parsed,
            "body": body,
        }
        with self.lock:
            self.received.append(record)
            # Preserve the original Store API's observable log as an additional check.
            with open("/tmp/store_api_received.log", "a", encoding="utf-8") as log:
                log.write(json.dumps(parsed) + "\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, fmt, *args):
        pass


def wait_for_count(count, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with CaptureHandler.lock:
            current = len(CaptureHandler.received)
        if current >= count:
            return
        time.sleep(0.05)
    with CaptureHandler.lock:
        current = len(CaptureHandler.received)
    pytest.fail(f"Timed out waiting for {count} Store API requests; received {current}")


def reset_capture():
    with CaptureHandler.lock:
        CaptureHandler.received.clear()
    if os.path.exists("/tmp/store_api_received.log"):
        os.remove("/tmp/store_api_received.log")


def test_part2_pipeline_worker():
    try:
        import redis
    except ImportError:
        pytest.fail("redis library is required but not installed.")

    worker_path = "/home/user/worker.py"
    assert os.path.isfile(worker_path), f"Worker script not found at {worker_path}"
    existing_workers = processes_containing(worker_path)
    assert existing_workers, "worker.py was not left running in the background"

    r = redis.Redis(host="localhost", port=6379, db=0)
    try:
        r.ping()
    except redis.ConnectionError:
        pytest.fail("Redis is not running on localhost:6379")

    # Stop pre-existing workers and the image Store API, then execute the submitted
    # worker itself against a verifier-owned HTTP capture server.
    for pid in existing_workers:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    subprocess.run(["pkill", "-f", "/app/services/store_api.py"], check=False)
    time.sleep(0.5)

    server = ThreadingHTTPServer(("127.0.0.1", 8002), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    r.delete("raw_configs")
    reset_capture()
    worker = subprocess.Popen(
        ["python3", worker_path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(0.7)
    assert worker.poll() is None, "Submitted worker.py exited instead of running continuously"

    try:
        # Retain the original five behavioral cases and assertions, but enqueue in
        # deterministic FIFO order.
        payload1 = {"service_name": "model\u2160", "weights": [0.5, 0.5]}
        payload2 = {"service_name": "model\u202E", "weights": [0.5, 0.5]}
        payload3 = {"service_name": "modelI", "weights": [0.50001, 0.49999]}
        payload4 = {"service_name": "model2", "weights": [float("nan"), 1.0]}
        payload5 = {"service_name": "model3", "weights": [0.2, 0.8]}
        r.rpush("raw_configs", *(json.dumps(p) for p in [payload1, payload2, payload3, payload4, payload5]))

        wait_for_count(2)
        time.sleep(0.5)
        assert os.path.exists("/tmp/store_api_received.log"), "Store API log not found; worker failed to send POST"
        with open("/tmp/store_api_received.log", "r", encoding="utf-8") as handle:
            lines = [line.strip() for line in handle if line.strip()]
        assert len(lines) == 2, f"Expected exactly 2 payloads to reach the Store API, but found {len(lines)}."
        received1 = json.loads(lines[0])
        received2 = json.loads(lines[1])
        assert received1["service_name"] == "modelI", "Payload 1 service_name not properly NFKC normalized."
        assert received2["service_name"] == "model3", "Payload 5 service_name incorrect."

        with CaptureHandler.lock:
            first_stage = list(CaptureHandler.received)
        assert len(first_stage) == 2
        assert all(item["path"] == "/api/store" for item in first_stage)
        assert all(item["content_type"].split(";", 1)[0].strip().lower() == "application/json" for item in first_stage)

        # Fresh unpredictable cases verify recursive string checks, malformed input,
        # canonical NFKC normalization, key sorting, weight rounding, deduplication,
        # and preservation of the first unique payload.
        reset_capture()
        nonce = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(24))
        first = {
            "z": {"label": "\ufb03", "nonce": nonce},
            "weights": [0.123441, 0.876559],
            "service_name": "svc\uff21-" + nonce,
            "generation": 7,
        }
        duplicate = {
            "generation": 7,
            "service_name": "svcA-" + nonce,
            "weights": [0.123449, 0.876551],
            "z": {"nonce": nonce, "label": "ffi"},
        }
        unique = {
            "service_name": "node\u2163-" + nonce,
            "weights": [0.4, 0.6],
            "meta": {"nonce": nonce, "value": 3.25},
        }
        bidi_nested = {
            "service_name": "nested-" + nonce,
            "weights": [0.5, 0.5],
            "meta": {"text": "left\u202eright"},
        }
        wrong_sum = {"service_name": "sum-" + nonce, "weights": [0.1, 0.7]}
        nonfinite = {"service_name": "finite-" + nonce, "weights": [float("inf"), float("-inf")]}

        raw_messages = [
            json.dumps(first, ensure_ascii=False),
            json.dumps(duplicate, ensure_ascii=False),
            json.dumps(unique, ensure_ascii=False),
            json.dumps(bidi_nested, ensure_ascii=False),
            json.dumps(wrong_sum),
            json.dumps(nonfinite),
            '{"service_name":"' + nonce + '","weights":[0.5,0.5]',
            '{"service_name":"bad\\ud800-' + nonce + '","weights":[0.5,0.5]}',
        ]
        r.rpush("raw_configs", *raw_messages)

        wait_for_count(2)
        time.sleep(0.7)
        with CaptureHandler.lock:
            records = list(CaptureHandler.received)
        assert len(records) == 2, f"Expected two unique valid dynamic payloads, got {len(records)}"
        assert all(record["path"] == "/api/store" for record in records)
        assert all(record["content_type"].split(";", 1)[0].strip().lower() == "application/json" for record in records)

        expected_first = dict(first)
        expected_first["service_name"] = unicodedata.normalize("NFKC", first["service_name"])
        expected_unique = dict(unique)
        expected_unique["service_name"] = unicodedata.normalize("NFKC", unique["service_name"])
        assert records[0]["json"] == expected_first, "First unique payload was altered incorrectly or replaced by its duplicate"
        assert records[1]["json"] == expected_unique, "Unique payload was not normalized and forwarded correctly"
        assert worker.poll() is None, "worker.py stopped during processing"
    finally:
        server.shutdown()
        server.server_close()


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
