#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import hashlib
import base64
import secrets
import shutil
import pytest

PASSPHRASE = "hunter two security"
HOST = "127.0.0.1"
PORT = 8080
UPLOAD_DIR = "/home/user/uploads"
LOG_PATH = "/home/user/server.log"


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def request_bytes(filename, payload_bytes, passphrase=PASSPHRASE, override_hash=None):
    payload_b64 = base64.b64encode(payload_bytes).decode("ascii")
    if override_hash is None:
        digest = hashlib.sha256(payload_bytes + passphrase.encode("utf-8")).hexdigest()
    else:
        digest = override_hash
    return f"FILENAME {filename}\nHASH {digest}\nPAYLOAD {payload_b64}\n".encode("utf-8")


def send_raw(data):
    chunks = []
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((HOST, PORT))
        s.sendall(data)
        s.shutdown(socket.SHUT_WR)
        while True:
            try:
                chunk = s.recv(1024)
            except ConnectionResetError:
                break
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode("utf-8", errors="strict")


def send_request(filename, payload_bytes, passphrase, override_hash=None):
    # Preserve the original request construction and one-read response check.
    payload_b64 = base64.b64encode(payload_bytes).decode('utf-8')
    if override_hash:
        hash_hex = override_hash
    else:
        m = hashlib.sha256()
        m.update(payload_bytes)
        m.update(passphrase.encode('utf-8'))
        hash_hex = m.hexdigest()

    req = f"FILENAME {filename}\nHASH {hash_hex}\nPAYLOAD {payload_b64}\n"

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((HOST, PORT))
        s.sendall(req.encode('utf-8'))
        resp = s.recv(1024).decode('utf-8')
        return resp


def test_valid_request():
    payload = b"hello world"
    filename = "valid.txt"
    remove_path(f"{UPLOAD_DIR}/{filename}")
    resp = send_request(filename, payload, PASSPHRASE)
    assert resp == "OK\n", f"Expected OK\\n for valid request, got: {repr(resp)}"

    filepath = f"/home/user/uploads/{filename}"
    assert os.path.isfile(filepath), f"File {filepath} was not created."
    with open(filepath, "rb") as f:
        assert f.read() == payload, f"File {filepath} content mismatch."


def test_path_traversal():
    payload = b"evil payload"
    filename = "../hacked.txt"
    remove_path("/home/user/hacked.txt")
    resp = send_request(filename, payload, PASSPHRASE)
    assert resp == "ERROR\n", f"Expected ERROR\\n for path traversal, got: {repr(resp)}"

    filepath = "/home/user/hacked.txt"
    assert not os.path.exists(filepath), f"Path traversal succeeded, {filepath} was created."


def test_invalid_hash():
    payload = b"bad hash payload"
    filename = "badhash.txt"
    remove_path(f"{UPLOAD_DIR}/{filename}")
    resp = send_request(filename, payload, PASSPHRASE, override_hash="badhash"*8)
    assert resp == "ERROR\n", f"Expected ERROR\\n for invalid hash, got: {repr(resp)}"

    filepath = f"/home/user/uploads/{filename}"
    assert not os.path.exists(filepath), f"File {filepath} was created despite invalid hash."


def test_server_log():
    log_path = "/home/user/server.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()

    assert "Written: valid.txt" in content, f"Log file does not contain expected entry. Content: {content}"


def test_randomized_valid_uploads_and_exact_logging():
    before = []
    if os.path.exists(LOG_PATH):
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            before = f.read().splitlines()

    expected_lines = []
    for i in range(4):
        filename = f"upload_{secrets.token_hex(10)}_{i}.bin"
        payload = secrets.token_bytes(31 + i * 47) + bytes([0, 10, 255, i])
        path = os.path.join(UPLOAD_DIR, filename)
        remove_path(path)
        assert send_raw(request_bytes(filename, payload)) == "OK\n"
        assert os.path.isfile(path)
        with open(path, "rb") as f:
            assert f.read() == payload
        expected_lines.append(f"Written: {filename}")

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        after = f.read().splitlines()
    assert after[:len(before)] == before
    assert after[len(before):] == expected_lines


