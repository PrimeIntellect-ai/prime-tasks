#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import stat
import tarfile
import zlib

BUNDLE = "/home/user/doc_bundle.bin"
SAFE_ROOT = "/home/user/docs_safe"


def parse_bundle():
    with open(BUNDLE, "rb") as f:
        blob = f.read()

    assert len(blob) > 128, "Bundle is too short"
    assert blob[:9] == b"DOCMGR_V1", "Bundle header is invalid"

    decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
    tar_bytes = decompressor.decompress(blob[128:])
    tar_bytes += decompressor.flush()
    assert decompressor.eof, "The gzip stream is incomplete"
    log_bytes = decompressor.unused_data

    members = []
    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as archive:
        for member in archive.getmembers():
            if member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None
                members.append((member.name, extracted.read()))
    return members, log_bytes


def safe_relative_path(name):
    parts = []
    for part in name.replace("\\", "/").split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    assert parts, f"Archive member has no safe output path: {name!r}"
    return "/".join(parts)


def decode_archive_text(data):
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    if data and data.count(b"\x00") * 4 >= len(data):
        return data.decode("utf-16le")
    return data.decode("iso-8859-1")


def warning_records(log_bytes):
    text = log_bytes.decode("iso-8859-1")
    records = []
    current = []
    keep = False
    for line in text.splitlines(keepends=True):
        if re.match(r"^\[[^]\r\n]+\]", line):
            if keep:
                records.extend(current)
            current = [line]
            keep = line.startswith("[WARNING]")
        else:
            current.append(line)
    if keep:
        records.extend(current)
    return "".join(records)


ARCHIVE_MEMBERS, LOG_BYTES = parse_bundle()
EXPECTED_FILES = {
    safe_relative_path(name): decode_archive_text(data)
    for name, data in ARCHIVE_MEMBERS
}
EXPECTED_WARNINGS = warning_records(LOG_BYTES)


def test_files_extracted_safely():
    """Retain the original assertions for the required safe paths."""
    expected_files = [
        "/home/user/docs_safe/docs/index.txt",
        "/home/user/docs_safe/styles/main.css"
    ]
    for file_path in expected_files:
        assert os.path.exists(file_path), f"Expected file {file_path} is missing. Path traversal may not have been neutralized correctly or extraction failed."
        assert os.path.isfile(file_path), f"Expected {file_path} to be a file."


def test_files_utf8_encoded():
    """Retain the original UTF-8 and content assertions."""
    index_path = "/home/user/docs_safe/docs/index.txt"
    css_path = "/home/user/docs_safe/styles/main.css"
    with open(index_path, "r", encoding="utf-8") as f:
        index_content = f.read()
    assert "Welcome to the documentation." in index_content
    with open(css_path, "r", encoding="utf-8") as f:
        css_content = f.read()
    assert "body { background: white; }" in css_content


def test_every_archive_file_and_exact_converted_content():
    """Derive and verify every required output from the actual bundle."""
    assert os.path.isdir(SAFE_ROOT), f"Missing extraction root {SAFE_ROOT}"
    actual_files = set()
    for root, dirs, files in os.walk(SAFE_ROOT, followlinks=False):
        for dirname in dirs:
            path = os.path.join(root, dirname)
            assert not os.path.islink(path), f"Symlink directory is unsafe: {path}"
        for filename in files:
            path = os.path.join(root, filename)
            rel = os.path.relpath(path, SAFE_ROOT).replace(os.sep, "/")
            mode = os.lstat(path).st_mode
            assert stat.S_ISREG(mode), f"Output is not a regular file: {path}"
            actual_files.add(rel)

    assert actual_files == set(EXPECTED_FILES), (
        f"Extracted file set differs from archive: expected {set(EXPECTED_FILES)!r}, "
        f"got {actual_files!r}"
    )
    for rel, expected in EXPECTED_FILES.items():
        path = os.path.join(SAFE_ROOT, *rel.split("/"))
        with open(path, "r", encoding="utf-8", errors="strict", newline="") as f:
            actual = f.read()
        assert actual == expected, f"Incorrect converted content in {path}"


def test_traversal_destinations_do_not_exist_outside_safe_root():
    """Ensure unsafe member names did not leave files at their raw destinations."""
    root_real = os.path.realpath(SAFE_ROOT)
    for name, _ in ARCHIVE_MEMBERS:
        raw_destination = os.path.abspath(os.path.join(SAFE_ROOT, name))
        if os.path.commonpath([root_real, raw_destination]) != root_real:
            assert not os.path.lexists(raw_destination), (
                f"Archive traversal wrote outside {SAFE_ROOT}: {raw_destination}"
            )


def test_warnings_log():
    """Retain the original warning assertions and add bundle-derived verification."""
    log_path = "/home/user/warnings.log"
    assert os.path.exists(log_path), f"Warnings log {log_path} is missing."
    with open(log_path, "r", encoding="utf-8", errors="strict", newline="") as f:
        log_content = f.read()

    expected_warnings_original = (
        "[WARNING] Font missing\n"
        "Falling back to default sans-serif font.\n"
        "Please install the required fonts.\n"
        "[WARNING] Unused stylesheet\n"
        "The main.css file is not linked.\n"
    )
    assert log_content.strip() == expected_warnings_original.strip(), (
        "The parsed warnings log does not match the expected multi-line warning records."
    )
    assert log_content == EXPECTED_WARNINGS, (
        "warnings.log does not exactly match warning records derived from the bundle"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
