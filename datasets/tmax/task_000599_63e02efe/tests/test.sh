#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import socket
import stat
import string
import subprocess
import threading
import time

import pytest
import redis
import requests

API_URL = "http://127.0.0.1:8080/top-words"
VALID_TOKEN = "SecretAutomationToken2024"
AUTH_HEADERS = {"Authorization": f"Bearer {VALID_TOKEN}"}
API_LOG = open("/tmp/verifier_api.log", "wb")
PROCESSOR_LOG = open("/tmp/verifier_processor.log", "wb")


def kill_port_listeners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.5)


def kill_matching_processes(fragment):
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="ignore")
            if fragment in cmdline:
                os.kill(int(name), 9)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def wait_for_api(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(API_URL, timeout=1)
            return
        except requests.RequestException:
            time.sleep(0.2)
    pytest.fail("API started from /home/user/api.py did not become reachable")


def redis_client():
    return redis.Redis(host="127.0.0.1", port=6379, socket_connect_timeout=2, socket_timeout=2)


# Execute the submitted API artifact rather than trusting an already-running service.
kill_port_listeners(8080)
API_PROCESS = subprocess.Popen(
    ["python3", "/home/user/api.py"],
    cwd="/home/user",
    stdout=API_LOG,
    stderr=subprocess.STDOUT,
)
wait_for_api()

# A runtime-generated value prevents a static authorized response from passing.
rng = random.SystemRandom()
probe_words = [
    "probe" + "".join(rng.choice(string.ascii_lowercase) for _ in range(12))
    for _ in range(3)
]
rdb = redis_client()
rdb.set("window_top_words", json.dumps(probe_words, ensure_ascii=False))


def test_services_and_artifacts():
    for path in ("/home/user/api.py", "/home/user/processor.py"):
        info = os.stat(path)
        assert stat.S_ISREG(info.st_mode), f"{path} must be a regular file"
        assert info.st_size > 0, f"{path} must not be empty"

    assert rdb.ping() is True, "Redis is not running on localhost:6379"

    # Preserve the requirement that the simulator was left running and streaming.
    with socket.create_connection(("127.0.0.1", 9000), timeout=3) as conn:
        conn.settimeout(3)
        line = b""
        while not line.endswith(b"\n"):
            chunk = conn.recv(4096)
            assert chunk, "Simulator closed without streaming a line"
            line += chunk
        parts = line.rstrip(b"\r\n").split(b",", 2)
        assert len(parts) == 3, f"Simulator line has invalid structure: {line!r}"
        int(parts[0])


def test_unauthorized_no_token():
    try:
        response = requests.get(API_URL, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for no token, got {response.status_code}"


def test_unauthorized_bad_token():
    headers = {"Authorization": "Bearer BadToken123"}
    try:
        response = requests.get(API_URL, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for bad token, got {response.status_code}"


def test_authorized_success_and_redis_binding():
    response = requests.get(API_URL, headers=AUTH_HEADERS, timeout=5)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert "top_words" in data, "Response JSON missing 'top_words' key."
    assert isinstance(data["top_words"], list), "'top_words' must be a list."
    assert len(data["top_words"]) > 0, "Expected a nonempty top_words list."
    assert len(data["top_words"]) <= 5, f"Expected up to 5 top words, got {len(data['top_words'])}."
    for word in data["top_words"]:
        assert isinstance(word, str), "Each top word must be a string."
    assert data["top_words"] == probe_words, "API did not return the current Redis value"


def test_processor_decoding_timestamp_windows_and_counts():
    # Stop the shipped simulator and any old processor, then substitute a controlled
    # TCP stream. The submitted processor is freshly executed against that stream.
    kill_matching_processes("/home/user/processor.py")
    kill_port_listeners(9000)
    rdb.delete("window_top_words")

    suffix = "".join(rng.choice(string.ascii_lowercase) for _ in range(10))
    words = [
        "alpha" + suffix,
        "café" + suffix,
        "東京" + suffix,
        "delta" + suffix,
        "echo" + suffix,
        "foxtrot" + suffix,
    ]
    expected = words[:5]
    base = 1700000000000

    def repetitions(word, count):
        return " ".join(word.upper() if i % 2 else word for i in range(count))

    records = [
        str(base + 100).encode() + b",utf-8," + repetitions(words[0], 9).encode("utf-8") + b"\n",
        str(base + 200).encode() + b",iso-8859-1," + repetitions(words[1], 8).encode("iso-8859-1") + b"\n",
        str(base + 300).encode() + b",shift_jis," + repetitions(words[2], 7).encode("shift_jis") + b"\n",
        str(base + 400).encode() + b",utf-8," + repetitions(words[3], 6).encode("utf-8") + b"\n",
        str(base + 500).encode() + b",utf-8," + repetitions(words[4], 5).encode("utf-8") + b"\n",
        str(base + 600).encode() + b",utf-8," + repetitions(words[5], 4).encode("utf-8") + b"\n",
        # These must be dropped entirely.
        str(base + 700).encode() + b",unknown-encoding," + (b"intruder " * 30) + b"\n",
        str(base + 800).encode() + b",utf-8," + (b"corruptword " * 30) + b"\xff\n",
        # This event is exactly in the next timestamp-based tumbling window and
        # must cause the prior window to be committed.
        str(base + 10000).encode() + b",utf-8,boundaryword\n",
    ]

    ready = threading.Event()
    connected = threading.Event()
    server_errors = []

    def serve_stream():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 9000))
                server.listen(5)
                server.settimeout(12)
                ready.set()
                conn, _ = server.accept()
                connected.set()
                with conn:
                    for record in records:
                        conn.sendall(record)
                        time.sleep(0.03)
                    time.sleep(2)
        except Exception as exc:
            server_errors.append(repr(exc))
            ready.set()

    thread = threading.Thread(target=serve_stream, daemon=True)
    thread.start()
    assert ready.wait(3), "Controlled simulator did not start"
    assert not server_errors, f"Controlled simulator failed: {server_errors}"

    processor = subprocess.Popen(
        ["python3", "/home/user/processor.py"],
        cwd="/home/user",
        stdout=PROCESSOR_LOG,
        stderr=subprocess.STDOUT,
    )
    assert connected.wait(8), "processor.py did not connect to localhost:9000"

    deadline = time.time() + 15
    observed = None
    raw = None
    while time.time() < deadline:
        raw = rdb.get("window_top_words")
        if raw is not None:
            try:
                observed = json.loads(raw.decode("utf-8"))
            except Exception:
                observed = None
            if observed == expected:
                break
        if processor.poll() is not None:
            break
        time.sleep(0.2)

    assert processor.poll() is None, "processor.py exited while processing the stream"
    assert raw is not None, "processor did not write window_top_words to Redis"
    assert observed == expected, (
        "Incorrect timestamp-window aggregation, decoding, filtering, counting, "
        f"or ranking. Expected {expected!r}, got {observed!r}"
    )

    response = requests.get(API_URL, headers=AUTH_HEADERS, timeout=5)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert "top_words" in data, "Response JSON missing 'top_words' key."
    assert isinstance(data["top_words"], list), "'top_words' must be a list."
    assert len(data["top_words"]) == 5, f"Expected 5 top words, got {len(data['top_words'])}."
    assert data["top_words"] == expected, "API did not expose the processor's Redis result"
    for word in data["top_words"]:
        assert isinstance(word, str), "Each top word must be a string."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
