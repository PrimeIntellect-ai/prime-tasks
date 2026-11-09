#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import struct
import subprocess
import tempfile
import uuid
import pytest


def test_extracted_files_content():
    """Verify the safe files are extracted and [COMPANY_NAME] is replaced with AcmeCorp in .md files."""

    expected_files = {
        "/home/user/docs_safe/intro.md": "# Welcome to AcmeCorp Docs\nThis is the intro.",
        "/home/user/docs_safe/api/setup.md": "## API Setup\nAcmeCorp provides a REST API.",
        "/home/user/docs_safe/internal/notes.txt": "Random notes. No company name here."
    }

    for path, expected_content in expected_files.items():
        assert os.path.isfile(path), f"Expected file {path} is missing."
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {path}."


def test_malicious_files_skipped():
    """Verify that files with '../' in their path were not extracted."""

    malicious_paths = [
        "/home/user/hacked_root.md",
        "/home/etc_fake/passwd",
        "/home/user/sneaky.md",
        "/home/user/docs_safe/../hacked_root.md",
        "/home/user/docs_safe/api/../../etc_fake/passwd",
        "/home/user/docs_safe/nested/../../sneaky.md"
    ]

    for path in malicious_paths:
        resolved_path = os.path.abspath(path)
        assert not os.path.exists(resolved_path), f"Malicious file {resolved_path} was extracted!"


def test_manifest_file():
    """Verify that the manifest file is generated correctly with sorted relative paths."""
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "api/setup.md",
        "internal/notes.txt",
        "intro.md"
    ]

    assert lines == expected_lines, f"Manifest content mismatch. Expected {expected_lines}, got {lines}."


def _entry(path, content):
    path_bytes = path.encode("ascii")
    return struct.pack("<H", len(path_bytes)) + path_bytes + struct.pack("<I", len(content)) + content


def _remove(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_extraction_utility_compiles_and_handles_unseen_archive():
    source = "/home/user/extract.cpp"
    archive = "/home/user/docpack.bin"
    output = "/home/user/docs_safe"

    assert os.path.isfile(source), "Required C++ source /home/user/extract.cpp is missing."
    assert stat.S_ISREG(os.stat(source).st_mode), "extract.cpp must be a regular source file."
    assert os.path.getsize(source) > 0, "extract.cpp is empty."

    token = uuid.uuid4().hex
    executable = os.path.join(tempfile.gettempdir(), "extract_verifier_" + token)
    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert build.returncode == 0, "extract.cpp failed to compile:\n" + build.stderr

    safe_entries = {
        f"probe_{token}.bin": b"binary\x00payload\xff" + os.urandom(19),
        f"deep_{token}/chapter/data.txt": os.urandom(41),
        f"deep_{token}/empty.dat": b"",
    }
    outside_one = f"/home/user/escape_{token}.bin"
    outside_two = f"/home/user/escape2_{token}.bin"
    inside_skipped = f"inside_escape_{token}.bin"

    malicious_entries = {
        f"../escape_{token}.bin": b"must not escape",
        f"nest/../../escape2_{token}.bin": b"must also be skipped",
        f"folder/../{inside_skipped}": b"substring rule requires skipping",
    }

    original_archive = open(archive, "rb").read()
    backup_root = tempfile.mkdtemp(prefix="docs_safe_backup_")
    backup_docs = os.path.join(backup_root, "docs_safe")
    had_output = os.path.lexists(output)
    if had_output:
        shutil.copytree(output, backup_docs, symlinks=True)

    try:
        assert not os.path.lexists(outside_one)
        assert not os.path.lexists(outside_two)

        archive_bytes = b"DOCP"
        for path, content in list(safe_entries.items()) + list(malicious_entries.items()):
            archive_bytes += _entry(path, content)
        with open(archive, "wb") as f:
            f.write(archive_bytes)

        if os.path.lexists(output):
            _remove(output)
        os.makedirs(output)

        run = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run.returncode == 0, f"Compiled extractor exited with status {run.returncode}."

        actual_files = set()
        for root, dirs, files in os.walk(output):
            for name in files:
                full = os.path.join(root, name)
                actual_files.add(os.path.relpath(full, output).replace(os.sep, "/"))

        assert actual_files == set(safe_entries), (
            f"Unexpected extraction result for generated archive: {sorted(actual_files)}"
        )
        for relative, expected in safe_entries.items():
            with open(os.path.join(output, *relative.split("/")), "rb") as f:
                assert f.read() == expected, f"Content mismatch for generated entry {relative}."

        assert not os.path.exists(outside_one), "A generated '../' entry escaped docs_safe."
        assert not os.path.exists(outside_two), "A generated nested traversal entry escaped docs_safe."
        assert not os.path.exists(os.path.join(output, inside_skipped)), (
            "An entry containing '../' was not skipped."
        )
    finally:
        with open(archive, "wb") as f:
            f.write(original_archive)
        if os.path.lexists(output):
            _remove(output)
        if had_output:
            shutil.copytree(backup_docs, output, symlinks=True)
        shutil.rmtree(backup_root, ignore_errors=True)
        if os.path.lexists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
