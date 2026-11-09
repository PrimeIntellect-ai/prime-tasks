#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import struct
import tarfile

import pytest
import requests

ARCHIVE = "/app/project_archive.bin"
EXTRACTED = "/home/user/extracted"
TARBALL = "/home/user/backup/latest.tar.gz"
TMP_TARBALL = "/home/user/backup/.latest.tar.gz.tmp"
MANIFEST = "/home/user/backup/manifest.txt"
BASE_URL = "http://127.0.0.1:8080"
EXPECTED_FIXED_PATHS = ["config.json", "src/main.py", "assets/logo.png"]
TOKEN_CANDIDATES = ["DELTA 42", "DELTA42", "DELTA FORTY TWO"]


def parse_archive():
    with open(ARCHIVE, "rb") as f:
        raw = f.read()

    assert raw[:6] == b"PROJ\x01\x00", "Invalid project archive header/version"
    offset = 6
    records = {}
    while offset < len(raw):
        assert offset + 2 <= len(raw), "Truncated path length"
        path_len = struct.unpack_from("<H", raw, offset)[0]
        offset += 2
        assert offset + path_len + 4 <= len(raw), "Truncated archive record"
        path_bytes = raw[offset:offset + path_len]
        offset += path_len
        try:
            path = path_bytes.decode("ascii")
        except UnicodeDecodeError:
            pytest.fail("Archive path is not ASCII")
        size = struct.unpack_from("<I", raw, offset)[0]
        offset += 4
        assert offset + size <= len(raw), f"Truncated data for {path}"
        data = raw[offset:offset + size]
        offset += size

        assert path and not os.path.isabs(path), f"Unsafe archive path: {path}"
        normalized = os.path.normpath(path).replace(os.sep, "/")
        assert normalized == path and normalized != ".." and not normalized.startswith("../"), f"Unsafe archive path: {path}"
        assert path not in records, f"Duplicate archive path: {path}"
        records[path] = data

    assert offset == len(raw), "Archive has trailing or malformed data"
    return records


def canonical_tar_name(name):
    name = name.replace("\\", "/")
    assert not name.startswith("/"), f"Absolute tar member: {name}"
    parts = [p for p in name.split("/") if p not in ("", ".")]
    assert ".." not in parts, f"Traversal tar member: {name}"
    name = "/".join(parts)
    for prefix in ("home/user/extracted/", "extracted/"):
        if name.startswith(prefix):
            return name[len(prefix):]
    if name in ("home/user/extracted", "extracted"):
        return ""
    return name


def canonical_manifest_path(path):
    path = path.replace("\\", "/")
    for prefix in ("/home/user/extracted/", "home/user/extracted/", "extracted/", "./"):
        if path.startswith(prefix):
            path = path[len(prefix):]
            break
    return path


def get_working_token():
    for token in TOKEN_CANDIDATES:
        try:
            response = requests.get(
                f"{BASE_URL}/files",
                headers={"X-Project-Token": token},
                timeout=2,
            )
            if response.status_code == 200:
                return token
        except requests.exceptions.RequestException:
            pass
    pytest.fail("Could not authenticate with any expected token variant (e.g., DELTA 42, DELTA42)")


def test_extracted_files_and_contents():
    records = parse_archive()

    # Preserve the original fixed path assertions.
    for relative in EXPECTED_FIXED_PATHS:
        path = os.path.join(EXTRACTED, relative)
        assert os.path.isfile(path), f"Extracted file missing: {path}"

    actual = set()
    for root, dirs, files in os.walk(EXTRACTED, followlinks=False):
        for dirname in dirs:
            assert not os.path.islink(os.path.join(root, dirname)), "Extracted directory contains a symlink"
        for filename in files:
            full_path = os.path.join(root, filename)
            assert not os.path.islink(full_path), f"Extracted file is a symlink: {full_path}"
            relative = os.path.relpath(full_path, EXTRACTED).replace(os.sep, "/")
            actual.add(relative)
            assert relative in records, f"Unexpected extracted file: {relative}"
            with open(full_path, "rb") as f:
                assert f.read() == records[relative], f"Wrong extracted contents: {relative}"

    assert actual == set(records), "Extracted membership does not match the archive"


