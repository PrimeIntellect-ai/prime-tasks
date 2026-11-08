#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile

def test_final_docs_archive():
    archive_path = "/home/user/final_docs.tar.gz"
    assert os.path.isfile(archive_path), f"File {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    expected_files = {
        "doc_01.md": b"System Architecture Overview\n[END OF DOCUMENT]",
        "doc_02.md": b"API Endpoint Specification\n[END OF DOCUMENT]",
        "doc_3.md": b"User Authentication Flow\n[END OF DOCUMENT]",
        "asset_1.bin": b"binary_blob_alpha_9982",
        "image_asset_2.bin": b"binary_blob_beta_1123"
    }

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()

        # Check that files are at the root of the archive (no directories or nested paths)
        for member in members:
            assert '/' not in member.name and '\\' not in member.name, \
                f"Archive contains a subdirectory or nested file: {member.name}. Files must be at the root."
            assert member.isfile(), f"Archive contains non-file member: {member.name}"

        member_names = [m.name for m in members]

        # Check expected files and their contents
        for expected_name, expected_content in expected_files.items():
            assert expected_name in member_names, f"Expected file {expected_name} not found in archive."

            f = tar.extractfile(expected_name)
            assert f is not None, f"Could not extract {expected_name}"
            content = f.read()
            assert content == expected_content, \
                f"Content of {expected_name} is incorrect.\nExpected: {expected_content!r}\nGot: {content!r}"

        # Ensure no extra files are present
        extra_files = set(member_names) - set(expected_files.keys())
        assert not extra_files, f"Archive contains unexpected files: {extra_files}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
