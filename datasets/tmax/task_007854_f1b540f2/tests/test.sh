#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_final_docs_exist_and_content():
    user_guide_path = "/home/user/final_docs/User_Guide.md"
    api_ref_path = "/home/user/final_docs/API_Reference.md"

    assert os.path.isfile(user_guide_path), f"File {user_guide_path} is missing."
    assert os.path.isfile(api_ref_path), f"File {api_ref_path} is missing."

    # Expected content based on joining with a single newline and replacing headers
    expected_user_guide = (
        "# Introduction\nWelcome to the system.\n\n"
        "# Installation\n## Prerequisites\nNeed python.\n\n"
        "# Usage\nRun the script.\n"
    )

    expected_api_ref = (
        "# API Overview\nRESTful API.\n\n"
        "## GET /users\nReturns users.\n"
    )

    with open(user_guide_path, "r") as f:
        user_guide_content = f.read()

    with open(api_ref_path, "r") as f:
        api_ref_content = f.read()

    # We allow some flexibility with trailing whitespace/newlines
    assert user_guide_content.strip() == expected_user_guide.strip(), "User_Guide.md content is incorrect."
    assert api_ref_content.strip() == expected_api_ref.strip(), "API_Reference.md content is incorrect."

def test_publish_directory_and_hard_links():
    publish_dir = "/home/user/publish"
    assert os.path.isdir(publish_dir), f"Directory {publish_dir} is missing."

    user_guide_final = "/home/user/final_docs/User_Guide.md"
    api_ref_final = "/home/user/final_docs/API_Reference.md"

    user_guide_pub = "/home/user/publish/User_Guide.md"
    api_ref_pub = "/home/user/publish/API_Reference.md"

    assert os.path.isfile(user_guide_pub), f"Hard link {user_guide_pub} is missing."
    assert os.path.isfile(api_ref_pub), f"Hard link {api_ref_pub} is missing."

    # Check if they are actually hard links (same inode)
    stat_ug_final = os.stat(user_guide_final)
    stat_ug_pub = os.stat(user_guide_pub)
    assert stat_ug_final.st_ino == stat_ug_pub.st_ino, f"{user_guide_pub} is not a hard link to {user_guide_final}."

    stat_api_final = os.stat(api_ref_final)
    stat_api_pub = os.stat(api_ref_pub)
    assert stat_api_final.st_ino == stat_api_pub.st_ino, f"{api_ref_pub} is not a hard link to {api_ref_final}."

def test_latest_docs_symlink():
    symlink_path = "/home/user/latest_docs"
    assert os.path.islink(symlink_path), f"{symlink_path} is missing or not a symlink."

    target = os.readlink(symlink_path)
    # The target could be absolute or relative, but it must resolve to /home/user/publish
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert resolved_target == "/home/user/publish", f"Symlink {symlink_path} does not point to /home/user/publish/."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
