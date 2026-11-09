#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import subprocess
import tarfile
from collections import Counter

import pytest

DOCS_ROOT = "/home/user/docs_raw"
SOURCE_PATH = "/home/user/doc_builder.go"
ARCHIVE_PATH = "/home/user/published_docs.tar.gz"
ELIGIBLE_SUFFIXES = (".md", ".txt", ".md.gz", ".txt.gz")


def is_publish(data):
    return any(line.startswith(b"Status: Publish") for line in data.splitlines())


def archive_name(path):
    name = os.path.relpath(path, DOCS_ROOT).replace(os.sep, "/")
    return name[:-3] if name.endswith(".gz") else name


def expected_documents():
    expected = {}
    for root, _, files in os.walk(DOCS_ROOT):
        for filename in files:
            if not filename.endswith(ELIGIBLE_SUFFIXES):
                continue
            path = os.path.join(root, filename)
            if filename.endswith(".gz"):
                with gzip.open(path, "rb") as f:
                    data = f.read()
            else:
                with open(path, "rb") as f:
                    data = f.read()
            if is_publish(data):
                name = archive_name(path)
                assert name not in expected, f"Test input has colliding archive name: {name}"
                expected[name] = data
    return expected


def test_published_docs_archive():
    assert os.path.isfile(SOURCE_PATH), f"Go program {SOURCE_PATH} does not exist"

    # Add unpredictable nested inputs so a hard-coded archive cannot pass.
    token = secrets.token_hex(16)
    dynamic_dir = os.path.join(DOCS_ROOT, "verification_" + token, "deep", "nested")
    os.makedirs(dynamic_dir)

    plain_publish = (
        f"Status: Publish\nTitle: Dynamic plain {token}\n\n"
        f"Complete plain payload {secrets.token_hex(32)}\n"
    ).encode()
    gzip_publish = (
        f"Metadata: generated\nStatus: Publish - approved\nTitle: Dynamic gzip {token}\n\n"
        f"Complete compressed payload {secrets.token_hex(32)}\n"
    ).encode()
    gzip_draft = (
        f"Status: Draft\nTitle: Dynamic draft {token}\n\n"
        f"Must not be archived {secrets.token_hex(24)}\n"
    ).encode()
    near_match = (
        f"XStatus: Publish\nTitle: Not a status line {token}\n\n"
        f"Must not be archived {secrets.token_hex(24)}\n"
    ).encode()

    with open(os.path.join(dynamic_dir, "plain_" + token + ".txt"), "wb") as f:
        f.write(plain_publish)
    with gzip.open(os.path.join(dynamic_dir, "compressed_" + token + ".md.gz"), "wb") as f:
        f.write(gzip_publish)
    with gzip.open(os.path.join(dynamic_dir, "draft_" + token + ".txt.gz"), "wb") as f:
        f.write(gzip_draft)
    with open(os.path.join(dynamic_dir, "near_" + token + ".md"), "wb") as f:
        f.write(near_match)
    with open(os.path.join(dynamic_dir, "ignored_" + token + ".bin"), "wb") as f:
        f.write(b"Status: Publish\nThis extension is unsupported.\n")

    expected = expected_documents()

    # Remove any prebuilt artifact and require the submitted Go source to recreate it.
    if os.path.lexists(ARCHIVE_PATH):
        os.remove(ARCHIVE_PATH)
    result = subprocess.run(
        ["go", "run", SOURCE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"go run failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist. Did you run the Go program?"

    try:
        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            members = tar.getnames()

            # Original fixed assertions remain in force.
            assert "api/v1/endpoints.txt" in members, "api/v1/endpoints.txt is missing from the archive"
            assert "tutorials/getting_started.md" in members, "tutorials/getting_started.md is missing from the archive"
            assert "guide.md" not in members, "guide.md is marked as Draft and should not be in the archive"
            assert "api/v2/auth.md" not in members, "api/v2/auth.md is marked as Draft and should not be in the archive"
            assert "api/v2/auth.md.gz" not in members, "api/v2/auth.md.gz should not be in the archive"
            for member in members:
                assert not member.endswith(".gz"), f"File {member} still has a .gz extension in the archive"

            endpoints_f = tar.extractfile("api/v1/endpoints.txt")
            assert endpoints_f is not None, "Could not read api/v1/endpoints.txt from archive"
            endpoints_content = endpoints_f.read().decode("utf-8")
            assert "Status: Publish" in endpoints_content, "Missing 'Status: Publish' in api/v1/endpoints.txt"
            assert "GET /api/v1/status" in endpoints_content, "Missing expected content in api/v1/endpoints.txt"

            getting_started_f = tar.extractfile("tutorials/getting_started.md")
            assert getting_started_f is not None, "Could not read tutorials/getting_started.md from archive"
            getting_started_content = getting_started_f.read().decode("utf-8")
            assert "Status: Publish" in getting_started_content, "Missing 'Status: Publish' in tutorials/getting_started.md"

            # The archive must contain exactly every currently publishable document.
            assert Counter(members) == Counter(expected), (
                f"Archive members differ from recursively derived expected members. "
                f"Expected {sorted(expected)}, got {members}"
            )
            for member in tar.getmembers():
                assert member.isfile(), f"Archive member {member.name} is not a regular file"
                assert member.mode & 0o777 == 0o644, f"Archive member {member.name} has mode {oct(member.mode & 0o777)}, expected 0o644"
                assert member.size == len(expected[member.name]), f"Incorrect tar header size for {member.name}"
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read {member.name} from archive"
                assert extracted.read() == expected[member.name], f"Contents of {member.name} were not preserved exactly"

            assert endpoints_content.encode() == expected["api/v1/endpoints.txt"]
            assert getting_started_content.encode() == expected["tutorials/getting_started.md"]
    except tarfile.ReadError:
        pytest.fail(f"{ARCHIVE_PATH} is not a valid gzip-compressed tar archive")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
