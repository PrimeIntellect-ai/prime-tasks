#!/bin/bash
mkdir -p /logs/verifier

cleanup() {
    pkill -f '^python3 /home/user/archiver/api.py$' 2>/dev/null || true
    pkill -f '^python3 /home/user/archiver/worker.py$' 2>/dev/null || true
    redis-cli -s /home/user/archiver/redis.sock shutdown nosave >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Ensure the test controls the service instances and queue state.
pkill -f '^python3 /home/user/archiver/api.py$' 2>/dev/null || true
pkill -f '^python3 /home/user/archiver/worker.py$' 2>/dev/null || true
redis-cli -s /home/user/archiver/redis.sock shutdown nosave >/dev/null 2>&1 || true
rm -f /home/user/archiver/redis.sock
redis-server /home/user/archiver/redis.conf >/tmp/verifier_redis.log 2>&1 || true

for i in $(seq 1 50); do
    if redis-cli -s /home/user/archiver/redis.sock ping 2>/dev/null | grep -q PONG; then
        break
    fi
    sleep 0.1
done
redis-cli -s /home/user/archiver/redis.sock flushall >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.util
import json
import os
import random
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request

import pytest
import redis

ROOT = "/home/user/archiver"
SOCKET = os.path.join(ROOT, "redis.sock")


def load_sanitizer():
    sanitizer_path = os.path.join(ROOT, "sanitizer.py")
    if not os.path.exists(sanitizer_path):
        pytest.fail(f"File not found: {sanitizer_path}")

    spec = importlib.util.spec_from_file_location("sanitizer", sanitizer_path)
    sanitizer = importlib.util.module_from_spec(spec)
    sys.modules["sanitizer"] = sanitizer
    try:
        spec.loader.exec_module(sanitizer)
    except Exception as e:
        pytest.fail(f"Failed to import sanitizer.py: {e}")
    return sanitizer


def make_chunk(payload, source="db_server", magic=b"BKP1", header=None, declared_len=None):
    if header is None:
        header = {
            "timestamp": random.randint(1, 2**31),
            "source": source,
            "checksum": hashlib.sha256(payload).hexdigest(),
        }
    header_bytes = json.dumps(header, separators=(",", ":")).encode("utf-8")
    if declared_len is None:
        declared_len = len(header_bytes)
    return magic + struct.pack("<I", declared_len) + header_bytes + payload


def test_sanitizer_adversarial_corpus():
    sanitizer = load_sanitizer()
    assert hasattr(sanitizer, "sanitize_chunk"), "Function 'sanitize_chunk' is missing from sanitizer.py"
    sanitize_chunk = sanitizer.sanitize_chunk

    evil_dir = os.path.join(ROOT, "corpus/evil")
    clean_dir = os.path.join(ROOT, "corpus/clean")
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, "No files found in evil corpus directory"
    assert clean_files, "No files found in clean corpus directory"

    evil_bypassed = []
    for path in evil_files:
        try:
            if sanitize_chunk(path) is not False:
                evil_bypassed.append(os.path.basename(path))
        except Exception:
            evil_bypassed.append(os.path.basename(path) + " (exception raised)")

    clean_modified = []
    for path in clean_files:
        try:
            if sanitize_chunk(path) is not True:
                clean_modified.append(os.path.basename(path))
        except Exception:
            clean_modified.append(os.path.basename(path) + " (exception raised)")

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_sanitizer_generated_inputs_at_unlabeled_paths():
    sanitize = load_sanitizer().sanitize_chunk

    with tempfile.TemporaryDirectory(prefix="archiver-hidden-") as td:
        cases = []

        # Fresh valid chunks deliberately receive suspicious-looking names.
        for i in range(8):
            payload = os.urandom(random.randint(0, 300))
            source = "prod-" + os.urandom(5).hex()
            cases.append((f"evil_generated_{i}.bin", make_chunk(payload, source=source), True))

        payload = os.urandom(57)
        good_checksum = hashlib.sha256(payload).hexdigest()
        base = {"source": "prod", "checksum": good_checksum}
        cases.extend([
            ("clean_wrong_magic.bin", make_chunk(payload, magic=b"BKP2"), False),
            ("clean_forbidden_test.bin", make_chunk(payload, source="test"), False),
            ("clean_forbidden_unknown.bin", make_chunk(payload, source="unknown"), False),
            ("clean_missing_source.bin", make_chunk(payload, header={"checksum": good_checksum}), False),
            ("clean_missing_checksum.bin", make_chunk(payload, header={"source": "prod"}), False),
            ("clean_bad_checksum.bin", make_chunk(payload, header={"source": "prod", "checksum": "0" * 64}), False),
            ("clean_short_file.bin", b"BKP1\x01\x00", False),
            ("clean_malformed_json.bin", b"BKP1" + struct.pack("<I", 5) + b"{nope" + payload, False),
            ("clean_invalid_utf8.bin", b"BKP1" + struct.pack("<I", 2) + b"\xff\xfe" + payload, False),
            ("clean_json_array.bin", b"BKP1" + struct.pack("<I", 2) + b"[]" + payload, False),
            ("clean_truncated_header.bin", b"BKP1" + struct.pack("<I", 100) + b"{}", False),
            ("clean_oversize_header.bin", b"BKP1" + struct.pack("<I", 1025) + b" " * 1025 + payload, False),
        ])

        random.shuffle(cases)
        for name, data, expected in cases:
            path = os.path.join(td, name)
            with open(path, "wb") as f:
                f.write(data)
            try:
                result = sanitize(path)
            except Exception as exc:
                pytest.fail(f"sanitize_chunk raised for generated case {name}: {exc}")
            assert result is expected, f"wrong result for generated case {name}: got {result!r}"


def test_api_redis_config():
    api_path = os.path.join(ROOT, "api.py")
    assert os.path.exists(api_path), f"File not found: {api_path}"
    with open(api_path, "r") as f:
        content = f.read()
    assert "redis.sock" in content, "api.py does not appear to be configured to use redis.sock"
    assert "6379" not in content, "api.py still contains the default TCP port 6379"


def test_worker_redis_config():
    worker_path = os.path.join(ROOT, "worker.py")
    assert os.path.exists(worker_path), f"File not found: {worker_path}"
    with open(worker_path, "r") as f:
        content = f.read()
    assert "redis.sock" in content, "worker.py does not appear to be configured to use redis.sock"
    assert "6379" not in content, "worker.py still contains the default TCP port 6379"


def test_worker_integration_source_assertions():
    worker_path = os.path.join(ROOT, "worker.py")
    assert os.path.exists(worker_path), f"File not found: {worker_path}"
    with open(worker_path, "r") as f:
        content = f.read()
    assert "sanitize_chunk" in content, "worker.py does not appear to use the sanitize_chunk function"
    assert "master_archive.bin" in content, "worker.py does not reference master_archive.bin"
    assert "rejected.log" in content, "worker.py does not reference rejected.log"


def wait_for(predicate, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def wait_for_api(proc):
    def ready():
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.15):
                return True
        except OSError:
            return False
    assert wait_for(ready), "Flask API did not start on port 8080"


def upload(data):
    request = urllib.request.Request(
        "http://127.0.0.1:8080/upload", data=data, method="POST",
        headers={"Content-Type": "application/octet-stream"},
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        assert response.status == 200


def start_worker():
    return subprocess.Popen(
        [sys.executable, os.path.join(ROOT, "worker.py")],
        cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def test_actual_api_redis_worker_archive_and_rejection_behavior():
    client = redis.Redis(unix_socket_path=SOCKET)
    assert client.ping() is True, "Redis is not running on the required Unix socket"
    client.flushall()

    archive = os.path.join(ROOT, "master_archive.bin")
    rejected = os.path.join(ROOT, "rejected.log")
    for path in (archive, rejected):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    api = subprocess.Popen(
        [sys.executable, os.path.join(ROOT, "api.py")],
        cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    worker = None
    try:
        wait_for_api(api)

        # Verify that the API writes the exact body to disk and queues its path.
        valid_payload = b"hidden-valid-payload:" + os.urandom(96)
        valid_chunk = make_chunk(valid_payload, source="live-" + os.urandom(4).hex())
        upload(valid_chunk)
        queued = client.brpop("backup_queue", timeout=3)
        assert queued is not None, "API did not enqueue the uploaded chunk in Redis"
        valid_path = queued[1].decode("utf-8")
        assert os.path.isfile(valid_path), "API queued a nonexistent filepath"
        with open(valid_path, "rb") as f:
            assert f.read() == valid_chunk, "API did not preserve the binary request body"

        client.lpush("backup_queue", valid_path)
        worker = start_worker()
        assert wait_for(lambda: os.path.exists(archive) and open(archive, "rb").read() == valid_payload), \
            "Worker did not append exactly the valid chunk payload to master_archive.bin"
        stop_process(worker)
        worker = None

        # Exercise rejection through the same API/Redis path with a fresh random file.
        bad_payload = b"hidden-invalid-payload:" + os.urandom(64)
        bad_chunk = make_chunk(
            bad_payload,
            header={"source": "prod", "checksum": hashlib.sha256(b"different").hexdigest()},
        )
        upload(bad_chunk)
        queued = client.brpop("backup_queue", timeout=3)
        assert queued is not None, "API did not enqueue the invalid upload"
        bad_path = queued[1].decode("utf-8")
        client.lpush("backup_queue", bad_path)

        worker = start_worker()
        def rejected_logged():
            if not os.path.exists(rejected):
                return False
            with open(rejected, "r", errors="replace") as f:
                lines = [line.strip() for line in f if line.strip()]
            return any(os.path.basename(line) == os.path.basename(bad_path) for line in lines)

        assert wait_for(rejected_logged), "Worker did not log the rejected upload filename"
        with open(archive, "rb") as f:
            assert f.read() == valid_payload, "Invalid chunk data was appended to the master archive"
    finally:
        stop_process(worker)
        stop_process(api)
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
