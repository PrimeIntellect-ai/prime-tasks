#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import struct
import subprocess
import tempfile
import uuid
import zipfile

SCRIPT_PATH = '/home/user/curate.sh'
ZIP_PATH = '/home/user/curated_artifacts.zip'
ARTIFACTS_PATH = '/home/user/artifacts'
CURATED_PATH = '/home/user/curated'

ARM_BYTES = bytes.fromhex(
    '7f454c460101010000000000000000000200280001000000'
)
GCODE_BYTES = b'G21\nG90\nG28 X Y\nG1 X10\n'
WAL1_BYTES = bytes.fromhex('377f068200000000')
WAL2_BYTES = bytes.fromhex('377f068300000000')

EXPECTED_ARCHIVE = {
    'elf/arm_app1': ARM_BYTES,
    'gcode/print1.gcode': GCODE_BYTES,
    'wal/db1.wal': WAL1_BYTES,
    'wal/db2.wal': WAL2_BYTES,
}


def normalized_zip_entries(z):
    entries = []
    for info in z.infolist():
        if info.is_dir():
            continue
        name = info.filename
        while name.startswith('./'):
            name = name[2:]
        assert name and not name.startswith('/'), f'Unsafe absolute ZIP path: {info.filename}'
        assert '..' not in name.split('/'), f'Unsafe parent traversal in ZIP path: {info.filename}'
        entries.append((name, info))
    names = [name for name, _ in entries]
    assert len(names) == len(set(names)), f'Duplicate file entries in ZIP: {names}'
    return entries


def is_arm_elf(data):
    if len(data) < 20 or data[:4] != b'\x7fELF':
        return False
    if data[5] == 1:
        endian = '<'
    elif data[5] == 2:
        endian = '>'
    else:
        return False
    return struct.unpack(endian + 'H', data[18:20])[0] == 40


def classify_tree(root):
    expected = {'elf': {}, 'gcode': {}, 'wal': {}}
    g28 = re.compile(rb'(?<![A-Za-z0-9_])G28(?![A-Za-z0-9_])')
    for base, _, files in os.walk(root):
        for filename in files:
            path = os.path.join(base, filename)
            with open(path, 'rb') as f:
                data = f.read()
            if is_arm_elf(data):
                expected['elf'][filename] = data
            if filename.endswith('.gcode') and g28.search(data):
                expected['gcode'][filename] = data
            if data[:4] in (b'\x37\x7f\x06\x82', b'\x37\x7f\x06\x83'):
                expected['wal'][filename] = data
    return expected


def assert_curated_matches(expected):
    assert os.path.isdir(CURATED_PATH), f'{CURATED_PATH} was not created'
    assert not os.path.islink(CURATED_PATH), f'{CURATED_PATH} must be a directory, not a symlink'
    assert set(os.listdir(CURATED_PATH)) == {'elf', 'gcode', 'wal'}, (
        f'Curated root must contain exactly elf, gcode, and wal; found {os.listdir(CURATED_PATH)}'
    )
    for category in ('elf', 'gcode', 'wal'):
        category_path = os.path.join(CURATED_PATH, category)
        assert os.path.isdir(category_path), f'Missing curated directory: {category_path}'
        actual_names = set(os.listdir(category_path))
        expected_names = set(expected[category])
        assert actual_names == expected_names, (
            f'Wrong files in {category_path}: expected {expected_names}, found {actual_names}'
        )
        for name, wanted in expected[category].items():
            path = os.path.join(category_path, name)
            assert os.path.isfile(path), f'Expected a regular file at {path}'
            with open(path, 'rb') as f:
                actual = f.read()
            assert actual == wanted, f'Copied bytes differ from the source for {path}'


def test_01_curate_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f'The script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} is not a file.'
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f'The script {SCRIPT_PATH} is not executable.'


def test_02_source_archive_was_extracted():
    required = {
        'dir1/arm_app1': ARM_BYTES,
        'dir1/dir2/print1.gcode': GCODE_BYTES,
        'dir3/print2.gcode': b'G21\nG90\nG1 X10\n',
        'dir3/db1.wal': WAL1_BYTES,
        'dir1/db2.wal': WAL2_BYTES,
        'dir1/dir2/db3.wal': bytes.fromhex('377f068400000000'),
        'readme.txt': b'Just some text\n',
    }
    assert os.path.isdir(ARTIFACTS_PATH), f'{ARTIFACTS_PATH} does not exist'
    for relative, wanted in required.items():
        path = os.path.join(ARTIFACTS_PATH, relative)
        assert os.path.isfile(path), f'Extracted source file is missing: {path}'
        with open(path, 'rb') as f:
            assert f.read() == wanted, f'Extracted source file has wrong bytes: {path}'
    x86_path = os.path.join(ARTIFACTS_PATH, 'dir3/x86_app')
    assert os.path.isfile(x86_path), f'Extracted source file is missing: {x86_path}'
    with open(x86_path, 'rb') as f:
        x86_data = f.read(20)
    assert x86_data[:4] == b'\x7fELF' and not is_arm_elf(x86_data), 'x86_app is not the expected non-ARM ELF'


