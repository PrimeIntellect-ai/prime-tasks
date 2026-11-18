#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile

EXPECTED_CONTENT = """Status: PUBLISHED

# API V2
These are the new API docs.
Use the endpoints carefully.
Status: PUBLISHED

# Setup Guide
Run the installer to begin.
"""

def test_release_manual_content():
    manual_path = "/home/user/release_manual.md"
    assert os.path.isfile(manual_path), f"Expected file {manual_path} does not exist."

    with open(manual_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content.strip() == EXPECTED_CONTENT.strip(), "The contents of release_manual.md do not match the expected output."

def test_release_archive_exists_and_contains_manual():
    archive_path = "/home/user/release.tar.gz"
    manual_path = "/home/user/release_manual.md"
    assert os.path.isfile(archive_path), f"Expected archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"The file {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()
        # Preserve the original presence check, including its allowed path forms.
        found = any(m.endswith("release_manual.md") for m in members)
        assert found, f"The archive {archive_path} does not contain release_manual.md. Contents: {members}"

        all_members = tar.getmembers()
        assert len(all_members) == 1, (
            f"The archive must contain only the generated manual, but contains: {members}"
        )
        member = all_members[0]
        assert member.isfile(), "The sole archive member must be a regular file."
        assert os.path.basename(member.name.rstrip("/")) == "release_manual.md", (
            f"The archived file must be release_manual.md, not {member.name!r}."
        )

        archived_file = tar.extractfile(member)
        assert archived_file is not None, "Could not read the archived release_manual.md."
        archived_content = archived_file.read()

    with open(manual_path, "rb") as f:
        generated_content = f.read()

    assert archived_content == generated_content, (
        "The release_manual.md stored in the archive does not exactly match the generated manual."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
