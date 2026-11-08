#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile


def test_final_archive_exists():
    archive_path = "/home/user/final_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Final archive missing: {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"Final archive is not a valid tar file: {archive_path}"


def test_final_archive_contents():
    archive_path = "/home/user/final_backup.tar.gz"
    if not os.path.isfile(archive_path) or not tarfile.is_tarfile(archive_path):
        return  # Handled by previous test

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()

        # Preserve the original expected-file and symlink assertions.
        basenames = [os.path.basename(m) for m in members if not m.endswith('/')]

        expected_files = {"legacy.txt", "app1.log", "app2.log", "app3.log"}
        for ef in expected_files:
            assert ef in basenames, f"Expected file {ef} missing from the root of the archive."

        assert "current.log" not in basenames, "Symlink current.log should not be included in the archive."


def test_archive_has_only_expected_root_files():
    archive_path = "/home/user/final_backup.tar.gz"
    if not os.path.isfile(archive_path) or not tarfile.is_tarfile(archive_path):
        return  # Handled by test_final_archive_exists

    expected_files = {"legacy.txt", "app1.log", "app2.log", "app3.log"}
    archived_files = []

    with tarfile.open(archive_path, "r:gz") as tar:
        for member in tar.getmembers():
            name = member.name

            # A tar created from staging/. may contain a root directory entry and
            # may prefix root-level files with "./".
            if name in (".", "./"):
                assert member.isdir(), "The archive root entry must be a directory."
                continue

            root_name = name[2:] if name.startswith("./") else name
            assert root_name in expected_files, (
                f"Unexpected or non-root archive member: {name}"
            )
            assert member.isfile(), f"Archive member must be a regular file: {name}"
            archived_files.append(root_name)

    assert len(archived_files) == len(expected_files), (
        "Archive must contain each expected file exactly once and no extra files."
    )
    assert set(archived_files) == expected_files, (
        "Archive must contain exactly the expected files at its root."
    )


def test_sanitized_contents():
    archive_path = "/home/user/final_backup.tar.gz"
    if not os.path.isfile(archive_path) or not tarfile.is_tarfile(archive_path):
        return  # Handled by previous test

    with tarfile.open(archive_path, "r:gz") as tar:
        # Helper to read file from tar
        def read_file(filename):
            for member in tar.getmembers():
                if os.path.basename(member.name) == filename and member.isfile():
                    f = tar.extractfile(member)
                    return f.read().decode('utf-8')
            return None

        app1_content = read_file("app1.log")
        assert app1_content is not None, "app1.log not found in archive."
        assert "REDACTED" in app1_content, "app1.log was not properly sanitized (missing REDACTED)."
        assert "SECRET" not in app1_content, "app1.log was not properly sanitized (still contains SECRET)."
        assert app1_content.strip() == "User admin REDACTED data"

        app2_content = read_file("app2.log")
        assert app2_content is not None, "app2.log not found in archive."
        assert app2_content.strip() == "Nothing here to see"

        app3_content = read_file("app3.log")
        assert app3_content is not None, "app3.log not found in archive."
        assert "REDACTED" in app3_content, "app3.log was not properly sanitized (missing REDACTED)."
        assert "SECRET" not in app3_content, "app3.log was not properly sanitized (still contains SECRET)."
        assert app3_content.strip() == "Another REDACTED line"

        legacy_content = read_file("legacy.txt")
        assert legacy_content is not None, "legacy.txt not found in archive."
        assert legacy_content.strip() == "Old log data"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
