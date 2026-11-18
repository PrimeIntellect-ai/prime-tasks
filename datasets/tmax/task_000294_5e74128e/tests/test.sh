#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import io
import os
import re
import stat
import subprocess
import tarfile

import pytest

RAW_ARCHIVE = "/home/user/raw_data.tar"
CLEAN_DIR = "/home/user/clean_docs"
OUTPUT_ARCHIVE = "/home/user/organized_docs.tar.gz"
EXPECTED_FILES = {"intro.md", "setup.md", "api.txt", "build_tool"}
EXPECTED_TEXT = {
    "intro.md": b"# Introduction\n",
    "setup.md": b"Setup instructions\n",
    "api.txt": b"API reference\n",
}


def regular_member_bytes(tar, member):
    assert member.isfile(), f"Source member '{member.name}' is not a regular file."
    extracted = tar.extractfile(member)
    assert extracted is not None
    return extracted.read()


@pytest.fixture(scope="module")
def source_data():
    assert os.path.isfile(RAW_ARCHIVE), f"Source archive {RAW_ARCHIVE} is missing."
    assert not os.path.islink(RAW_ARCHIVE), f"Source archive {RAW_ARCHIVE} must not be a symlink."

    with tarfile.open(RAW_ARCHIVE, "r:") as master:
        members = {m.name: m for m in master.getmembers()}
        assert "rules.ini" in members
        assert "backup.log" in members

        rules_bytes = regular_member_bytes(master, members["rules.ini"])
        log_bytes = regular_member_bytes(master, members["backup.log"])

        parser = configparser.ConfigParser()
        parser.read_string(rules_bytes.decode("utf-8"))
        extensions = tuple(
            ext.strip() for ext in parser.get("Output", "extensions").split(",") if ext.strip()
        )
        tool_format = parser.get("Tools", "format").strip()
        assert extensions == (".md", ".txt")
        assert tool_format == "ELF"

        log = log_bytes.decode("utf-8")
        blocks = re.findall(
            r"(?ms)^\[[^\n]+\] ERROR Incident ID: (\d+)\n(.*?)(?=^\[[^\n]+\] |\Z)",
            log,
        )
        incidents = [incident for incident, body in blocks if "InfiniteSymlinkException" in body]
        assert incidents == ["88310"], f"Unexpected InfiniteSymlinkException incidents: {incidents}"

        nested_members = [
            m for m in master.getmembers()
            if m.isfile() and re.fullmatch(r"docs_[^/]+\.tar\.gz", m.name)
        ]
        assert {m.name for m in nested_members} == {"docs_a.tar.gz", "docs_b.tar.gz"}

        docs = {}
        tools = []
        for nested_member in nested_members:
            nested_bytes = regular_member_bytes(master, nested_member)
            with tarfile.open(fileobj=io.BytesIO(nested_bytes), mode="r:gz") as nested:
                for member in nested.getmembers():
                    # Symlinks, directories, and all other non-regular members are ignored.
                    if not member.isfile():
                        continue
                    data = regular_member_bytes(nested, member)
                    basename = os.path.basename(member.name)
                    if basename.endswith(extensions):
                        assert basename not in docs, f"Duplicate flattened documentation name: {basename}"
                        docs[basename] = data
                    if (
                        tool_format == "ELF"
                        and data.startswith(b"\x7fELF")
                        and member.mode & 0o111
                    ):
                        tools.append((member.name, data))

    assert docs == EXPECTED_TEXT, "Documentation in the source archives is not the expected input."
    assert len(tools) == 1, f"Expected exactly one executable ELF source tool, found {len(tools)}."
    tool_name, tool_bytes = tools[0]
    assert os.path.basename(tool_name) == "doc_generator"
    with open("/bin/ls", "rb") as system_ls:
        assert tool_bytes == system_ls.read(), "The source build tool does not match the packaged executable."

    expected = dict(docs)
    expected["build_tool"] = tool_bytes
    return {"incident": incidents[0], "files": expected}


def test_incident_id(source_data):
    incident_file = "/home/user/incident_id.txt"
    assert os.path.exists(incident_file), f"File {incident_file} does not exist."
    assert os.path.isfile(incident_file) and not os.path.islink(incident_file)
    with open(incident_file, "r") as f:
        content = f.read().strip()
    assert content == "88310", f"Expected incident ID '88310', but got '{content}'."
    assert content == source_data["incident"]


def test_clean_docs(source_data):
    assert os.path.isdir(CLEAN_DIR), f"Directory {CLEAN_DIR} does not exist."
    assert not os.path.islink(CLEAN_DIR), f"Directory {CLEAN_DIR} must not be a symlink."

    entries = list(os.scandir(CLEAN_DIR))
    assert {entry.name for entry in entries} == EXPECTED_FILES
    assert len(entries) == 4

    for entry in entries:
        info = entry.stat(follow_symlinks=False)
        assert stat.S_ISREG(info.st_mode), f"{entry.path} is not a regular file."
        assert not entry.is_symlink(), f"{entry.path} is a symbolic link."
        with open(entry.path, "rb") as f:
            assert f.read() == source_data["files"][entry.name], f"Incorrect contents in {entry.path}."

    tool_path = os.path.join(CLEAN_DIR, "build_tool")
    assert os.access(tool_path, os.X_OK), "build_tool is not executable."
    result = subprocess.run(
        [tool_path, "--version"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, "build_tool could not be executed successfully."


def test_organized_docs_archive(source_data):
    archive_path = OUTPUT_ARCHIVE
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."
    assert os.path.isfile(archive_path) and not os.path.islink(archive_path)
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."

    expected_files = {"intro.md", "setup.md", "api.txt", "build_tool"}

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()

        # Check that there are exactly 4 members
        assert len(members) == 4, f"Expected exactly 4 files in the archive, found {len(members)}."

        actual_files = set()
        for member in members:
            # Must be a regular file
            assert member.isfile(), f"Archive member '{member.name}' is not a regular file."
            # Must not contain directory separators (i.e. must be at the root)
            assert "/" not in member.name and "\\" not in member.name, f"File '{member.name}' is not at the root of the archive."
            actual_files.add(member.name)
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == source_data["files"][member.name], f"Incorrect contents for archive member '{member.name}'."

        assert actual_files == expected_files, f"Archive contents {actual_files} do not match expected {expected_files}."

        # Verify build_tool is an ELF binary
        build_tool_member = tar.getmember("build_tool")
        with tar.extractfile(build_tool_member) as f:
            header = f.read(4)
            assert header == b"\x7fELF", "The 'build_tool' file does not have a valid ELF header."
        assert build_tool_member.mode & 0o111, "The archived build_tool is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
