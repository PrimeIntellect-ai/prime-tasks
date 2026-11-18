#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import re
import secrets
import shutil
import struct
import subprocess
import tarfile
import tempfile
import time

SCRIPT_PATH = "/home/user/archive_logs.py"
ARCHIVE_PATH = "/home/user/backups/logs_archive.tar.gz"
SOURCE_DIR = "/home/user/logs_source"
STAGING_DIR = "/home/user/staging"

assert os.path.isfile(SCRIPT_PATH), f"Python script not found at {SCRIPT_PATH}"

# Add unpredictable verification-time inputs so a preconstructed archive cannot pass.
token = secrets.token_hex(6)
large_probe = os.path.join(SOURCE_DIR, f"probe_{token}.log")
threshold_probe = os.path.join(SOURCE_DIR, f"threshold_{token}.log")
nonlog_probe = os.path.join(SOURCE_DIR, f"ignored_{token}.txt")

with open(large_probe, "wb") as f:
    f.write(os.urandom(10241))
with open(threshold_probe, "wb") as f:
    f.write(os.urandom(10240))
with open(nonlog_probe, "wb") as f:
    f.write(os.urandom(12000))

probe_mtime = 1707213600
os.utime(large_probe, (probe_mtime, probe_mtime))
os.utime(threshold_probe, (probe_mtime, probe_mtime))
os.utime(nonlog_probe, (probe_mtime, probe_mtime))

# Derive all expected results from the source metadata and contents.
expected = {}
for entry in os.scandir(SOURCE_DIR):
    if entry.is_file() and entry.name.endswith(".log") and entry.stat().st_size > 10240:
        stem, ext = os.path.splitext(entry.name)
        date = time.strftime("%Y%m%d", time.localtime(entry.stat().st_mtime))
        archived_name = f"{stem}_{date}{ext}"
        with open(entry.path, "rb") as f:
            expected[archived_name] = hashlib.sha256(f.read()).hexdigest()

# Remove all prior outputs, forcing the submitted script to produce them itself.
os.makedirs(STAGING_DIR, exist_ok=True)
for name in os.listdir(STAGING_DIR):
    path = os.path.join(STAGING_DIR, name)
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)
os.makedirs(os.path.dirname(ARCHIVE_PATH), exist_ok=True)
if os.path.lexists(ARCHIVE_PATH):
    os.unlink(ARCHIVE_PATH)

# Watch for a rename into manifest.sha256. IN_MOVED_TO demonstrates that the final
# manifest appeared through a filesystem rename rather than direct writing.
libc = ctypes.CDLL(None, use_errno=True)
IN_NONBLOCK = getattr(os, "O_NONBLOCK", 0x800)
IN_CLOEXEC = getattr(os, "O_CLOEXEC", 0x80000)
IN_MOVED_TO = 0x00000080
fd = libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
assert fd >= 0, "Unable to initialize inotify"
wd = libc.inotify_add_watch(fd, STAGING_DIR.encode(), IN_MOVED_TO)
assert wd >= 0, "Unable to watch staging directory"

run_result = subprocess.run(
    ["python3", SCRIPT_PATH],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
)

manifest_was_renamed = False
try:
    while True:
        data = os.read(fd, 65536)
        offset = 0
        while offset + 16 <= len(data):
            event_wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            if event_wd == wd and mask & IN_MOVED_TO and name == "manifest.sha256":
                manifest_was_renamed = True
except BlockingIOError:
    pass
finally:
    os.close(fd)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python script not found at {SCRIPT_PATH}"


def test_script_executes_successfully():
    assert run_result.returncode == 0, (
        f"archive_logs.py failed with exit code {run_result.returncode}\n"
        f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
    )


def test_manifest_is_atomically_renamed():
    assert manifest_was_renamed, (
        "manifest.sha256 must be written to a temporary file and atomically renamed into place"
    )


def test_archive_exists():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive not found at {ARCHIVE_PATH}"


