#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import tarfile
import tempfile
from pathlib import Path

import pytest

CONFIG_DIR = Path("/home/user/configs")
BACKUP_DIR = Path("/home/user/backup")
LOG_PATH = Path("/home/user/changes.log")
ARCHIVE_PATH = Path("/home/user/archive.b64")


def last_commit_files():
    lines = LOG_PATH.read_text().splitlines()
    commit_starts = [i for i, line in enumerate(lines) if line.startswith("COMMIT:")]
    assert commit_starts, "No commits found in changes.log."

    entry = lines[commit_starts[-1]:]
    files_header = next((i for i, line in enumerate(entry) if line.strip() == "FILES:"), None)
    assert files_header is not None, "Last commit has no FILES section."

    files = []
    for line in entry[files_header + 1:]:
        stripped = line.strip()
        if stripped.startswith("-"):
            name = stripped[1:].strip()
            assert name, "Empty filename in last commit."
            files.append(name)
        elif stripped:
            break

    assert files, "Last commit contains no modified files."
    assert len(files) == len(set(files)), "Last commit lists a file more than once."
    return files


def parse_conf(path):
    result = {}
    with path.open("r") as f:
        for line_number, raw_line in enumerate(f, 1):
            line = raw_line.rstrip("\r\n")
            if not line:
                continue
            assert "=" in line, f"Invalid config line {line_number} in {path}."
            key, value = line.split("=", 1)
            result[key] = value
    return result


def expected_outputs():
    expected = {}
    for config_name in last_commit_files():
        config_path = CONFIG_DIR / config_name
        assert config_path.is_file(), f"Modified config does not exist: {config_path}"
        output_name = f"backup_{Path(config_name).stem}.json"
        assert output_name not in expected, "Modified config names collide after renaming."
        expected[output_name] = parse_conf(config_path)
    return expected


def normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name


def test_backup_json_files():
    expected = expected_outputs()
    assert BACKUP_DIR.is_dir(), f"Directory {BACKUP_DIR} does not exist."

    actual_entries = os.listdir(BACKUP_DIR)
    assert set(actual_entries) == set(expected), (
        f"Backup directory must contain only the JSON files for the last commit; "
        f"expected {sorted(expected)}, got {sorted(actual_entries)}"
    )

    for output_name, expected_data in expected.items():
        output_path = BACKUP_DIR / output_name
        assert output_path.is_file(), f"File {output_path} does not exist or is not a regular file."
        try:
            with output_path.open("r") as f:
                actual_data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{output_path} is not valid JSON: {exc}")
        assert isinstance(actual_data, dict), f"{output_path} must contain a JSON object."
        assert actual_data == expected_data, f"Incorrect content in {output_path}."


def test_archive_b64():
    expected = expected_outputs()
    assert ARCHIVE_PATH.is_file(), f"File {ARCHIVE_PATH} does not exist."

    try:
        encoded = ARCHIVE_PATH.read_text()
        compact_encoded = "".join(encoded.split()).encode("ascii")
        tar_gz_data = base64.b64decode(compact_encoded, validate=True)
    except Exception as exc:
        pytest.fail(f"Failed to Base64 decode {ARCHIVE_PATH}: {exc}")

    assert tar_gz_data.startswith(b"\x1f\x8b"), "Decoded archive is not gzip-compressed."

    with tempfile.NamedTemporaryFile(delete=False) as tmp_tar:
        tmp_tar.write(tar_gz_data)
        tmp_tar_path = tmp_tar.name

    try:
        assert tarfile.is_tarfile(tmp_tar_path), "Decoded data is not a valid tar file."
        try:
            archive = tarfile.open(tmp_tar_path, "r:gz")
        except tarfile.TarError as exc:
            pytest.fail(f"Decoded data is not a valid gzip tarball: {exc}")

        with archive:
            members = archive.getmembers()
            normalized_names = [normalized_member_name(member.name) for member in members]

            assert len(members) == len(expected), (
                f"Tarball must contain only the relevant JSON files; found {normalized_names}"
            )
            assert set(normalized_names) == set(expected), (
                f"Tarball contents are incorrect; expected {sorted(expected)}, "
                f"got {sorted(normalized_names)}"
            )
            assert len(normalized_names) == len(set(normalized_names)), "Tarball contains duplicate files."

            for member, name in zip(members, normalized_names):
                assert member.isfile(), f"Tarball member is not a regular file: {member.name}"
                assert member.name in (name, f"./{name}"), (
                    f"Tarball member must not include a parent directory path: {member.name}"
                )

                archived_file = archive.extractfile(member)
                assert archived_file is not None, f"Could not read tarball member: {member.name}"
                archived_bytes = archived_file.read()
                disk_bytes = (BACKUP_DIR / name).read_bytes()
                assert archived_bytes == disk_bytes, (
                    f"Archived {name} does not match the JSON file in the backup directory."
                )

                try:
                    archived_data = json.loads(archived_bytes.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    pytest.fail(f"Archived {name} is not valid JSON: {exc}")
                assert archived_data == expected[name], f"Archived {name} has incorrect content."
    finally:
        os.remove(tmp_tar_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
