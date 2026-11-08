#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import hashlib
import csv

EXPECTED_FILES = {
    'engineering/backend/api-specs.md': (
        "Title: Backend API\n"
        "Status: Published\n"
        "Company: GlobalTech\n"
        "Description: This is the API specification for GlobalTech systems.\n"
    ),
    'engineering/backend/db-schema.md': (
        "Title: Database Schema\n"
        "Status: Published\n"
        "Property of GlobalTech.\n"
    ),
    'engineering/frontend/ui-components.md': (
        "Title: UI Components\n"
        "Status: Published\n"
        "Company: GlobalTech\n"
        "Contains GlobalTech standard buttons.\n"
    ),
    'engineering/frontend/styling-guide.md': (
        "Title: Styling Guide\n"
        "Status: Published\n"
        "Design system for GlobalTech.\n"
    )
}


def test_processed_directory_and_files():
    processed_dir = '/home/user/docs_processed'
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    expected_files = EXPECTED_FILES

    # Check that nested archives are deleted
    assert not os.path.exists(os.path.join(processed_dir, 'engineering/backend/backend.zip')), "Nested archive backend.zip was not deleted."
    assert not os.path.exists(os.path.join(processed_dir, 'engineering/frontend/frontend.tar.gz')), "Nested archive frontend.tar.gz was not deleted."

    # Reject extra, unmanifested files and symlinks in the processed tree.
    actual_files = set()
    for root, dirs, files in os.walk(processed_dir):
        for dirname in dirs:
            path = os.path.join(root, dirname)
            assert not os.path.islink(path), f"Unexpected symlink in processed directory: {path}"
        for filename in files:
            path = os.path.join(root, filename)
            rel_path = os.path.relpath(path, processed_dir).replace(os.sep, '/')
            assert not os.path.islink(path), f"Unexpected symlink in processed directory: {path}"
            assert os.path.isfile(path), f"Unexpected non-regular entry in processed directory: {path}"
            actual_files.add(rel_path)

    assert actual_files == set(expected_files), \
        f"Processed directory has missing or extra files: {sorted(actual_files)}"

    for rel_path, expected_content in expected_files.items():
        file_path = os.path.join(processed_dir, rel_path)
        assert os.path.isfile(file_path), f"Expected processed file missing: {file_path}"

        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        assert "AcmeCorp" not in content, f"'AcmeCorp' still found in {file_path}"
        assert "Draft: Yes" not in content, f"'Draft: Yes' still found in {file_path}"
        assert content == expected_content, f"Content mismatch in {file_path}"


def test_manifest_generation():
    manifest_path = '/home/user/doc_manifest.csv'
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    processed_dir = '/home/user/docs_processed'
    expected_entries = []

    # Compute expected hashes dynamically
    expected_files = [
        'engineering/backend/api-specs.md',
        'engineering/backend/db-schema.md',
        'engineering/frontend/styling-guide.md',
        'engineering/frontend/ui-components.md'
    ]

    for rel_path in expected_files:
        file_path = os.path.join(processed_dir, rel_path)
        if os.path.isfile(file_path):
            with open(file_path, 'rb') as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()
            expected_entries.append(f"{rel_path},{file_hash}")

    with open(manifest_path, 'r', encoding='utf-8') as f:
        manifest_lines = [line.strip() for line in f if line.strip()]

    assert manifest_lines == expected_entries, "Manifest contents or sorting is incorrect."


def test_rearchiving():
    archive_path = '/home/user/published_docs.tar.gz'
    assert os.path.isfile(archive_path), f"Final archive missing: {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"Final archive is not a valid tar file: {archive_path}"

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()

        # Should contain the top level 'engineering' directory without wrapper
        assert any(name == 'engineering' or name.startswith('engineering/') for name in names), \
            "Archive should contain 'engineering' at the top level, without a wrapper folder."

        expected_files = [
            'engineering/backend/api-specs.md',
            'engineering/backend/db-schema.md',
            'engineering/frontend/styling-guide.md',
            'engineering/frontend/ui-components.md'
        ]

        for expected_file in expected_files:
            assert expected_file in names or f"./{expected_file}" in names, \
                f"Expected file {expected_file} missing from final archive."

        # Normalize the optional './' prefix and verify the archive contains
        # exactly the processed files, as regular files, with identical bytes.
        archived_files = {}
        for member in tar.getmembers():
            normalized = member.name
            while normalized.startswith('./'):
                normalized = normalized[2:]
            normalized = normalized.rstrip('/')

            assert not normalized.startswith('/') and '..' not in normalized.split('/'), \
                f"Unsafe path in final archive: {member.name}"

            if member.isdir() or normalized == '':
                continue

            assert member.isfile(), f"Unexpected non-regular archive member: {member.name}"
            assert normalized not in archived_files, f"Duplicate archive member: {normalized}"
            archived_files[normalized] = member

        assert set(archived_files) == set(expected_files), \
            f"Archive has missing or extra files: {sorted(archived_files)}"

        for rel_path in expected_files:
            extracted = tar.extractfile(archived_files[rel_path])
            assert extracted is not None, f"Could not read archived file: {rel_path}"
            archived_content = extracted.read()
            with open(os.path.join('/home/user/docs_processed', rel_path), 'rb') as f:
                processed_content = f.read()
            assert archived_content == processed_content, \
                f"Archived content does not match docs_processed for {rel_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
