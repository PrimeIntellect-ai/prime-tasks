#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import stat
import tarfile
import zipfile
import pytest

RESEARCH_DIR = '/home/user/research_data'
EXTRACTED_DIR = '/home/user/extracted_code'
LOC_PATH = '/home/user/loc_summary.txt'
CLEAN_TAR = '/home/user/clean_dataset.tar'


def canonical_path(name):
    name = name.replace('\\', '/')
    while name.startswith('./'):
        name = name[2:]
    if name.startswith('/'):
        raise AssertionError(f'Absolute archive path is not allowed: {name!r}')
    parts = [p for p in name.split('/') if p not in ('', '.')]
    if any(p == '..' for p in parts):
        raise AssertionError(f'Unsafe archive path: {name!r}')
    return '/'.join(parts)


def derive_expected():
    sources = {}
    manifests = []
    valid_archives = []

    for root, _, files in os.walk(RESEARCH_DIR):
        for filename in files:
            path = os.path.join(root, filename)
            if not filename.endswith(('.tar.gz', '.zip', '.tar')):
                continue
            if os.path.getsize(path) <= 10240:
                continue
            valid_archives.append(path)

            if filename.endswith('.zip'):
                with zipfile.ZipFile(path) as archive:
                    for info in archive.infolist():
                        if info.is_dir():
                            continue
                        member = canonical_path(info.filename)
                        data = archive.read(info)
                        if member.endswith(('.py', '.js')):
                            assert member not in sources, f'Duplicate source path in inputs: {member}'
                            sources[member] = data
                        if os.path.basename(member) == 'index.csv':
                            manifests.append((member, data))
            else:
                with tarfile.open(path, 'r:*') as archive:
                    for info in archive.getmembers():
                        if not info.isfile():
                            continue
                        member = canonical_path(info.name)
                        extracted = archive.extractfile(info)
                        assert extracted is not None
                        data = extracted.read()
                        if member.endswith(('.py', '.js')):
                            assert member not in sources, f'Duplicate source path in inputs: {member}'
                            sources[member] = data
                        if os.path.basename(member) == 'index.csv':
                            manifests.append((member, data))

    assert valid_archives, 'No qualifying archives were found.'
    assert len(manifests) == 1, f'Expected exactly one index.csv in qualifying archives, found {len(manifests)}.'

    manifest_path, manifest_bytes = manifests[0]
    text = manifest_bytes.decode('utf-8-sig')
    rows = list(csv.DictReader(io.StringIO(text, newline='')))
    return sources, manifest_path, manifest_bytes, rows


EXPECTED_SOURCES, MANIFEST_PATH, MANIFEST_BYTES, EXPECTED_ROWS = derive_expected()
EXPECTED_FILES = dict(EXPECTED_SOURCES)
EXPECTED_FILES[MANIFEST_PATH] = MANIFEST_BYTES


def actual_regular_files(base):
    result = {}
    for root, dirs, files in os.walk(base, followlinks=False):
        for dirname in dirs:
            path = os.path.join(root, dirname)
            assert not os.path.islink(path), f'Symlink directory is not allowed: {path}'
        for filename in files:
            path = os.path.join(root, filename)
            mode = os.lstat(path).st_mode
            assert stat.S_ISREG(mode), f'Expected a regular file, got another file type: {path}'
            rel = os.path.relpath(path, base).replace(os.sep, '/')
            with open(path, 'rb') as handle:
                result[rel] = handle.read()
    return result


def test_extracted_files_exist_and_match_archives():
    expected_files = [
        'python_scripts/main.py',
        'python_scripts/utils.py',
        'js_scripts/app.js',
    ]
    for rel in expected_files:
        full_path = os.path.join(EXTRACTED_DIR, rel)
        assert os.path.isfile(full_path), f'Expected extracted file {full_path} is missing.'

    actual = actual_regular_files(EXTRACTED_DIR)
    expected_names = set(EXPECTED_FILES) | {'index.json'}
    assert set(actual) == expected_names, (
        f'Extracted directory has the wrong files. Expected {sorted(expected_names)}, '
        f'got {sorted(actual)}.'
    )
    for rel, expected_data in EXPECTED_FILES.items():
        assert actual[rel] == expected_data, f'Extracted file content does not match its archive member: {rel}'


def test_ignored_files_do_not_exist():
    junk_path = '/home/user/extracted_code/ignored.py'
    assert not os.path.exists(junk_path), f'File {junk_path} from junk archive should not have been extracted.'


def test_index_json_conversion():
    json_path = '/home/user/extracted_code/index.json'
    assert os.path.isfile(json_path), f'{json_path} is missing.'
    assert not os.path.islink(json_path), f'{json_path} must be a regular file, not a symlink.'

    with open(json_path, 'r', encoding='utf-8') as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f'{json_path} is not valid JSON.')

    assert isinstance(data, list), f'{json_path} should contain a JSON array.'
    assert len(data) == 3, f'{json_path} should have exactly 3 entries.'
    expected_entry = {'id': '1', 'filename': 'main.py', 'language': 'python'}
    assert expected_entry in data, f'Expected entry {expected_entry} not found in {json_path}.'
    assert data == EXPECTED_ROWS, f'{json_path} does not exactly represent index.csv.'


def test_loc_summary():
    assert os.path.isfile(LOC_PATH), f'{LOC_PATH} is missing.'
    assert not os.path.islink(LOC_PATH), f'{LOC_PATH} must be a regular file, not a symlink.'
    with open(LOC_PATH, 'r', encoding='utf-8') as handle:
        content = handle.read().strip()

    expected_count = sum(len(data.splitlines()) for data in EXPECTED_SOURCES.values())
    assert content == '18', f"Expected LOC summary to be '18', got '{content}'."
    assert content == str(expected_count), f'LOC summary should be {expected_count}, got {content!r}.'


def normalize_tar_member(name):
    normalized = canonical_path(name)
    if normalized == 'extracted_code':
        return ''
    if normalized.startswith('extracted_code/'):
        return normalized[len('extracted_code/'):]
    return normalized


def test_rearchived_dataset():
    assert os.path.isfile(CLEAN_TAR), f'{CLEAN_TAR} is missing.'
    assert not os.path.islink(CLEAN_TAR), f'{CLEAN_TAR} must be a regular file, not a symlink.'
    assert tarfile.is_tarfile(CLEAN_TAR), f'{CLEAN_TAR} is not a valid tar file.'

    archived_files = {}
    with tarfile.open(CLEAN_TAR, 'r:') as archive:
        names = archive.getnames()
        has_index = any(name.endswith('index.json') for name in names)
        has_main = any(name.endswith('main.py') for name in names)
        assert has_index, f'index.json is missing from {CLEAN_TAR}.'
        assert has_main, f'main.py is missing from {CLEAN_TAR}.'

        for member in archive.getmembers():
            rel = normalize_tar_member(member.name)
            if member.isdir():
                continue
            assert member.isfile(), f'Tar contains a non-regular member: {member.name}'
            assert rel, f'Tar contains an invalid file path: {member.name}'
            assert rel not in archived_files, f'Tar contains duplicate path: {rel}'
            handle = archive.extractfile(member)
            assert handle is not None
            archived_files[rel] = handle.read()

    disk_files = actual_regular_files(EXTRACTED_DIR)
    assert set(archived_files) == set(disk_files), (
        f'Tar does not contain exactly the extracted_code files. '
        f'Expected {sorted(disk_files)}, got {sorted(archived_files)}.'
    )
    for rel, data in disk_files.items():
        assert archived_files[rel] == data, f'Tar content differs from extracted_code for {rel}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
