#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import stat
import subprocess
import tarfile
import xml.etree.ElementTree as ET
from pathlib import PurePosixPath

import pytest

SOURCE = "/home/user/data_to_backup"
SCRIPT = "/home/user/backup_generator.py"
ARCHIVE = "/home/user/backup.tar.gz"
LIMIT = 5 * 1024 * 1024


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def normalize_member(name):
    while name.startswith("./"):
        name = name[2:]
    if name in ("", "."):
        return "."
    p = PurePosixPath(name)
    assert not p.is_absolute(), f"Archive member has an absolute path: {name}"
    assert ".." not in p.parts, f"Archive member escapes the source directory: {name}"
    return str(p)


def source_snapshot():
    files = {}
    directories = {"."}
    for root, dirs, names in os.walk(SOURCE, topdown=True, followlinks=False):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        relroot = os.path.relpath(root, SOURCE)
        directories.add("." if relroot == "." else relroot.replace(os.sep, "/"))
        for d in dirs:
            rel = os.path.relpath(os.path.join(root, d), SOURCE).replace(os.sep, "/")
            directories.add(rel)
        for name in names:
            path = os.path.join(root, name)
            st = os.lstat(path)
            if stat.S_ISREG(st.st_mode) and st.st_size <= LIMIT:
                rel = os.path.relpath(path, SOURCE).replace(os.sep, "/")
                files[rel] = (st.st_size, sha256_file(path))
    return files, directories


