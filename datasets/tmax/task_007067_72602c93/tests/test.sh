#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import os
import posixpath
import tarfile
import tempfile

import pytest

INCOMING_PARTS = sorted(glob.glob('/home/user/incoming/update.tar.gz.part*'))
assert INCOMING_PARTS, 'No incoming archive parts found'
SOURCE_ARCHIVE = b''.join(open(path, 'rb').read() for path in INCOMING_PARTS)

EXPECTED_SOURCE = {
    'configs/app1.conf': b'SERVER_PORT=8080\nLOG_LEVEL=WARN\nENABLE_FEATURE_X=true\n',
    'configs/app2.conf': b'SERVER_PORT=9090\nLOG_LEVEL=DEBUG\nENABLE_FEATURE_X=false\n',
}
EXPECTED_UNSAFE = {
    '../setup_configs/malicious/escape.txt',
    '/tmp/setup_configs/malicious/absolute.txt',
}


def normalized_member_name(name):
    while name.startswith('./'):
        name = name[2:]
    return posixpath.normpath(name)


def transformed(data):
    lines = data.decode('utf-8').splitlines()
    lines = ['LOG_LEVEL=TRACE' if line.startswith('LOG_LEVEL=') else line for line in lines]
    lines.append('MANAGED_BY=SECURE_CONF_MANAGER')
    return ('\n'.join(lines) + '\n').encode('utf-8')


EXPECTED_OUTPUT = {name: transformed(data) for name, data in EXPECTED_SOURCE.items()}


def read_source_members():
    files = {}
    names = set()
    with tarfile.open(fileobj=io.BytesIO(SOURCE_ARCHIVE), mode='r:gz') as archive:
        for member in archive.getmembers():
            names.add(member.name)
            if member.isfile():
                stream = archive.extractfile(member)
                assert stream is not None
                files[member.name] = stream.read()
    return names, files


SOURCE_NAMES, SOURCE_FILES = read_source_members()
assert {name: SOURCE_FILES.get(name) for name in EXPECTED_SOURCE} == EXPECTED_SOURCE, 'Incoming configuration contents are not the supplied inputs'
assert EXPECTED_UNSAFE.issubset(SOURCE_NAMES), 'Incoming archive no longer contains the traversal cases the workflow must filter'


def test_merged_archive_exists():
    assert os.path.isfile('/home/user/update.tar.gz'), 'Merged archive /home/user/update.tar.gz is missing'
    with open('/home/user/update.tar.gz', 'rb') as stream:
        assert stream.read() == SOURCE_ARCHIVE, 'Merged archive is not the exact concatenation of the incoming parts'


def test_extracted_configs_exist():
    assert os.path.isfile('/home/user/extracted/configs/app1.conf'), 'app1.conf missing in extracted directory'
    assert os.path.isfile('/home/user/extracted/configs/app2.conf'), 'app2.conf missing in extracted directory'


def test_zip_slip_prevented():
    # Preserve the original traversal assertions.
    assert not os.path.exists('/home/user/extracted/malicious/escape.txt'), 'Malicious escape file was extracted!'
    assert not os.path.exists('/tmp/setup_configs/malicious/absolute.txt'), 'Malicious absolute file was extracted!'
    assert not os.path.exists('/home/user/extracted/../malicious/escape.txt'), 'Malicious escape file was extracted outside target!'

    # This is the actual destination of the archive's ../setup_configs entry.
    assert not os.path.exists('/home/user/setup_configs/malicious/escape.txt'), 'Traversal entry escaped to /home/user/setup_configs!'

    extracted_root = '/home/user/extracted'
    allowed_dirs = {
        os.path.realpath(extracted_root),
        os.path.realpath(os.path.join(extracted_root, 'configs')),
    }
    allowed_files = {
        os.path.realpath(os.path.join(extracted_root, name)) for name in EXPECTED_OUTPUT
    }
    seen_files = set()
    for root, dirs, files in os.walk(extracted_root, followlinks=False):
        assert not os.path.islink(root), f'Symlink directory found in extracted tree: {root}'
        assert os.path.realpath(root) in allowed_dirs, f'Unexpected directory extracted: {root}'
        for directory in dirs:
            path = os.path.join(root, directory)
            assert not os.path.islink(path), f'Symlink directory found in extracted tree: {path}'
        for filename in files:
            path = os.path.join(root, filename)
            assert not os.path.islink(path), f'Symlink file found in extracted tree: {path}'
            assert os.path.isfile(path), f'Extracted entry is not a regular file: {path}'
            real_path = os.path.realpath(path)
            assert real_path in allowed_files, f'Unexpected file extracted: {path}'
            seen_files.add(real_path)
    assert seen_files == allowed_files, 'Extracted tree does not contain exactly the supplied configs'


