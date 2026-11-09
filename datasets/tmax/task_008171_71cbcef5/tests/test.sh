#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid

STAGING_DIR = '/home/user/docs_staging'
MANIFEST_PATH = '/home/user/manifest.txt'
SCRIPT_PATH = '/home/user/build_manifest.py'
ARCHIVE_PATH = '/home/user/docs_archive.tar.gz'
OLD = b'ProductX-v1.0-alpha'
NEW = b'ProductX-v1.0-stable'


def archive_contents():
    files = {}
    directories = set()
    with tarfile.open(ARCHIVE_PATH, 'r:gz') as archive:
        for member in archive.getmembers():
            name = member.name.rstrip('/')
            assert name and not os.path.isabs(name), f'Unsafe archive path: {member.name}'
            normalized = os.path.normpath(name)
            assert normalized == name and normalized != '..' and not normalized.startswith('../'), \
                f'Unsafe archive path: {member.name}'
            if member.isdir():
                directories.add(normalized)
            elif member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None
                files[normalized] = extracted.read()
                parent = os.path.dirname(normalized)
                while parent:
                    directories.add(parent)
                    parent = os.path.dirname(parent)
            else:
                raise AssertionError(f'Unsupported archive entry type: {member.name}')
    return files, directories


def staged_entries():
    files = set()
    directories = set()
    for root, dirnames, filenames in os.walk(STAGING_DIR, followlinks=False):
        for dirname in dirnames:
            path = os.path.join(root, dirname)
            assert not os.path.islink(path), f'Staged directory must not be a symlink: {path}'
            directories.add(os.path.relpath(path, STAGING_DIR).replace(os.sep, '/'))
        for filename in filenames:
            path = os.path.join(root, filename)
            assert os.path.isfile(path) and not os.path.islink(path), \
                f'Staged entry must be a regular file: {path}'
            files.add(os.path.relpath(path, STAGING_DIR).replace(os.sep, '/'))
    return files, directories


def expected_manifest_for(directory):
    entries = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if filename.endswith('.md'):
                full_path = os.path.join(root, filename)
                rel_path = os.path.relpath(full_path, directory).replace(os.sep, '/')
                with open(full_path, 'rb') as handle:
                    digest = hashlib.sha256(handle.read()).hexdigest()
                entries.append((rel_path, f'{digest}  {rel_path}'))
    return [entry for _, entry in sorted(entries)]


def assert_manifest_exact(path, expected):
    assert os.path.isfile(path), f'Manifest file {path} does not exist.'
    with open(path, 'r', encoding='utf-8') as handle:
        text = handle.read()
    lines = text.splitlines()
    assert lines == expected, f'Manifest contents are incorrect.\nExpected: {expected!r}\nFound: {lines!r}'
    for line in lines:
        assert re.fullmatch(r'[0-9a-f]{64}  [^\r\n]+', line), \
            f'Manifest line has invalid format: {line!r}'


def test_files_extracted():
    """Verify that the archive was extracted to the correct location."""
    assert os.path.exists(STAGING_DIR), f"Directory {STAGING_DIR} does not exist."
    assert os.path.isdir(STAGING_DIR), f"{STAGING_DIR} is not a directory."

    expected_files = [
        'intro.md',
        'api/auth.md',
        'setup/install.md',
        'setup/notes.txt'
    ]
    for f in expected_files:
        full_path = os.path.join(STAGING_DIR, f)
        assert os.path.exists(full_path), f"Expected file {full_path} is missing."


def test_staging_matches_complete_archive_with_only_required_replacements():
    """Compare every staged entry and its contents with the actual archive."""
    archived_files, archived_dirs = archive_contents()
    actual_files, actual_dirs = staged_entries()
    assert actual_files == set(archived_files), \
        f'Staged files differ from archive files: expected {sorted(archived_files)}, found {sorted(actual_files)}'
    assert actual_dirs == archived_dirs, \
        f'Staged directories differ from archive directories: expected {sorted(archived_dirs)}, found {sorted(actual_dirs)}'

    for rel_path, original in archived_files.items():
        expected = original.replace(OLD, NEW) if rel_path.endswith('.md') else original
        with open(os.path.join(STAGING_DIR, *rel_path.split('/')), 'rb') as handle:
            actual = handle.read()
        assert actual == expected, f'Staged file {rel_path} does not match the required archive transformation.'