def test_03_zip_archive_exists_valid_and_has_correct_bytes():
    assert os.path.exists(ZIP_PATH), f'The archive {ZIP_PATH} does not exist.'
    assert os.path.isfile(ZIP_PATH), f'The path {ZIP_PATH} is not a file.'
    assert zipfile.is_zipfile(ZIP_PATH), f'The file {ZIP_PATH} is not a valid zip archive.'
    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        entries = normalized_zip_entries(z)
        names = {name for name, _ in entries}
        for expected_name in EXPECTED_ARCHIVE:
            assert expected_name in names, (
                f"Expected file '{expected_name}' not found in the root of the zip archive. "
                f'Found files: {names}'
            )
        excluded_names = ['x86_app', 'print2.gcode', 'db3.wal', 'readme.txt']
        for name in names:
            for excluded in excluded_names:
                assert excluded not in name, f"File '{excluded}' should not be in the archive, but found '{name}'."
        assert names == set(EXPECTED_ARCHIVE), f'Unexpected files in archive: {names - set(EXPECTED_ARCHIVE)}'
        for name, info in entries:
            assert z.read(info) == EXPECTED_ARCHIVE[name], f'Archived bytes are wrong for {name}'


def test_04_script_really_classifies_recursively_and_copies_bytes():
    token = uuid.uuid4().hex
    probe_files = {
        f'nested/{token}/arm_{token}': ARM_BYTES + token.encode(),
        f'nested/{token}/x86_{token}': ARM_BYTES[:18] + b'\x03\x00' + ARM_BYTES[20:] + b'x86',
        f'deep/more/home_{token}.gcode': b'G21\nG28 X Y\nG1 X5\n',
        f'deep/more/not_home_{token}.gcode': b'G21\nG280 X Y\n',
        f'deep/wal_a_{token}.bin': WAL1_BYTES + token.encode(),
        f'wal_b_{token}': WAL2_BYTES + token.encode(),
        f'bad_wal_{token}.wal': bytes.fromhex('377f0684') + b'bad',
        f'noise_{token}.txt': b'ordinary noise\n',
    }

    backup_root = tempfile.mkdtemp(prefix='curate-verifier-')
    artifacts_backup = os.path.join(backup_root, 'artifacts')
    curated_backup = os.path.join(backup_root, 'curated')
    zip_backup = os.path.join(backup_root, 'curated_artifacts.zip')
    shutil.copytree(ARTIFACTS_PATH, artifacts_backup)
    if os.path.exists(CURATED_PATH):
        shutil.copytree(CURATED_PATH, curated_backup)
    shutil.copy2(ZIP_PATH, zip_backup)

    try:
        shutil.rmtree(ARTIFACTS_PATH)
        if os.path.lexists(CURATED_PATH):
            if os.path.isdir(CURATED_PATH) and not os.path.islink(CURATED_PATH):
                shutil.rmtree(CURATED_PATH)
            else:
                os.unlink(CURATED_PATH)
        os.makedirs(ARTIFACTS_PATH)
        for relative, data in probe_files.items():
            path = os.path.join(ARTIFACTS_PATH, relative)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'wb') as f:
                f.write(data)

        expected = classify_tree(ARTIFACTS_PATH)
        result = subprocess.run(
            [SCRIPT_PATH], cwd='/home/user', stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=30
        )
        assert result.returncode == 0, f'curate.sh failed with exit {result.returncode}:\n{result.stdout}'
        assert_curated_matches(expected)
    finally:
        if os.path.lexists(ARTIFACTS_PATH):
            shutil.rmtree(ARTIFACTS_PATH, ignore_errors=True)
        shutil.copytree(artifacts_backup, ARTIFACTS_PATH)
        if os.path.lexists(CURATED_PATH):
            if os.path.isdir(CURATED_PATH) and not os.path.islink(CURATED_PATH):
                shutil.rmtree(CURATED_PATH, ignore_errors=True)
            else:
                os.unlink(CURATED_PATH)
        if os.path.isdir(curated_backup):
            shutil.copytree(curated_backup, CURATED_PATH)
        shutil.copy2(zip_backup, ZIP_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
