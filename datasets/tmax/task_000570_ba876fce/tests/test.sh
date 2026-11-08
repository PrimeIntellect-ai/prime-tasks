#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import glob
import os
import random
import shutil
import string
import subprocess
import tempfile

import pytest

EXECUTABLE = '/home/user/query_sanitizer'
SOURCE = '/home/user/query_sanitizer.c'
CLEAN_CORPUS_DIR = '/app/corpus/clean'
EVIL_CORPUS_DIR = '/app/corpus/evil'
TEST_DIR = tempfile.mkdtemp(prefix='qs_behavior_')
REBUILT = os.path.join(TEST_DIR, 'rebuilt_sanitizer')
atexit.register(lambda: shutil.rmtree(TEST_DIR, ignore_errors=True))


def run_binary(binary, filepath):
    return subprocess.run(
        [binary, filepath],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        cwd=TEST_DIR,
    )


@pytest.fixture(scope='session', autouse=True)
def compile_submitted_source():
    assert os.path.exists(SOURCE), f'Source file {SOURCE} does not exist.'
    assert os.path.isfile(SOURCE), f'{SOURCE} is not a file.'
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', SOURCE, '-o', REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{SOURCE} did not compile as C source:\n'
        + result.stderr.decode(errors='replace')
    )
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)
    yield


def test_executable_exists_and_is_executable():
    assert os.path.exists(EXECUTABLE), f'Executable {EXECUTABLE} does not exist.'
    assert os.path.isfile(EXECUTABLE), f'{EXECUTABLE} is not a file.'
    assert os.access(EXECUTABLE, os.X_OK), f'{EXECUTABLE} is not executable.'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXECUTABLE} is not a compiled executable.'


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, '*'))
    assert len(clean_files) > 0, f'No files found in clean corpus directory {CLEAN_CORPUS_DIR}.'

    failed_files = []
    for filepath in clean_files:
        if not os.path.isfile(filepath):
            continue
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    total = len(clean_files)
    failed_count = len(failed_files)
    assert failed_count == 0, f"{failed_count} of {total} clean queries were rejected (expected 0). Offending files: {', '.join(failed_files)}"


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, '*'))
    assert len(evil_files) > 0, f'No files found in evil corpus directory {EVIL_CORPUS_DIR}.'

    bypassed_files = []
    for filepath in evil_files:
        if not os.path.isfile(filepath):
            continue
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(filepath))

    total = len(evil_files)
    bypassed_count = len(bypassed_files)
    assert bypassed_count == 0, f"{bypassed_count} of {total} evil queries bypassed the sanitizer (expected 0). Offending files: {', '.join(bypassed_files)}"


def random_identifier(prefix):
    suffix = ''.join(random.SystemRandom().choice(string.ascii_letters) for _ in range(12))
    return prefix + suffix


def write_query(text):
    fd, path = tempfile.mkstemp(prefix=random_identifier('case_'), suffix='.dat', dir=TEST_DIR)
    with os.fdopen(fd, 'w') as f:
        f.write(text)
    return path


def make_query(traversal, returned, where=None, second_traversal=None):
    left = random_identifier('src')
    middle = random_identifier('dst')
    end = random_identifier('end')
    relation = random_identifier('REL')
    lines = [f'MATCH ({left}:Node)-[{relation}:{relation}{traversal}]->({middle}:Node)']
    if second_traversal is not None:
        relation2 = random_identifier('REL')
        lines[0] += f'-[{relation2}:{relation2}{second_traversal}]->({end}:Node)'
    if where is not None:
        lines.append(f'WHERE {where}')
    lines.append(f'RETURN {returned}')
    return '\n'.join(lines) + '\n'


def assert_accepts_all_builds(query):
    path = write_query(query)
    try:
        for binary in (EXECUTABLE, REBUILT):
            result = run_binary(binary, path)
            assert result.returncode == 0, (
                f'{binary} rejected a valid unseen query with code {result.returncode}: '
                + result.stderr.decode(errors='replace')
            )
    finally:
        os.unlink(path)


def assert_rejects_all_builds(query):
    path = write_query(query)
    try:
        for binary in (EXECUTABLE, REBUILT):
            result = run_binary(binary, path)
            assert result.returncode != 0, f'{binary} accepted an invalid unseen query.'
            assert result.stderr.strip(), f'{binary} rejected an invalid query without an error on stderr.'
    finally:
        os.unlink(path)


def test_unseen_valid_depths_and_return_schema():
    # Exercise every allowed exact depth and several bounded ranges using fresh,
    # opaque paths and identifiers rather than the labeled corpus directories.
    for depth in range(1, 5):
        alias = random_identifier('n')
        assert_accepts_all_builds(make_query(f'*{depth}', f'{alias}.id, {alias}.node_centrality'))

    for upper in range(1, 5):
        lower = random.randint(1, upper)
        alias = random_identifier('m')
        assert_accepts_all_builds(make_query(f'*{lower}..{upper}', f'{alias}.node_centrality, {alias}.name'))

    alias = random_identifier('z')
    assert_accepts_all_builds(make_query('*1..3', f'{alias}.node_centrality', second_traversal='*4'))


def test_unseen_excessive_and_unbounded_traversals():
    excessive = random.SystemRandom().randint(5, 50)
    alias = random_identifier('n')
    assert_rejects_all_builds(make_query(f'*{excessive}', f'{alias}.node_centrality'))
    assert_rejects_all_builds(make_query(f'*2..{excessive}', f'{alias}.node_centrality'))
    assert_rejects_all_builds(make_query('*1..', f'{alias}.node_centrality'))
    assert_rejects_all_builds(make_query('*', f'{alias}.node_centrality'))
    assert_rejects_all_builds(make_query('*1..2', f'{alias}.node_centrality', second_traversal=f'*{excessive}'))


def test_unseen_return_clause_validation():
    alias = random_identifier('q')
    assert_rejects_all_builds(make_query('*1..4', f'{alias}.id, {alias}.name'))
    assert_rejects_all_builds(make_query(
        '*2',
        f'{alias}.id, {alias}.name',
        where=f'{alias}.node_centrality > 0',
    ))
    assert_rejects_all_builds(make_query('*3', f'{alias}.id, {alias}.node_centrality_backup'))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
