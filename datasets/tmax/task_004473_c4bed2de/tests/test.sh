#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import secrets
import stat
import subprocess

import pytest
import redis
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

AUDIT_DIR = "/home/user/secure_audit"
AUDIT_FILE = "/home/user/secure_audit/audit.enc"
PROJECT_DIR = "/home/user/ids_analyzer"
LOG_FILE = "/home/user/logs/access.log"


def assert_permissions():
    assert os.path.isdir(AUDIT_DIR), f"Expected directory {AUDIT_DIR} is missing."
    dir_perms = stat.S_IMODE(os.stat(AUDIT_DIR).st_mode)
    assert dir_perms == 0o700, f"Directory {AUDIT_DIR} must have 0700 permissions, but has {oct(dir_perms)}."

    assert os.path.isfile(AUDIT_FILE), f"Expected file {AUDIT_FILE} is missing."
    file_perms = stat.S_IMODE(os.stat(AUDIT_FILE).st_mode)
    assert file_perms == 0o600, f"File {AUDIT_FILE} must have 0600 permissions, but has {oct(file_perms)}."


def read_records():
    assert os.path.isfile(AUDIT_FILE), f"File {AUDIT_FILE} does not exist."
    with open(AUDIT_FILE, "rb") as f:
        data = f.read()

    assert len(data) > 0, f"File {AUDIT_FILE} is empty."

    records = []
    offset = 0
    while offset < len(data):
        if offset + 2 > len(data):
            pytest.fail(f"Incomplete 2-byte length header at offset {offset} in {AUDIT_FILE}.")
        length = int.from_bytes(data[offset:offset + 2], byteorder="big")
        offset += 2
        if offset + length > len(data):
            pytest.fail(f"Record length {length} at offset {offset - 2} exceeds remaining file size.")
        records.append(data[offset:offset + length])
        offset += length

    assert records, f"No valid encrypted records found in {AUDIT_FILE}."
    return records


def test_secure_audit_permissions():
    assert_permissions()


def test_audit_file_structure():
    read_records()


def build_release_binary():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(cargo_toml), "The required Rust project Cargo.toml is missing."
    assert os.path.isfile(main_rs), "The required Rust program src/main.rs is missing."
    assert os.path.getsize(main_rs) > 0, "src/main.rs is empty."

    result = subprocess.run(
        ["cargo", "build", "--release", "--message-format=json"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, f"cargo build --release failed:\n{result.stderr}"

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get("target", {})
        executable = message.get("executable")
        if message.get("reason") == "compiler-artifact" and executable and "bin" in target.get("kind", []):
            executables.append(executable)

    assert executables, "Cargo did not produce a release binary target."
    binary = executables[-1]
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "The release binary is missing or not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The Cargo binary is not a native executable."
    return binary


def test_f1_score_metric():
    binary = build_release_binary()

    client = redis.Redis(host="localhost", port=6379, socket_connect_timeout=2, socket_timeout=2)
    try:
        assert client.ping(), "Redis is not running on localhost:6379."
    except Exception as exc:
        pytest.fail(f"Redis is not running on localhost:6379: {exc}")

    old_patterns = client.smembers("threat_patterns")
    old_log_exists = os.path.exists(LOG_FILE)
    old_log = open(LOG_FILE, "rb").read() if old_log_exists else b""
    old_log_mode = stat.S_IMODE(os.stat(LOG_FILE).st_mode) if old_log_exists else None

    token = secrets.token_hex(8)
    first = "u" + token
    second = "s" + token
    xss = "x" + token
    traversal = "e" + token
    patterns = [
        rf"(?i){first}.*{second}",
        rf"(?i){xss}",
        rf"(?i){traversal}/passwd",
    ]
    compiled = [re.compile(pattern) for pattern in patterns]

    lines = []
    expected_indexes = []
    for i in range(60):
        kind = i % 5
        if kind == 0:
            target = f"/?q={first.upper()}{i}middle{second.upper()}"
        elif kind == 1:
            target = f"/search/{xss.upper()}{i}?source=audit"
        elif kind == 2:
            target = f"/../../{traversal.upper()}/passwd?attempt={i}"
        elif kind == 3:
            target = f"/?q={first}{i}"
        else:
            target = f"/normal/resource/{i}?q=safe"

        line = f'127.0.0.1 - - [01/Jan/2026:00:00:{i:02d} +0000] "GET {target} HTTP/1.1" 200 3 "-" "ids-verifier"'
        lines.append(line)
        if any(pattern.search(target) for pattern in compiled):
            expected_indexes.append(i)

    try:
        client.delete("threat_patterns")
        client.sadd("threat_patterns", *patterns)
        with open(LOG_FILE, "wb") as f:
            f.write(("\n".join(lines) + "\n").encode("utf-8"))

        result = subprocess.run(
            [binary],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, f"IDS analyzer failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

        assert_permissions()
        encrypted_records = read_records()

        key_text = open("/home/user/keys/audit.key", "r", encoding="ascii").read().strip()
        key = bytes.fromhex(key_text)
        assert len(key) == 32, "The supplied audit key is not 32 bytes."
        aesgcm = AESGCM(key)
        nonce = bytes(12)

        variants = {}
        for index, line in enumerate(lines):
            raw = line.encode("utf-8")
            variants[raw] = index
            variants[raw + b"\n"] = index
            variants[raw + b"\r\n"] = index

        predicted = collections.Counter()
        for record_number, ciphertext in enumerate(encrypted_records):
            assert len(ciphertext) >= 16, f"Encrypted record {record_number} is too short to contain an AES-GCM tag."
            try:
                plaintext = aesgcm.decrypt(nonce, ciphertext, None)
            except Exception as exc:
                pytest.fail(f"Encrypted record {record_number} is not valid AES-256-GCM with the supplied key and nonce: {exc}")
            assert plaintext in variants, f"Record {record_number} does not decrypt to an unaltered input log line."
            predicted[variants[plaintext]] += 1

        expected = collections.Counter(expected_indexes)
        true_positives = sum(min(predicted[i], expected[i]) for i in expected)
        false_positives = sum(predicted.values()) - true_positives
        false_negatives = sum(expected.values()) - true_positives
        denominator = 2 * true_positives + false_positives + false_negatives
        score = (2 * true_positives / denominator) if denominator else 0.0
        assert score >= 0.95, (
            f"F1 score {score:.4f} is below 0.95 "
            f"(TP={true_positives}, FP={false_positives}, FN={false_negatives})."
        )
    finally:
        client.delete("threat_patterns")
        if old_patterns:
            client.sadd("threat_patterns", *old_patterns)
        if old_log_exists:
            with open(LOG_FILE, "wb") as f:
                f.write(old_log)
            os.chmod(LOG_FILE, old_log_mode)
        elif os.path.exists(LOG_FILE):
            os.unlink(LOG_FILE)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
