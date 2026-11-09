#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import tarfile
import tempfile

import pytest


def get_sha256(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def test_cpp_files_exist():
    assert os.path.isfile("/home/user/tracker.cpp"), "/home/user/tracker.cpp is missing."
    assert os.path.isfile("/home/user/tracker"), "/home/user/tracker executable is missing."
    assert os.access("/home/user/tracker", os.X_OK), "/home/user/tracker is not executable."
    with open("/home/user/tracker", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/tracker is not a compiled Linux executable."


def test_manifest_v2_correctness():
    manifest_path = "/home/user/manifest_v2.txt"
    assert os.path.isfile(manifest_path), f"{manifest_path} is missing."

    sha_a = get_sha256("/home/user/gcode_current/partA.gcode")
    sha_b = get_sha256("/home/user/gcode_current/partB.gcode")
    sha_c = get_sha256("/home/user/gcode_current/partC.gcode")

    expected_lines = [
        f"partA.gcode,1.0,{sha_a}",
        f"partB.gcode,1.2,{sha_b}",
        f"partC.gcode,2.0,{sha_c}"
    ]

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Manifest contents are incorrect or not sorted properly.\n"
        f"Expected:\n{expected_lines}\n"
        f"Actual:\n{actual_lines}"
    )


def test_incremental_archive():
    archive_path = "/home/user/incremental.tar.gz"
    assert os.path.isfile(archive_path), f"{archive_path} is missing."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()
            members = tar.getmembers()
            archived_data = {
                member.name: tar.extractfile(member).read()
                for member in members
                if member.isfile()
            }
    except tarfile.ReadError:
        pytest.fail(f"{archive_path} is not a valid gzip-compressed tarball.")

    expected_files = {"partB.gcode", "partC.gcode"}
    actual_files = set(names)

    assert actual_files == expected_files, (
        f"Archive contents do not match expected NEW_OR_CHANGED files at the root.\n"
        f"Expected exactly: {expected_files}\n"
        f"Found: {actual_files}"
    )
    assert len(names) == len(expected_files), "Archive contains duplicate or extra entries."
    assert all(member.isfile() for member in members), "Archive entries must be regular files."
    for name in expected_files:
        with open(f"/home/user/gcode_current/{name}", "rb") as f:
            assert archived_data[name] == f.read(), f"Archived contents of {name} are incorrect."


def test_tracker_four_argument_behavior_on_generated_inputs():
    token = secrets.token_hex(8)
    version_new = f"new-{secrets.token_hex(5)}"
    version_unchanged = f"same-{secrets.token_hex(5)}"

    new_name = f"a_{token}.gcode"
    changed_name = f"b_{token}.gcode"
    unchanged_name = f"c_{token}.gcode"
    ignored_name = f"ignored_{token}.txt"

    with tempfile.TemporaryDirectory(prefix="tracker_verify_") as root:
        current_dir = os.path.join(root, "current")
        os.mkdir(current_dir)

        files = {
            new_name: f";; VERSION: {version_new}\nG90\nM104 S{secrets.randbelow(150) + 100}\n".encode(),
            changed_name: f";;VERSION: malformed-{token}\nG21\nM140 S{secrets.randbelow(50) + 40}\n".encode(),
            unchanged_name: f";; VERSION: {version_unchanged}\nG28\nM84\n".encode(),
        }
        for name, data in files.items():
            with open(os.path.join(current_dir, name), "wb") as f:
                f.write(data)
        with open(os.path.join(current_dir, ignored_name), "wb") as f:
            f.write(b";; VERSION: should-not-be-scanned\n")

        hashes = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
        old_manifest = os.path.join(root, "old_manifest.txt")
        with open(old_manifest, "w") as f:
            f.write(f"{unchanged_name},obsolete-version,{hashes[unchanged_name]}\n")
            f.write(f"{changed_name},old-version,{secrets.token_hex(32)}\n")
            f.write(f"removed_{token}.gcode,1.0,{secrets.token_hex(32)}\n")

        new_manifest = os.path.join(root, "new_manifest.txt")
        archive = os.path.join(root, "incremental.tar.gz")
        result = subprocess.run(
            ["/home/user/tracker", old_manifest, current_dir, new_manifest, archive],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"tracker failed on valid four-argument input with code {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(new_manifest), "tracker did not create the requested manifest."
        assert os.path.isfile(archive), "tracker did not create the requested archive."

        expected_manifest = [
            f"{new_name},{version_new},{hashes[new_name]}",
            f"{changed_name},UNKNOWN,{hashes[changed_name]}",
            f"{unchanged_name},{version_unchanged},{hashes[unchanged_name]}",
        ]
        with open(new_manifest) as f:
            actual_manifest = [line.rstrip("\r\n") for line in f if line.strip()]
        assert actual_manifest == expected_manifest, (
            f"Generated-input manifest is incorrect.\n"
            f"Expected: {expected_manifest}\nActual: {actual_manifest}"
        )

        try:
            with tarfile.open(archive, "r:gz") as tar:
                members = tar.getmembers()
                names = [member.name for member in members]
                assert names == [new_name, changed_name] or set(names) == {new_name, changed_name}
                assert len(names) == 2, "Generated archive contains duplicate or extra entries."
                assert all(member.isfile() for member in members), "Archive entries must be regular files."
                for member in members:
                    assert "/" not in member.name, "Archive files must be stored at its root."
                    assert tar.extractfile(member).read() == files[member.name], (
                        f"Archived contents of {member.name} differ from the input file."
                    )
        except tarfile.ReadError:
            pytest.fail("tracker did not produce a valid gzip-compressed tar archive.")


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
