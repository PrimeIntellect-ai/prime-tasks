#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import zlib
import hashlib
import pytest
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

PROCESSED_DOCS_DIR = "/home/user/processed_docs"

EXPECTED_DOCS = {
    "intro_001.md": (
        "---\n"
        "title: Introduction\n"
        "author: Alice\n"
        "date: 2023-01-01\n"
        "---\n\n"
        "Welcome to the documentation.\n"
    ),
    "api_002.md": (
        "---\n"
        "title: API Reference\n"
        "author: Bob\n"
        "date: 2023-01-02\n"
        "---\n\n"
        "Here is the API.\n"
    ),
    "storage_003.md": (
        "---\n"
        "title: Storage Guide\n"
        "author: Charlie\n"
        "date: 2023-01-03\n"
        "---\n\n"
        "Data storage concepts.\n"
    )
}

def test_scripts_exist():
    assert os.path.isfile("/home/user/transformer.py"), "transformer.py is missing."
    assert os.path.isfile("/home/user/compress.py"), "compress.py is missing."


def test_transformer_general_behavior():
    token = secrets.token_hex(12)
    cases = [
        (
            f"Title: Generated {token}\n"
            f"Author: Author {token[::-1]}\n"
            "Date: 2042-07-19\n"
            "\n"
            f"First generated body {token}.\n\nSecond line.\n",
            f"---\ntitle: Generated {token}\nauthor: Author {token[::-1]}\n"
            f"date: 2042-07-19\n---\n\nFirst generated body {token}.\n\nSecond line.\n",
        ),
        (
            f"Title: Other {token}\n"
            "Author: Test Writer\n"
            "Date: 1999-12-31\n"
            f"Body begins immediately: {token}",
            f"---\ntitle: Other {token}\nauthor: Test Writer\n"
            f"date: 1999-12-31\n---\nBody begins immediately: {token}",
        ),
    ]

    for input_text, expected_text in cases:
        result = subprocess.run(
            [sys.executable, "/home/user/transformer.py"],
            input=input_text.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"transformer.py exited with {result.returncode}: "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )
        assert result.stdout == expected_text.encode("utf-8"), (
            "transformer.py did not correctly transform generated input or "
            "preserve its body exactly"
        )


def test_compressor_general_behavior():
    token = secrets.token_hex(12)
    backup_dir = tempfile.mkdtemp(prefix="processed_docs_backup_")
    os.rmdir(backup_dir)
    os.rename(PROCESSED_DOCS_DIR, backup_dir)

    try:
        os.mkdir(PROCESSED_DOCS_DIR)
        generated_docs = {
            f"generated_{token}.md": b"# Generated\n\n" + token.encode("ascii") + b"\n",
            f"binary_{token}.md": bytes(range(256)) + os.urandom(37),
        }
        manifest_bytes = f"manifest sentinel {token}\n".encode("ascii")

        for filename, content in generated_docs.items():
            with open(os.path.join(PROCESSED_DOCS_DIR, filename), "wb") as f:
                f.write(content)
        with open(os.path.join(PROCESSED_DOCS_DIR, "manifest.txt"), "wb") as f:
            f.write(manifest_bytes)

        result = subprocess.run(
            [sys.executable, "/home/user/compress.py"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"compress.py exited with {result.returncode}: "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )

        for filename, original_content in generated_docs.items():
            original_path = os.path.join(PROCESSED_DOCS_DIR, filename)
            compressed_path = original_path + ".zlib"
            assert not os.path.exists(original_path), f"compress.py did not delete {filename}"
            assert os.path.isfile(compressed_path), f"compress.py did not create {filename}.zlib"
            with open(compressed_path, "rb") as f:
                assert zlib.decompress(f.read()) == original_content, (
                    f"compress.py did not correctly zlib-compress {filename}"
                )

        with open(os.path.join(PROCESSED_DOCS_DIR, "manifest.txt"), "rb") as f:
            assert f.read() == manifest_bytes, "compress.py modified manifest.txt"

        expected_files = {"manifest.txt"} | {f"{name}.zlib" for name in generated_docs}
        assert set(os.listdir(PROCESSED_DOCS_DIR)) == expected_files, (
            "compress.py produced unexpected files during generated-input test"
        )
    finally:
        if os.path.lexists(PROCESSED_DOCS_DIR):
            if os.path.islink(PROCESSED_DOCS_DIR) or not os.path.isdir(PROCESSED_DOCS_DIR):
                os.unlink(PROCESSED_DOCS_DIR)
            else:
                shutil.rmtree(PROCESSED_DOCS_DIR)
        os.rename(backup_dir, PROCESSED_DOCS_DIR)


def test_no_uncompressed_md_files():
    md_files = glob.glob(os.path.join(PROCESSED_DOCS_DIR, "*.md"))
    assert len(md_files) == 0, f"Uncompressed .md files should have been deleted, found: {md_files}"


def test_manifest_exists_and_correct():
    manifest_path = os.path.join(PROCESSED_DOCS_DIR, "manifest.txt")
    assert os.path.isfile(manifest_path), "manifest.txt is missing."

    with open(manifest_path, "r") as f:
        manifest_content = f.read()

    for filename, content in EXPECTED_DOCS.items():
        expected_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()
        assert expected_hash in manifest_content, f"Expected hash {expected_hash} for {filename} not found in manifest.txt"
        assert filename in manifest_content, f"Filename {filename} not found in manifest.txt"

    lines = manifest_content.splitlines()
    assert len(lines) == len(EXPECTED_DOCS), "manifest.txt must contain exactly one line per processed document"
    expected_lines = {
        f"{hashlib.sha256(content.encode('utf-8')).hexdigest()}  {filename}"
        for filename, content in EXPECTED_DOCS.items()
    }
    for line in lines:
        assert re.fullmatch(r"[0-9a-f]{64}  [^/\n]+\.md", line), (
            f"Manifest line is not in standard sha256sum format with a base filename: {line!r}"
        )
    assert set(lines) == expected_lines, "Manifest hashes are not correctly paired with their filenames"


def test_zlib_files_exist_and_correct():
    for filename, expected_content in EXPECTED_DOCS.items():
        zlib_filename = f"{filename}.zlib"
        zlib_path = os.path.join(PROCESSED_DOCS_DIR, zlib_filename)
        assert os.path.isfile(zlib_path), f"Compressed file {zlib_filename} is missing."

        with open(zlib_path, "rb") as f:
            compressed_data = f.read()

        try:
            decompressed_data = zlib.decompress(compressed_data).decode('utf-8')
        except Exception as e:
            pytest.fail(f"Failed to decompress {zlib_filename}: {e}")

        assert decompressed_data == expected_content, f"Decompressed content of {zlib_filename} does not match expected output."


def test_no_unexpected_files_in_processed_docs():
    expected_files = {f"{k}.zlib" for k in EXPECTED_DOCS.keys()}
    expected_files.add("manifest.txt")

    found_files = set(os.listdir(PROCESSED_DOCS_DIR))
    unexpected = found_files - expected_files
    assert not unexpected, f"Unexpected files found in processed_docs: {unexpected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
