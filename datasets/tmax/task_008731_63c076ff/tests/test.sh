#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tarfile
import tempfile
import uuid
import xml.etree.ElementTree as ET

import pytest

INCOMING = "/home/user/docs_incoming"
PROCESSED = "/home/user/docs_processed"
BACKUP = "/home/user/docs_backup/backup_1.tar"
SNAPSHOT = "/home/user/docs_backup/snapshot.snar"
SCRIPT = "/home/user/organize_docs.py"

EXPECTED_CONTENTS = {
    "lovelace_1001.json": b'{\n    "doc_id": "1001",\n    "author": "lovelace",\n    "content": "Introduction to analytical engines."\n}\n',
    "turing_1002.xml": b'<doc>\n    <doc_id>1002</doc_id>\n    <author>turing</author>\n    <content>On computable numbers.</content>\n</doc>\n',
    "hopper_1003.json": b'{\n    "doc_id": "1003",\n    "author": "hopper",\n    "content": "Compilers and debugging."\n}\n',
}
EXPECTED_FILES = set(EXPECTED_CONTENTS)


def test_docs_incoming_empty():
    assert os.path.isdir(INCOMING), f"Directory {INCOMING} does not exist"
    files = os.listdir(INCOMING)
    assert len(files) == 0, f"Directory {INCOMING} is not empty, found: {files}"


def test_docs_processed_files():
    assert os.path.isdir(PROCESSED), f"Directory {PROCESSED} does not exist"
    processed_files = set(os.listdir(PROCESSED))
    assert processed_files == EXPECTED_FILES, (
        f"Expected files {EXPECTED_FILES} in {PROCESSED}, but found {processed_files}"
    )


def test_processed_file_contents():
    for name, expected in EXPECTED_CONTENTS.items():
        path = os.path.join(PROCESSED, name)
        assert os.path.isfile(path), f"Processed file {path} is missing"
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Processed file {path} does not preserve the draft content"

    with open(os.path.join(PROCESSED, "lovelace_1001.json"), encoding="utf-8") as f:
        assert json.load(f)["content"] == "Introduction to analytical engines."
    with open(os.path.join(PROCESSED, "hopper_1003.json"), encoding="utf-8") as f:
        assert json.load(f)["content"] == "Compilers and debugging."
    root = ET.parse(os.path.join(PROCESSED, "turing_1002.xml")).getroot()
    assert root.findtext("content") == "On computable numbers."


def test_backup_files_exist():
    assert os.path.isfile(BACKUP), f"Backup tarball {BACKUP} is missing"
    assert os.path.isfile(SNAPSHOT), f"Snapshot file {SNAPSHOT} is missing"


def test_tar_contents():
    assert os.path.isfile(BACKUP), f"Backup tarball {BACKUP} is missing"
    try:
        with tarfile.open(BACKUP, "r") as tar:
            tar_names = tar.getnames()
            for expected in EXPECTED_FILES:
                assert any(expected in name for name in tar_names), (
                    f"File {expected} is missing from the tarball {BACKUP}"
                )
    except tarfile.ReadError:
        pytest.fail(f"File {BACKUP} is not a valid tar archive")


def test_tar_contains_original_files_and_incremental_metadata():
    with tarfile.open(BACKUP, "r") as tar:
        members_by_basename = {}
        for member in tar.getmembers():
            members_by_basename.setdefault(os.path.basename(member.name.rstrip("/")), []).append(member)

        for name, expected in EXPECTED_CONTENTS.items():
            matches = [m for m in members_by_basename.get(name, []) if m.isfile()]
            assert len(matches) == 1, f"Expected exactly one regular {name} in the backup"
            extracted = tar.extractfile(matches[0])
            assert extracted is not None
            assert extracted.read() == expected, f"Backup content for {name} is incorrect"

        assert any(member.type == tarfile.GNUTYPE_DUMPDIR for member in tar.getmembers()), (
            "Backup does not contain GNU incremental directory metadata"
        )


def test_snapshot_is_gnu_tar_incremental_metadata():
    with open(SNAPSHOT, "rb") as f:
        snapshot_data = f.read()
    assert snapshot_data.startswith(b"GNU tar-"), (
        "snapshot.snar is not GNU tar listed-incremental metadata"
    )
    assert len(snapshot_data) > len(b"GNU tar-"), "snapshot.snar is incomplete"

    with tempfile.TemporaryDirectory() as tmp:
        snapshot_copy = os.path.join(tmp, "snapshot.snar")
        archive = os.path.join(tmp, "probe.tar")
        with open(snapshot_copy, "wb") as f:
            f.write(snapshot_data)
        result = subprocess.run(
            [
                "tar",
                f"--listed-incremental={snapshot_copy}",
                "-cf",
                archive,
                "-C",
                "/home/user",
                "docs_processed",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"GNU tar rejected snapshot.snar: {result.stderr}"


def test_script_exists_and_processes_new_inputs():
    assert os.path.lexists(SCRIPT), f"Required script {SCRIPT} is missing"
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular Python script"

    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, f"{SCRIPT} is not valid Python: {compile_result.stderr}"

    token = uuid.uuid4().hex
    author_json = f"author{token[:10]}"
    doc_json = f"j{token[10:20]}"
    author_xml = f"writer{token[20:26]}"
    doc_xml = f"x{token[26:]}"

    json_bytes = json.dumps({
        "doc_id": doc_json,
        "author": author_json,
        "content": f"random-json-content-{token}",
    }, indent=2).encode("utf-8") + b"\n"
    xml_bytes = (
        f"<doc><content>random-xml-content-{token}</content>"
        f"<author>{author_xml}</author><doc_id>{doc_xml}</doc_id></doc>\n"
    ).encode("utf-8")

    source_json = os.path.join(INCOMING, f"unstructured_{token}.json")
    source_xml = os.path.join(INCOMING, f"unstructured_{token}.xml")
    with open(source_json, "wb") as f:
        f.write(json_bytes)
    with open(source_xml, "wb") as f:
        f.write(xml_bytes)

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Script failed on new drafts: {result.stderr}"
    assert os.listdir(INCOMING) == [], f"Script did not empty {INCOMING}: {os.listdir(INCOMING)}"

    expected_new = {
        f"{author_json}_{doc_json}.json": json_bytes,
        f"{author_xml}_{doc_xml}.xml": xml_bytes,
    }
    assert set(os.listdir(PROCESSED)) == EXPECTED_FILES | set(expected_new), (
        "Script did not rename the generated JSON and XML drafts as required"
    )
    for name, expected in expected_new.items():
        with open(os.path.join(PROCESSED, name), "rb") as f:
            assert f.read() == expected, f"Script changed the content of generated draft {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
