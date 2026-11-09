#!/bin/bash
mkdir -p /logs/verifier

ORIGINAL_CONF="$(cat /home/user/server.conf 2>/dev/null)"
CURRENT_PORT=""
SERVER_PID=""

kill_listeners() {
    local port="$1"
    python3 - "$port" <<'PY'
import os
import signal
import sys
import time

port = int(sys.argv[1])
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[3] == "0A":
                    try:
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    except ValueError:
                        continue
                    if local_port == port:
                        inodes.add(fields[9])
    except OSError:
        pass

pids = set()
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
                pids.add(int(name))
                break
    except OSError:
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
PY
}

cleanup() {
    if [ -n "$CURRENT_PORT" ]; then
        kill_listeners "$CURRENT_PORT" >/dev/null 2>&1 || true
    fi
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$ORIGINAL_CONF" > /home/user/server.conf
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import time

import pytest
import requests

PORT = 8080
BASE_URL = f"http://127.0.0.1:{PORT}/upload"
AUTH_HEADER = {"Authorization": "Bearer golden eagle"}
EXTRACT_DIR = "/home/user/artifacts"


def create_artf_payload(files):
    """files is a list of tuples: (filename: str, content: bytes)."""
    payload = b"ARTF"
    payload += struct.pack("<H", len(files))
    for filename, content in files:
        filename_bytes = filename.encode("ascii")
        payload += struct.pack("<H", len(filename_bytes))
        payload += filename_bytes
        payload += struct.pack("<I", len(content))
        payload += content
    return payload


def wait_for_server():
    for _ in range(30):
        try:
            requests.get(f"http://127.0.0.1:{PORT}/", timeout=0.3)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.2)
    pytest.fail("Server did not start on configured address and port")


@pytest.fixture(scope="module", autouse=True)
def setup():
    wait_for_server()


def post(payload, headers=AUTH_HEADER):
    try:
        return requests.post(BASE_URL, headers=headers, data=payload, timeout=3)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")


