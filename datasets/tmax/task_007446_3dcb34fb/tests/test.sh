#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import tarfile
import hashlib
import re
import tempfile

MANIFEST_PATH = "/home/user/manifest.csv"
TARBALL_PATH = "/home/user/safe_backup.tar.gz"
BACKUP_PLAN_PATH = "/home/user/server_data/backup_plan.json"
SOURCE_ROOT = "/home/user/server_data"

EXPECTED_PLAN = [
    {"file": "logs/access.csv", "redact": "ipv4"},
    {"file": "conf/settings.xml", "redact": "none"},
    {"file": "logs/system.log", "redact": "ipv4"},
]

ORIGINAL_SOURCES = {
    "logs/access.csv": (
        b"timestamp,ip_address,status\n"
        b"2023-10-01T10:00:00Z,192.168.1.50,200\n"
        b"2023-10-01T10:05:00Z,10.0.0.15,404\n"
        b"2023-10-01T10:10:00Z,172.16.254.1,500\n"
    ),
    "conf/settings.xml": (
        b"<?xml version=\"1.0\"?>\n"
        b"<config>\n"
        b"  <database>\n"
        b"    <host>db.internal.local</host>\n"
        b"    <port>5432</port>\n"
        b"  </database>\n"
        b"</config>\n"
    ),
    "logs/system.log": (
        b"System boot initiated.\n"
        b"Network interface eth0 configured with 192.168.100.22.\n"
        b"Connecting to external API at 203.0.113.5.\n"
    ),
}

OCTET = r"(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
VALID_IPV4 = re.compile(r"(?<![0-9.])" + OCTET + r"(?:\." + OCTET + r"){3}(?![0-9.])")
SHAPE_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def get_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def expected_processed_files():
    assert os.path.isfile(BACKUP_PLAN_PATH), "Backup plan is missing"
    with open(BACKUP_PLAN_PATH, "r", encoding="utf-8") as f:
        plan = json.load(f)
    assert plan.get("targets") == EXPECTED_PLAN, "Master backup plan was altered"

    expected = {}
    for target in plan["targets"]:
        relpath = target["file"]
        source_path = os.path.join(SOURCE_ROOT, relpath)
        assert os.path.isfile(source_path), f"Source file missing: {relpath}"
        with open(source_path, "rb") as f:
            source_data = f.read()
        assert source_data == ORIGINAL_SOURCES[relpath], f"Source file was altered: {relpath}"

        text = source_data.decode("utf-8")
        if target["redact"] == "ipv4":
            text = VALID_IPV4.sub("[REDACTED]", text)
        elif target["redact"] != "none":
            raise AssertionError(f"Unsupported redaction rule: {target['redact']}")
        expected[relpath] = text.encode("utf-8")
    return expected


def read_manifest():
    with open(MANIFEST_PATH, "r", newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    assert rows, "Manifest is empty"
    assert rows[0] == ["file_path", "sha256_hash"], "Manifest header is incorrect"
    data_rows = rows[1:]
    assert len(data_rows) == 3, "Manifest should contain exactly 3 entries"
    assert all(len(row) == 2 for row in data_rows), "Manifest must have exactly two columns"
    return data_rows


def test_manifest_exists_and_format():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"
    assert not os.path.islink(MANIFEST_PATH), "Manifest must be a regular file, not a symlink"

    rows = read_manifest()
    file_paths = [row[0] for row in rows]
    assert file_paths == sorted(file_paths), "Manifest rows are not sorted alphabetically by file_path"

    expected_files = ["conf/settings.xml", "logs/access.csv", "logs/system.log"]
    assert set(file_paths) == set(expected_files), "Manifest contains incorrect file paths"

    expected = expected_processed_files()
    for file_path, digest in rows:
        assert re.fullmatch(r"[0-9a-f]{64}", digest), f"Invalid SHA256 hash for {file_path}"
        assert digest == sha256_bytes(expected[file_path]), (
            f"Manifest hash is not the hash of the correctly processed source: {file_path}"
        )


def test_tarball_exists_and_contents():
    assert os.path.isfile(TARBALL_PATH), f"Tarball missing: {TARBALL_PATH}"
    assert not os.path.islink(TARBALL_PATH), "Tarball must be a regular file, not a symlink"
    assert tarfile.is_tarfile(TARBALL_PATH), f"{TARBALL_PATH} is not a valid tar file"

    with tarfile.open(TARBALL_PATH, "r:gz") as tar:
        members = tar.getnames()

        for member in members:
            assert not member.startswith("/"), f"Tarball contains absolute paths: {member}"
            assert not member.startswith("server_data"), (
                f"Tarball contains parent directory 'server_data': {member}"
            )

        file_members = [m.name for m in tar.getmembers() if m.isfile()]
        expected_files = {"conf/settings.xml", "logs/access.csv", "logs/system.log"}
        assert set(file_members) == expected_files, f"Tarball contains incorrect files. Found: {file_members}"
        assert len(file_members) == len(expected_files), "Tarball contains duplicate target file entries"
        assert "conf/secrets.txt" not in file_members, "Tarball incorrectly contains conf/secrets.txt"

        expected = expected_processed_files()
        for relpath, expected_data in expected.items():
            member = tar.getmember(relpath)
            archived = tar.extractfile(member)
            assert archived is not None, f"Cannot read archived file: {relpath}"
            assert archived.read() == expected_data, (
                f"Archived content does not equal the independently processed source: {relpath}"
            )


def test_extraction_redaction_and_hashes():
    assert os.path.isfile(MANIFEST_PATH), "Manifest missing"
    assert os.path.isfile(TARBALL_PATH), "Tarball missing"

    rows = read_manifest()
    manifest_hashes = {file_path: digest for file_path, digest in rows}
    expected = expected_processed_files()

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(TARBALL_PATH, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        for file_path, expected_hash in manifest_hashes.items():
            extracted_file = os.path.join(tmpdir, file_path)
            assert os.path.isfile(extracted_file), f"File {file_path} missing from extracted tarball"

            actual_hash = get_sha256(extracted_file)
            assert actual_hash == expected_hash, (
                f"Hash mismatch for {file_path}. Manifest: {expected_hash}, Actual: {actual_hash}"
            )

            with open(extracted_file, "rb") as f:
                extracted_data = f.read()
            assert extracted_data == expected[file_path], f"Incorrect processed content for {file_path}"

            content = extracted_data.decode("utf-8")
            if file_path in ("logs/access.csv", "logs/system.log"):
                assert "[REDACTED]" in content, f"Expected [REDACTED] string not found in {file_path}"
                matches = SHAPE_IPV4.findall(content)
                assert not matches, f"Found unredacted IPv4 addresses in {file_path}: {matches}"
            elif file_path == "conf/settings.xml":
                assert "[REDACTED]" not in content, f"File {file_path} should not be redacted"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
