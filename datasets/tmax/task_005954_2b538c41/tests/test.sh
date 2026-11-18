#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import pytest

def test_new_docs_files_and_contents():
    expected_files = {
        "/home/user/new_docs/System_Overview/introduction.txt": "Welcome to the GlobalTech system docs.\n",
        "/home/user/new_docs/API_Reference/authentication.txt": "The GlobalTech API is RESTful.\n",
        "/home/user/new_docs/User_Guides/routing_setup.txt": "GlobalTech guide to routing.\n"
    }

    for path, expected_content in expected_files.items():
        assert os.path.isfile(path), f"Expected file {path} was not created."
        with open(path, "r") as f:
            content = f.read()
            assert content.strip() == expected_content.strip(), f"Content of {path} is incorrect. Expected '{expected_content.strip()}', got '{content.strip()}'."

def test_release_tarball():
    tar_path = "/home/user/release.tar.gz"
    assert os.path.isfile(tar_path), f"Tarball {tar_path} was not created."

    expected_entries = {
        "new_docs/System_Overview/introduction.txt": "/home/user/new_docs/System_Overview/introduction.txt",
        "new_docs/API_Reference/authentication.txt": "/home/user/new_docs/API_Reference/authentication.txt",
        "new_docs/User_Guides/routing_setup.txt": "/home/user/new_docs/User_Guides/routing_setup.txt"
    }

    with tarfile.open(tar_path, "r:gz") as tar:
        names = tar.getnames()

        # Keep the original required-member assertion.
        for expected in expected_entries:
            found = any(name.endswith(expected) for name in names)
            assert found, f"Expected file {expected} not found in tarball {tar_path}."

        # Every member must be rooted directly under new_docs, not under an
        # arbitrary prefix that merely ends with the expected path.
        for member in tar.getmembers():
            assert member.name == "new_docs" or member.name.startswith("new_docs/"), \
                f"Archive member {member.name!r} is not rooted under new_docs."

        # Required entries must be unique regular files whose bytes are copies
        # of the corresponding processed files.
        members = tar.getmembers()
        for expected, source_path in expected_entries.items():
            matches = [member for member in members if member.name == expected]
            assert len(matches) == 1, f"Expected exactly one archive member named {expected}, found {len(matches)}."
            member = matches[0]
            assert member.isfile(), f"Archive member {expected} is not a regular file."
            archived = tar.extractfile(member)
            assert archived is not None, f"Could not read archive member {expected}."
            with open(source_path, "rb") as source:
                assert archived.read() == source.read(), f"Archive member {expected} does not match {source_path}."

def test_migration_log():
    log_path = "/home/user/migration.log"
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "authentication.txt",
        "introduction.txt",
        "routing_setup.txt"
    ]

    assert lines == expected_lines, f"Log file contents incorrect. Expected {expected_lines}, got {lines}."

def test_ignored_file_not_processed():
    # Ensure that ignore_me.txt.gz was not processed
    # We can check if any file contains its text
    for root, dirs, files in os.walk("/home/user/new_docs"):
        for file in files:
            with open(os.path.join(root, file), "r") as f:
                content = f.read()
                assert "Ignore this file" not in content, f"Ignored file content found in {file}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
