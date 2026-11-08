#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import subprocess
import tarfile
import tempfile

import pytest

BACKUP_SCRIPT = "/home/user/scripts/backup.sh"
ROTATE_SCRIPT = "/home/user/scripts/rotate_logs.sh"
SANITIZER_SOURCE = "/home/user/backend/sanitizer.c"
SANITIZER_BIN = "/home/user/backend/sanitizer"
BACKUP_ARCHIVE = "/home/user/archives/secure_backups/data_backup.tar.gz"
BACKEND_DATA_DIR = "/home/user/backend/data"
LOG_FILE = "/home/user/backend/logs/server.log"
ROTATED_LOG_FILE = "/home/user/backend/logs/server.log.1.gz"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def run_backup():
    result = subprocess.run(
        ["bash", BACKUP_SCRIPT],
        env={"PATH": ""},
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Backup script failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def snapshot_data():
    result = {}
    for root, _, files in os.walk(BACKEND_DATA_DIR):
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.isfile(path) and not os.path.islink(path):
                rel = os.path.relpath(path, BACKEND_DATA_DIR).replace(os.sep, "/")
                with open(path, "rb") as f:
                    result[rel] = f.read()
    return result


def verify_archive(expected):
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} was not created."

    try:
        with tarfile.open(BACKUP_ARCHIVE, "r:gz") as tar:
            members = tar.getmembers()
            tar_names = tar.getnames()

            # Preserve the original basename assertions.
            tar_basenames = [os.path.basename(name.rstrip("/")) for name in tar_names]
            for rel in expected:
                basename = os.path.basename(rel)
                assert basename in tar_basenames, (
                    f"File {basename} from data directory not found in the backup archive."
                )

            for rel, wanted in expected.items():
                accepted_names = {
                    rel,
                    "data/" + rel,
                    "home/user/backend/data/" + rel,
                }
                matches = []
                for member in members:
                    normalized = member.name.lstrip("./").lstrip("/")
                    if normalized in accepted_names:
                        matches.append(member)

                assert matches, f"File {rel} from data directory not found at its proper archive path."
                assert len(matches) == 1, f"Archive contains duplicate entries for {rel}."
                member = matches[0]
                assert member.isfile(), f"Archive entry for {rel} is not a regular file."
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archive entry for {rel}."
                assert extracted.read() == wanted, f"Archived contents of {rel} do not match the source."
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"Failed to open {BACKUP_ARCHIVE} as a tar.gz file: {e}")


def test_backup_script():
    assert os.path.isfile(BACKUP_SCRIPT), f"Backup script {BACKUP_SCRIPT} not found."
    assert os.access(BACKUP_SCRIPT, os.X_OK), f"Backup script {BACKUP_SCRIPT} is not executable."

    token = secrets.token_hex(10)
    nested = os.path.join(BACKEND_DATA_DIR, "verification_" + token, "nested")
    os.makedirs(nested, exist_ok=True)
    dynamic_path = os.path.join(nested, "payload_" + token + ".bin")
    first_contents = secrets.token_bytes(8193)
    with open(dynamic_path, "wb") as f:
        f.write(first_contents)

    expected = snapshot_data()
    run_backup()
    verify_archive(expected)

    # Exercise idempotency and ensure the archive is regenerated from current data.
    second_contents = secrets.token_bytes(12345)
    with open(dynamic_path, "wb") as f:
        f.write(second_contents)
    added_path = os.path.join(nested, "added_" + secrets.token_hex(6) + ".txt")
    with open(added_path, "wb") as f:
        f.write(secrets.token_bytes(257))

    expected = snapshot_data()
    run_backup()
    verify_archive(expected)


