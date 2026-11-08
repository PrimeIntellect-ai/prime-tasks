#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import gzip
import hashlib
import os
import secrets
import stat
import subprocess
import time

import pytest

SCRIPT = "/home/user/archive_worker.sh"
ACTIVE_DIR = "/home/user/active_logs"
ARCHIVE_DIR = "/home/user/archived_logs"
MANIFEST = os.path.join(ARCHIVE_DIR, "manifest.txt")

ORIGINAL_DATA = {
    "web.log": b"Web log line 1: GET /index.html 200\nWeb log line 2: POST /login 401\n",
    "db.log": b"Database connection established\n" + b"".join(
        f"DB query {i} executed\n".encode() for i in range(1, 101)
    ),
    "auth.log": b"Auth failure: user admin from 192.168.1.50\nAuth success: user root from 10.0.0.5\n",
}


def run_worker(path, *extra, timeout=10):
    return subprocess.run(
        [SCRIPT, path, *extra],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def manifest_lines():
    with open(MANIFEST, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def assert_archival_result(path, expected):
    basename = os.path.basename(path)
    archive = os.path.join(ARCHIVE_DIR, basename + ".gz")
    assert os.path.isfile(path), f"Log file {path} is missing."
    assert os.path.getsize(path) == 0, f"Log file {path} was not truncated to 0 bytes."
    assert os.path.isfile(archive), f"Archive {archive} does not exist."
    with open(archive, "rb") as f:
        assert f.read(2) == b"\x1f\x8b", f"File {archive} is not a valid gzip file."
    with gzip.open(archive, "rb") as f:
        archived = f.read()
    assert archived == expected, "Decompressed archive does not match the original log data."
    expected_line = f"{hashlib.sha256(expected).hexdigest()}  {basename}"
    assert expected_line in manifest_lines(), f"Missing exact manifest entry: {expected_line}"


def launch(path):
    return subprocess.Popen(
        [SCRIPT, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )


def finish(proc):
    try:
        out, err = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        pytest.fail("archive_worker.sh did not finish after the lock was released")
    assert proc.returncode == 0, (
        f"archive_worker.sh failed with status {proc.returncode}: "
        f"{err.decode(errors='replace')}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."


def test_script_uses_flock():
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "flock" in content, "The script must use 'flock' to lock files."


def test_logs_truncated():
    for name in ORIGINAL_DATA:
        path = os.path.join(ACTIVE_DIR, name)
        assert os.path.isfile(path), f"Log file {path} is missing."
        assert os.path.getsize(path) == 0, f"Log file {path} was not truncated to 0 bytes."


def test_archives_created_and_valid():
    for name, expected in ORIGINAL_DATA.items():
        archive = os.path.join(ARCHIVE_DIR, name + ".gz")
        assert os.path.isfile(archive), f"Archive {archive} does not exist."
        with open(archive, "rb") as f:
            magic = f.read(2)
        assert magic == b"\x1f\x8b", f"File {archive} is not a valid gzip file."
        with gzip.open(archive, "rb") as f:
            assert f.read() == expected, f"Archive {archive} has incorrect contents."


def test_manifest_contents():
    assert os.path.isfile(MANIFEST), f"Manifest file {MANIFEST} does not exist."
    with open(MANIFEST, "r") as f:
        manifest_content = f.read()

    for name, data in ORIGINAL_DATA.items():
        digest = hashlib.sha256(data).hexdigest()
        assert digest in manifest_content, f"Hash {digest} not found in manifest."
        assert name in manifest_content, f"{name} filename not found in manifest."
        assert f"{digest}  {name}" in manifest_lines(), (
            f"Manifest lacks the standard checksum entry for {name}."
        )


def test_executes_on_fresh_derived_input_and_locks_source():
    token = secrets.token_hex(8)
    name = f"verifier-source-{token}.log"
    path = os.path.join(ACTIVE_DIR, name)
    archive = os.path.join(ARCHIVE_DIR, name + ".gz")
    data = (f"dynamic {token} first line\n" + "".join(
        f"record {i}: {secrets.token_hex(12)}\n" for i in range(40)
    )).encode()
    with open(path, "wb") as f:
        f.write(data)
    if os.path.exists(archive):
        os.unlink(archive)

    with open(path, "r+b") as locked:
        fcntl.flock(locked.fileno(), fcntl.LOCK_EX)
        proc = launch(path)
        time.sleep(0.5)
        was_blocked = proc.poll() is None
        locked.seek(0)
        unchanged = locked.read() == data
        fcntl.flock(locked.fileno(), fcntl.LOCK_UN)
    finish(proc)

    assert was_blocked, "Worker did not wait for an exclusive lock on the target log."
    assert unchanged, "Worker changed the target while another process held its lock."
    assert_archival_result(path, data)


def test_manifest_append_is_exclusively_locked():
    token = secrets.token_hex(8)
    name = f"verifier-manifest-{token}.log"
    path = os.path.join(ACTIVE_DIR, name)
    archive = os.path.join(ARCHIVE_DIR, name + ".gz")
    data = f"manifest lock test {token}\n{secrets.token_hex(64)}\n".encode()
    with open(path, "wb") as f:
        f.write(data)
    if os.path.exists(archive):
        os.unlink(archive)

    with open(MANIFEST, "a+") as manifest:
        fcntl.flock(manifest.fileno(), fcntl.LOCK_EX)
        proc = launch(path)
        time.sleep(0.5)
        was_blocked = proc.poll() is None
        fcntl.flock(manifest.fileno(), fcntl.LOCK_UN)
    finish(proc)

    assert was_blocked, "Worker did not wait for the exclusive manifest lock."
    assert_archival_result(path, data)


def test_accepts_exactly_one_argument():
    no_arg = subprocess.run(
        [SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert no_arg.returncode != 0, "Worker must reject zero arguments."

    token = secrets.token_hex(8)
    path = os.path.join(ACTIVE_DIR, f"verifier-args-{token}.log")
    with open(path, "wb") as f:
        f.write(b"argument validation data\n")
    two_args = run_worker(path, "unexpected-extra-argument", timeout=5)
    assert two_args.returncode != 0, "Worker must reject more than one argument."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
