#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import stat
import tarfile
from pathlib import PurePosixPath

import pytest

BASE = "/home/user/config_manager"
CHANGELOG = os.path.join(BASE, "changelog.txt")


def derive_target_commit():
    with open(CHANGELOG, "r", encoding="utf-8") as f:
        text = f.read()

    matches = []
    for entry in re.split(r"\r?\n[ \t]*\r?\n", text.strip()):
        fields = {}
        for line in entry.splitlines():
            if ":" in line:
                key, value = line.split(":", 1)
                fields[key.strip()] = value.strip()
        if fields.get("Message") == "Stable release v2.4":
            assert fields.get("Commit"), "Stable release entry has no Commit field"
            matches.append(fields["Commit"])

    assert len(matches) == 1, "Expected exactly one Stable release v2.4 entry"
    commit = matches[0]
    assert re.fullmatch(r"[A-Za-z0-9._-]+", commit), "Unsafe commit value in changelog"
    return commit


def expected_manifest_from_archive(commit):
    archive_path = os.path.join(BASE, "archives", f"backup_{commit}.tar")
    assert os.path.isfile(archive_path), f"Matching archive {archive_path} does not exist"

    chunks = []
    with tarfile.open(archive_path, "r:") as outer:
        for member in outer.getmembers():
            basename = PurePosixPath(member.name).name
            if basename.startswith("config.tar.gz."):
                assert member.isfile(), f"Archive chunk {member.name} is not a regular file"
                extracted = outer.extractfile(member)
                assert extracted is not None
                chunks.append((basename, extracted.read()))

    assert chunks, "No config.tar.gz split chunks found in matching archive"
    names = [name for name, _ in chunks]
    assert len(names) == len(set(names)), "Duplicate split chunk names in matching archive"
    chunks.sort(key=lambda item: item[0])
    inner_bytes = b"".join(data for _, data in chunks)

    manifest = {}
    top_levels = set()
    with tarfile.open(fileobj=io.BytesIO(inner_bytes), mode="r:gz") as inner:
        members = inner.getmembers()
        assert members, "Reassembled configuration archive is empty"

        normalized = []
        for member in members:
            raw = member.name.rstrip("/")
            if not raw or raw == ".":
                continue
            path = PurePosixPath(raw)
            assert not path.is_absolute() and ".." not in path.parts, "Unsafe path in configuration archive"
            parts = tuple(part for part in path.parts if part not in ("", "."))
            assert parts, "Invalid path in configuration archive"
            top_levels.add(parts[0])
            normalized.append((member, parts))

        assert len(top_levels) == 1, "Expected one configuration directory in inner archive"

        for member, parts in normalized:
            relative_parts = parts[1:]
            if not relative_parts:
                assert member.isdir(), "Top-level archive entry must be a directory"
                continue
            rel = "/".join(relative_parts)

            for index in range(1, len(relative_parts)):
                parent = "/".join(relative_parts[:index])
                manifest.setdefault(parent, ("dir", None))

            if member.isdir():
                value = ("dir", None)
            elif member.isfile():
                extracted = inner.extractfile(member)
                assert extracted is not None
                value = ("file", extracted.read())
            elif member.issym():
                value = ("symlink", member.linkname)
            else:
                pytest.fail(f"Unsupported entry type in configuration archive: {member.name}")

            if rel in manifest:
                assert manifest[rel] == value, f"Conflicting duplicate archive entry: {rel}"
            manifest[rel] = value

    assert "database.conf" in manifest and manifest["database.conf"][0] == "file", \
        "Extracted configuration archive has no regular database.conf"
    return manifest


def actual_manifest(root):
    result = {}

    def visit(directory, prefix=""):
        with os.scandir(directory) as entries:
            for entry in entries:
                rel = f"{prefix}/{entry.name}" if prefix else entry.name
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode):
                    result[rel] = ("symlink", os.readlink(entry.path))
                elif stat.S_ISDIR(info.st_mode):
                    result[rel] = ("dir", None)
                    visit(entry.path, rel)
                elif stat.S_ISREG(info.st_mode):
                    with open(entry.path, "rb") as f:
                        result[rel] = ("file", f.read())
                else:
                    pytest.fail(f"Unexpected filesystem object in deployed configuration: {rel}")

    visit(root)
    return result


COMMIT = derive_target_commit()
EXPECTED_MANIFEST = expected_manifest_from_archive(COMMIT)
VERSION_DIR = os.path.join(BASE, "versions", COMMIT)
DB_BYTES = EXPECTED_MANIFEST["database.conf"][1]
DB_TEXT = DB_BYTES.decode("utf-8")
MAX_MATCHES = re.findall(r"(?m)^\s*max_connections\s*=\s*(.*?)\s*$", DB_TEXT)
assert len(MAX_MATCHES) == 1, "Expected exactly one max_connections setting in archived database.conf"
MAX_CONNECTIONS = MAX_MATCHES[0]


def test_live_config_symlink():
    symlink_path = os.path.join(BASE, "live_config")
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."

    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert abs_target == VERSION_DIR, \
        f"Symlink target {target} does not point directly to the expected {VERSION_DIR} directory."
    assert os.path.isdir(VERSION_DIR), f"Expected version directory {VERSION_DIR} does not exist"
    assert not os.path.islink(VERSION_DIR), f"Expected {VERSION_DIR} itself to be a real directory"


def test_deployed_configuration_matches_archive():
    assert actual_manifest(VERSION_DIR) == EXPECTED_MANIFEST, \
        "Deployed version does not exactly match the configuration in the matching backup archive"


def test_database_conf_in_live_config():
    db_conf_path = os.path.join(BASE, "live_config", "database.conf")
    assert os.path.isfile(db_conf_path), f"Expected configuration file {db_conf_path} does not exist. Did the extraction or symlink fail?"

    with open(db_conf_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert f"max_connections={MAX_CONNECTIONS}" in content, \
        "The database.conf file does not contain the correct max_connections value."
    assert content.encode("utf-8") == DB_BYTES, \
        "The live database.conf does not exactly match the file from the matching archive."


def test_rollback_report():
    report_path = os.path.join(BASE, "rollback_report.txt")
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_content = f"Rollback Hash: {COMMIT}\nMax Connections: {MAX_CONNECTIONS}"
    assert content == expected_content, \
        f"Report file content is incorrect.\nExpected:\n{expected_content}\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
