#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid

EXPECTED = {
    "deadbeef.bin": ("core-v1.2.0.bin", b"binary data 1\n"),
    "cafebabe.bin": ("core-v1.2.1.bin", b"binary data 2\n"),
    "8badf00d.bin": ("utils-v0.9.bin", b"binary data 3\n"),
}


def test_cpp_exists():
    assert os.path.isfile("/home/user/renamer.cpp"), "/home/user/renamer.cpp does not exist."


def test_cpp_compiles():
    result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/renamer.cpp", "-o", "/tmp/renamer-verifier"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"renamer.cpp did not compile:\n{result.stderr}"
    assert os.path.isfile("/tmp/renamer-verifier")


def test_original_binaries_untouched():
    expected_binaries = [
        "deadbeef.bin",
        "cafebabe.bin",
        "8badf00d.bin"
    ]
    for binary in expected_binaries:
        path = os.path.join("/home/user/repo/binaries", binary)
        assert os.path.isfile(path), f"Original binary {path} is missing or was modified."
        with open(path, "rb") as f:
            assert f.read() == EXPECTED[binary][1], f"Original binary {path} was modified."


def test_staging_renamed():
    staging_dir = "/home/user/repo/staging"
    assert os.path.isdir(staging_dir), "Staging directory does not exist."

    expected_files = [
        "core-v1.2.0.bin",
        "core-v1.2.1.bin",
        "utils-v0.9.bin"
    ]
    unexpected_files = [
        "deadbeef.bin",
        "cafebabe.bin",
        "8badf00d.bin"
    ]

    files_in_staging = os.listdir(staging_dir)

    for f in expected_files:
        assert f in files_in_staging, f"Expected file {f} not found in staging directory."

    for f in unexpected_files:
        assert f not in files_in_staging, f"Original hashed file {f} should not exist in staging directory."

    assert set(files_in_staging) == set(expected_files), "Staging contains unexpected entries."
    for hashed, (semantic, expected_data) in EXPECTED.items():
        path = os.path.join(staging_dir, semantic)
        assert os.path.isfile(path), f"Staged output {path} is not a regular file."
        with open(path, "rb") as f:
            assert f.read() == expected_data, f"Staged file {semantic} does not match {hashed}."


def test_tarball_exists_and_contents():
    tarball_path = "/home/user/backup/incremental.tar.gz"
    assert os.path.isfile(tarball_path), f"Backup tarball {tarball_path} does not exist."

    expected_basenames = {
        "core-v1.2.0.bin",
        "core-v1.2.1.bin",
        "utils-v0.9.bin"
    }

    found_basenames = set()
    regular_members = {}
    has_incremental_directory = False
    with tarfile.open(tarball_path, "r:gz") as tar:
        for member in tar.getmembers():
            basename = os.path.basename(member.name)
            if basename:
                found_basenames.add(basename)

            normalized = member.name
            while normalized.startswith("./"):
                normalized = normalized[2:]
            normalized = normalized.rstrip("/")

            if member.type == tarfile.GNUTYPE_DUMPDIR:
                has_incremental_directory = True

            if member.isfile():
                assert normalized and "/" not in normalized, \
                    f"Tar member {member.name} is not at the staging root."
                assert normalized not in regular_members, f"Duplicate tar member {member.name}."
                extracted = tar.extractfile(member)
                assert extracted is not None
                regular_members[normalized] = extracted.read()

    for expected in expected_basenames:
        assert expected in found_basenames, f"File {expected} is missing from the tarball."

    for found in found_basenames:
        if found not in expected_basenames and found != "." and found != "":
            assert not found.endswith(".bin") or found in expected_basenames, f"Unexpected binary {found} found in tarball."

    assert set(regular_members) == expected_basenames, "Tarball has missing or unexpected regular files."
    expected_by_semantic = {semantic: data for semantic, data in EXPECTED.values()}
    for name, data in regular_members.items():
        assert data == expected_by_semantic[name], f"Tar member {name} has incorrect contents."
    assert has_incremental_directory, "Archive is not a GNU incremental tar archive."


def test_snapshot_updated():
    snapshot_path = "/home/user/backup/snapshot.snar"
    assert os.path.isfile(snapshot_path), f"Snapshot file {snapshot_path} does not exist."

    binary_mtime = os.path.getmtime("/home/user/repo/binaries/deadbeef.bin")
    snapshot_mtime = os.path.getmtime(snapshot_path)

    assert snapshot_mtime >= binary_mtime, "Snapshot file does not appear to have been updated."

    with open(snapshot_path, "rb") as f:
        snapshot = f.read()
    assert snapshot.startswith(b"GNU tar-"), "Snapshot is not a GNU tar incremental snapshot."
    assert b"/home/user/repo/staging" in snapshot, "Snapshot does not track the staging directory."
    for semantic, _ in EXPECTED.values():
        assert semantic.encode() in snapshot, f"Snapshot does not record {semantic}."


def test_submitted_program_executes_and_renames_derived_inputs():
    executable = "/tmp/renamer-verifier"
    assert os.path.isfile(executable), "Compiled renamer executable is missing."

    repo = "/home/user/repo"
    staging = os.path.join(repo, "staging")
    mapping = os.path.join(repo, "mapping.csv")

    with tempfile.TemporaryDirectory(prefix="renamer-test-") as temp:
        saved_staging = os.path.join(temp, "original-staging")
        saved_mapping = os.path.join(temp, "original-mapping.csv")
        shutil.copy2(mapping, saved_mapping)
        os.rename(staging, saved_staging)

        token = uuid.uuid4().hex
        cases = []
        try:
            os.mkdir(staging)
            for i in range(3):
                old_name = f"{token}_{i}.bin"
                new_name = f"release-{token}-{i}.bin"
                data = os.urandom(97 + i)
                cases.append((old_name, new_name, data))
                with open(os.path.join(staging, old_name), "wb") as f:
                    f.write(data)

            with open(mapping, "w", newline="") as f:
                for old_name, new_name, _ in cases:
                    f.write(f"{old_name},{new_name}\n")

            result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, \
                f"Compiled renamer failed on verifier inputs:\n{result.stdout}\n{result.stderr}"

            assert set(os.listdir(staging)) == {new for _, new, _ in cases}, \
                "Compiled renamer did not produce exactly the mapped filenames."
            for old_name, new_name, data in cases:
                assert not os.path.exists(os.path.join(staging, old_name))
                with open(os.path.join(staging, new_name), "rb") as f:
                    assert f.read() == data, f"Renaming {old_name} did not preserve file contents."
        finally:
            if os.path.lexists(staging):
                if os.path.isdir(staging) and not os.path.islink(staging):
                    shutil.rmtree(staging)
                else:
                    os.unlink(staging)
            os.rename(saved_staging, staging)
            shutil.copy2(saved_mapping, mapping)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
