#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import io
import os
import subprocess
import tarfile
import tempfile
import time
import zipfile

import pytest

BACKUP_OPS_DIR = "/home/user/backup_ops"
MASTER_ARCHIVE = os.path.join(BACKUP_OPS_DIR, "master_backup.tar.gz")
UTF8_LOG = os.path.join(BACKUP_OPS_DIR, "legacy_app_utf8.log")
UPDATER_C = os.path.join(BACKUP_OPS_DIR, "updater.c")
UPDATER_BIN = os.path.join(BACKUP_OPS_DIR, "updater")
CATALOG_TXT = os.path.join(BACKUP_OPS_DIR, "catalog.txt")


def archived_log_text():
    with tarfile.open(MASTER_ARCHIVE, "r:gz") as tf:
        member = tf.getmember("logs_2022.zip")
        nested = tf.extractfile(member)
        assert nested is not None
        zip_bytes = nested.read()
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        raw = zf.read("legacy_app.log")
    return raw.decode("iso-8859-1")


def fatal_count():
    return sum("FATAL" in line for line in archived_log_text().splitlines())


def test_utf8_log_exists_and_valid():
    assert os.path.isfile(UTF8_LOG), f"File {UTF8_LOG} does not exist."

    try:
        with open(UTF8_LOG, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"File {UTF8_LOG} is not valid UTF-8.")

    assert "FATAL" in content, f"Expected content not found in {UTF8_LOG}."


def test_utf8_log_matches_iso_8859_1_file_in_nested_archive():
    with open(UTF8_LOG, "r", encoding="utf-8", newline="") as f:
        actual = f.read()
    assert actual == archived_log_text()


def test_updater_c_exists_and_contains_lock():
    assert os.path.isfile(UPDATER_C), f"File {UPDATER_C} does not exist."

    with open(UPDATER_C, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    assert "flock" in content or "fcntl" in content, f"File {UPDATER_C} does not contain 'flock' or 'fcntl' for file locking."


def test_updater_bin_exists_and_executable():
    assert os.path.isfile(UPDATER_BIN), f"Executable {UPDATER_BIN} does not exist."
    assert os.access(UPDATER_BIN, os.X_OK), f"File {UPDATER_BIN} is not executable."
    with open(UPDATER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {UPDATER_BIN} is not a compiled ELF binary."


def test_catalog_txt_updated():
    assert os.path.isfile(CATALOG_TXT), f"File {CATALOG_TXT} does not exist."

    with open(CATALOG_TXT, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    expected_line = "legacy_app_utf8.log recorded 3 FATAL events"
    assert expected_line in content, f"Expected line '{expected_line}' not found in {CATALOG_TXT}."
    derived_line = f"legacy_app_utf8.log recorded {fatal_count()} FATAL events"
    assert derived_line in content


def exercise_updater(executable):
    with open(CATALOG_TXT, "rb") as f:
        original = f.read()

    try:
        for args in ([], ["1", "2"]):
            result = subprocess.run(
                [executable] + args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=3,
            )
            assert result.returncode != 0, "updater must reject any argument count other than one"
            with open(CATALOG_TXT, "rb") as f:
                assert f.read() == original, "invalid invocation modified catalog.txt"

        value = fatal_count() + 14
        expected = f"legacy_app_utf8.log recorded {value} FATAL events\n".encode("utf-8")
        lock_file = open(CATALOG_TXT, "r+b", buffering=0)
        proc = None
        try:
            # Hold both Linux advisory-lock families so either permitted locking
            # implementation must wait before writing.
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen(
                [executable, str(value)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            time.sleep(0.4)
            blocked = proc.poll() is None
            fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            stdout, stderr = proc.communicate(timeout=3)
            assert blocked, "updater did not wait for the catalog's exclusive lock"
            assert proc.returncode == 0, stderr.decode("utf-8", errors="replace")
        finally:
            try:
                fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            lock_file.close()
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.wait()

        with open(CATALOG_TXT, "rb") as f:
            updated = f.read()
        assert updated == original + expected, "updater did not append exactly the required line"
    finally:
        with open(CATALOG_TXT, "wb") as f:
            f.write(original)


def test_submitted_updater_behavior_and_locking():
    exercise_updater(UPDATER_BIN)


def test_source_compiles_and_implements_updater_behavior():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "updater-from-source")
        result = subprocess.run(
            ["gcc", "-Wall", "-Wextra", "-o", rebuilt, UPDATER_C],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        exercise_updater(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
