#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile

def test_processed_directory_and_files():
    processed_dir = "/home/user/processed"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    expected_files = {
        "intro.md": "# Introduction\nWelcome to NexusOS.\n",
        "setup.md": "# Setup\nRun the installer and reboot.\n",
        "advanced.md": "# Advanced\nConfigure the NexusOS kernel.\n"
    }

    for fname, expected_content in expected_files.items():
        filepath = os.path.join(processed_dir, fname)
        assert os.path.isfile(filepath), f"Processed file {filepath} does not exist."

        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
            assert content == expected_content, f"Content of {filepath} is incorrect. Expected:\n{expected_content}\nGot:\n{content}"

def test_incremental_archive():
    archive_path = "/home/user/incremental_docs.tar.gz"
    assert os.path.isfile(archive_path), f"Incremental archive {archive_path} does not exist."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()

        # Files should be at the root of the archive
        assert "advanced.md" in names, "advanced.md is missing from the incremental archive."
        assert "setup.md" in names, "setup.md is missing from the incremental archive."
        assert "intro.md" not in names, "intro.md should NOT be in the incremental archive (it is unchanged)."

        # Check that there are no extra files or directories
        assert set(names) == {"advanced.md", "setup.md"}, f"Incremental archive contains unexpected files or paths: {names}"

        # Verify content of the archived files
        setup_member = tar.extractfile("setup.md")
        assert setup_member is not None, "Could not extract setup.md from archive."
        setup_content = setup_member.read().decode("utf-8")
        assert setup_content == "# Setup\nRun the installer and reboot.\n", "Archived setup.md has incorrect content."

        advanced_member = tar.extractfile("advanced.md")
        assert advanced_member is not None, "Could not extract advanced.md from archive."
        advanced_content = advanced_member.read().decode("utf-8")
        assert advanced_content == "# Advanced\nConfigure the NexusOS kernel.\n", "Archived advanced.md has incorrect content."

def test_changelog_file():
    changelog_path = "/home/user/changelog.txt"
    assert os.path.isfile(changelog_path), f"Changelog file {changelog_path} does not exist."

    with open(changelog_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["advanced.md", "setup.md"]
    assert lines == expected_lines, f"Changelog content is incorrect or not sorted properly. Expected {expected_lines}, got {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
