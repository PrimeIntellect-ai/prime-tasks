#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tarfile
import uuid
import zipfile

import pytest

HOME = "/home/user"
WORKSPACE = os.path.join(HOME, "docs_workspace")
SOURCE = os.path.join(HOME, "organizer.cpp")
ARCHIVE = os.path.join(HOME, "raw_docs.tar.gz")
ZIP_PATH = os.path.join(HOME, "release_docs.zip")

EXPECTED_DOCS = [
    {
        "directory": "raw_docs/api",
        "target": "endpoints.md",
        "renamed": "api_v1.0_endpoints.md",
        "status": "approved",
        "content": b"# API v1\n",
    },
    {
        "directory": "raw_docs/api",
        "target": "legacy.md",
        "renamed": "api_v0.9_legacy.md",
        "status": "deprecated",
        "content": b"# Old API\n",
    },
    {
        "directory": "raw_docs/core",
        "target": "engine.md",
        "renamed": "core_v3.2_engine.md",
        "status": "approved",
        "content": b"# Core Engine\n",
    },
    {
        "directory": "raw_docs/core",
        "target": "future.md",
        "renamed": "core_v4.0_future.md",
        "status": "draft",
        "content": b"# Core Draft\n",
    },
    {
        "directory": "raw_docs/ui",
        "target": "buttons.md",
        "renamed": "frontend_v1.5_buttons.md",
        "status": "approved",
        "content": b"# UI Components\n",
    },
]

EXPECTED_APPROVED = {
    doc["renamed"]: doc["content"]
    for doc in EXPECTED_DOCS
    if doc["status"] == "approved"
}


def test_release_docs_zip_exists():
    assert os.path.isfile(ZIP_PATH), "Failed: /home/user/release_docs.zip does not exist"


def test_release_docs_zip_contents():
    assert os.path.isfile(ZIP_PATH), "Failed: /home/user/release_docs.zip does not exist"

    with zipfile.ZipFile(ZIP_PATH, "r") as z:
        file_list = z.namelist()

        # Preserve the original filename assertions.
        files_only = [f for f in file_list if not f.endswith("/")]
        expected_files = {
            "api_v1.0_endpoints.md",
            "core_v3.2_engine.md",
            "frontend_v1.5_buttons.md",
        }
        actual_files = set(files_only)

        missing = expected_files - actual_files
        assert not missing, f"Failed: Missing expected files in zip: {missing}"

        unexpected = actual_files - expected_files
        assert not unexpected, f"Failed: Zip contains unexpected files: {unexpected}"

        for f in actual_files:
            assert "/" not in f and "\\" not in f, (
                f"Failed: Zip file contains directory paths '{f}'. Should be flattened."
            )

        # Reject duplicate entries, directory entries, empty placeholders, and wrong content.
        assert len(file_list) == len(expected_files), "ZIP must contain exactly three flat files"
        assert len(files_only) == len(set(files_only)), "ZIP contains duplicate file entries"
        for name, expected_content in EXPECTED_APPROVED.items():
            assert z.read(name) == expected_content, f"Wrong archived content for {name}"


def test_organizer_cpp_exists():
    assert os.path.isfile(SOURCE), f"Failed: C++ source file {SOURCE} does not exist"


def test_docs_workspace_exists():
    assert os.path.isdir(WORKSPACE), f"Failed: Extracted directory {WORKSPACE} does not exist"


def test_archive_and_final_workspace_state():
    # Confirm the immutable task input still describes the expected documents rather
    # than trusting a possibly modified archive as an oracle.
    with tarfile.open(ARCHIVE, "r:gz") as tf:
        members = {m.name: m for m in tf.getmembers() if m.isfile()}
        metadata_names = sorted(n for n in members if n.endswith(".meta.json"))
        assert len(metadata_names) == 5, "Input archive metadata was altered"

        observed = []
        for metadata_name in metadata_names:
            metadata = json.loads(tf.extractfile(members[metadata_name]).read().decode("utf-8"))
            directory = os.path.dirname(metadata_name)
            target_path = os.path.join(directory, metadata["target_file"])
            assert target_path in members, f"Metadata target is missing: {target_path}"
            observed.append({
                "directory": directory,
                "target": metadata["target_file"],
                "renamed": f'{metadata["component"]}_{metadata["version"]}_{metadata["target_file"]}',
                "status": metadata["status"],
                "content": tf.extractfile(members[target_path]).read(),
            })

    assert sorted(observed, key=lambda d: (d["directory"], d["target"])) == sorted(
        EXPECTED_DOCS, key=lambda d: (d["directory"], d["target"])
    ), "Input archive content or metadata was altered"

    for doc in EXPECTED_DOCS:
        directory = os.path.join(WORKSPACE, doc["directory"])
        original = os.path.join(directory, doc["target"])
        renamed = os.path.join(directory, doc["renamed"])
        if doc["status"] == "approved":
            assert not os.path.exists(original), f"Approved source was not renamed: {original}"
            assert os.path.isfile(renamed), f"Renamed approved document is missing: {renamed}"
            with open(renamed, "rb") as f:
                assert f.read() == doc["content"], f"Wrong workspace content: {renamed}"
        else:
            assert os.path.isfile(original), f"Unapproved source should remain unrenamed: {original}"
            with open(original, "rb") as f:
                assert f.read() == doc["content"], f"Wrong workspace content: {original}"
            assert not os.path.exists(renamed), f"Unapproved document was renamed: {renamed}"


