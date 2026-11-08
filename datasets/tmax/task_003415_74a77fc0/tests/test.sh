#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
from collections import defaultdict

import pytest
import redis
import requests

ORIG_MANIFEST = '/home/user/project_dump/manifest.txt'
NEW_MANIFEST = '/home/user/manifest_updated.txt'
PROJECT_ROOT = '/home/user/project_dump'
ORGANIZED_ROOT = '/home/user/organized'


def true_extension(data):
    if data.startswith(b'\x89PNG\x0d\x0a\x1a\x0a'):
        return 'png'
    if data.startswith(b'\xff\xd8\xff'):
        return 'jpg'
    if data.startswith(b'%PDF-'):
        return 'pdf'
    return None


def parse_original_line(line):
    assert line.startswith('Asset: '), f'Malformed original manifest line: {line!r}'
    return line[len('Asset: '):].rstrip('\r\n')


def test_organization_accuracy_score():
    assert os.path.exists(ORIG_MANIFEST), f'Original manifest missing at {ORIG_MANIFEST}'
    assert os.path.exists(NEW_MANIFEST), f'Updated manifest missing at {NEW_MANIFEST}'

    with open(ORIG_MANIFEST, 'r', newline='') as orig:
        orig_lines = orig.readlines()
    with open(NEW_MANIFEST, 'r', newline='') as new_m:
        new_lines = new_m.readlines()

    assert len(orig_lines) == len(new_lines), (
        'Updated manifest must have the same number of lines as the original manifest'
    )

    # The required Redis service must still be available, and its command statistics
    # must show that a locking-capable command was used before verification.
    try:
        redis_client = redis.Redis(host='127.0.0.1', port=6379, socket_timeout=2,
                                   decode_responses=True)
        assert redis_client.ping(), 'Redis did not answer PING'
        command_stats = redis_client.info('commandstats')
    except Exception as exc:
        pytest.fail(f'Redis is not running on 127.0.0.1:6379: {exc}')

    locking_calls = 0
    for command in ('cmdstat_set', 'cmdstat_setnx', 'cmdstat_eval', 'cmdstat_evalsha'):
        locking_calls += int(command_stats.get(command, {}).get('calls', 0))
    assert locking_calls > 0, 'Redis shows no commands capable of acquiring a distributed lock'

    records = []
    unique_valid = {}
    total_valid = 0

    for orig_l, new_l in zip(orig_lines, new_lines):
        orig_path_rel = parse_original_line(orig_l)
        full_orig = os.path.join(PROJECT_ROOT, orig_path_rel)
        assert os.path.isfile(full_orig), f'Original file missing: {full_orig}'

        with open(full_orig, 'rb') as source:
            data = source.read()

        ext = true_extension(data)
        if ext is None:
            assert new_l == orig_l, f'Unknown-type manifest line was changed: {orig_l!r}'
            records.append((False, None, None, None, new_l))
            continue

        total_valid += 1
        digest = hashlib.sha256(data).hexdigest()
        canonical_name = f'asset_{digest[:8]}.{ext}'
        expected_path = os.path.join(ORGANIZED_ROOT, ext, canonical_name)
        expected_line = f'Asset: {expected_path}' + ('\r\n' if orig_l.endswith('\r\n') else '\n' if orig_l.endswith('\n') else '')
        unique_valid.setdefault((digest, ext), (canonical_name, expected_path, data))
        records.append((True, digest, expected_path, expected_line, new_l))

    assert total_valid > 0, 'No valid files found in the original dump. Setup might be corrupted.'

    # Exercise the actual metadata service and independently validate every distinct
    # API-derived canonical filename used by the expected result.
    session = requests.Session()
    for (digest, ext), (canonical_name, _, _) in unique_valid.items():
        try:
            response = session.get(
                'http://127.0.0.1:5000/get_name',
                params={'hash': digest, 'ext': ext},
                timeout=2,
            )
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:
            pytest.fail(f'Metadata API is unavailable or returned invalid data: {exc}')
        assert payload == {'filename': canonical_name}, (
            f'Metadata API returned the wrong canonical name for {digest}/{ext}: {payload!r}'
        )

    correct_mapped = 0
    referenced_paths = set()
    paths_by_hash = defaultdict(set)

    for is_valid, digest, expected_path, expected_line, new_l in records:
        if not is_valid or new_l != expected_line:
            continue

        assert os.path.isfile(expected_path), f'Canonical organized file missing: {expected_path}'
        assert not os.path.islink(expected_path), f'Organized output must be a real file: {expected_path}'
        with open(expected_path, 'rb') as organized_file:
            organized_data = organized_file.read()
        assert hashlib.sha256(organized_data).hexdigest() == digest, (
            f'Organized file content does not match its source hash: {expected_path}'
        )

        correct_mapped += 1
        referenced_paths.add(os.path.normpath(expected_path))
        paths_by_hash[digest].add(os.path.normpath(expected_path))

    score = correct_mapped / total_valid
    assert score >= 0.95, (
        f'Organization Accuracy Score is {score:.3f}, which is below the threshold of 0.95. '
        f'Correctly mapped: {correct_mapped}/{total_valid}.'
    )

    # Every successfully mapped SHA-256 must have exactly one canonical destination.
    for digest, paths in paths_by_hash.items():
        assert len(paths) == 1, f'Hash {digest} was not deduplicated: {sorted(paths)}'

    # Reject arbitrary stand-in files and duplicate/extra outputs. The organized tree
    # may contain only canonical files actually referenced by correct manifest entries.
    actual_paths = set()
    if os.path.exists(ORGANIZED_ROOT):
        assert os.path.isdir(ORGANIZED_ROOT), f'{ORGANIZED_ROOT} is not a directory'
        for root, dirs, files in os.walk(ORGANIZED_ROOT, followlinks=False):
            for dirname in dirs:
                directory = os.path.join(root, dirname)
                assert not os.path.islink(directory), f'Symlinked organized directory is not allowed: {directory}'
            for filename in files:
                path = os.path.normpath(os.path.join(root, filename))
                assert not os.path.islink(path), f'Symlinked organized file is not allowed: {path}'
                assert os.path.isfile(path), f'Non-regular organized entry: {path}'
                actual_paths.add(path)

    assert actual_paths == referenced_paths, (
        'Organized output contains missing, duplicate, noncanonical, or unreferenced files. '
        f'Missing: {sorted(referenced_paths - actual_paths)}; '
        f'Unexpected: {sorted(actual_paths - referenced_paths)}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
