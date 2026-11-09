#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import shutil
import subprocess
import tarfile
import tempfile

CURATED = "/home/user/curated_repo"
BACKUP = "/home/user/backup"
RAW = "/home/user/raw_artifacts"

EXPECTED_CONTENT = {
    "stable_app_v1.bin": "app_v1.exe",
    "stable_Network_Tool_v2.bin": "Network Tool v2.out",
    "stable_script_file.bin": "script_file",
}
PATCH = "stable_patch.bin"


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def assert_safe_member_names(tf):
    for member in tf.getmembers():
        name = member.name
        assert not name.startswith("/"), f"Archive contains absolute path {name!r}."
        assert ".." not in name.split("/"), f"Archive contains traversal path {name!r}."


def regular_members(tf):
    return [m for m in tf.getmembers() if m.isfile()]


def assert_gnu_incremental_archive(tf, path):
    assert any(m.type == tarfile.GNUTYPE_DUMPDIR for m in tf.getmembers()), \
        f"{path} does not contain GNU listed-incremental directory metadata."


def test_curated_repo_files_exist_and_match_sources():
    expected_files = set(EXPECTED_CONTENT) | {PATCH}
    assert os.path.isdir(CURATED), f"Directory {CURATED} does not exist."

    actual_files = set(os.listdir(CURATED))
    for name in expected_files:
        assert name in actual_files, f"Expected file {name} is missing from {CURATED}."

    # Preserve the original exclusions.
    for name in ["stable_small_app.bin", "stable_library.bin"]:
        assert name not in actual_files, f"File {name} should not be in {CURATED}."

    assert actual_files == expected_files, \
        f"Curated repository has unexpected or missing entries: {actual_files!r}."

    for curated_name, raw_name in EXPECTED_CONTENT.items():
        curated_path = os.path.join(CURATED, curated_name)
        raw_path = os.path.join(RAW, raw_name)
        assert os.path.isfile(curated_path), f"{curated_path} is not a regular file."
        assert read_bytes(curated_path) == read_bytes(raw_path), \
            f"{curated_name} does not match its raw source {raw_name}."

    patch_path = os.path.join(CURATED, PATCH)
    assert os.path.isfile(patch_path), f"{patch_path} is not a regular file."
    assert os.path.getsize(patch_path) == 0, "stable_patch.bin was not created with touch semantics."


def test_backup_files_exist():
    assert os.path.isdir(BACKUP), f"Directory {BACKUP} does not exist."
    for name in ["full.tar", "inc.tar", "repo.snar"]:
        path = os.path.join(BACKUP, name)
        assert os.path.isfile(path), f"Backup file {path} is missing."


def test_full_tar_contents():
    path = os.path.join(BACKUP, "full.tar")
    assert tarfile.is_tarfile(path), f"{path} is not a valid tar file."

    with tarfile.open(path, "r") as tf:
        assert_safe_member_names(tf)
        assert_gnu_incremental_archive(tf, path)
        members = regular_members(tf)
        basenames = [os.path.basename(m.name.rstrip("/")) for m in members]
        counts = collections.Counter(basenames)

        assert set(basenames) == set(EXPECTED_CONTENT), \
            f"Full backup has incorrect regular-file payloads: {basenames!r}."
        assert all(counts[name] == 1 for name in EXPECTED_CONTENT), \
            "Full backup contains duplicate curated payloads."
        assert PATCH not in basenames, "Full backup incorrectly contains the later patch file."

        for member in members:
            name = os.path.basename(member.name.rstrip("/"))
            archived = tf.extractfile(member).read()
            source = read_bytes(os.path.join(RAW, EXPECTED_CONTENT[name]))
            assert archived == source, f"Full backup payload for {name} is incorrect."


def test_inc_tar_contents():
    path = os.path.join(BACKUP, "inc.tar")
    assert tarfile.is_tarfile(path), f"{path} is not a valid tar file."

    with tarfile.open(path, "r") as tf:
        assert_safe_member_names(tf)
        assert_gnu_incremental_archive(tf, path)
        members = regular_members(tf)
        basenames = [os.path.basename(m.name.rstrip("/")) for m in members]

        # Preserve the original required patch assertion.
        assert PATCH in basenames, f"stable_patch.bin was not found in {path}."
        patch_members = [m for m in members if os.path.basename(m.name.rstrip("/")) == PATCH]
        assert len(patch_members) == 1, "Incremental backup must contain one patch payload."
        assert patch_members[0].size == 0
        assert tf.extractfile(patch_members[0]).read() == b""

        allowed = set(EXPECTED_CONTENT) | {PATCH}
        assert set(basenames) <= allowed, \
            f"Incremental backup contains unrelated files: {basenames!r}."

        # Preserve the original assertion that unchanged files carry no data.
        for member in members:
            name = os.path.basename(member.name.rstrip("/"))
            if name in EXPECTED_CONTENT:
                assert member.size == 0, \
                    f"Unchanged file {member.name} was included with data in incremental backup."


def test_snapshot_is_valid_and_tracks_final_state():
    snar = os.path.join(BACKUP, "repo.snar")
    data = read_bytes(snar)
    assert data.startswith(b"GNU tar-"), "repo.snar lacks a GNU tar snapshot header."

    # A copied snapshot must be accepted by GNU tar and identify all current
    # curated files as already backed up. Try the two standard invocation forms
    # permitted by the instruction, without modifying the submitted snapshot.
    commands = [
        ["tar", "-cf", "{archive}", "--listed-incremental={snapshot}",
         "-C", "/home/user", "curated_repo"],
        ["tar", "-cf", "{archive}", "--listed-incremental={snapshot}",
         "-C", CURATED, "."],
    ]

    successes = []
    with tempfile.TemporaryDirectory() as td:
        for index, template in enumerate(commands):
            snapshot = os.path.join(td, f"probe-{index}.snar")
            archive = os.path.join(td, f"probe-{index}.tar")
            shutil.copyfile(snar, snapshot)
            command = [part.format(archive=archive, snapshot=snapshot) for part in template]
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode != 0 or not tarfile.is_tarfile(archive):
                continue
            with tarfile.open(archive, "r") as tf:
                successes.append(not any(m.isfile() for m in tf.getmembers()))

    assert successes, "repo.snar is not accepted as a GNU tar listed-incremental snapshot."
    assert any(successes), \
        "repo.snar does not record the final curated repository as already backed up."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
