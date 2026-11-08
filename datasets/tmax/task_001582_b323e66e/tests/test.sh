#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import fcntl
import os
import struct
import subprocess
import time
from pathlib import Path

import pytest

SANITIZER_DIR = "/home/user/sanitizer"
RUN_CMD = ["cargo", "run", "-q", "--release", "--"]
DECODER = Path("/app/chunk_decoder")


def invoke(path, *, log=None, timeout=15):
    env = os.environ.copy()
    if log is not None:
        env["DECODER_AUDIT_LOG"] = str(log)
    return subprocess.run(
        RUN_CMD + [str(path)],
        cwd=SANITIZER_DIR,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def entry(filename_bytes, payload, magic=b"CPCK", declared_len=None):
    if declared_len is None:
        declared_len = len(payload)
    return (
        magic
        + struct.pack("<H", len(filename_bytes))
        + filename_bytes
        + struct.pack("<I", declared_len)
        + payload
    )


def logged_payloads(log):
    if not Path(log).exists():
        return []
    lines = Path(log).read_text().splitlines()
    return [base64.b64decode(line) for line in lines if line]


@pytest.fixture(scope="session", autouse=True)
def audited_decoder():
    original = DECODER.read_bytes()
    original_mode = DECODER.stat().st_mode
    replacement = b'''#!/usr/bin/env python3
import base64
import os
import signal
import sys

data = sys.stdin.buffer.read()
log = os.environ.get("DECODER_AUDIT_LOG")
if log:
    with open(log, "ab", buffering=0) as f:
        f.write(base64.b64encode(data) + b"\\n")
if data.startswith(b"\\xde\\xad"):
    os.kill(os.getpid(), signal.SIGABRT)
if data.startswith(b"EXIT7:"):
    sys.exit(7)
sys.exit(0)
'''
    DECODER.write_bytes(replacement)
    DECODER.chmod(0o755)
    try:
        yield
    finally:
        DECODER.write_bytes(original)
        DECODER.chmod(original_mode & 0o7777)


def test_sanitizer_adversarial_corpus():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    assert os.path.isdir(SANITIZER_DIR), f"Directory {SANITIZER_DIR} does not exist."
    assert os.path.isfile(os.path.join(SANITIZER_DIR, "Cargo.toml")), "Cargo.toml not found in sanitizer dir."

    build_res = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=SANITIZER_DIR,
        capture_output=True,
        text=True,
    )
    assert build_res.returncode == 0, f"Failed to build the Rust project:\n{build_res.stderr}"

    clean_files = sorted(f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f)))
    evil_files = sorted(f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f)))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    evil_bypassed = []

    for cf in clean_files:
        path = os.path.join(clean_dir, cf)
        res = invoke(path)
        stdout = res.stdout.strip()
        if res.returncode != 0 or stdout != "ACCEPT":
            clean_failed.append((cf, res.returncode, stdout))

    for ef in evil_files:
        path = os.path.join(evil_dir, ef)
        res = invoke(path)
        stdout = res.stdout.strip()
        if res.returncode != 1 or not stdout.startswith("REJECT:"):
            evil_bypassed.append((ef, res.returncode, stdout))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed:")
        for ef, rc, out in evil_bypassed:
            error_messages.append(f"  {ef} (rc={rc}, stdout={out!r})")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/failed:")
        for cf, rc, out in clean_failed:
            error_messages.append(f"  {cf} (rc={rc}, stdout={out!r})")
    if error_messages:
        pytest.fail("\n".join(error_messages))


def test_generated_valid_archive_and_exact_decoder_input(tmp_path):
    payload1 = os.urandom(137)
    payload2 = os.urandom(4097)
    name1 = "price€-café.ini".encode("cp1252")
    name2 = ("x" * 300).encode("cp1252")
    archive = tmp_path / ("generated-" + os.urandom(8).hex() + ".bin")
    log = tmp_path / "decoder.log"
    archive.write_bytes(entry(name1, payload1) + entry(name2, payload2))

    res = invoke(archive, log=log)
    assert res.returncode == 0, (res.returncode, res.stdout, res.stderr)
    assert res.stdout.strip() == "ACCEPT"
    assert logged_payloads(log) == [payload1, payload2], "Each payload must be passed exactly once and unchanged to chunk_decoder"