def test_00_execute_fixed_generator_and_validate_complete_archive():
    assert os.path.isfile(SCRIPT), f"File missing: {SCRIPT}"

    nonce = secrets.token_hex(12)
    nested = os.path.join(SOURCE, "docs", "verify_" + nonce)
    os.makedirs(nested)

    root_fixture = os.path.join(SOURCE, "verify_" + nonce + ".txt")
    nested_fixture = os.path.join(nested, "nested.bin")
    exact_limit = os.path.join(nested, "exactly_5mb.bin")
    oversized = os.path.join(nested, "over_5mb.bin")
    file_link = os.path.join(SOURCE, "file_link_" + nonce)
    dir_link = os.path.join(SOURCE, "dir_link_" + nonce)

    with open(root_fixture, "wb") as f:
        f.write(("dynamic archive fixture " + nonce).encode())
    with open(nested_fixture, "wb") as f:
        f.write(secrets.token_bytes(257))
    with open(exact_limit, "wb") as f:
        f.truncate(LIMIT)
    with open(oversized, "wb") as f:
        f.truncate(LIMIT + 1)
    os.symlink(root_fixture, file_link)
    os.symlink(nested, dir_link)

    expected_files, expected_dirs = source_snapshot()
    assert os.path.relpath(exact_limit, SOURCE).replace(os.sep, "/") in expected_files
    assert os.path.relpath(oversized, SOURCE).replace(os.sep, "/") not in expected_files

    if os.path.lexists(ARCHIVE):
        os.unlink(ARCHIVE)

    try:
        result = subprocess.run(
            ["python3", SCRIPT], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
    except subprocess.TimeoutExpired:
        pytest.fail("backup_generator.py did not terminate; symlink traversal may still loop")

    assert result.returncode == 0, (
        f"backup_generator.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(ARCHIVE), "Executing backup_generator.py did not create backup.tar.gz"
    assert tarfile.is_tarfile(ARCHIVE), f"{ARCHIVE} is not a valid tar archive"

    seen_files = {}
    seen_dirs = set()
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            name = normalize_member(member.name)
            assert not member.issym() and not member.islnk(), (
                f"Archive contains a link member: {member.name}"
            )
            assert not member.ischr() and not member.isblk() and not member.isfifo(), (
                f"Archive contains a special-file member: {member.name}"
            )
            if member.isdir():
                assert name in expected_dirs, f"Unexpected directory in archive: {member.name}"
                seen_dirs.add(name)
                continue
            assert member.isfile(), f"Unexpected archive member type: {member.name}"
            assert name not in seen_files, f"Duplicate archive member: {name}"
            assert name in expected_files, (
                f"Archive contains a symlink, oversized file, or unexpected file: {member.name}"
            )
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member: {member.name}"
            h = hashlib.sha256()
            size = 0
            for block in iter(lambda: extracted.read(1024 * 1024), b""):
                size += len(block)
                h.update(block)
            expected_size, expected_hash = expected_files[name]
            assert size == expected_size, f"Wrong size for archived file {name}"
            assert h.hexdigest() == expected_hash, f"Archived file differs from source: {name}"
            seen_files[name] = True

    assert set(seen_files) == set(expected_files), (
        "Archive is incomplete or has extra files. "
        f"Missing: {sorted(set(expected_files) - set(seen_files))}; "
        f"Extra: {sorted(set(seen_files) - set(expected_files))}"
    )

    for link in (file_link, dir_link,
                 os.path.join(SOURCE, "loop_a", "to_b"),
                 os.path.join(SOURCE, "loop_b", "to_a"),
                 os.path.join(SOURCE, "docs_link")):
        rel = os.path.relpath(link, SOURCE).replace(os.sep, "/")
        assert rel not in seen_files and rel not in seen_dirs, f"Symlink was archived: {rel}"


def test_config_xml_redacted():
    config_path = "/home/user/data_to_backup/config.xml"
    assert os.path.isfile(config_path), f"File missing: {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    original_ips = ["192.168.1.100", "10.0.0.5", "172.16.0.1", "172.16.0.2"]
    for ip in original_ips:
        assert ip not in content, f"Sensitive IP {ip} was not redacted in config.xml"

    assert "XXX.XXX.XXX.XXX" in content, "The exact replacement string 'XXX.XXX.XXX.XXX' was not found in config.xml"
    redacted_count = content.count("XXX.XXX.XXX.XXX")
    assert redacted_count >= 4, f"Expected at least 4 redactions, found {redacted_count}"

    ET.fromstring(content)
    ipv4 = re.compile(r"(?<![A-Za-z0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9])")
    assert not ipv4.search(content), "An unredacted IPv4-like address remains in config.xml"


def expected_errors_from_log(path):
    header = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ([A-Z]+) - (.*)$")
    entries = []
    current = None
    with open(path, "r", newline="") as f:
        for raw in f.read().splitlines():
            match = header.match(raw)
            if match:
                if current is not None:
                    entries.append(current)
                current = {
                    "timestamp": match.group(1),
                    "level": match.group(2),
                    "message": match.group(3),
                    "trace_lines": [],
                }
            elif current is not None:
                current["trace_lines"].append(raw)
    if current is not None:
        entries.append(current)
    return [entry for entry in entries if entry["level"] == "ERROR"]


def test_extracted_errors_json():
    json_path = "/home/user/extracted_errors.json"
    assert os.path.isfile(json_path), f"File missing: {json_path}"

    try:
        with open(json_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{json_path} is not valid JSON")

    assert isinstance(data, list), "JSON root should be a list"
    assert len(data) == 2, f"Expected 2 error objects, found {len(data)}"

    err1 = data[0]
    assert err1.get("timestamp") == "2023-10-01 10:15:30", "Incorrect timestamp for first error"
    assert err1.get("level") == "ERROR", "Incorrect level for first error"
    assert err1.get("message") == "NullPointerException in processing module", "Incorrect message for first error"
    assert "at com.app.Module.process" in err1.get("traceback", ""), "Missing traceback content in first error"

    err2 = data[1]
    assert err2.get("timestamp") == "2023-10-01 10:16:05", "Incorrect timestamp for second error"
    assert err2.get("level") == "ERROR", "Incorrect level for second error"
    assert err2.get("message") == "Database connection failed", "Incorrect message for second error"
    assert "at com.db.Connection.connect" in err2.get("traceback", ""), "Missing traceback content in second error"
    assert "Caused by: TimeoutException" in err2.get("traceback", ""), "Missing caused-by in second error traceback"

    expected = expected_errors_from_log("/home/user/data_to_backup/app.log")
    assert len(data) == len(expected), "JSON does not contain every ERROR entry from app.log"
    for actual, wanted in zip(data, expected):
        assert set(actual) == {"timestamp", "level", "message", "traceback"}, "Error object has missing or unexpected fields"
        assert actual["timestamp"] == wanted["timestamp"]
        assert actual["level"] == wanted["level"]
        assert actual["message"] == wanted["message"]
        assert isinstance(actual["traceback"], str)
        assert actual["traceback"].splitlines() == wanted["trace_lines"], (
            "Traceback does not exactly preserve all continuation lines and indentation"
        )


def test_backup_tar_gz_original_assertions():
    tar_path = "/home/user/backup.tar.gz"
    assert os.path.isfile(tar_path), f"Archive missing: {tar_path}"
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive"

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getnames()

    def contains_file(filename):
        return any(m == filename or m.endswith("/" + filename) for m in members)

    assert contains_file("config.xml"), "config.xml is missing from the backup archive"
    assert contains_file("app.log"), "app.log is missing from the backup archive"

    forbidden_links = ["to_b", "to_a", "docs_link"]
    for m in members:
        for link in forbidden_links:
            assert not m.endswith(link), f"Symlink {link} was improperly included in the backup archive"

    with tarfile.open(tar_path, "r:gz") as tar:
        config_member = next((m for m in tar.getmembers() if m.name.endswith("config.xml")), None)
        assert config_member is not None, "Could not find config.xml member to read"
        f = tar.extractfile(config_member)
        assert f is not None
        content = f.read().decode("utf-8")
        assert "192.168.1.100" not in content, "config.xml inside the tarball still contains sensitive IPs"
        assert "XXX.XXX.XXX.XXX" in content, "config.xml inside the tarball is not redacted correctly"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
