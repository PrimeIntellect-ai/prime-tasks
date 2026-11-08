#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile

PROCESSING = '/home/user/processing'
ARCHIVE = '/home/user/sanitized_data.tar.gz'

EXPECTED_DIRS = {
    'source_data',
    'source_data/app1',
    'source_data/app2',
}
EXPECTED_FILES = {
    'source_data/app1/server.log': b'INFO: Starting server\nAPI_KEY=REDACTED\nDEBUG: Connection established\n',
    'source_data/app2/database.log': b'WARN: Retrying connection\nAPI_KEY=REDACTED\nERROR: Timeout\n',
    'source_data/app1/readme.txt': b'This is a documentation file.\nExample key usage:\nAPI_KEY=EXAMPLEKEY123\nDo not redact this file.\n',
}


def normalize_member(name):
    while name.startswith('./'):
        name = name[2:]
    name = name.rstrip('/')
    assert name and not name.startswith('/'), f'Unsafe archive member: {name!r}'
    parts = name.split('/')
    assert all(part not in ('', '.', '..') for part in parts), f'Unsafe archive member: {name!r}'
    return '/'.join(parts)


def snapshot_processing():
    assert os.path.isdir(PROCESSING), f'Missing directory: {PROCESSING}'
    dirs = set()
    files = {}

    def visit(path, rel):
        with os.scandir(path) as entries:
            for entry in entries:
                child_rel = f'{rel}/{entry.name}' if rel else entry.name
                mode = entry.stat(follow_symlinks=False).st_mode
                if stat.S_ISDIR(mode):
                    dirs.add(child_rel)
                    visit(entry.path, child_rel)
                elif stat.S_ISREG(mode):
                    with open(entry.path, 'rb') as f:
                        files[child_rel] = f.read()
                else:
                    raise AssertionError(f'Unexpected non-regular entry in processing: {child_rel}')

    visit(PROCESSING, '')
    return dirs, files


def test_result_log():
    """Test that result.log exists and contains the correct text."""
    result_path = '/home/user/result.log'
    assert os.path.exists(result_path), f'Missing file: {result_path}'
    with open(result_path, 'r') as f:
        content = f.read().strip()
    assert content == 'INTEGRITY_VALID', f"Expected 'INTEGRITY_VALID' in {result_path}, got '{content}'"


def test_processing_tree_is_complete_and_exact():
    dirs, files = snapshot_processing()
    assert dirs == EXPECTED_DIRS, f'Processing directory structure differs: {dirs}'
    assert set(files) == set(EXPECTED_FILES), f'Processing file set differs: {set(files)}'
    for path, expected in EXPECTED_FILES.items():
        assert files[path] == expected, f'Incorrect in-place content for {path}'


def test_sanitized_archive():
    """Test that sanitized_data.tar.gz exists, is valid, and contains correctly sanitized files."""
    archive_path = ARCHIVE
    assert os.path.exists(archive_path), f'Missing file: {archive_path}'
    assert tarfile.is_tarfile(archive_path), f'File is not a valid tar archive: {archive_path}'

    archive_dirs = set()
    archive_files = {}
    seen = set()
    with tarfile.open(archive_path, 'r:gz') as tar:
        for member in tar.getmembers():
            name = normalize_member(member.name)
            assert name not in seen, f'Duplicate archive member: {name}'
            seen.add(name)
            assert name == 'processing' or name.startswith('processing/'), \
                f'Archive member is outside processing/: {name}'
            rel = name[len('processing/'): ] if name.startswith('processing/') else ''

            if member.isdir():
                if rel:
                    archive_dirs.add(rel)
            elif member.isfile():
                assert rel, 'The processing root cannot be a regular file'
                extracted = tar.extractfile(member)
                assert extracted is not None, f'Could not read archive member: {name}'
                archive_files[rel] = extracted.read()
            else:
                raise AssertionError(f'Unexpected archive entry type: {name}')

    assert 'processing' in seen, 'Archive does not contain the processing directory root'
    assert archive_dirs == EXPECTED_DIRS, f'Archived directory structure differs: {archive_dirs}'
    assert set(archive_files) == set(EXPECTED_FILES), \
        f'Archived file set differs: {set(archive_files)}'
    for path, expected in EXPECTED_FILES.items():
        assert archive_files[path] == expected, f'Incorrect archived content for {path}'

    # Retain the original explicit content assertions.
    server_log = archive_files.get('source_data/app1/server.log')
    database_log = archive_files.get('source_data/app2/database.log')
    readme_txt = archive_files.get('source_data/app1/readme.txt')
    assert server_log is not None, 'server.log not found in the sanitized archive.'
    assert database_log is not None, 'database.log not found in the sanitized archive.'
    assert readme_txt is not None, 'readme.txt not found in the sanitized archive.'

    server_content = server_log.decode()
    assert 'API_KEY=A1B2C3D4E5' not in server_content, 'server.log was not sanitized properly.'
    assert 'API_KEY=REDACTED' in server_content, 'server.log lacks REDACTED string.'

    database_content = database_log.decode()
    assert 'API_KEY=9988776655QWERTY' not in database_content, 'database.log was not sanitized properly.'
    assert 'API_KEY=REDACTED' in database_content, 'database.log lacks REDACTED string.'

    readme_content = readme_txt.decode()
    assert 'API_KEY=EXAMPLEKEY123' in readme_content, 'readme.txt was incorrectly modified.'
    assert 'API_KEY=REDACTED' not in readme_content, 'readme.txt should not be sanitized.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