def test_randomized_authentication_failures_do_not_write():
    for i in range(4):
        filename = f"reject_{secrets.token_hex(10)}_{i}.dat"
        payload = secrets.token_bytes(20 + i * 13)
        path = os.path.join(UPLOAD_DIR, filename)
        remove_path(path)

        if i == 0:
            bad_hash = hashlib.sha256(payload + b"wrong passphrase").hexdigest()
        elif i == 1:
            good = hashlib.sha256(payload + PASSPHRASE.encode()).hexdigest()
            bad_hash = ("0" if good[0] != "0" else "1") + good[1:]
        elif i == 2:
            bad_hash = "g" * 64
        else:
            good = hashlib.sha256(payload + PASSPHRASE.encode()).hexdigest()
            bad_hash = good.upper()
            if bad_hash == good:
                bad_hash = ("a" if good[0] != "a" else "b") + good[1:]

        assert send_raw(request_bytes(filename, payload, override_hash=bad_hash)) == "ERROR\n"
        assert not os.path.exists(path)


def test_randomized_traversal_and_forbidden_names():
    token = secrets.token_hex(10)
    nested_dir = os.path.join(UPLOAD_DIR, f"dir_{token}")
    os.makedirs(nested_dir, exist_ok=True)

    cases = [
        (f"../escape_{token}.bin", f"/home/user/escape_{token}.bin"),
        (f"prefix..suffix_{token}.bin", os.path.join(UPLOAD_DIR, f"prefix..suffix_{token}.bin")),
        (f"dir_{token}/nested.bin", os.path.join(nested_dir, "nested.bin")),
        (f"/tmp/absolute_{token}.bin", f"/tmp/absolute_{token}.bin"),
    ]
    for filename, possible_target in cases:
        remove_path(possible_target)
        payload = secrets.token_bytes(39)
        assert send_raw(request_bytes(filename, payload)) == "ERROR\n"
        assert not os.path.exists(possible_target)


def test_malformed_protocol_and_base64_are_rejected():
    token = secrets.token_hex(10)
    payload = secrets.token_bytes(25)
    encoded = base64.b64encode(payload).decode("ascii")
    digest = hashlib.sha256(payload + PASSPHRASE.encode()).hexdigest()

    malformed = [
        (f"missing_{token}.bin", f"FILENAME missing_{token}.bin\nHASH {digest}\n"),
        (f"order_{token}.bin", f"HASH {digest}\nFILENAME order_{token}.bin\nPAYLOAD {encoded}\n"),
        (f"label_{token}.bin", f"FILE label_{token}.bin\nHASH {digest}\nPAYLOAD {encoded}\n"),
        (f"base64a_{token}.bin", f"FILENAME base64a_{token}.bin\nHASH {digest}\nPAYLOAD !!!!\n"),
        (f"base64b_{token}.bin", f"FILENAME base64b_{token}.bin\nHASH {digest}\nPAYLOAD A===\n"),
    ]

    for filename, raw in malformed:
        path = os.path.join(UPLOAD_DIR, filename)
        remove_path(path)
        assert send_raw(raw.encode("utf-8")) == "ERROR\n"
        assert not os.path.exists(path)


def test_listener_is_a_compiled_native_process():
    listener_inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                listener_inodes.add(fields[9])
    assert listener_inodes, "No TCP listener found on 127.0.0.1:8080"

    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if any(target == f"socket:[{inode}]" for inode in listener_inodes):
                    owners.append(pid)
                    break
        except OSError:
            continue

    assert owners, "Could not identify the listening server process"
    native_owner = False
    interpreters = {"python", "python3", "perl", "ruby", "node", "java", "bash", "sh"}
    for pid in owners:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(exe, "rb") as f:
                is_elf = f.read(4) == b"\x7fELF"
            name = os.path.basename(exe).lower().split(".")[0]
            if is_elf and name not in interpreters:
                native_owner = True
        except OSError:
            pass
    assert native_owner, "The listening service is not running as a compiled native program"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
