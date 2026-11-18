#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import signal
import stat
import subprocess
import tempfile
import uuid

import pytest

SOURCE = '/home/user/backup_source'
MANIFEST = '/home/user/backup_manifest.json'
MAGIC = b'BKP\x01'


def make_challenge():
    token = uuid.uuid4().hex
    local_dir = os.path.join(SOURCE, 'verify_' + token)
    external_dir = os.path.join('/tmp', 'backup_verify_' + token)
    os.makedirs(local_dir)
    os.makedirs(external_dir)

    local_valid = os.path.join(local_dir, 'dynamic.bin')
    with open(local_valid, 'wb') as f:
        f.write(MAGIC + os.urandom(41))

    with open(os.path.join(local_dir, 'wrong_magic.bin'), 'wb') as f:
        f.write(b'BKP\x02' + os.urandom(19))
    with open(os.path.join(local_dir, 'too_short.bin'), 'wb') as f:
        f.write(b'BKP')

    linked_file_target = os.path.join('/tmp', 'linked_backup_' + token + '.bin')
    with open(linked_file_target, 'wb') as f:
        f.write(MAGIC + os.urandom(37))
    os.symlink(linked_file_target, os.path.join(local_dir, 'linked_file.bin'))

    external_valid = os.path.join(external_dir, 'through_directory_link.bin')
    with open(external_valid, 'wb') as f:
        f.write(MAGIC + os.urandom(53))
    os.symlink(external_dir, os.path.join(local_dir, 'linked_directory'))

    # Add fresh loops unknown to the submission when it was written.
    os.symlink(SOURCE, os.path.join(local_dir, 'loop_to_root'))
    os.symlink(external_dir, os.path.join(external_dir, 'loop_to_self'))

    return [local_valid, linked_file_target, external_valid]


def discover_expected():
    expected = {}
    visited_dirs = set()

    def visit(path):
        try:
            st = os.stat(path)
        except (OSError, RuntimeError):
            return

        if stat.S_ISDIR(st.st_mode):
            identity = (st.st_dev, st.st_ino)
            if identity in visited_dirs:
                return
            visited_dirs.add(identity)
            try:
                entries = list(os.scandir(path))
            except OSError:
                return
            for entry in entries:
                visit(entry.path)
            return

        if not stat.S_ISREG(st.st_mode):
            return

        resolved = os.path.realpath(path)
        try:
            with open(resolved, 'rb') as f:
                content = f.read()
        except OSError:
            return
        if content[:4] == MAGIC:
            expected[resolved] = hashlib.sha256(content).hexdigest()

    visit(SOURCE)
    return [
        {'path': path, 'checksum': expected[path]}
        for path in sorted(expected)
    ]


CHALLENGE_PATHS = make_challenge()
EXPECTED_FILES = discover_expected()


def ignored_path(path):
    normalized = os.path.abspath(path)
    if normalized.startswith(SOURCE + os.sep):
        return True
    ignored_parts = {'__pycache__', '.cache', '.git', 'go-build', 'pkg', 'node_modules'}
    return any(part in ignored_parts for part in normalized.split(os.sep))


def find_go_artifacts():
    roots = ['/home', '/root', '/tmp', '/workspace', '/app']
    binaries = []
    source_dirs = {}

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if not ignored_path(os.path.join(current, d))]
            if ignored_path(current):
                dirs[:] = []
                continue

            go_files = [
                os.path.join(current, name) for name in files
                if name.endswith('.go') and not name.endswith('_test.go')
            ]
            if go_files:
                source_dirs[current] = sorted(go_files)

            for name in files:
                path = os.path.join(current, name)
                try:
                    mode = os.stat(path, follow_symlinks=False).st_mode
                except OSError:
                    continue
                if stat.S_ISREG(mode) and mode & 0o111:
                    try:
                        probe = subprocess.run(
                            ['go', 'version', '-m', path],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=2,
                        )
                    except (OSError, subprocess.TimeoutExpired):
                        continue
                    if probe.returncode == 0:
                        binaries.append(path)

    binaries.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    sources = sorted(source_dirs.items(), key=lambda item: max(os.path.getmtime(p) for p in item[1]), reverse=True)
    return binaries, sources


def run_with_timeout(command, cwd):
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        process.communicate(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        return False
    return process.returncode == 0


def execute_submission():
    binaries, sources = find_go_artifacts()
    assert binaries or sources, 'No submitted Go source code or compiled Go executable was found.'

    attempts = []
    for binary in binaries:
        attempts.append(([binary], os.path.dirname(binary)))
    for directory, files in sources:
        attempts.append((['go', 'run'] + files, directory))

    for command, cwd in attempts:
        try:
            os.remove(MANIFEST)
        except FileNotFoundError:
            pass
        if not run_with_timeout(command, cwd):
            continue
        if not os.path.isfile(MANIFEST):
            continue
        try:
            with open(MANIFEST, 'r') as f:
                json.load(f)
            return
        except (OSError, json.JSONDecodeError):
            continue

    pytest.fail('No submitted Go program completed safely and generated a valid JSON manifest.')


@pytest.fixture(scope='session', autouse=True)
def run_submitted_go_program():
    execute_submission()


def test_manifest_exists_and_valid_json():
    manifest_path = MANIFEST
    assert os.path.isfile(manifest_path), f'Manifest file {manifest_path} is missing. The Go program must generate this file.'

    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'Manifest file {manifest_path} is not valid JSON.')

    assert 'files' in manifest, "Manifest JSON must contain a 'files' key at the root level."
    assert isinstance(manifest['files'], list), "The 'files' key in the manifest must be a list."


def test_manifest_content_and_checksums():
    manifest_path = MANIFEST
    if not os.path.isfile(manifest_path):
        pytest.skip('Manifest file missing, skipping content test.')

    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.skip('Manifest is not valid JSON, skipping content test.')

    # Preserve the original environment assertions.
    known_valid_paths = [
        '/home/user/backup_source/level1/level2/valid2.bin',
        '/home/user/backup_source/valid1.bin',
    ]
    for path in known_valid_paths:
        assert os.path.isfile(path), f'Expected valid backup file {path} is missing from the system.'
        with open(path, 'rb') as f:
            content = f.read()
        assert content.startswith(MAGIC), f'File {path} does not have the correct magic bytes.'

    for path in CHALLENGE_PATHS:
        assert os.path.isfile(path), f'The dynamically added valid backup file {path} was removed.'

    actual_files = manifest.get('files', [])
    assert len(actual_files) == len(EXPECTED_FILES), (
        f'Expected {len(EXPECTED_FILES)} valid files in the manifest, but found {len(actual_files)}. '
        'Ensure the complete tree, directory symlinks, file symlinks, invalid files, and loops are handled.'
    )

    for i, (expected, actual) in enumerate(zip(EXPECTED_FILES, actual_files)):
        assert isinstance(actual, dict), f'Manifest entry at index {i} must be an object.'
        assert actual.get('path') == expected['path'], (
            f"File path mismatch at index {i}. Expected '{expected['path']}', got '{actual.get('path')}'. "
            'Ensure paths are absolute, resolved, and sorted alphabetically.'
        )
        assert actual.get('checksum') == expected['checksum'], (
            f"Checksum mismatch for {expected['path']}. Expected '{expected['checksum']}', "
            f"got '{actual.get('checksum')}'."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