def test_config_modifications():
    for app in ['app1.conf', 'app2.conf']:
        path = f'/home/user/extracted/configs/{app}'
        with open(path, 'rb') as stream:
            actual = stream.read()
        assert actual == EXPECTED_OUTPUT[f'configs/{app}'], f'{app} was not correctly derived from the supplied configuration'

        # Preserve the original line-level assertions.
        lines = actual.decode('utf-8').splitlines()
        assert len(lines) > 0, f'{app} is empty'
        log_levels = [line for line in lines if line.startswith('LOG_LEVEL=')]
        assert len(log_levels) == 1, f'Expected exactly one LOG_LEVEL in {app}'
        assert log_levels[0] == 'LOG_LEVEL=TRACE', f'LOG_LEVEL not set to TRACE in {app}'
        assert lines[-1] == 'MANAGED_BY=SECURE_CONF_MANAGER', f'Last line of {app} is not MANAGED_BY=SECURE_CONF_MANAGER'


def test_safe_update_archive_exists():
    assert os.path.isfile('/home/user/safe_update.tar.gz'), 'Repackaged archive /home/user/safe_update.tar.gz is missing'


def validate_safe_archive(path):
    assert tarfile.is_tarfile(path), 'Concatenated chunks do not form a valid tar archive'
    regular_files = {}
    with tarfile.open(path, 'r:gz') as archive:
        names = archive.getnames()
        assert any(name.endswith('app1.conf') for name in names), 'app1.conf not found in the repackaged archive'
        assert any(name.endswith('app2.conf') for name in names), 'app2.conf not found in the repackaged archive'

        for member in archive.getmembers():
            original = member.name
            parts = [part for part in original.split('/') if part not in ('', '.')]
            assert not original.startswith('/'), f'Absolute member in safe archive: {original}'
            assert '..' not in parts, f'Traversal member in safe archive: {original}'
            normalized = normalized_member_name(original)
            assert normalized == 'configs' or normalized.startswith('configs/'), f'Non-config member in safe archive: {original}'
            assert not member.issym() and not member.islnk(), f'Link member in safe archive: {original}'
            assert member.isdir() or member.isfile(), f'Unsupported member type in safe archive: {original}'
            if member.isfile():
                assert normalized not in regular_files, f'Duplicate archive member: {normalized}'
                stream = archive.extractfile(member)
                assert stream is not None
                regular_files[normalized] = stream.read()

    assert regular_files == EXPECTED_OUTPUT, 'Safe archive does not contain exactly the transformed supplied configs'


def chunk_suffix(index):
    assert index < 26 * 26, 'Unexpectedly many output chunks'
    return chr(ord('a') + index // 26) + chr(ord('a') + index % 26)


def test_split_chunks_exist_and_valid():
    chunks = sorted(glob.glob('/home/user/outgoing/safe_update.tar.gz.chunk-*'))
    assert len(chunks) > 0, 'No chunks found in /home/user/outgoing/'

    expected_names = [
        f'/home/user/outgoing/safe_update.tar.gz.chunk-{chunk_suffix(i)}'
        for i in range(len(chunks))
    ]
    assert chunks == expected_names, 'Chunk names are stale, missing, or not a contiguous split sequence'

    for chunk in chunks[:-1]:
        assert os.path.getsize(chunk) == 500, f'Chunk {chunk} is not exactly 500 bytes'
    assert 0 < os.path.getsize(chunks[-1]) <= 500, 'Final chunk has an invalid size'

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        for chunk in chunks:
            with open(chunk, 'rb') as stream:
                tmp.write(stream.read())
        tmp_path = tmp.name

    try:
        with open(tmp_path, 'rb') as rebuilt, open('/home/user/safe_update.tar.gz', 'rb') as safe:
            assert rebuilt.read() == safe.read(), 'Output chunks are not the split form of safe_update.tar.gz'
        validate_safe_archive(tmp_path)
    finally:
        os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