@pytest.fixture(scope="session")
def compiled_organizer():
    output = "/tmp/organizer_verifier_binary"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-I/home/user", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"organizer.cpp failed to compile:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def test_compiles(compiled_organizer):
    assert os.path.isfile(compiled_organizer)


def test_organizer_executes_and_parses_json(compiled_organizer):
    # Re-run the submitted program against a clean extraction plus unpredictable,
    # valid metadata so pre-created filenames or hardcoded known documents cannot pass.
    token = uuid.uuid4().hex[:12]
    component = "audit" + token
    version = "v9.9" + token
    approved_target = "probe.md"
    rejected_target = "private.md"
    approved_new = f"{component}_{version}_{approved_target}"
    rejected_new = f"{component}_{version}_{rejected_target}"
    approved_content = ("# verifier approved " + token + "\n").encode()
    rejected_content = ("# verifier rejected " + token + "\n").encode()

    backup = "/tmp/docs_workspace_backup_" + uuid.uuid4().hex
    assert not os.path.exists(backup)
    shutil.move(WORKSPACE, backup)
    try:
        os.makedirs(WORKSPACE)
        with tarfile.open(ARCHIVE, "r:gz") as tf:
            tf.extractall(WORKSPACE)

        case_dir = os.path.join(WORKSPACE, "raw_docs", "audit_case_" + token)
        os.makedirs(case_dir)
        with open(os.path.join(case_dir, approved_target), "wb") as f:
            f.write(approved_content)
        with open(os.path.join(case_dir, "probe.meta.json"), "w", encoding="utf-8") as f:
            json.dump({
                "target_file": approved_target,
                "component": component,
                "version": version,
                "status": "approved",
            }, f)
        with open(os.path.join(case_dir, rejected_target), "wb") as f:
            f.write(rejected_content)
        with open(os.path.join(case_dir, "private.meta.json"), "w", encoding="utf-8") as f:
            json.dump({
                "target_file": rejected_target,
                "component": component,
                "version": version,
                "status": "draft",
            }, f)

        result = subprocess.run(
            [compiled_organizer],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Compiled organizer failed when executed:\nstdout: {result.stdout}\n"
            f"stderr: {result.stderr}"
        )

        approved_path = os.path.join(case_dir, approved_new)
        assert not os.path.exists(os.path.join(case_dir, approved_target))
        assert os.path.isfile(approved_path), "Organizer did not rename dynamic approved document"
        with open(approved_path, "rb") as f:
            assert f.read() == approved_content

        rejected_path = os.path.join(case_dir, rejected_target)
        assert os.path.isfile(rejected_path), "Organizer removed or renamed a draft document"
        with open(rejected_path, "rb") as f:
            assert f.read() == rejected_content
        assert not os.path.exists(os.path.join(case_dir, rejected_new))

        # The clean archive's approved files must also have been processed recursively.
        for doc in EXPECTED_DOCS:
            directory = os.path.join(WORKSPACE, doc["directory"])
            original = os.path.join(directory, doc["target"])
            renamed = os.path.join(directory, doc["renamed"])
            if doc["status"] == "approved":
                assert os.path.isfile(renamed) and not os.path.exists(original)
            else:
                assert os.path.isfile(original) and not os.path.exists(renamed)
    finally:
        shutil.rmtree(WORKSPACE, ignore_errors=True)
        if os.path.exists(backup):
            shutil.move(backup, WORKSPACE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
