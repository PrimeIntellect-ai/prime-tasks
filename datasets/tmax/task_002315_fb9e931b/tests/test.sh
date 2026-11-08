#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import pytest

DOCS = '/home/user/docs'
OUTPUTS = ['intro_part1.txt', 'intro_part2.txt', 'intro_part3.txt', 'guide.txt']


def hash_file(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        h.update(f.read())
    return h.hexdigest()


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def test_manifest_accuracy():
    source_path = '/home/user/doc_manager.c'
    config_path = '/home/user/config.ini'
    binary_path = '/home/user/doc_manager'

    assert os.path.isfile(source_path) and not os.path.islink(source_path), 'doc_manager.c must be a regular file'
    assert os.path.isfile(config_path) and not os.path.islink(config_path), 'config.ini must be a regular file'
    assert os.path.getsize(config_path) > 0, 'config.ini must not be empty'
    assert os.path.isfile(binary_path) and not os.path.islink(binary_path), 'doc_manager must be a regular file'
    assert os.access(binary_path, os.X_OK), 'doc_manager must be executable'

    expected_intro = b'A\n' * 1250
    expected_setup = b'B\n' * 400
    expected_usage = b'C\n' * 600

    with open(os.path.join(DOCS, 'introduction.txt'), 'rb') as f:
        assert f.read() == expected_intro, 'introduction.txt was modified'
    with open(os.path.join(DOCS, 'setup.txt'), 'rb') as f:
        assert f.read() == expected_setup, 'setup.txt was modified'
    with open(os.path.join(DOCS, 'usage.txt'), 'rb') as f:
        assert f.read() == expected_usage, 'usage.txt was modified'

    for name in OUTPUTS:
        remove_path(os.path.join(DOCS, name))
    remove_path('/home/user/manifest.json')

    build = subprocess.run(
        ['gcc', source_path, '-o', binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f'doc_manager.c failed to compile: {build.stderr}'
    assert os.path.isfile(binary_path) and not os.path.islink(binary_path), 'Compiled doc_manager is not a regular file'
    assert os.access(binary_path, os.X_OK), 'Compiled doc_manager is not executable'

    run = subprocess.run(
        [binary_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, f'doc_manager failed when executed: {run.stderr}'

    with open(os.path.join(DOCS, 'introduction.txt'), 'rb') as f:
        assert f.read() == expected_intro, 'doc_manager modified introduction.txt'
    with open(os.path.join(DOCS, 'setup.txt'), 'rb') as f:
        assert f.read() == expected_setup, 'doc_manager modified setup.txt'
    with open(os.path.join(DOCS, 'usage.txt'), 'rb') as f:
        assert f.read() == expected_usage, 'doc_manager modified usage.txt'

    manifest_path = '/home/user/manifest.json'
    assert os.path.exists(manifest_path), f'Manifest file missing: {manifest_path}'
    assert os.path.isfile(manifest_path) and not os.path.islink(manifest_path), 'manifest.json must be a regular file'

    try:
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to parse manifest.json: {e}')

    expected_files = {
        'intro_part1.txt': 1000,
        'intro_part2.txt': 1000,
        'intro_part3.txt': 500,
        'guide.txt': 2000,
    }
    expected_contents = {
        'intro_part1.txt': expected_intro[0:1000],
        'intro_part2.txt': expected_intro[1000:2000],
        'intro_part3.txt': expected_intro[2000:2500],
        'guide.txt': expected_setup + expected_usage,
    }

    correct_count = 0
    assert isinstance(manifest, list), 'Manifest JSON should be a list of objects'
    manifest_dict = {item.get('filename'): item.get('hash') for item in manifest if isinstance(item, dict)}

    for fname, size in expected_files.items():
        fpath = os.path.join(DOCS, fname)
        assert os.path.exists(fpath), f'Expected file missing: {fpath}'
        assert os.path.isfile(fpath) and not os.path.islink(fpath), f'{fname} must be a regular file'

        actual_size = os.path.getsize(fpath)
        assert actual_size == size, f'File {fname} has incorrect size: {actual_size} bytes (expected {size} bytes)'

        with open(fpath, 'rb') as f:
            actual_content = f.read()
        assert actual_content == expected_contents[fname], f'File {fname} has incorrect content'

        actual_hash = hash_file(fpath)
        manifest_hash = manifest_dict.get(fname)
        assert manifest_hash == actual_hash, f'Hash mismatch or missing for {fname} in manifest. Expected {actual_hash}, got {manifest_hash}'

        correct_count += 1

    accuracy = correct_count / len(expected_files)
    assert accuracy >= 1.0, f'Accuracy metric failed: {accuracy} < 1.0'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
