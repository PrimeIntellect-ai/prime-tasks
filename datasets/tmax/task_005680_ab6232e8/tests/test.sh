#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import base64
import stat
import pytest

CONFIG_PATH = "/home/user/backup_config.json"
MANIFEST_PATH = "/home/user/backup_manifest.csv"
SYMLINK_LOG_PATH = "/home/user/symlink_loops.log"
SOURCE_DIR = "/home/user/source_data"
DEST_DIR = "/home/user/backup_dest"

BASELINE_FILES = {
    "/home/user/source_data/info.json",
    "/home/user/source_data/level1/data.csv",
    "/home/user/source_data/level1/level2/config.xml",
    "/home/user/source_data/level1/valid_link/config.xml",
}
BASELINE_LOOPS = {
    "/home/user/source_data/level1/level2/loop_link",
    "/home/user/source_data/level1/valid_link/loop_link",
}

@pytest.fixture(scope="module")
def config():
    with open(CONFIG_PATH, "r") as f:
        return json.load(f)


def traverse_source_tree():
    files = []
    loops = []

    root_stat = os.stat(SOURCE_DIR)
    root_identity = (root_stat.st_dev, root_stat.st_ino)

    def visit(directory, ancestors):
        for entry in sorted(os.scandir(directory), key=lambda item: item.name):
            path = os.path.abspath(entry.path)
            try:
                target_stat = entry.stat(follow_symlinks=True)
            except (FileNotFoundError, OSError):
                continue

            if stat.S_ISDIR(target_stat.st_mode):
                identity = (target_stat.st_dev, target_stat.st_ino)
                if entry.is_symlink() and identity in ancestors:
                    loops.append(path)
                    continue
                visit(path, ancestors | {identity})
            elif stat.S_ISREG(target_stat.st_mode):
                files.append(path)

    visit(SOURCE_DIR, {root_identity})
    return files, loops


@pytest.fixture(scope="module")
def expected_tree():
    files, loops = traverse_source_tree()
    assert set(files) == BASELINE_FILES, "The source tree's required files or valid symlink traversal are missing."
    assert len(files) == len(set(files)), "Traversal unexpectedly produced duplicate lexical file paths."
    assert set(loops) == BASELINE_LOOPS, "The source tree's required loop symlinks are missing or altered."
    assert len(loops) == len(set(loops)), "Traversal unexpectedly produced duplicate loop paths."
    return set(files), set(loops)


def test_symlink_loops_logged(expected_tree):
    assert os.path.exists(SYMLINK_LOG_PATH), f"Symlink log file missing at {SYMLINK_LOG_PATH}"
    with open(SYMLINK_LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_loops = {
        "/home/user/source_data/level1/level2/loop_link",
        "/home/user/source_data/level1/valid_link/loop_link"
    }

    assert len(lines) > 0, "Symlink log is empty, expected to find loop links."
    for line in lines:
        assert line in expected_loops, f"Unexpected symlink loop logged: {line}"

    traversed_loops = expected_tree[1]
    assert len(lines) == len(set(lines)), "Symlink log contains duplicate paths."
    assert set(lines) == traversed_loops, "Symlink log must contain every detected infinite symlink exactly once."


def test_manifest_exists_and_format(expected_tree):
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["original_path", "base64_length"], "Manifest header is incorrect."

        rows = list(reader)
        assert len(rows) >= 3, "Manifest should contain at least the 3 original files."

        for row in rows:
            assert len(row) == 2, f"Invalid manifest row: {row}"
            path, length = row
            assert path.startswith(SOURCE_DIR), f"Path in manifest does not start with source_dir: {path}"
            assert length.isdigit(), f"Length in manifest is not a digit: {length}"

    manifest_paths = [row[0] for row in rows]
    expected_files = expected_tree[0]
    assert len(manifest_paths) == len(set(manifest_paths)), "Manifest contains duplicate original paths."
    assert set(manifest_paths) == expected_files, "Manifest must contain exactly every regular file encountered while following valid symlinks."


def test_backed_up_files(config, expected_tree):
    encodings = config["encodings"]
    compression_key = config["compression_key"]

    assert os.path.exists(MANIFEST_PATH), "Manifest missing."

    with open(MANIFEST_PATH, "r") as f:
        reader = csv.reader(f)
        next(reader) # skip header
        manifest_entries = list(reader)

    assert {row[0] for row in manifest_entries} == expected_tree[0]

    for original_path, b64_length in manifest_entries:
        # Determine relative path
        rel_path = os.path.relpath(original_path, SOURCE_DIR)
        dest_path = os.path.join(DEST_DIR, rel_path) + ".bak"

        assert os.path.exists(dest_path), f"Backup file missing: {dest_path}"
        assert os.path.isfile(dest_path), f"Backup path is not a regular file: {dest_path}"

        # Read backup file
        with open(dest_path, "r") as f:
            b64_content = f.read().strip()

        assert len(b64_content) == int(b64_length), f"Manifest length {b64_length} does not match actual length {len(b64_content)} for {dest_path}"

        # Decode and un-XOR
        try:
            xor_bytes = base64.b64decode(b64_content)
        except Exception as e:
            pytest.fail(f"Failed to decode base64 for {dest_path}: {e}")

        unxored_bytes = bytes(b ^ compression_key for b in xor_bytes)

        try:
            restored_text = unxored_bytes.decode("utf-8")
        except Exception as e:
            pytest.fail(f"Failed to decode UTF-8 after un-XOR for {dest_path}: {e}")

        # Read original file
        _, ext = os.path.splitext(original_path)
        encoding = encodings.get(ext, "utf-8")

        with open(original_path, "r", encoding=encoding) as f:
            original_text = f.read()

        assert restored_text == original_text, f"Restored content does not match original for {original_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
