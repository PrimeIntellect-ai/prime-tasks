#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the mutable documentation producers, but keep/start Redis for metadata tests.
pkill -f '[d]oc_writer.py' 2>/dev/null || true
pkill -f '[d]oc_server.py' 2>/dev/null || true
redis-server --daemonize yes >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time

import pytest
import redis

BACKUP_FILE = "/home/user/backup.tar.xz"
ARCHIVER = "/home/user/archiver.py"
LAST_RUN = "/home/user/last_run.txt"
DOCS_DIR = "/app/docs"


def redis_client():
    client = redis.Redis(host="localhost", port=6379, db=0)
    client.ping()
    return client


def install_fixture():
    shutil.rmtree(DOCS_DIR, ignore_errors=True)
    os.makedirs(DOCS_DIR, mode=0o777)

    sources = {
        "latin.txt": ("iso-8859-1", ("Café documentation section. " * 5000).encode("iso-8859-1")),
        "manual.md": ("shift_jis", ("日本語の文書です。" * 5000).encode("shift_jis")),
        "unicode.txt": ("utf-16", ("UTF sixteen documentation. " * 5000).encode("utf-16")),
    }
    media = {
        "audio.media": bytes(range(32)) + os.urandom(65536),
        "video.media": bytes(reversed(range(32))) + os.urandom(65536),
    }

    client = redis_client()
    client.flushdb()
    now = time.time()
    for name, (encoding, data) in sources.items():
        with open(os.path.join(DOCS_DIR, name), "wb") as handle:
            handle.write(data)
        client.set(f"encoding:{name}", encoding)
        client.set(f"last_modified:{name}", str(now))
    for name, data in media.items():
        with open(os.path.join(DOCS_DIR, name), "wb") as handle:
            handle.write(data)
        client.set(f"last_modified:{name}", str(now))

    os.chmod(DOCS_DIR, 0o777)
    for name in os.listdir(DOCS_DIR):
        os.chmod(os.path.join(DOCS_DIR, name), 0o666)

    with open(LAST_RUN, "w", encoding="utf-8") as handle:
        handle.write("0\n")
    for path in (BACKUP_FILE,):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def expected_text(names):
    client = redis_client()
    result = {}
    for name in names:
        encoding_raw = client.get(f"encoding:{name}")
        assert encoding_raw is not None, f"Missing Redis encoding metadata for {name}"
        encoding = encoding_raw.decode("ascii")
        with open(os.path.join(DOCS_DIR, name), "rb") as handle:
            result[name] = handle.read().decode(encoding).encode("utf-8")
    return result


def expected_headers(names):
    result = {}
    for name in names:
        with open(os.path.join(DOCS_DIR, name), "rb") as handle:
            result[name] = handle.read(32).hex()
    return result


def read_last_run():
    assert os.path.isfile(LAST_RUN), "last_run.txt was not created"
    with open(LAST_RUN, "r", encoding="utf-8") as handle:
        value = float(handle.read().strip())
    assert value > 0, "last_run.txt does not contain a positive Unix timestamp"
    return value


