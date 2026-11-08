#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile


def test_release_docs_tar_exists():
    """Verify that the final release archive exists."""
    release_path = '/home/user/release_docs.tar'
    assert os.path.isfile(release_path), f"The target output file {release_path} is missing."


def test_release_docs_tar_contents():
    """Verify that the archive contains exactly the renamed files and their original contents."""
    release_path = '/home/user/release_docs.tar'
    assert os.path.isfile(release_path), f"Cannot check contents, {release_path} does not exist."

    expected_files = {
        '01_Introduction.md',
        '02_API_Reference.md',
        '03_Changelog.md'
    }
    expected_contents = {
        '01_Introduction.md': b'# Introduction Draft\n',
        '02_API_Reference.md': b'# API Details\n',
        '03_Changelog.md': b'# Change history\n',
    }

    try:
        with tarfile.open(release_path, 'r') as tar:
            members = tar.getmembers()

            actual_files = set()
            for member in members:
                # Ensure no directories are included
                assert member.isfile(), f"Archive contains non-file member: {member.name}. It should only contain files."
                # Ensure files are at the root level (no slashes in the path)
                assert '/' not in member.name, f"File {member.name} is not at the root level of the archive."
                actual_files.add(member.name)

            assert actual_files == expected_files, (
                f"Archive contents do not match exactly.\n"
                f"Expected: {expected_files}\n"
                f"Actual: {actual_files}"
            )

            assert len(members) == len(expected_files), (
                f"Archive contains {len(members)} members; expected exactly {len(expected_files)}."
            )

            for member in members:
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archived file: {member.name}"
                actual_content = extracted.read()
                assert actual_content == expected_contents[member.name], (
                    f"Content of {member.name} does not match its source draft."
                )
    except tarfile.ReadError:
        assert False, f"The file {release_path} is not a valid tar archive."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
