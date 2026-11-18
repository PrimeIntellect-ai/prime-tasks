#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import uuid

EXPECTED = [
    {"date": "2023-10-01", "build_id": "B101", "path": "/home/user/repo/2023/10/B101.tar.gz"},
    {"date": "2023-10-02", "build_id": "B102", "path": "/home/user/repo/2023/10/B102.tar.gz"},
    {"date": "2023-11-05", "build_id": "B103", "path": "/home/user/repo/2023/11/B103.tar.gz"},
    {"date": "2024-01-15", "build_id": "B104", "path": "/home/user/repo/2024/01/B104.tar.gz"},
    {"date": "2024-02-28", "build_id": "B105", "path": "/home/user/repo/2024/02/B105.tar.gz"},
]


def test_incoming_empty():
    incoming_dir = "/home/user/incoming"
    assert os.path.exists(incoming_dir), f"{incoming_dir} should still exist"
    files = os.listdir(incoming_dir)
    assert len(files) == 0, f"Expected {incoming_dir} to be empty, but found: {files}"


def test_repo_structure():
    expected_files = [entry["path"] for entry in EXPECTED]
    for path in expected_files:
        assert os.path.isfile(path), f"Expected artifact not found at {path}"


def test_archives_are_valid_and_contain_expected_data():
    for entry in EXPECTED:
        path = entry["path"]
        try:
            with tarfile.open(path, "r:gz") as archive:
                names = archive.getnames()
                assert set(names) == {"metadata.txt", "payload.bin"}, \
                    f"Unexpected archive members in {path}: {names}"

                metadata_member = archive.getmember("metadata.txt")
                payload_member = archive.getmember("payload.bin")
                assert metadata_member.isfile(), f"metadata.txt is not a regular file in {path}"
                assert payload_member.isfile(), f"payload.bin is not a regular file in {path}"

                metadata_file = archive.extractfile(metadata_member)
                payload_file = archive.extractfile(payload_member)
                assert metadata_file is not None and payload_file is not None
                metadata = metadata_file.read().decode("utf-8")
                payload = payload_file.read()
        except (tarfile.TarError, OSError) as exc:
            assert False, f"{path} is not a valid tar.gz archive: {exc}"

        lines = metadata.splitlines()
        assert f"Build-ID: {entry['build_id']}" in lines, f"Wrong Build-ID in {path}"
        assert f"Date: {entry['date']}" in lines, f"Wrong Date in {path}"
        assert "Author: System" in lines, f"Expected metadata missing from {path}"
        assert len(payload) == 1024, f"payload.bin in {path} has the wrong size"


def test_manifest_content():
    manifest_path = "/home/user/repo/manifest.json"
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "manifest.json is not valid JSON"

    assert data == EXPECTED, f"Manifest content does not match expected.\nExpected: {EXPECTED}\nGot: {data}"


def test_atomic_write_in_code():
    script_path = "/home/user/curate.py"
    assert os.path.isfile(script_path), f"Script missing at {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    has_rename = "os.replace" in content or "os.rename" in content or "shutil.move" in content
    has_tmp = ".tmp" in content or "tmp" in content or "temp" in content
    assert has_rename and has_tmp, \
        "Script does not appear to use an atomic write pattern (missing .tmp usage or os.replace/os.rename)."

    try:
        ast.parse(content, filename=script_path)
    except SyntaxError as exc:
        assert False, f"curate.py is not valid Python: {exc}"


def test_script_processes_unseen_archive_and_atomically_replaces_manifest():
    script_path = "/home/user/curate.py"
    incoming_dir = "/home/user/incoming"
    manifest_path = "/home/user/repo/manifest.json"

    build_id = "VERIFY_" + uuid.uuid4().hex.upper()
    date = "2023-10-15"
    source_path = os.path.join(incoming_dir, "unpredictable_" + uuid.uuid4().hex + ".tar.gz")
    destination = f"/home/user/repo/2023/10/{build_id}.tar.gz"
    payload = os.urandom(131071)
    metadata = (
        f"Build-ID: {build_id}\n"
        f"Date: {date}\n"
        f"Verifier-Nonce: {uuid.uuid4().hex}\n"
    ).encode("utf-8")

    with tarfile.open(source_path, "w:gz") as archive:
        metadata_info = tarfile.TarInfo("metadata.txt")
        metadata_info.size = len(metadata)
        archive.addfile(metadata_info, io.BytesIO(metadata))
        payload_info = tarfile.TarInfo("payload.bin")
        payload_info.size = len(payload)
        archive.addfile(payload_info, io.BytesIO(payload))

    with open(source_path, "rb") as f:
        original_digest = hashlib.sha256(f.read()).hexdigest()
    with open(manifest_path, "r", encoding="utf-8") as f:
        old_manifest = json.load(f)

    # Keep the old inode alive so a non-atomic in-place rewrite cannot appear to
    # have replaced the manifest through immediate inode reuse.
    old_manifest_handle = open(manifest_path, "rb")
    old_inode = os.fstat(old_manifest_handle.fileno()).st_ino
    try:
        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"curate.py failed on a new archive. stdout={result.stdout!r} stderr={result.stderr!r}"

        assert not os.path.exists(source_path), "The newly supplied archive was not removed from incoming"
        assert os.path.isfile(destination), f"New archive was not moved to {destination}"
        with open(destination, "rb") as f:
            moved_digest = hashlib.sha256(f.read()).hexdigest()
        assert moved_digest == original_digest, "The moved archive was not preserved byte-for-byte"

        new_inode = os.stat(manifest_path).st_ino
        assert new_inode != old_inode, \
            "manifest.json was rewritten in place instead of being atomically replaced"

        with open(manifest_path, "r", encoding="utf-8") as f:
            updated_manifest = json.load(f)
        new_entry = {"date": date, "build_id": build_id, "path": destination}
        expected_manifest = sorted(old_manifest + [new_entry], key=lambda item: item["date"])
        assert updated_manifest == expected_manifest, \
            f"Manifest was not correctly updated for unseen input: {updated_manifest}"

        with tarfile.open(destination, "r:gz") as archive:
            assert archive.extractfile("metadata.txt").read() == metadata
            assert archive.extractfile("payload.bin").read() == payload
    finally:
        old_manifest_handle.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