def inspect_archive(text_expected, headers_expected):
    assert os.path.exists(BACKUP_FILE), f"Backup file {BACKUP_FILE} not found."
    archive_size = os.path.getsize(BACKUP_FILE)
    assert archive_size > 0, "Backup file is empty."

    try:
        archive = tarfile.open(BACKUP_FILE, "r:xz")
    except tarfile.ReadError:
        pytest.fail(f"Backup file {BACKUP_FILE} is not a valid tar.xz archive.")

    with archive:
        regular = [member for member in archive.getmembers() if member.isfile()]
        basenames = [os.path.basename(member.name) for member in regular]
        assert len(basenames) == len(set(basenames)), "Archive contains duplicate file basenames"
        expected_names = set(text_expected) | {"media_headers.json"}
        assert set(basenames) == expected_names, (
            f"Archive files are incorrect. Expected {sorted(expected_names)}, got {sorted(basenames)}"
        )
        members = {os.path.basename(member.name): member for member in regular}

        raw_text_size = 0
        for name, wanted in text_expected.items():
            extracted = archive.extractfile(members[name])
            assert extracted is not None
            content = extracted.read()
            try:
                content.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail(f"File {name} is not valid UTF-8 in the archive.")
            assert content == wanted, f"Archived UTF-8 content for {name} does not match the source"
            raw_text_size += len(content)

        header_member = members["media_headers.json"]
        header_bytes = archive.extractfile(header_member).read()
        try:
            media_headers = json.loads(header_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            pytest.fail("media_headers.json is not valid UTF-8 JSON.")
        assert media_headers == headers_expected, (
            f"Incorrect media header mapping. Expected {headers_expected}, got {media_headers}"
        )

    header_data_size = len(header_bytes)
    efficiency_score = (raw_text_size + header_data_size) / archive_size
    assert efficiency_score >= 4.5, (
        f"Efficiency score {efficiency_score:.2f} is below threshold 4.5. "
        f"Archive size: {archive_size}, Text size: {raw_text_size}, Header size: {header_data_size}"
    )


def test_archiver_behavior():
    assert os.path.isfile(ARCHIVER), f"Archiver script {ARCHIVER} not found."
    install_fixture()

    all_text = ["latin.txt", "manual.md", "unicode.txt"]
    all_media = ["audio.media", "video.media"]
    first_text_expected = expected_text(all_text)
    first_headers_expected = expected_headers(all_media)

    # Hold exclusive locks on every source. A conforming archiver must remain blocked
    # until shared locks can be acquired, then complete after the locks are released.
    locked = []
    proc = None
    started = time.time()
    try:
        for name in all_text + all_media:
            handle = open(os.path.join(DOCS_DIR, name), "rb")
            fcntl.flock(handle, fcntl.LOCK_EX)
            locked.append(handle)
        proc = subprocess.Popen(
            [sys.executable, ARCHIVER],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={**os.environ, "HOME": "/home/user"},
        )
        time.sleep(1.0)
        assert proc.poll() is None, "Archiver did not wait for exclusively locked source files"
    finally:
        for handle in locked:
            fcntl.flock(handle, fcntl.LOCK_UN)
            handle.close()

    stdout, stderr = proc.communicate(timeout=45)
    assert proc.returncode == 0, f"Archiver failed:\nstdout:\n{stdout}\nstderr:\n{stderr}"
    finished = time.time()
    inspect_archive(first_text_expected, first_headers_expected)
    first_run = read_last_run()
    assert started - 2 <= first_run <= finished + 2, "last_run.txt was not updated after the backup"

    # Exercise incrementality: modify exactly one text and one media file after the
    # previous run. The replacement archive must contain only those modified items.
    time.sleep(1.2)
    changed_text = "latin.txt"
    changed_media = "audio.media"
    new_text_raw = ("Résumé incremental update. " * 6000).encode("iso-8859-1")
    with open(os.path.join(DOCS_DIR, changed_text), "wb") as handle:
        handle.write(new_text_raw)
    new_media = b"INCREMENTAL-MEDIA-HEADER-123456"[:32] + os.urandom(65536)
    assert len(new_media[:32]) == 32
    with open(os.path.join(DOCS_DIR, changed_media), "wb") as handle:
        handle.write(new_media)

    changed_at = time.time()
    client = redis_client()
    client.set(f"encoding:{changed_text}", "iso-8859-1")
    client.set(f"last_modified:{changed_text}", str(changed_at))
    client.set(f"last_modified:{changed_media}", str(changed_at))

    second_started = time.time()
    result = subprocess.run(
        [sys.executable, ARCHIVER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
        env={**os.environ, "HOME": "/home/user"},
    )
    second_finished = time.time()
    assert result.returncode == 0, (
        f"Incremental archiver run failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    inspect_archive(expected_text([changed_text]), expected_headers([changed_media]))
    second_run = read_last_run()
    assert second_run > first_run, "last_run.txt was not advanced after the incremental backup"
    assert second_started - 2 <= second_run <= second_finished + 2, "last_run.txt has an invalid timestamp"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