@pytest.mark.parametrize("filename", [b"../secret", b"dir/../secret", b"..\\secret", b"dir\\..\\secret", b"/rooted", b"\\rooted"])
def test_generated_traversal_rejections(tmp_path, filename):
    archive = tmp_path / ("case-" + os.urandom(7).hex())
    log = tmp_path / ("log-" + os.urandom(7).hex())
    archive.write_bytes(entry(filename, os.urandom(31)))
    res = invoke(archive, log=log)
    assert res.returncode == 1
    assert res.stdout.strip() == "REJECT: TRAVERSAL"
    assert logged_payloads(log) == [], "Unsafe entries must not reach the decoder"


def test_generated_bad_magic_and_trailing_entry(tmp_path):
    payload = os.urandom(53)
    archive = tmp_path / ("neutral-" + os.urandom(8).hex())
    log = tmp_path / "magic.log"
    archive.write_bytes(entry(b"valid-name", payload) + entry(b"later", b"data", magic=b"NOPE"))
    res = invoke(archive, log=log)
    assert res.returncode == 1
    assert res.stdout.strip() == "REJECT: BAD MAGIC"
    assert logged_payloads(log) == [payload], "Parser must process sequential entries and stop at the bad magic"


def test_generated_oversize_is_rejected_before_payload_or_decoder(tmp_path):
    archive = tmp_path / ("large-" + os.urandom(8).hex())
    log = tmp_path / "large.log"
    archive.write_bytes(entry(b"ordinary", b"", declared_len=10_485_761))
    res = invoke(archive, log=log)
    assert res.returncode == 1
    assert res.stdout.strip() == "REJECT: TOO LARGE"
    assert logged_payloads(log) == []


@pytest.mark.parametrize("payload", [b"\xde\xad" + b"signal", b"EXIT7:" + b"nonzero"])
def test_decoder_signal_and_nonzero_are_rejected(tmp_path, payload):
    archive = tmp_path / ("decoder-" + os.urandom(8).hex())
    log = tmp_path / ("decoder-log-" + os.urandom(8).hex())
    archive.write_bytes(entry(b"safe-name", payload))
    res = invoke(archive, log=log)
    assert res.returncode == 1
    assert res.stdout.strip() == "REJECT: DECODER CRASH"
    assert logged_payloads(log) == [payload]


def test_truncated_archive_is_not_accepted(tmp_path):
    archive = tmp_path / ("truncated-" + os.urandom(8).hex())
    archive.write_bytes(b"CPCK" + struct.pack("<H", 20) + b"short")
    res = invoke(archive)
    assert res.returncode == 1
    assert res.stdout.strip().startswith("REJECT:")


def test_shared_lock_is_taken_before_reading(tmp_path):
    initial = entry(b"ordinary", b"payload-one")
    replacement = entry(b"ordinary", b"payload-two", magic=b"BADC")
    assert len(initial) == len(replacement)

    archive = tmp_path / ("locked-" + os.urandom(8).hex())
    log = tmp_path / "lock.log"
    archive.write_bytes(initial)

    with open(archive, "r+b", buffering=0) as held:
        fcntl.flock(held.fileno(), fcntl.LOCK_EX)
        env = os.environ.copy()
        env["DECODER_AUDIT_LOG"] = str(log)
        proc = subprocess.Popen(
            RUN_CMD + [str(archive)],
            cwd=SANITIZER_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.75)
        assert proc.poll() is None, "Sanitizer did not block on the existing exclusive lock"
        assert logged_payloads(log) == [], "Decoder ran while another process held an exclusive lock"

        held.seek(0)
        held.write(replacement)
        held.truncate()
        os.fsync(held.fileno())
        fcntl.flock(held.fileno(), fcntl.LOCK_UN)

        try:
            stdout, stderr = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail("Sanitizer remained blocked after the lock was released")

    assert proc.returncode == 1, (proc.returncode, stdout, stderr)
    assert stdout.strip() == "REJECT: BAD MAGIC", "The archive must be locked before any header bytes are read"
    assert logged_payloads(log) == []
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
