#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import io
import json
import os
import secrets
import stat
import subprocess
import tarfile
import uuid
import zipfile

import pytest

ANALYZER = '/home/user/analyzer.py'
RUNNER = '/home/user/run_parallel.sh'
BACKUPS = '/home/user/old_backups'
MANIFEST = '/home/user/dedup_manifest.json'
LOCKFILE = '/home/user/dedup_manifest.json.lock'
STATE = '/tmp/analyzer_wrapper_state.json'


def make_zip(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as zf:
        for name, content in entries:
            zf.writestr(name, content)
        zf.writestr('ignored.txt', b'not a log')
    return buffer.getvalue()


def add_random_archives(count=24):
    token = uuid.uuid4().hex
    shared = secrets.token_bytes(37)
    created = []
    for i in range(count):
        tar_path = os.path.join(BACKUPS, f'audit_{token}_{i}.tar')
        with tarfile.open(tar_path, 'w') as tf:
            for j in range(2):
                zip_name = f'nested_{token}_{i}_{j}.zip'
                entries = [
                    (f'shared_{i}_{j}.log', shared),
                    (f'unique_{i}_{j}_a.log', secrets.token_bytes(20 + i + j)),
                    (f'unique_{i}_{j}_b.log', secrets.token_bytes(50 + j)),
                    (f'empty_{i}_{j}.log', b''),
                ]
                data = make_zip(entries)
                info = tarfile.TarInfo(zip_name)
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
            ignored = b'not a zip'
            info = tarfile.TarInfo(f'ignored_{i}.bin')
            info.size = len(ignored)
            tf.addfile(info, io.BytesIO(ignored))
        created.append(tar_path)
    return created


def expected_from_tars(paths):
    expected = collections.defaultdict(list)
    for tar_path in paths:
        with tarfile.open(tar_path, 'r') as tf:
            for member in tf.getmembers():
                if not member.isfile() or not member.name.endswith('.zip'):
                    continue
                extracted = tf.extractfile(member)
                assert extracted is not None
                with zipfile.ZipFile(io.BytesIO(extracted.read())) as zf:
                    for name in zf.namelist():
                        if name.endswith('.log') and not name.endswith('/'):
                            content = zf.read(name)
                            digest = hashlib.sha256(content).hexdigest()
                            expected[digest].append(
                                f'{os.path.basename(tar_path)}/{member.name}/{name}'
                            )
    return dict(expected)


def assert_exact_manifest(manifest, expected):
    assert isinstance(manifest, dict), 'Manifest root must be a JSON object.'
    assert set(manifest) == set(expected), (
        f'Manifest hash keys differ. Missing: {set(expected) - set(manifest)}; '
        f'Extra: {set(manifest) - set(expected)}'
    )
    for digest, suffixes in expected.items():
        actual = manifest[digest]
        assert isinstance(actual, list), f'Manifest value for {digest} is not a list.'
        assert all(isinstance(path, str) for path in actual)
        assert len(actual) == len(suffixes), (
            f'Wrong number of paths for {digest}: expected {suffixes}, got {actual}'
        )
        unmatched = list(actual)
        for suffix in suffixes:
            matches = [path for path in unmatched if path.endswith(suffix)]
            assert len(matches) == 1, f'Expected exactly one path ending in {suffix}; got {actual}'
            unmatched.remove(matches[0])
        assert not unmatched


def install_instrumented_wrapper():
    submission = ANALYZER + '.submission'
    os.replace(ANALYZER, submission)
    wrapper = r'''#!/usr/bin/env python3
import fcntl
import json
import os
import subprocess
import sys
import time

STATE = '/tmp/analyzer_wrapper_state.json'
REAL = '/home/user/analyzer.py.submission'

def update(start, parent=None, argument=None):
    with open(STATE, 'a+') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        f.seek(0)
        try:
            state = json.load(f)
        except Exception:
            state = {'active': 0, 'maximum': 0, 'calls': [], 'orphaned': 0}
        if start:
            state['active'] += 1
            state['maximum'] = max(state['maximum'], state['active'])
            state['calls'].append(argument)
        else:
            state['active'] -= 1
            if os.getppid() != parent:
                state['orphaned'] += 1
        f.seek(0)
        f.truncate()
        json.dump(state, f)
        f.flush()
        os.fsync(f.fileno())
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)

if len(sys.argv) != 2:
    sys.exit(97)
parent = os.getppid()
update(True, argument=sys.argv[1])
try:
    time.sleep(0.20)
    result = subprocess.run([sys.executable, REAL, sys.argv[1]])
    code = result.returncode
finally:
    update(False, parent=parent)
sys.exit(code)
'''
    with open(ANALYZER, 'w') as f:
        f.write(wrapper)
    os.chmod(ANALYZER, 0o755)
    return submission


def restore_analyzer(submission):
    try:
        os.remove(ANALYZER)
    except FileNotFoundError:
        pass
    os.replace(submission, ANALYZER)


def test_scripts_exist_and_executable():
    """Test that analyzer.py and run_parallel.sh exist, and run_parallel.sh is executable."""
    analyzer_path = '/home/user/analyzer.py'
    runner_path = '/home/user/run_parallel.sh'

    assert os.path.isfile(analyzer_path), f"{analyzer_path} is missing."
    assert os.path.isfile(runner_path), f"{runner_path} is missing."

    st = os.stat(runner_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{runner_path} is not executable."


def test_execution_and_manifest():
    """Test that running run_parallel.sh produces the correct dedup_manifest.json."""
    manifest_path = '/home/user/dedup_manifest.json'

    generated = add_random_archives()
    all_tars = sorted(
        os.path.join(root, name)
        for root, _, names in os.walk(BACKUPS)
        for name in names
        if name.endswith('.tar')
    )
    expected = expected_from_tars(all_tars)

    # Remove manifest if it exists to ensure the script creates it
    if os.path.exists(manifest_path):
        os.remove(manifest_path)
    if os.path.exists(LOCKFILE):
        os.remove(LOCKFILE)
    if os.path.exists(STATE):
        os.remove(STATE)

    submission = install_instrumented_wrapper()
    try:
        # Run the bash script
        result = subprocess.run(['/home/user/run_parallel.sh'], capture_output=True, text=True, timeout=90)
    finally:
        restore_analyzer(submission)

    assert result.returncode == 0, f"run_parallel.sh failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"

    assert os.path.isfile(manifest_path), "dedup_manifest.json was not created after running run_parallel.sh"

    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("dedup_manifest.json does not contain valid JSON.")

    # Compute expected hashes dynamically
    hash_A = hashlib.sha256(b"ERROR: Disk full\n").hexdigest()
    hash_B = hashlib.sha256(b"WARN: High memory usage\n").hexdigest()
    hash_C = hashlib.sha256(b"INFO: System rebooted\n").hexdigest()

    assert hash_A in manifest, f"Manifest is missing hash for content A: {hash_A}"
    assert hash_B in manifest, f"Manifest is missing hash for content B: {hash_B}"
    assert hash_C in manifest, f"Manifest is missing hash for content C: {hash_C}"

    # Expected path suffixes
    expected_A = {
        "backup1.tar/logs1.zip/logA.log",
        "backup2.tar/logs2.zip/logA_dup.log"
    }
    expected_B = {
        "backup1.tar/logs1.zip/logB.log",
        "backup3.tar/logs3.zip/logB_dup.log"
    }
    expected_C = {
        "backup2.tar/logs2.zip/logC.log"
    }

    def check_paths(actual_paths, expected_suffixes):
        for expected_suffix in expected_suffixes:
            # Check if any actual path ends with the expected suffix
            # (allowing for absolute paths like /home/user/old_backups/backup1.tar/...)
            assert any(p.endswith(expected_suffix) for p in actual_paths), \
                f"Expected path ending with '{expected_suffix}' not found in {actual_paths}"

        # Also ensure no extra paths are present
        assert len(actual_paths) == len(expected_suffixes), \
            f"Expected {len(expected_suffixes)} paths, but found {len(actual_paths)}: {actual_paths}"

    check_paths(manifest[hash_A], expected_A)
    check_paths(manifest[hash_B], expected_B)
    check_paths(manifest[hash_C], expected_C)

    # Reject missing randomized results and unrelated extra hash keys/paths.
    assert_exact_manifest(manifest, expected)

    # Instrumentation proves the runner invoked analyzer once per tar, concurrently,
    # and kept the launching shell alive until each background job completed.
    with open(STATE) as f:
        state = json.load(f)
    expected_names = sorted(os.path.basename(path) for path in all_tars)
    actual_names = sorted(os.path.basename(path) for path in state['calls'])
    assert actual_names == expected_names, (
        f'Runner did not invoke analyzer exactly once for every tar: {state}'
    )
    assert state['maximum'] >= 2, 'Analyzer invocations were not run concurrently.'
    assert state['active'] == 0, 'Runner exited before all analyzer processes completed.'
    assert state['orphaned'] == 0, 'Background analyzers outlived their launching shell; runner did not wait.'
    assert generated


def test_analyzer_directly_on_unseen_archive():
    token = uuid.uuid4().hex
    tar_path = f'/tmp/direct_{token}.tar'
    first = secrets.token_bytes(41)
    second = secrets.token_bytes(73)
    with tarfile.open(tar_path, 'w') as tf:
        for zip_name, entries in [
            (f'one_{token}.zip', [('a.log', first), ('b.log', second)]),
            (f'two_{token}.zip', [('duplicate.log', first)]),
        ]:
            data = make_zip(entries)
            info = tarfile.TarInfo(zip_name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

    expected = expected_from_tars([tar_path])
    for path in (MANIFEST, LOCKFILE):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ['python3', ANALYZER, tar_path], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'analyzer.py failed on an unseen archive\nStdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert os.path.isfile(MANIFEST), 'analyzer.py did not create the manifest.'
    with open(MANIFEST) as f:
        manifest = json.load(f)
    assert_exact_manifest(manifest, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
