#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile

import pytest

SOURCE = '/home/user/generate_manifest.c'
MANIFEST = '/home/user/manifest.txt'
TARGET = '/app/data'
EXPECTED_PATHS = {
    'file1.txt',
    'dirA/file2.txt',
    'dirB/file3.txt',
}


def md5_file(path):
    digest = hashlib.md5()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(65536), b''):
            digest.update(chunk)
    return digest.hexdigest()


def parse_manifest(path):
    entries = []
    with open(path, 'r', encoding='utf-8') as stream:
        for line_number, line in enumerate(stream, 1):
            parts = line.rstrip('\n').split()
            assert len(parts) == 3, (
                f'Malformed manifest line {line_number}: expected exactly three fields'
            )
            checksum, size_text, relative_path = parts
            assert re.fullmatch(r'[0-9a-fA-F]{32}', checksum), (
                f'Invalid MD5 on line {line_number}'
            )
            assert re.fullmatch(r'[0-9]+', size_text), (
                f'Invalid file size on line {line_number}'
            )
            assert not os.path.isabs(relative_path), (
                f'Path on line {line_number} is not relative: {relative_path}'
            )
            normalized = os.path.normpath(relative_path)
            assert normalized == relative_path and normalized != '..' and not normalized.startswith('../'), (
                f'Unsafe or non-normalized path on line {line_number}: {relative_path}'
            )
            entries.append((checksum.lower(), int(size_text), relative_path))
    return entries


def test_manifest_f1_score():
    assert os.path.isfile(MANIFEST), f'Manifest file {MANIFEST} not found.'

    with open(MANIFEST, 'r', encoding='utf-8') as stream:
        lines = stream.readlines()

    found_paths = set()
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 3:
            path = parts[2].replace('/app/data/', '')
            for expected_path in EXPECTED_PATHS:
                if path.endswith(expected_path):
                    found_paths.add(expected_path)

    true_positives = len(found_paths.intersection(EXPECTED_PATHS))
    false_positives = len(found_paths - EXPECTED_PATHS)
    false_negatives = len(EXPECTED_PATHS - found_paths)
    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * precision * recall / (precision + recall)

    assert f1 >= 0.95, (
        f'F1 score {f1:.2f} is below 0.95. Found: {found_paths}, '
        f'expected: {EXPECTED_PATHS}'
    )


def test_c_source_file_exists():
    assert os.path.isfile(SOURCE), f'C source file {SOURCE} not found.'


def test_required_manifest_contents_are_genuine():
    entries = parse_manifest(MANIFEST)
    assert len(entries) == len(EXPECTED_PATHS), (
        f'Expected exactly {len(EXPECTED_PATHS)} unique files, got {len(entries)} lines'
    )
    assert {entry[2] for entry in entries} == EXPECTED_PATHS

    seen_inodes = set()
    for checksum, size, relative_path in entries:
        actual_path = os.path.join(TARGET, relative_path)
        assert os.path.isfile(actual_path), f'Manifest path is not a regular file: {relative_path}'
        stat_result = os.stat(actual_path)
        inode_key = (stat_result.st_dev, stat_result.st_ino)
        assert inode_key not in seen_inodes, f'Duplicate file in manifest: {relative_path}'
        seen_inodes.add(inode_key)
        assert size == stat_result.st_size, f'Wrong size for {relative_path}'
        assert checksum == md5_file(actual_path), f'Wrong MD5 for {relative_path}'


def test_source_compiles_runs_and_handles_symlink_loops():
    with tempfile.TemporaryDirectory(prefix='manifest-verifier-') as work:
        executable = os.path.join(work, 'generate_manifest')
        compile_result = subprocess.run(
            ['gcc', SOURCE, '-o', executable, '-lcrypto'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, f'Compilation failed:\n{compile_result.stderr}'
        assert os.path.isfile(executable) and os.access(executable, os.X_OK)

        root = os.path.join(work, 'target')
        outside = os.path.join(work, 'symlink-only-directory')
        os.makedirs(os.path.join(root, 'nested', 'deeper'))
        os.makedirs(outside)

        files = {
            'plain.bin': b'\x00dynamic test payload\xff\n',
            'nested/alpha.txt': b'alpha generated at verification time\n',
            'nested/deeper/beta.dat': b'beta' * 137,
            'linked/gamma.txt': b'only reachable by following a directory symlink\n',
        }
        for relative_path, content in files.items():
            if relative_path.startswith('linked/'):
                destination = os.path.join(outside, relative_path.split('/', 1)[1])
            else:
                destination = os.path.join(root, relative_path)
            with open(destination, 'wb') as stream:
                stream.write(content)

        # One directory is reachable only through a symlink. Both that directory
        # and a nested directory link back into already visited directories.
        os.symlink(outside, os.path.join(root, 'linked'))
        os.symlink(os.path.join(root, 'nested'), os.path.join(root, 'nested', 'deeper', 'back'))
        os.symlink(root, os.path.join(outside, 'back_to_root'))

        output = os.path.join(work, 'result.manifest')
        try:
            run_result = subprocess.run(
                [executable, root, output],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail('Program did not terminate within 5 seconds on symlink loops')

        assert run_result.returncode == 0, (
            f'Program exited with {run_result.returncode}:\n{run_result.stderr}'
        )
        assert os.path.isfile(output), 'Program did not create the requested output manifest'

        entries = parse_manifest(output)
        assert len(entries) == len(files), (
            f'Expected {len(files)} unique files, got {len(entries)} manifest lines'
        )
        actual = {}
        for checksum, size, relative_path in entries:
            assert relative_path not in actual, f'Duplicate manifest path: {relative_path}'
            actual[relative_path] = (checksum, size)

        assert set(actual) == set(files), (
            f'Wrong traversed paths. Found {set(actual)}, expected {set(files)}'
        )
        for relative_path, content in files.items():
            expected_hash = hashlib.md5(content).hexdigest()
            assert actual[relative_path] == (expected_hash, len(content)), (
                f'Incorrect checksum or size for {relative_path}'
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
