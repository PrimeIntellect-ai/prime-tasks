#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import hashlib
import pytest

SERVER_CONFIGS_DIR = "/home/user/server_configs"
MANIFEST_PATH = "/home/user/manifest.sha256"
ARCHIVE_PATH = "/home/user/config_backup.tar.gz"

EXPECTED_CONF_FILES = {
    "app1/settings.conf",
    "app2/nested/db.conf",
    "app3/cache.conf"
}

EXPECTED_CONTENTS = {
    "app1/settings.conf": (
        "PORT=8080\n"
        "HOST=localhost\n"
        "SECRET_KEY=REDACTED\n"
        "DEBUG=true\n"
    ),
    "app2/nested/db.conf": (
        "DB_USER=admin\n"
        "DB_PASS=password123\n"
        "SECRET_KEY=REDACTED\n"
        "TIMEOUT=30\n"
    ),
    "app3/cache.conf": (
        "MAX_MEMORY=512M\n"
        "SECRET_KEY=REDACTED\n"
        "EVICTION_POLICY=LRU\n"
    ),
}

def get_file_hash(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_conf_files_redacted():
    for rel_path in EXPECTED_CONF_FILES:
        abs_path = os.path.join(SERVER_CONFIGS_DIR, rel_path)
        assert os.path.isfile(abs_path), f"File {abs_path} is missing."

        with open(abs_path, "r") as f:
            content = f.read()

        assert "SECRET_KEY=REDACTED" in content, f"SECRET_KEY not redacted in {abs_path}"

        # Ensure no original secrets are left
        for line in content.splitlines():
            if line.startswith("SECRET_KEY="):
                assert line == "SECRET_KEY=REDACTED", f"Found unredacted secret key in {abs_path}: {line}"

        # Redaction must preserve every other byte of the original configuration.
        assert content == EXPECTED_CONTENTS[rel_path], f"Unexpected content change in {abs_path}"

def test_txt_file_unmodified():
    readme_path = os.path.join(SERVER_CONFIGS_DIR, "app1/readme.txt")
    assert os.path.isfile(readme_path), f"File {readme_path} is missing."

    with open(readme_path, "r") as f:
        content = f.read()

    assert "SECRET_KEY=should_not_be_redacted_or_archived" in content, "Readme file was incorrectly modified."
    assert "SECRET_KEY=REDACTED" not in content, "Readme file was incorrectly redacted."

def test_manifest_correctness():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Manifest should contain exactly 3 lines, found {len(lines)}."

    manifest_entries = {}
    for line in lines:
        parts = line.split(maxsplit=1)
        assert len(parts) == 2, f"Invalid manifest line format: {line}"
        file_hash, rel_path = parts

        # Handle potential leading './' in paths
        if rel_path.startswith("./"):
            rel_path = rel_path[2:]

        manifest_entries[rel_path] = file_hash

    assert set(manifest_entries.keys()) == EXPECTED_CONF_FILES, "Manifest does not contain the correct files."

    for rel_path, expected_hash in manifest_entries.items():
        abs_path = os.path.join(SERVER_CONFIGS_DIR, rel_path)
        actual_hash = get_file_hash(abs_path)
        assert expected_hash == actual_hash, f"Hash mismatch in manifest for {rel_path}."

def test_archive_correctness():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} is missing."
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive."

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()

        # Filter out directories
        file_members = [m for m in members if m.isfile()]

        archived_files = set()
        for m in file_members:
            path = m.name
            if path.startswith("./"):
                path = path[2:]
            archived_files.add(path)

        assert archived_files == EXPECTED_CONF_FILES, "Archive does not contain the exact expected .conf files."

        # Verify contents inside the archive
        for m in file_members:
            f = tar.extractfile(m)
            assert f is not None, f"Could not extract {m.name} from archive."
            content = f.read().decode("utf-8")
            assert "SECRET_KEY=REDACTED" in content, f"SECRET_KEY not redacted in archived file {m.name}."

            for line in content.splitlines():
                if line.startswith("SECRET_KEY="):
                    assert line == "SECRET_KEY=REDACTED", f"Found unredacted secret key in archived {m.name}: {line}"

            path = m.name
            if path.startswith("./"):
                path = path[2:]
            assert content == EXPECTED_CONTENTS[path], f"Unexpected content change in archived file {m.name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