def test_archive_matches_verification_time_sources():
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive"
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = [m.name for m in members]
        assert len(names) == len(set(names)), "Archive contains duplicate member names"
        assert set(names) == set(expected) | {"manifest.sha256"}, (
            f"Archive contents do not match eligible source files: {names}"
        )
        for member in members:
            assert member.isfile(), f"Archive member {member.name} is not a regular file"
            assert "/" not in member.name, f"Archive contains nested file {member.name}"

        manifest_file = tar.extractfile("manifest.sha256")
        assert manifest_file is not None, "manifest.sha256 is missing"
        manifest_text = manifest_file.read().decode("utf-8")
        lines = manifest_text.strip().split("\n") if manifest_text.strip() else []
        assert len(lines) == len(expected), "Manifest has the wrong number of entries"

        manifest_data = {}
        for line in lines:
            parts = line.split("  ")
            assert len(parts) == 2, f"Invalid manifest line format: {line!r}"
            digest, filename = parts
            assert re.fullmatch(r"[0-9a-f]{64}", digest), f"Invalid lowercase SHA-256: {digest!r}"
            assert filename == os.path.basename(filename), "Manifest must contain base filenames only"
            assert filename not in manifest_data, f"Duplicate manifest entry for {filename}"
            manifest_data[filename] = digest

        assert manifest_data == expected, "Manifest entries do not match source-derived checksums"
        for filename, digest in expected.items():
            archived = tar.extractfile(filename)
            assert archived is not None, f"Missing archived file {filename}"
            assert hashlib.sha256(archived.read()).hexdigest() == digest, (
                f"Archived content for {filename} does not match its source"
            )


def test_archive_contents_and_manifest():
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive"

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getnames()

        expected_files = {
            "db_20231001.log",
            "web_20231002.log",
            "app_20231004.log",
            "manifest.sha256"
        }

        actual_files = set(members)
        assert expected_files.issubset(actual_files), f"Archive is missing expected files. Expected {expected_files}, got {actual_files}"
        assert "api_20231003.log" not in actual_files, "api.log should not be included as it is <= 10KB"

        # Verify no directories are included (files should be at root)
        for member in tar.getmembers():
            assert not member.isdir(), f"Archive contains directory {member.name}, but files should be at the root."
            assert "/" not in member.name, f"Archive contains nested file {member.name}, but files should be at the root."

        with tempfile.TemporaryDirectory() as tmpdir:
            tar.extractall(path=tmpdir)

            # Verify manifest
            manifest_path = os.path.join(tmpdir, "manifest.sha256")
            assert os.path.isfile(manifest_path), "manifest.sha256 was not extracted correctly"

            with open(manifest_path, "r") as f:
                manifest_lines = f.read().strip().split('\n')

            # The original three entries must remain present; verification-time probes may add entries.
            assert len(manifest_lines) >= 3, f"manifest.sha256 should have at least 3 lines, found {len(manifest_lines)}"

            manifest_data = {}
            for line in manifest_lines:
                parts = line.split("  ")
                assert len(parts) == 2, f"Invalid manifest line format: '{line}'. Expected '<hash>  <filename>'"
                file_hash, filename = parts
                manifest_data[filename] = file_hash

            expected_log_files = ["db_20231001.log", "web_20231002.log", "app_20231004.log"]
            for log_file in expected_log_files:
                assert log_file in manifest_data, f"{log_file} missing from manifest.sha256"

                # Calculate actual hash
                extracted_log_path = os.path.join(tmpdir, log_file)
                assert os.path.isfile(extracted_log_path), f"Expected {log_file} to be extracted"

                with open(extracted_log_path, "rb") as f:
                    actual_hash = hashlib.sha256(f.read()).hexdigest()

                assert manifest_data[log_file] == actual_hash, f"Hash mismatch in manifest for {log_file}"

                # Also verify the content matches the original source file
                original_filename = log_file.split("_")[0] + ".log"
                original_filepath = os.path.join(SOURCE_DIR, original_filename)

                with open(original_filepath, "rb") as f:
                    original_hash = hashlib.sha256(f.read()).hexdigest()

                assert actual_hash == original_hash, f"Content of {log_file} in archive does not match original {original_filename}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