def test_log_rotation():
    assert os.path.isfile(ROTATE_SCRIPT), f"Rotate script {ROTATE_SCRIPT} not found."
    assert os.access(ROTATE_SCRIPT, os.X_OK), f"Rotate script {ROTATE_SCRIPT} is not executable."

    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    original_data = secrets.token_bytes(2 * 1024 * 1024 + 317)
    with open(LOG_FILE, "wb") as f:
        f.write(original_data)

    # A prior rotation must be overwritten, not reused.
    with gzip.open(ROTATED_LOG_FILE, "wb") as f:
        f.write(b"stale rotation data")

    # Keep the original file descriptor open to verify copy/truncate semantics.
    held_fd = open(LOG_FILE, "rb")
    original_stat = os.fstat(held_fd.fileno())
    try:
        result = subprocess.run(
            ["bash", ROTATE_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Rotate script failed with exit code {result.returncode}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )

        assert os.path.isfile(LOG_FILE), f"Original log file {LOG_FILE} missing after rotation."
        assert os.path.getsize(LOG_FILE) == 0, f"Original log file {LOG_FILE} was not truncated to 0 bytes."
        current_stat = os.stat(LOG_FILE)
        held_stat = os.fstat(held_fd.fileno())
        assert (current_stat.st_dev, current_stat.st_ino) == (original_stat.st_dev, original_stat.st_ino), (
            "Log rotation replaced the original log inode and disrupted open file descriptors."
        )
        assert (held_stat.st_dev, held_stat.st_ino) == (original_stat.st_dev, original_stat.st_ino)
        assert held_stat.st_size == 0, "The log visible through the original file descriptor was not truncated."
        held_fd.seek(0)
        assert held_fd.read() == b"", "The original open log descriptor still contains data."

        assert os.path.isfile(ROTATED_LOG_FILE), f"Rotated log file {ROTATED_LOG_FILE} missing."
        try:
            with gzip.open(ROTATED_LOG_FILE, "rb") as f:
                # Preserve the original validity/read assertion and verify all contents.
                prefix = f.read(1024)
                rotated_data = prefix + f.read()
        except Exception as e:
            pytest.fail(f"Rotated log file {ROTATED_LOG_FILE} is not a valid gzip file: {e}")
        assert rotated_data == original_data, "Compressed rotated log does not contain the original log data."
    finally:
        held_fd.close()


def sanitizer_expected(data):
    if b"DROP_TABLE" in data:
        return 1
    for byte in data:
        if byte not in (9, 10, 13) and not (32 <= byte <= 126):
            return 1
    return 0


def invoke_sanitizer(path):
    return subprocess.run(
        [SANITIZER_BIN, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_sanitizer():
    assert os.path.isfile(SANITIZER_SOURCE), f"Sanitizer source {SANITIZER_SOURCE} not found."
    assert os.path.isfile(SANITIZER_BIN), f"Sanitizer binary {SANITIZER_BIN} not found."
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary {SANITIZER_BIN} is not executable."
    with open(SANITIZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled ELF executable."

    # Preserve all original visible-corpus checks.
    evil_files = [
        os.path.join(EVIL_CORPUS_DIR, f)
        for f in os.listdir(EVIL_CORPUS_DIR)
        if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))
    ]
    clean_files = [
        os.path.join(CLEAN_CORPUS_DIR, f)
        for f in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    ]
    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []
    for evil in evil_files:
        if invoke_sanitizer(evil) != 1:
            evil_bypassed.append(os.path.basename(evil))
    for clean in clean_files:
        if invoke_sanitizer(clean) != 0:
            clean_modified.append(os.path.basename(clean))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        error_msgs.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}"
        )
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

    # Generate hidden inputs at verification time under unrelated, misleading paths.
    printable = bytes(range(32, 127)) + b"\n\r\t"
    samples = [
        b"",
        b"ordinary text\nwith\ttabs and carriage return\r",
        b"DROP-TABLE and DROP_TABLEX are different except the latter includes DROP_TABLE",
        b"prefixDROP_TABLEsuffix",
        b"drop_table is case sensitive",
        b"DROP_TABL",
    ]
    for _ in range(12):
        samples.append(bytes(printable[secrets.randbelow(len(printable))] for _ in range(1000 + secrets.randbelow(4000))))
    for bad_byte in (0, 1, 8, 11, 12, 31, 127, 128, 200, 255):
        prefix = bytes(printable[secrets.randbelow(len(printable))] for _ in range(secrets.randbelow(300)))
        suffix = bytes(printable[secrets.randbelow(len(printable))] for _ in range(secrets.randbelow(300)))
        samples.append(prefix + bytes([bad_byte]) + suffix)
    for _ in range(8):
        prefix = bytes(printable[secrets.randbelow(len(printable))] for _ in range(secrets.randbelow(500)))
        suffix = bytes(printable[secrets.randbelow(len(printable))] for _ in range(secrets.randbelow(500)))
        samples.append(prefix + b"DROP_TABLE" + suffix)

    with tempfile.TemporaryDirectory(prefix="sanitizer_hidden_") as root:
        for index, data in enumerate(samples):
            # Directory names intentionally do not reveal the expected result.
            directory = os.path.join(root, "clean" if index % 2 else "evil", secrets.token_hex(5))
            os.makedirs(directory, exist_ok=True)
            path = os.path.join(directory, "input_" + secrets.token_hex(8) + ".dat")
            with open(path, "wb") as f:
                f.write(data)
            expected = sanitizer_expected(data)
            actual = invoke_sanitizer(path)
            assert actual == expected, (
                f"Sanitizer returned {actual} for generated sample {index}; expected {expected}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