def test_markdown_files_updated():
    """Verify that all markdown files have 'alpha' replaced with 'stable'."""
    md_files = [
        'intro.md',
        'api/auth.md',
        'setup/install.md'
    ]
    for f in md_files:
        full_path = os.path.join(STAGING_DIR, f)
        with open(full_path, 'r', encoding='utf-8') as file:
            content = file.read()
            assert 'ProductX-v1.0-alpha' not in content, f"File {f} still contains 'ProductX-v1.0-alpha'."
            assert 'ProductX-v1.0-stable' in content, f"File {f} does not contain 'ProductX-v1.0-stable'."


def test_txt_files_unchanged():
    """Verify that non-markdown files were not modified."""
    txt_path = os.path.join(STAGING_DIR, 'setup/notes.txt')
    with open(txt_path, 'r', encoding='utf-8') as file:
        content = file.read()
        assert 'ProductX-v1.0-alpha' in content, "The file setup/notes.txt should not have been modified, but 'ProductX-v1.0-alpha' is missing."
        assert 'ProductX-v1.0-stable' not in content, "The file setup/notes.txt should not contain 'ProductX-v1.0-stable'."


def test_manifest_generated_correctly():
    """Verify the manifest.txt format and contents."""
    assert os.path.exists(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    expected_md_files = [
        'api/auth.md',
        'intro.md',
        'setup/install.md'
    ]

    expected_entries = []
    for rel_path in expected_md_files:
        full_path = os.path.join(STAGING_DIR, rel_path)
        with open(full_path, 'rb') as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected_entries.append(f"{file_hash}  {rel_path}")

    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_entries), f"Manifest should have exactly {len(expected_entries)} entries, found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_entries)):
        assert actual == expected, f"Manifest line {i+1} is incorrect.\nExpected: '{expected}'\nFound:    '{actual}'"

    assert_manifest_exact(MANIFEST_PATH, expected_manifest_for(STAGING_DIR))


def test_script_exists():
    """Verify that the build_manifest.py script was created."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must not be a symbolic link."


def test_script_executes_and_handles_recursive_unseen_inputs():
    """Run the submitted script on both the real staging tree and randomized test data."""
    result = subprocess.run(
        ['python3', SCRIPT_PATH], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f'Script failed on staged documentation:\n{result.stderr}'
    assert_manifest_exact(MANIFEST_PATH, expected_manifest_for(STAGING_DIR))

    token = uuid.uuid4().hex
    backup_dir = tempfile.mkdtemp(prefix='.manifest_verifier_', dir='/home/user')
    staging_backup = os.path.join(backup_dir, 'docs_staging')
    manifest_backup = os.path.join(backup_dir, 'manifest.txt')
    os.rename(STAGING_DIR, staging_backup)
    if os.path.exists(MANIFEST_PATH):
        os.rename(MANIFEST_PATH, manifest_backup)

    try:
        os.makedirs(os.path.join(STAGING_DIR, 'zeta', 'deep'))
        os.makedirs(os.path.join(STAGING_DIR, 'alpha'))
        samples = {
            f'root_{token}.md': f'root contents {token}\n'.encode(),
            f'alpha/first_{token}.md': b'first\x00markdown\n',
            f'zeta/deep/last_{token}.md': (token * 3).encode(),
            f'zeta/ignored_{token}.txt': b'not part of manifest',
        }
        for rel_path, data in samples.items():
            full_path = os.path.join(STAGING_DIR, *rel_path.split('/'))
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, 'wb') as handle:
                handle.write(data)

        result = subprocess.run(
            ['python3', SCRIPT_PATH], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, f'Script failed on randomized recursive inputs:\n{result.stderr}'
        assert_manifest_exact(MANIFEST_PATH, expected_manifest_for(STAGING_DIR))
    finally:
        if os.path.lexists(STAGING_DIR):
            if os.path.isdir(STAGING_DIR) and not os.path.islink(STAGING_DIR):
                shutil.rmtree(STAGING_DIR)
            else:
                os.unlink(STAGING_DIR)
        if os.path.lexists(MANIFEST_PATH):
            os.unlink(MANIFEST_PATH)
        os.rename(staging_backup, STAGING_DIR)
        if os.path.exists(manifest_backup):
            os.rename(manifest_backup, MANIFEST_PATH)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
