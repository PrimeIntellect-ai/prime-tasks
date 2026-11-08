#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import socket
import time

import pytest
import requests

SERVER_PATH = "/home/user/server"
URL = "http://127.0.0.1:8080/aggregate"
W = 4


def expected_counts(words):
    return [len(set(words[i:i + W])) for i in range(max(0, len(words) - W + 1))]


def assert_response(resp, expected):
    assert resp.status_code == 200, f"Expected status code 200, got {resp.status_code}"
    assert resp.raw.version == 11, "Server did not respond using HTTP/1.1"
    try:
        data = json.loads(resp.text)
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert data == expected, f"Expected {expected}, got {data}"


def test_server_executable_exists():
    """Test that the compiled C server executable exists."""
    assert os.path.isfile(SERVER_PATH), f"The server executable {SERVER_PATH} does not exist."
    assert os.access(SERVER_PATH, os.X_OK), f"The file {SERVER_PATH} is not executable."
    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The server is not a compiled ELF executable"


def test_server_aggregate_endpoint():
    """Retain the original three aggregate checks."""
    words_1 = "dog cat dog fish dog cat bird bird"
    expected_1 = [3, 3, 3, 4, 3]
    try:
        resp_1 = requests.post(URL, data=words_1, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert_response(resp_1, expected_1)

    words_2 = "a b c d e f"
    expected_2 = [4, 4, 4]
    resp_2 = requests.post(URL, data=words_2, timeout=5)
    assert_response(resp_2, expected_2)

    words_3 = "x x x x x"
    expected_3 = [1, 1]
    resp_3 = requests.post(URL, data=words_3, timeout=5)
    assert_response(resp_3, expected_3)


def test_randomized_rolling_windows():
    """Exercise unpredictable inputs and derive every expected result locally."""
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    nonce = secrets.token_hex(12)

    for case in range(24):
        vocabulary = [f"w{nonce}_{case}_{i}" for i in range(rng.randint(2, 14))]
        count = rng.randint(W, 90)
        words = [rng.choice(vocabulary) for _ in range(count)]
        expected = expected_counts(words)
        resp = requests.post(URL, data=" ".join(words), timeout=5)
        assert_response(resp, expected)

    # Include maximum-length words and a substantially larger body.
    long_words = []
    bases = [(secrets.token_hex(31) + c)[:64] for c in "abcdef"]
    for _ in range(1800):
        long_words.append(rng.choice(bases))
    resp = requests.post(URL, data=" ".join(long_words), timeout=10)
    assert_response(resp, expected_counts(long_words))


def test_reads_full_content_length_body():
    """Send a randomized request body in fragments over a raw HTTP connection."""
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    nonce = secrets.token_hex(16)
    vocabulary = [f"fragment_{nonce}_{i}" for i in range(9)]
    words = [rng.choice(vocabulary) for _ in range(57)]
    body = " ".join(words).encode("ascii")
    header = (
        b"POST /aggregate HTTP/1.1\r\n"
        b"Host: 127.0.0.1:8080\r\n"
        b"X-Random-Header: verifier\r\n"
        + f"Content-Length: {len(body)}\r\n".encode("ascii")
        + b"Connection: close\r\n\r\n"
    )

    with socket.create_connection(("127.0.0.1", 8080), timeout=5) as sock:
        sock.settimeout(5)
        split = max(1, len(body) // 3)
        sock.sendall(header + body[:split])
        time.sleep(0.05)
        sock.sendall(body[split:])
        chunks = []
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                pytest.fail("Server did not finish the fragmented HTTP response")
            if not chunk:
                break
            chunks.append(chunk)

    raw = b"".join(chunks)
    head, separator, response_body = raw.partition(b"\r\n\r\n")
    assert separator, f"Malformed HTTP response: {raw!r}"
    assert head.startswith(b"HTTP/1.1 200"), f"Expected HTTP/1.1 200 response, got {head!r}"
    try:
        result = json.loads(response_body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        pytest.fail(f"Invalid JSON response body: {e}: {response_body!r}")
    assert result == expected_counts(words)
TEST_EOF

# Remove any pre-existing listener so the verifier exercises /home/user/server
# itself rather than an unrelated process left on the configured port.
python3 << 'KILL_EOF'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
    except OSError:
        continue
    if any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
        try:
            os.kill(int(name), signal.SIGTERM)
        except (OSError, ValueError):
            pass
time.sleep(0.25)
KILL_EOF

/home/user/server >/tmp/verifier_server.log 2>&1 &
SERVER_PID=$!
sleep 0.5

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
STATUS=$?

kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