def test_missing_auth():
    payload = create_artf_payload([("dummy.txt", b"dummy")])
    try:
        response = requests.post(BASE_URL, data=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {response.status_code}"


def test_incorrect_authorization_tokens():
    payload = create_artf_payload([("unauthorized.txt", b"must not be written")])
    destination = os.path.join(EXTRACT_DIR, "unauthorized.txt")
    if os.path.exists(destination):
        os.unlink(destination)
    bad_headers = [
        {"Authorization": "Bearer golden eaglex"},
        {"Authorization": "Bearer " + secrets.token_hex(16)},
        {"Authorization": "Basic golden eagle"},
    ]
    for headers in bad_headers:
        response = post(payload, headers)
        assert response.status_code == 401
        assert not os.path.exists(destination)


def test_valid_archive_extraction():
    payload = create_artf_payload([("test.txt", b"hello")])
    try:
        response = requests.post(BASE_URL, headers=AUTH_HEADER, data=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert response.status_code == 200, f"Expected 200 OK for valid archive, got {response.status_code}"
    extracted_file_path = os.path.join(EXTRACT_DIR, "test.txt")
    assert os.path.isfile(extracted_file_path), f"Expected extracted file at {extracted_file_path} does not exist"
    with open(extracted_file_path, "rb") as f:
        content = f.read()
    assert content == b"hello", f"Expected extracted file content to be 'hello', got {content}"


def test_randomized_multi_file_archives():
    for _ in range(3):
        files = []
        for index in range(4):
            name = f"artifact_{secrets.token_hex(7)}_{index}.bin"
            content = secrets.token_bytes(17 + index * 53)
            files.append((name, content))
            path = os.path.join(EXTRACT_DIR, name)
            if os.path.exists(path):
                os.unlink(path)
        response = post(create_artf_payload(files))
        assert response.status_code == 200
        for name, expected in files:
            path = os.path.join(EXTRACT_DIR, name)
            assert os.path.isfile(path)
            with open(path, "rb") as f:
                assert f.read() == expected


def test_malicious_archive_rejection():
    payload = create_artf_payload([("../hacked.txt", b"bad")])
    try:
        response = requests.post(BASE_URL, headers=AUTH_HEADER, data=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert response.status_code == 400, f"Expected 400 Bad Request for malicious archive, got {response.status_code}"
    hacked_file_path_1 = "/home/user/hacked.txt"
    hacked_file_path_2 = os.path.normpath(os.path.join(EXTRACT_DIR, "../hacked.txt"))
    assert not os.path.exists(hacked_file_path_1), f"Malicious file was extracted to {hacked_file_path_1}"
    assert not os.path.exists(hacked_file_path_2), f"Malicious file was extracted to {hacked_file_path_2}"


def test_randomized_absolute_and_traversal_names_are_rejected():
    marker = secrets.token_hex(10)
    outside = f"/tmp/artf_escape_{marker}"
    parent_escape = f"/home/user/artf_parent_{marker}"
    for path in (outside, parent_escape):
        if os.path.exists(path):
            os.unlink(path)
    malicious_names = [
        outside,
        f"../artf_parent_{marker}",
        f"folder/../escape_{marker}",
        f"prefix../suffix_{marker}",
    ]
    for name in malicious_names:
        response = post(create_artf_payload([(name, secrets.token_bytes(31))]))
        assert response.status_code == 400, f"Server accepted malicious filename {name!r}"
    assert not os.path.exists(outside)
    assert not os.path.exists(parent_escape)


def test_mixed_archive_is_rejected_atomically():
    marker = secrets.token_hex(12)
    safe_name = f"must_not_extract_{marker}.bin"
    escaped_name = f"escaped_{marker}.bin"
    safe_path = os.path.join(EXTRACT_DIR, safe_name)
    escaped_path = os.path.join("/home/user", escaped_name)
    for path in (safe_path, escaped_path):
        if os.path.exists(path):
            os.unlink(path)
    payload = create_artf_payload([
        (safe_name, secrets.token_bytes(97)),
        (f"../{escaped_name}", secrets.token_bytes(43)),
        (f"later_{marker}.bin", b"later"),
    ])
    response = post(payload)
    assert response.status_code == 400
    assert not os.path.exists(safe_path), "Safe entry from rejected mixed archive was extracted"
    assert not os.path.exists(escaped_path), "Traversal entry from rejected mixed archive was extracted"


def test_malformed_artf_is_rejected():
    malformed = [
        b"NOPE" + struct.pack("<H", 0),
        b"ARTF" + struct.pack("<H", 1),
        b"ARTF" + struct.pack("<H", 1) + struct.pack("<H", 10) + b"short",
        b"ARTF" + struct.pack("<H", 1) + struct.pack("<H", 3) + b"abc" + struct.pack("<I", 100) + b"tiny",
    ]
    for payload in malformed:
        response = post(payload)
        assert response.status_code == 400
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_config.py
import os
import secrets
import struct
import time

import requests

port = int(os.environ["DYN_PORT"])
extract_dir = os.environ["DYN_DIR"]
url = f"http://127.0.0.1:{port}/upload"

for _ in range(30):
    try:
        requests.get(f"http://127.0.0.1:{port}/", timeout=0.3)
        break
    except requests.exceptions.RequestException:
        time.sleep(0.2)
else:
    raise AssertionError("Server did not use the port from server.conf")

name = f"configured_{secrets.token_hex(8)}.bin"
data = secrets.token_bytes(113)
name_bytes = name.encode("ascii")
payload = (b"ARTF" + struct.pack("<H", 1) + struct.pack("<H", len(name_bytes)) +
           name_bytes + struct.pack("<I", len(data)) + data)
response = requests.post(url, headers={"Authorization": "Bearer golden eagle"}, data=payload, timeout=3)
assert response.status_code == 200
path = os.path.join(extract_dir, name)
assert os.path.isfile(path), "Server did not use or create extract_dir from server.conf"
with open(path, "rb") as f:
    assert f.read() == data
DYNAMIC_EOF

score=0
if [ -f /home/user/artifact_server.c ] && \
   gcc -O2 -pthread /home/user/artifact_server.c -o /tmp/verifier_artifact_server; then
    kill_listeners 8080 >/dev/null 2>&1 || true
    CURRENT_PORT=8080
    /tmp/verifier_artifact_server >/tmp/verifier_server.log 2>&1 &
    SERVER_PID=$!

    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        kill_listeners 8080 >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
        SERVER_PID=""

        DYN_PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
        DYN_DIR="/tmp/artf_dynamic_$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
        rm -rf "$DYN_DIR"
        printf 'port=%s\nextract_dir=%s\n' "$DYN_PORT" "$DYN_DIR" > /home/user/server.conf
        CURRENT_PORT="$DYN_PORT"
        export DYN_PORT DYN_DIR
        /tmp/verifier_artifact_server >/tmp/verifier_server_dynamic.log 2>&1 &
        SERVER_PID=$!
        if python3 /tmp/test_dynamic_config.py 2>&1; then
            score=1
        fi
    fi
fi

printf '%s\n' "$score" > /logs/verifier/reward.txt
exit 0
