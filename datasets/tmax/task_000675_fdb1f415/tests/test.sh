#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import uuid

import pytest

SOURCE = '/home/user/find_loops.c'
OUTPUT = '/home/user/loops.json'
EXECUTABLE = '/tmp/find_loops_verifier'
DATASET = '/home/user/dataset'

ORIGINAL_LOOPS = {
    '/home/user/dataset/loop_dir/child/grandchild/link_to_ancestor',
    '/home/user/dataset/mutualA/link_to_B',
    '/home/user/dataset/mutualB/link_to_A',
}


def compile_program():
    assert os.path.isfile(SOURCE), 'The C program /home/user/find_loops.c does not exist.'
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), 'The submitted C program must be a regular file.'

    result = subprocess.run(
        ['gcc', '-std=gnu11', '-Wall', '-Wextra', '-O2', SOURCE, '-o', EXECUTABLE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f'Failed to compile find_loops.c:\n{result.stderr}'


def run_and_read_output():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)

    result = subprocess.run(
        ['timeout', '20s', EXECUTABLE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=25,
    )
    assert result.returncode == 0, (
        f'The compiled program failed or timed out (exit {result.returncode}).\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(OUTPUT), 'The output file /home/user/loops.json does not exist.'

    try:
        with open(OUTPUT, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read or parse /home/user/loops.json: {e}')

    assert isinstance(data, list), 'The JSON root must be an array.'
    for item in data:
        assert isinstance(item, str), 'All items in the JSON array must be strings.'
        assert os.path.isabs(item), f'Output path is not absolute: {item}'
    assert len(data) == len(set(data)), 'The JSON array must not contain duplicate paths.'
    return data


def make_dynamic_case():
    token = uuid.uuid4().hex
    base = os.path.join(DATASET, uuid.uuid4().hex)

    ancestor_root = os.path.join(base, uuid.uuid4().hex)
    ancestor_child = os.path.join(ancestor_root, uuid.uuid4().hex, uuid.uuid4().hex)
    os.makedirs(ancestor_child)
    ancestor_link = os.path.join(ancestor_child, uuid.uuid4().hex)
    os.symlink(ancestor_root, ancestor_link)

    mutual_a = os.path.join(base, uuid.uuid4().hex)
    mutual_b = os.path.join(base, uuid.uuid4().hex)
    os.makedirs(mutual_a)
    os.makedirs(mutual_b)
    mutual_a_link = os.path.join(mutual_a, uuid.uuid4().hex)
    mutual_b_link = os.path.join(mutual_b, uuid.uuid4().hex)
    os.symlink(mutual_b, mutual_a_link)
    os.symlink(mutual_a, mutual_b_link)

    valid_target = os.path.join(base, uuid.uuid4().hex)
    valid_holder = os.path.join(base, uuid.uuid4().hex)
    os.makedirs(valid_target)
    os.makedirs(valid_holder)
    with open(os.path.join(valid_target, token), 'w', encoding='utf-8') as f:
        f.write('ordinary file\n')
    valid_link = os.path.join(valid_holder, uuid.uuid4().hex)
    os.symlink(valid_target, valid_link)

    expected_dynamic = {ancestor_link, mutual_a_link, mutual_b_link}
    return base, expected_dynamic, valid_link


def assert_original_requirements(data):
    found_ancestor = '/home/user/dataset/loop_dir/child/grandchild/link_to_ancestor' in data
    found_mutual = (
        '/home/user/dataset/mutualA/link_to_B' in data
        or '/home/user/dataset/mutualB/link_to_A' in data
    )
    assert found_ancestor, 'The ancestor loop symlink was not found in the output.'
    assert found_mutual, 'Neither of the mutual loop symlinks was found in the output.'


def test_compiled_program_detects_all_loops_without_false_positives():
    compile_program()

    # First preserve and strengthen the checks against the original dataset.
    original_data = run_and_read_output()
    assert_original_requirements(original_data)
    assert set(original_data) == ORIGINAL_LOOPS, (
        f'Expected exactly the original loop-causing symlinks; got {original_data}'
    )

    # Exercise the submitted executable twice on unpredictable additional cases.
    for _ in range(2):
        base, dynamic_loops, valid_link = make_dynamic_case()
        try:
            data = run_and_read_output()
            assert_original_requirements(data)
            expected = ORIGINAL_LOOPS | dynamic_loops
            assert set(data) == expected, (
                f'Incorrect loop detection. Expected {sorted(expected)}, got {sorted(data)}'
            )
            assert valid_link not in data, 'A non-looping symbolic link was reported as a loop.'
        finally:
            shutil.rmtree(base, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
