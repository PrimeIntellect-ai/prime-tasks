#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_manifest_file_exists():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Output file {manifest_path} does not exist. The task is not complete."


def test_manifest_contents():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Output file {manifest_path} does not exist."

    with open(manifest_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "auth_service_v2.tar.gz",
        "kernel_module_x86.tar.gz",
        "ui_assets.zip",
    ]
    expected_content = "\n".join(expected_lines)

    assert content == expected_content, (
        f"Contents of {manifest_path} do not match the expected verified artifacts.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )


def test_atomic_move_used():
    manifest_path = "/home/user/manifest.txt"
    parent_path = os.path.dirname(manifest_path)
    assert os.path.isfile(manifest_path), f"Output file {manifest_path} does not exist."

    manifest_stat = os.stat(manifest_path)
    parent_stat = os.stat(parent_path)

    # A direct write creates the destination directory entry before writing the
    # file, leaving the file's modification time later than the directory's.
    # Writing a temporary file and renaming it into place updates the parent
    # directory only after the temporary file's contents have been completed.
    assert parent_stat.st_mtime_ns > manifest_stat.st_mtime_ns, (
        "The manifest does not show evidence of atomic installation: the final "
        "file must be fully written as a temporary file and then moved to "
        f"{manifest_path}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
