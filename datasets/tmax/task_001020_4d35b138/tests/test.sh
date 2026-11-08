#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

import pytest

SOURCE = Path('/home/user/project_backup.tar.gz')
EXTRACTED = Path('/home/user/extracted_project')
ARCHIVE = Path('/home/user/clean_project.tar.bz2')
REPORT = Path('/home/user/todo_report.json')
ARCHIVE_SUFFIXES = ('.zip', '.tar.gz')

ORIGINAL_FILES = {
    'app/core.py': b'# FIXME: memory leak\n# TODO: add tests\ndef run(): pass\n',
    'app/plugin_a.py': b'# FIXME: bug 1\n# FIXME: bug 2\ndef a(): pass\n',
    'app/plugin_b.py': b'# TODO: x\n# TODO: y\n# TODO: z\n# FIXME: w\ndef b(): pass\n',
}


def safe_name(name):
    name = name.replace('\\', '/')
    while name.startswith('./'):
        name = name[2:]
    p = PurePosixPath(name)
    assert name not in ('', '.')
    assert not p.is_absolute()
    assert '..' not in p.parts
    return str(p)


def safe_extract_tar(path, destination):
    with tarfile.open(path, 'r:*') as tf:
        for member in tf.getmembers():
            safe_name(member.name)
            assert member.isdir() or member.isfile(), f'Unsupported member in source archive: {member.name}'
        tf.extractall(destination)


def safe_extract_zip(path, destination):
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            safe_name(info.filename.rstrip('/'))
        zf.extractall(destination)


def recursively_unpack_source(destination):
    assert SOURCE.is_file(), f'Source backup is missing: {SOURCE}'
    safe_extract_tar(SOURCE, destination)
    while True:
        nested = []
        for root, _, files in os.walk(destination):
            for filename in files:
                if filename.endswith(ARCHIVE_SUFFIXES):
                    nested.append(Path(root) / filename)
        if not nested:
            break
        for path in sorted(nested):
            if path.name.endswith('.zip'):
                safe_extract_zip(path, path.parent)
            else:
                safe_extract_tar(path, path.parent)
            path.unlink()


def filesystem_manifest(root):
    assert root.is_dir(), f'Directory not found: {root}'
    files = {}
    dirs = set()
    for current, dirnames, filenames in os.walk(root, followlinks=False):
        current_path = Path(current)
        rel_current = current_path.relative_to(root).as_posix()
        if rel_current != '.':
            dirs.add(rel_current)
        for name in list(dirnames):
            path = current_path / name
            assert not path.is_symlink(), f'Symlink directory is not allowed: {path}'
        for name in filenames:
            path = current_path / name
            mode = path.lstat().st_mode
            assert stat.S_ISREG(mode), f'Non-regular file is not allowed: {path}'
            rel = path.relative_to(root).as_posix()
            files[rel] = path.read_bytes()
    return files, dirs


@pytest.fixture(scope='module')
def expected():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        recursively_unpack_source(root)
        source_files, source_dirs = filesystem_manifest(root)
        assert source_files == ORIGINAL_FILES, 'The source backup contents were altered'
        assert source_dirs == {'app', 'app/plugins'}, 'The source backup directory structure was altered'

        cleaned = {
            name: data.replace(b'FIXME:', b'TODO:') if name.endswith('.py') else data
            for name, data in source_files.items()
        }
        report = {}
        for name, data in cleaned.items():
            if name.endswith('.py'):
                report[PurePosixPath(name).name] = data.count(b'TODO:')
        yield cleaned, source_dirs, report


def test_clean_project_archive_exists_and_valid():
    assert ARCHIVE.is_file(), f'Archive not found: {ARCHIVE}'
    assert tarfile.is_tarfile(ARCHIVE), f'Not a valid tar archive: {ARCHIVE}'
    with tarfile.open(ARCHIVE, 'r:bz2') as tar:
        members = tar.getnames()
        assert len(members) > 0, 'The clean project archive is empty'
        for member in members:
            assert not member.endswith('.zip'), f'Nested zip archive found: {member}'
            assert not member.endswith('.tar.gz'), f'Nested tar.gz archive found: {member}'


def test_todo_report_json(expected):
    assert REPORT.is_file(), f'JSON report not found: {REPORT}'
    try:
        report = json.loads(REPORT.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'File {REPORT} is not valid JSON')
    expected_report = {'core.py': 2, 'plugin_a.py': 2, 'plugin_b.py': 4}
    assert report == expected_report, f'JSON report content is incorrect. Expected {expected_report}, got {report}'
    assert report == expected[2], 'JSON report does not match the cleaned source tree'
    assert all(type(value) is int for value in report.values())


def test_extracted_project_matches_cleaned_source(expected):
    expected_files, expected_dirs, _ = expected
    actual_files, actual_dirs = filesystem_manifest(EXTRACTED)
    assert actual_dirs == expected_dirs, f'Extracted directory structure is incorrect: {actual_dirs}'
    assert actual_files == expected_files, 'Extracted project does not exactly match the recursively extracted and cleaned backup'
    for name, content in actual_files.items():
        assert not name.endswith(ARCHIVE_SUFFIXES), f'Nested archive remains: {name}'
        if name.endswith('.py'):
            assert b'FIXME:' not in content, f"'FIXME:' found in {name}"


def archive_manifest():
    files = {}
    dirs = set()
    with tarfile.open(ARCHIVE, 'r:bz2') as tar:
        for member in tar.getmembers():
            name = safe_name(member.name)
            if member.isdir():
                dirs.add(name.rstrip('/'))
            elif member.isfile():
                assert name not in files, f'Duplicate archive member: {name}'
                extracted = tar.extractfile(member)
                assert extracted is not None
                files[name] = extracted.read()
            else:
                pytest.fail(f'Unsupported archive member type: {member.name}')
    return files, dirs


def normalize_archive_manifest(files, dirs):
    expected_roots = ('app',)
    if all(name == 'extracted_project' or name.startswith('extracted_project/') for name in set(files) | dirs):
        files = {name[len('extracted_project/'):]: data for name, data in files.items()}
        dirs = {name[len('extracted_project/'):]
                for name in dirs if name != 'extracted_project'}
    assert all(name == expected_roots[0] or name.startswith(expected_roots[0] + '/') for name in set(files) | dirs), \
        'Archive has an unexpected top-level layout'
    return files, dirs


def test_archive_contents_and_transformations(expected):
    expected_files, expected_dirs, _ = expected
    files, dirs = normalize_archive_manifest(*archive_manifest())
    assert files == expected_files, 'Clean archive files do not exactly match the cleaned extracted project'
    assert dirs == expected_dirs, 'Clean archive directory structure is incorrect'

    py_files_found = []
    for name, content in files.items():
        if name.endswith('.py'):
            file = PurePosixPath(name).name
            py_files_found.append(file)
            text = content.decode()
            assert 'FIXME:' not in text, f"'FIXME:' found in {file}"
            if file == 'core.py':
                assert text.count('TODO:') == 2
            elif file == 'plugin_a.py':
                assert text.count('TODO:') == 2
            elif file == 'plugin_b.py':
                assert text.count('TODO:') == 4
    assert 'core.py' in py_files_found, 'core.py is missing from the archive'
    assert 'plugin_a.py' in py_files_found, 'plugin_a.py is missing from the archive'
    assert 'plugin_b.py' in py_files_found, 'plugin_b.py is missing from the archive'
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
