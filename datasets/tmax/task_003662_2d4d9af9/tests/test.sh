#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

ARCHIVE_DIR = "/home/user/archive"
MANIFEST_PATH = os.path.join(ARCHIVE_DIR, "manifest.txt")
SCRIPT_PATH = "/home/user/config_tracker.sh"
WATCH_LIST = "/home/user/watch_list.txt"
CHUNK_SIZE = 50 * 1024


def get_sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def get_sha256(file_path):
    with open(file_path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def discover_sources(watched_dirs):
    sources = []
    for watched_dir in watched_dirs:
        watched_dir = os.path.abspath(watched_dir)
        for root, dirs, files in os.walk(watched_dir, followlinks=False):
            dirs[:] = [
                name for name in dirs
                if not os.path.islink(os.path.join(root, name))
            ]
            for name in files:
                path = os.path.join(root, name)
                if os.path.islink(path):
                    continue
                if os.path.isfile(path):
                    sources.append(os.path.abspath(path))
    return sorted(sources)


def build_expected(watched_dirs):
    archived = {}
    manifest = []

    for source in discover_sources(watched_dirs):
        with open(source, "rb") as f:
            data = f.read()
        basename = os.path.basename(source)

        if len(data) <= CHUNK_SIZE:
            pieces = [(basename, data)]
        else:
            pieces = []
            for index, start in enumerate(range(0, len(data), CHUNK_SIZE)):
                first = chr(ord("a") + index // 26)
                second = chr(ord("a") + index % 26)
                name = f"{basename}.part_{first}{second}"
                pieces.append((name, data[start:start + CHUNK_SIZE]))

        for archive_name, contents in pieces:
            assert archive_name not in archived, f"Test inputs unexpectedly collide on {archive_name}"
            archived[archive_name] = contents
            manifest.append(
                f"{source} | {archive_name} | {get_sha256_bytes(contents)}"
            )

    return archived, sorted(manifest)


def prepare_and_execute():
    assert os.path.isfile(SCRIPT_PATH), f"Required script missing: {SCRIPT_PATH}"
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular file"
    assert mode & 0o111, f"{SCRIPT_PATH} must be executable"

    with open(WATCH_LIST, "rb") as f:
        original_watch_list = f.read()

    token = uuid.uuid4().hex[:12]
    probe_dir = tempfile.mkdtemp(prefix="config_tracker_probe_", dir="/tmp")
    os.chmod(probe_dir, 0o755)
    boundary_name = f"boundary_{token}.bin"
    oversized_name = f"oversized_{token}.bin"
    ignored_name = f"ignored_symlink_{token}.bin"

    boundary_data = os.urandom(CHUNK_SIZE)
    oversized_data = os.urandom(CHUNK_SIZE + 17)
    with open(os.path.join(probe_dir, boundary_name), "wb") as f:
        f.write(boundary_data)
    with open(os.path.join(probe_dir, oversized_name), "wb") as f:
        f.write(oversized_data)
    os.chmod(os.path.join(probe_dir, boundary_name), 0o644)
    os.chmod(os.path.join(probe_dir, oversized_name), 0o644)
    os.symlink(os.path.join(probe_dir, boundary_name), os.path.join(probe_dir, ignored_name))

    try:
        watch_text = original_watch_list.decode()
        watched_dirs = [line for line in watch_text.splitlines() if line]
        watched_dirs.append(probe_dir)
        replacement = watch_text
        if replacement and not replacement.endswith("\n"):
            replacement += "\n"
        replacement += probe_dir + "\n"
        with open(WATCH_LIST, "w") as f:
            f.write(replacement)

        expected_archive, expected_manifest = build_expected(watched_dirs)

        shutil.rmtree(ARCHIVE_DIR, ignore_errors=True)
        os.makedirs(ARCHIVE_DIR, mode=0o777)
        os.chmod(ARCHIVE_DIR, 0o777)
        shutil.chown(ARCHIVE_DIR, user="user", group="user")

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "timeout", "15", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Script did not complete successfully (exit {result.returncode}).\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        return expected_archive, expected_manifest, ignored_name
    finally:
        with open(WATCH_LIST, "wb") as f:
            f.write(original_watch_list)
        shutil.rmtree(probe_dir, ignore_errors=True)


EXPECTED_ARCHIVE, EXPECTED_MANIFEST, IGNORED_SYMLINK_NAME = prepare_and_execute()


def test_manifest_exists():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"
    assert os.path.isfile(MANIFEST_PATH), f"{MANIFEST_PATH} is not a file"


def test_large_file_chunked():
    for part in ["aa", "ab", "ac"]:
        chunk_name = f"large_db.sqlite.part_{part}"
        chunk_path = os.path.join(ARCHIVE_DIR, chunk_name)
        assert os.path.exists(chunk_path), f"Expected chunk {chunk_name} missing in archive for file > 50KB"
        assert os.path.isfile(chunk_path), f"{chunk_path} is not a file"


def test_small_files_copied():
    for name in ["small_config.txt", "settings.json"]:
        path = os.path.join(ARCHIVE_DIR, name)
        assert os.path.exists(path), f"{name} missing in archive"
        assert os.path.isfile(path), f"{path} is not a file"


def test_archive_has_exact_files_and_contents():
    actual_names = set(os.listdir(ARCHIVE_DIR)) - {"manifest.txt"}
    assert actual_names == set(EXPECTED_ARCHIVE), (
        f"Archive file set differs: missing={set(EXPECTED_ARCHIVE) - actual_names}, "
        f"extra={actual_names - set(EXPECTED_ARCHIVE)}"
    )

    assert IGNORED_SYMLINK_NAME not in actual_names, "A symlink was traversed and archived"
    for name, expected_contents in EXPECTED_ARCHIVE.items():
        path = os.path.join(ARCHIVE_DIR, name)
        assert os.path.isfile(path), f"Expected regular archived file missing: {name}"
        with open(path, "rb") as f:
            actual_contents = f.read()
        assert actual_contents == expected_contents, f"Archived contents or chunk boundaries are wrong for {name}"
        assert len(actual_contents) <= CHUNK_SIZE, f"Chunk {name} exceeds 50KB"


def test_manifest_contents():
    assert os.path.exists(MANIFEST_PATH), "Manifest file must exist to check contents"
    with open(MANIFEST_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == EXPECTED_MANIFEST, (
        "Manifest contents do not match the source-derived, sorted output with correct checksums"
    )

    for line in actual_lines:
        source, archive_name, digest = line.split(" | ")
        assert os.path.isabs(source)
        assert digest == get_sha256(os.path.join(ARCHIVE_DIR, archive_name))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