def test_backup_files_integrity_and_manifest():
    records = parse_archive()

    # Preserve the original backup existence assertions.
    assert os.path.isfile(TARBALL), f"Backup tarball missing: {TARBALL}"
    assert os.path.isfile(MANIFEST), f"Manifest missing: {MANIFEST}"
    assert not os.path.lexists(TMP_TARBALL), "Atomic-write temporary tarball was not renamed away"

    archived = {}
    try:
        with tarfile.open(TARBALL, "r:gz") as tf:
            for member in tf.getmembers():
                relative = canonical_tar_name(member.name)
                if member.isdir():
                    continue
                assert member.isfile(), f"Backup contains a non-regular member: {member.name}"
                assert relative, f"Invalid backup member: {member.name}"
                assert relative not in archived, f"Duplicate backup member: {relative}"
                extracted_file = tf.extractfile(member)
                assert extracted_file is not None
                archived[relative] = extracted_file.read()
    except (tarfile.TarError, OSError) as exc:
        pytest.fail(f"Backup is not a valid gzip tar archive: {exc}")

    assert set(archived) == set(records), "Backup membership does not match the project archive"
    for path, expected_data in records.items():
        assert archived[path] == expected_data, f"Wrong backup contents: {path}"

    entries = {}
    with open(MANIFEST, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines, "Manifest is empty"
    for line in lines:
        match = re.fullmatch(r"MD5\((.+)\) = ([0-9a-fA-F]{32})", line)
        assert match, f"Malformed manifest line: {line!r}"
        path = canonical_manifest_path(match.group(1))
        assert path not in entries, f"Duplicate manifest entry: {path}"
        entries[path] = match.group(2).lower()

    expected_hashes = {
        path: hashlib.md5(data).hexdigest() for path, data in records.items()
    }
    assert entries == expected_hashes, "Manifest paths or MD5 checksums are incorrect"


def test_http_service_unauthorized():
    for endpoint in ("/files", "/transcript", "/backup/status"):
        try:
            response = requests.get(f"{BASE_URL}{endpoint}", timeout=2)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to the HTTP service: {exc}")
        assert response.status_code in (401, 403), f"Expected 401 or 403 for missing token on {endpoint}, got {response.status_code}"

        response = requests.get(
            f"{BASE_URL}{endpoint}",
            headers={"X-Project-Token": "NOT THE PROJECT CODE"},
            timeout=2,
        )
        assert response.status_code in (401, 403), f"Wrong token was accepted by {endpoint}"


def test_http_service_endpoints():
    records = parse_archive()
    working_token = get_working_token()
    headers = {"X-Project-Token": working_token}

    # Header value must be exact, including capitalization and punctuation.
    for altered in (working_token.lower(), working_token + "!"):
        response = requests.get(
            f"{BASE_URL}/files",
            headers={"X-Project-Token": altered},
            timeout=2,
        )
        assert response.status_code in (401, 403), "A non-exact project token was accepted"

    r_files = requests.get(f"{BASE_URL}/files", headers=headers, timeout=2)
    assert r_files.status_code == 200
    data_files = r_files.json()
    assert "files" in data_files
    assert isinstance(data_files["files"], list)
    for expected in EXPECTED_FIXED_PATHS:
        assert expected in data_files["files"], f"Missing {expected} in /files response"
    assert set(data_files["files"]) == set(records), "/files does not match archive membership"

    r_transcript = requests.get(f"{BASE_URL}/transcript", headers=headers, timeout=2)
    assert r_transcript.status_code == 200
    data_transcript = r_transcript.json()
    assert "transcript" in data_transcript
    assert isinstance(data_transcript["transcript"], str)
    assert len(data_transcript["transcript"]) > 0, "Transcript is empty"
    normalized = re.sub(r"[^A-Z0-9]+", " ", data_transcript["transcript"].upper()).strip()
    assert "DELTA" in normalized, "Transcript does not contain the spoken project code"
    assert "42" in normalized or "FORTY TWO" in normalized, "Transcript does not contain the spoken project number"

    r_backup = requests.get(f"{BASE_URL}/backup/status", headers=headers, timeout=2)
    assert r_backup.status_code == 200
    data_backup = r_backup.json()
    assert data_backup.get("backup_path") == TARBALL
    assert data_backup.get("manifest_exists") is True

    # Ensure status reflects the actual manifest rather than a fixed response.
    hidden_manifest = MANIFEST + ".verifier-hidden"
    assert not os.path.exists(hidden_manifest)
    os.rename(MANIFEST, hidden_manifest)
    try:
        r_missing = requests.get(f"{BASE_URL}/backup/status", headers=headers, timeout=2)
        assert r_missing.status_code == 200
        missing_data = r_missing.json()
        assert missing_data.get("backup_path") == TARBALL
        assert missing_data.get("manifest_exists") is False
    finally:
        os.rename(hidden_manifest, MANIFEST)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
