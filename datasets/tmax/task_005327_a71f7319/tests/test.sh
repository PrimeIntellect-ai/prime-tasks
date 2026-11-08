#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/backend-events /tmp/gateway-tmp
rm -f /tmp/backend-events/*

cleanup() {
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 5000/tcp 8000/tcp >/dev/null 2>&1 || true
    fi
    redis-cli shutdown nosave >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
redis-server --daemonize yes

cat <<'BACKEND_EOF' > /tmp/test_storage_backend.py
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
import re
import time

EVENTS = "/tmp/backend-events"
STORAGE = "/home/user/app/storage"
os.makedirs(EVENTS, exist_ok=True)
os.makedirs(STORAGE, exist_ok=True)

class Handler(BaseHTTPRequestHandler):
    def _receive(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        event = os.path.join(EVENTS, f"{time.time_ns()}-{os.getpid()}")
        with open(event + ".body", "wb") as f:
            f.write(body)
        with open(event + ".json", "w") as f:
            json.dump({"method": self.command, "path": self.path,
                       "headers": dict(self.headers)}, f)

        combined = self.path.encode() + b"\n" + str(dict(self.headers)).encode() + b"\n" + body
        names = re.findall(rb"[0-9a-fA-F]{64}\.czip", combined)
        data = None
        ctype = self.headers.get("Content-Type", "")
        match = re.search(r"boundary=(?:\"([^\"]+)\"|([^;]+))", ctype)
        if match:
            boundary = (match.group(1) or match.group(2)).encode()
            for part in body.split(b"--" + boundary):
                if b"filename=" not in part or b"\r\n\r\n" not in part:
                    continue
                candidate = part.split(b"\r\n\r\n", 1)[1]
                if candidate.endswith(b"\r\n"):
                    candidate = candidate[:-2]
                if candidate.startswith(b"CZIP"):
                    data = candidate
                    break
        elif body.startswith(b"CZIP"):
            data = body

        if data is not None:
            digest_name = (hashlib.sha256(data).hexdigest() + ".czip").encode()
            if digest_name in names:
                with open(os.path.join(STORAGE, digest_name.decode()), "wb") as f:
                    f.write(data)

        self.send_response(201)
        self.end_headers()
        self.wfile.write(b"stored")

    do_POST = _receive
    do_PUT = _receive

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
BACKEND_EOF
python3 /tmp/test_storage_backend.py >/tmp/test-storage.log 2>&1 &
BACKEND_PID=$!

export TMPDIR=/tmp/gateway-tmp
python3 -m flask --app /home/user/app/gateway.py run --host=127.0.0.1 --port=5000 >/tmp/test-gateway.log 2>&1 &
GATEWAY_PID=$!

python3 - <<'WAIT_EOF'
import socket, time
for port in (5000, 6379, 8000):
    for _ in range(100):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.2):
                break
        except OSError:
            time.sleep(.1)
    else:
        raise SystemExit(f"service on port {port} did not start")
WAIT_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import struct
import subprocess
import tempfile
import time
import zlib

import pytest
import redis
import requests

EVIL_DIR = "/home/user/corpora/evil/"
CLEAN_DIR = "/home/user/corpora/clean/"
FILTER_SCRIPT = "/home/user/app/artifact_filter.py"
GATEWAY_FILE = "/home/user/app/gateway.py"
GATEWAY_URL = "http://127.0.0.1:5000/upload"
STORAGE_DIR = "/home/user/app/storage/"
EVENT_DIR = "/tmp/backend-events"


def make_czip(filename, payload, declared=None, magic=b"CZIP"):
    name = filename.encode("ascii")
    if declared is None:
        declared = len(payload)
    return magic + struct.pack("<I", declared) + struct.pack("<H", len(name)) + name + zlib.compress(payload)


def run_filter(data, input_name=None):
    with tempfile.TemporaryDirectory() as root:
        input_name = input_name or (secrets.token_hex(10) + ".bin")
        source = os.path.join(root, input_name)
        output = os.path.join(root, secrets.token_hex(8))
        os.mkdir(output)
        with open(source, "wb") as f:
            f.write(data)
        result = subprocess.run(["python3", FILTER_SCRIPT, source, output], capture_output=True, timeout=10)
        files = {}
        for name in os.listdir(output):
            path = os.path.join(output, name)
            if os.path.isfile(path):
                with open(path, "rb") as f:
                    files[name] = f.read()
        return result, files


def clear_events():
    for name in os.listdir(EVENT_DIR):
        os.unlink(os.path.join(EVENT_DIR, name))


def backend_events():
    events = []
    for name in os.listdir(EVENT_DIR):
        if not name.endswith(".json"):
            continue
        base = os.path.join(EVENT_DIR, name[:-5])
        with open(base + ".json") as f:
            meta = json.load(f)
        with open(base + ".body", "rb") as f:
            body = f.read()
        events.append((meta, body))
    return events


def test_artifact_filter_evil_corpus():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing filter script: {FILTER_SCRIPT}"
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"
    bypassed = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for fname in evil_files:
            fpath = os.path.join(EVIL_DIR, fname)
            result = subprocess.run(["python3", FILTER_SCRIPT, fpath, tmpdir], capture_output=True)
            if result.returncode == 0:
                bypassed.append(fname)
    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_artifact_filter_clean_corpus():
    assert os.path.isfile(FILTER_SCRIPT), f"Missing filter script: {FILTER_SCRIPT}"
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"
    modified = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for fname in clean_files:
            fpath = os.path.join(CLEAN_DIR, fname)
            with open(fpath, "rb") as f:
                original = f.read()
            file_hash = hashlib.sha256(original).hexdigest()
            expected_out = os.path.join(tmpdir, f"{file_hash}.czip")
            result = subprocess.run(["python3", FILTER_SCRIPT, fpath, tmpdir], capture_output=True)
            if result.returncode != 0 or not os.path.isfile(expected_out):
                modified.append(fname)
            elif open(expected_out, "rb").read() != original:
                modified.append(fname + " (content changed)")
    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified (or rejected): {', '.join(modified)}")


def test_filter_randomized_derived_cases():
    assert os.path.isfile(FILTER_SCRIPT)
    for _ in range(5):
        payload = secrets.token_bytes(secrets.randbelow(6000) + 1)
        filename = "clean_" + secrets.token_hex(7) + ".dat"
        artifact = make_czip(filename, payload)
        result, files = run_filter(artifact)
        expected = hashlib.sha256(artifact).hexdigest() + ".czip"
        assert result.returncode == 0
        assert files == {expected: artifact}

    token = secrets.token_hex(8)
    invalid = [
        make_czip("bad_" + token, b"x", magic=b"NOPE"),
        make_czip("../" + token, b"x"),
        make_czip("dir/" + token, b"x"),
        make_czip("..\\" + token, b"x"),
        make_czip("bomb_" + token, b"small", declared=10_000_001),
        b"CZIP" + secrets.token_bytes(3),
    ]
    for artifact in invalid:
        result, files = run_filter(artifact)
        assert result.returncode == 1, result.stderr.decode(errors="replace")
        assert files == {}


def test_gateway_configuration_uses_required_pipeline():
    source = open(GATEWAY_FILE, encoding="utf-8").read()
    assert "artifact_filter.py" in source
    assert "/home/user/app/staging" in source
    assert re.search(r"\bsubprocess\b", source)
    assert re.search(r"(?:tempfile\s*\.\s*(?:TemporaryDirectory|mkdtemp|NamedTemporaryFile)|\b(?:TemporaryDirectory|mkdtemp|NamedTemporaryFile)\s*\()", source)
    assert re.search(r"\bredis\b", source, re.I)


def test_gateway_upload_clean():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    failed = []
    for fname in clean_files:
        fpath = os.path.join(CLEAN_DIR, fname)
        with open(fpath, "rb") as f:
            file_data = f.read()
            file_hash = hashlib.sha256(file_data).hexdigest()
        try:
            resp = requests.post(GATEWAY_URL, files={"file": (fname, file_data)}, timeout=5)
            if resp.status_code != 200:
                failed.append(fname)
            else:
                expected_storage = os.path.join(STORAGE_DIR, f"{file_hash}.czip")
                if not os.path.isfile(expected_storage):
                    failed.append(fname + " (not in storage)")
        except Exception as e:
            failed.append(fname + f" (error: {e})")
    if failed:
        pytest.fail(f"Gateway failed to process clean files: {', '.join(failed)}")


def test_gateway_upload_evil():
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    bypassed = []
    for fname in evil_files:
        fpath = os.path.join(EVIL_DIR, fname)
        with open(fpath, "rb") as f:
            file_data = f.read()
            file_hash = hashlib.sha256(file_data).hexdigest()
        try:
            resp = requests.post(GATEWAY_URL, files={"file": (fname, file_data)}, timeout=5)
            if resp.status_code == 200:
                bypassed.append(fname)
            else:
                expected_storage = os.path.join(STORAGE_DIR, f"{file_hash}.czip")
                if os.path.isfile(expected_storage):
                    bypassed.append(fname + " (found in storage despite error)")
        except Exception:
            pass
    if bypassed:
        pytest.fail(f"Gateway bypassed evil files: {', '.join(bypassed)}")


def test_gateway_randomized_http_forwarding_and_redis():
    clear_events()
    cache = redis.Redis(host="127.0.0.1", port=6379)
    cache.flushall()
    payload = secrets.token_bytes(8192)
    inner_name = "inside_" + secrets.token_hex(8) + ".bin"
    upload_name = "upload_" + secrets.token_hex(8) + ".czip"
    artifact = make_czip(inner_name, payload)
    digest = hashlib.sha256(artifact).hexdigest()
    destination = os.path.join(STORAGE_DIR, digest + ".czip")
    if os.path.exists(destination):
        os.unlink(destination)

    response = requests.post(GATEWAY_URL, files={"file": (upload_name, artifact)}, timeout=15)
    assert response.status_code == 200
    for _ in range(30):
        if backend_events():
            break
        time.sleep(.1)
    events = backend_events()
    assert events, "gateway did not contact the HTTP storage backend"
    assert any(artifact in body and digest.encode() in
               (meta["path"].encode() + str(meta["headers"]).encode() + body)
               for meta, body in events), "backend did not receive the renamed artifact bytes"
    assert os.path.isfile(destination)
    assert open(destination, "rb").read() == artifact

    keys = cache.keys("*")
    assert keys, "gateway did not write metadata to Redis"
    redis_data = b"\n".join(keys + [cache.dump(key) or b"" for key in keys])
    assert digest.encode() in redis_data or upload_name.encode() in redis_data, \
        "Redis metadata is unrelated to the randomized upload"


def test_gateway_randomized_rejections_are_not_forwarded():
    cases = [
        make_czip("../" + secrets.token_hex(8), b"evil"),
        make_czip("bomb_" + secrets.token_hex(8), b"tiny", declared=10_000_001),
        make_czip("bad_" + secrets.token_hex(8), b"evil", magic=b"XXXX"),
    ]
    for artifact in cases:
        clear_events()
        digest = hashlib.sha256(artifact).hexdigest()
        destination = os.path.join(STORAGE_DIR, digest + ".czip")
        if os.path.exists(destination):
            os.unlink(destination)
        response = requests.post(
            GATEWAY_URL,
            files={"file": (secrets.token_hex(10) + ".czip", artifact)},
            timeout=10,
        )
        assert response.status_code != 200
        time.sleep(.1)
        assert not backend_events(), "rejected artifact was forwarded over HTTP"
        assert not os.path.exists(destination)


def test_filter_results_log():
    path = "/home/user/app/filter_results.log"
    assert os.path.isfile(path), "missing filter_results.log"
    text = open(path, encoding="utf-8", errors="replace").read().lower()
    assert text.strip()
    for directory in (CLEAN_DIR, EVIL_DIR):
        for name in os.listdir(directory):
            if os.path.isfile(os.path.join(directory, name)):
                assert name.lower() in text, f"log does not detail {name}"
    assert "accept" in text
    assert "reject" in text
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
