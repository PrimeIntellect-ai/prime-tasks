#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import stat
import subprocess

import pytest

ROOT = "/home/user/legacy_data"
CONFIG = "/home/user/backup.conf"
ARCHIVE = "/home/user/backup.custom"


def read_config():
    mappings = {}
    with open(CONFIG, "r", encoding="utf-8") as f:
        for lineno, raw_line in enumerate(f, 1):
            line = raw_line.strip()
            if not line:
                continue
            parts = [part.strip() for part in line.split(",")]
            assert len(parts) == 2, f"Invalid configuration line {lineno}"
            extension, encoding = parts
            extension = extension.lstrip(".")
            assert extension and encoding, f"Invalid configuration line {lineno}"
            assert extension not in mappings, f"Duplicate extension in configuration: {extension}"
            mappings[extension] = encoding
    assert mappings, "backup.conf contains no extension mappings"
    return mappings


def is_regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except FileNotFoundError:
        return False


def derive_expected():
    mappings = read_config()
    expected = {}
    originals = []

    for dirpath, dirnames, filenames in os.walk(ROOT, followlinks=False):
        dirnames.sort()
        filenames.sort()
        for name in filenames:
            source = os.path.join(dirpath, name)
            if not is_regular_file(source):
                continue
            for extension, encoding in mappings.items():
                suffix = "." + extension
                output_suffix = ".utf8." + extension
                if name.endswith(suffix) and not name.endswith(output_suffix):
                    output_name = name[:-len(suffix)] + output_suffix
                    output = os.path.join(dirpath, output_name)
                    rel_output = os.path.relpath(output, ROOT).replace(os.sep, "/")
                    result = subprocess.run(
                        ["iconv", "-f", encoding, "-t", "UTF-8", source],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    assert result.returncode == 0, (
                        f"Could not derive conversion for {source} using {encoding}: "
                        + result.stderr.decode("utf-8", "replace")
                    )
                    result.stdout.decode("utf-8")
                    assert rel_output not in expected, f"Duplicate output path: {rel_output}"
                    expected[rel_output] = result.stdout
                    originals.append(source)
                    break

    assert expected, "No matching source files were found"
    return mappings, expected, originals


MAPPINGS, EXPECTED, ORIGINALS = derive_expected()


def discover_converted_files():
    found = set()
    suffixes = tuple(".utf8." + extension for extension in MAPPINGS)
    for dirpath, dirnames, filenames in os.walk(ROOT, followlinks=False):
        for name in filenames:
            path = os.path.join(dirpath, name)
            if name.endswith(suffixes) and is_regular_file(path):
                found.add(os.path.relpath(path, ROOT).replace(os.sep, "/"))
    return found


def parse_archive(raw):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Archive is not valid UTF-8 text: {exc}")

    lines = text.splitlines(keepends=True)
    assert lines, "Archive is empty"
    assert all(line.endswith("\n") for line in lines), "Every archive line must end with a newline"

    parsed = {}
    index = 0
    header_re = re.compile(r"^===FILE:(.+)===$")

    while index < len(lines):
        header = lines[index][:-1]
        match = header_re.fullmatch(header)
        assert match is not None, f"Malformed archive header at line {index + 1}"
        rel_path = match.group(1)
        assert rel_path not in parsed, f"Duplicate archive entry: {rel_path}"
        index += 1

        payload_lines = []
        while index < len(lines) and lines[index] != "===EOF===\n":
            assert not lines[index].startswith("===FILE:"), f"Missing footer before entry at line {index + 1}"
            payload_lines.append(lines[index])
            index += 1

        assert index < len(lines), f"Missing footer for archive entry {rel_path}"
        parsed[rel_path] = "".join(payload_lines)
        index += 1

    return parsed


def test_backup_custom_exists():
    assert is_regular_file(ARCHIVE), "/home/user/backup.custom does not exist or is not a regular file"


def test_original_files_still_exist():
    for path in ORIGINALS:
        assert is_regular_file(path), f"Original file was deleted: {path}"


def test_utf8_files_exist_and_content():
    assert discover_converted_files() == set(EXPECTED), "Missing or unexpected converted files"

    for rel_path, expected_bytes in EXPECTED.items():
        path = os.path.join(ROOT, *rel_path.split("/"))
        assert is_regular_file(path), f"Converted file {path} does not exist or is not a regular file"
        with open(path, "rb") as f:
            content = f.read()
        try:
            content.decode("utf-8")
        except UnicodeDecodeError as exc:
            pytest.fail(f"File {path} is not valid UTF-8: {exc}")
        assert content == expected_bytes, f"Exact content mismatch in {path}"


def test_backup_custom_content():
    assert is_regular_file(ARCHIVE), f"Archive {ARCHIVE} does not exist or is not a regular file"
    with open(ARCHIVE, "rb") as f:
        parsed = parse_archive(f.read())

    assert set(parsed) == set(EXPECTED), "Archive has missing, duplicate, or unexpected entries"

    for rel_path, expected_bytes in EXPECTED.items():
        payload = parsed[rel_path]
        expected_payload = base64.encodebytes(expected_bytes).decode("ascii")
        assert payload == expected_payload, f"Base64 formatting or content mismatch for {rel_path}"
        compact = "".join(payload.splitlines())
        try:
            decoded = base64.b64decode(compact, validate=True)
        except Exception as exc:
            pytest.fail(f"Invalid base64 content for {rel_path}: {exc}")
        assert decoded == expected_bytes, f"Decoded archive content mismatch for {rel_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
