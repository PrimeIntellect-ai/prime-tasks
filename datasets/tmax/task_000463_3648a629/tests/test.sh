#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess

HOME = '/home/user'
ARTIFACTS = ['generator', 'data.json', 'answer.txt']


def run(cmd, timeout=120):
    result = subprocess.run(
        cmd,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command {' '.join(cmd)} failed:\n{result.stdout}"
    return result.stdout


def clean_artifacts():
    for name in ARTIFACTS:
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                raise AssertionError(f'{path} should be a file, not a directory.')
            os.unlink(path)


def largest_prime_factor(value):
    if value in (0, 1):
        return 0
    largest = 1
    while value % 2 == 0:
        largest = 2
        value //= 2
    factor = 3
    while factor * factor <= value:
        while value % factor == 0:
            largest = factor
            value //= factor
        factor += 2
    if value > 1:
        largest = value
    return largest


def expected_data():
    result = []
    a, b = 0, 1
    for n in range(40):
        result.append({'n': n, 'fib': a, 'lpf': largest_prime_factor(a)})
        a, b = b, a + b
    return result


def test_00_pipeline_executes_from_source_and_make_targets_work():
    # The submitted Go source itself must compile and run successfully.
    source_binary = '/tmp/verifier_generator'
    if os.path.exists(source_binary):
        os.unlink(source_binary)
    run(['go', 'build', '-o', source_binary, '/home/user/generator.go'])
    if os.path.exists('/home/user/data.json'):
        os.unlink('/home/user/data.json')
    run([source_binary])
    assert os.path.isfile('/home/user/data.json'), 'The compiled generator.go did not create /home/user/data.json.'

    # Exercise each required Makefile target from a clean state.
    clean_artifacts()
    run(['make', 'build'])
    assert os.path.isfile('/home/user/generator'), "The 'build' target did not create /home/user/generator."
    with open('/home/user/generator', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The 'build' target did not produce a compiled executable."

    run(['make', 'run'])
    assert os.path.isfile('/home/user/data.json'), "The 'run' target did not create /home/user/data.json."

    run(['make', 'extract'])
    assert os.path.isfile('/home/user/answer.txt'), "The 'extract' target did not create /home/user/answer.txt."

    # Exercise all explicitly from a clean state.
    clean_artifacts()
    run(['make', 'all'])
    for name in ARTIFACTS:
        assert os.path.isfile(os.path.join(HOME, name)), f"'make all' did not create {name}."

    # The default target must also run the complete pipeline.
    clean_artifacts()
    run(['make'])
    for name in ARTIFACTS:
        assert os.path.isfile(os.path.join(HOME, name)), f"Default 'make' did not create {name}."


def test_generator_go_exists():
    assert os.path.isfile('/home/user/generator.go'), "/home/user/generator.go does not exist."


def test_makefile_exists_and_targets():
    makefile_path = '/home/user/Makefile'
    assert os.path.isfile(makefile_path), "/home/user/Makefile does not exist."
    with open(makefile_path, 'r') as f:
        content = f.read()

    for target in ['build', 'run', 'extract', 'all']:
        assert f"{target}:" in content or f"{target} :" in content, f"Makefile is missing the '{target}' target."

    dry_run = run(['make', '-Bn', 'extract'])
    assert re.search(r'(^|[\s;&|])(?:\S*/)?jq(?:\s|$)', dry_run, re.MULTILINE), \
        "The 'extract' target does not invoke jq."


def test_generator_executable_exists():
    exe_path = '/home/user/generator'
    assert os.path.isfile(exe_path), "/home/user/generator does not exist."
    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), "/home/user/generator is not executable."


def test_data_json_validity_and_content():
    json_path = '/home/user/data.json'
    assert os.path.isfile(json_path), "/home/user/data.json does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/data.json is not valid JSON."

    assert isinstance(data, list), "/home/user/data.json should contain a JSON array."
    assert len(data) >= 40, "/home/user/data.json should contain at least 40 elements."
    assert len(data) == 40, "/home/user/data.json should contain exactly the first 40 Fibonacci entries."

    expected = expected_data()
    for index, (item, wanted) in enumerate(zip(data, expected)):
        assert isinstance(item, dict), f"Element {index} is not a JSON object."
        assert set(item.keys()) == {'n', 'fib', 'lpf'}, f"Element {index} must use exactly the keys n, fib, and lpf."
        for key in ('n', 'fib', 'lpf'):
            assert type(item[key]) is int, f"Element {index} field '{key}' must be an integer."
        assert item == wanted, f"Incorrect entry at index {index}: expected {wanted}, got {item}."

    item_20 = None
    for item in data:
        if item.get("n") == 20:
            item_20 = item
            break

    assert item_20 is not None, "Element with n=20 not found in /home/user/data.json."
    assert item_20.get("fib") == 6765, f"Expected fib=6765 for n=20, got {item_20.get('fib')}."
    assert item_20.get("lpf") == 41, f"Expected lpf=41 for n=20, got {item_20.get('lpf')}."


def test_answer_txt_content():
    answer_path = '/home/user/answer.txt'
    assert os.path.isfile(answer_path), "/home/user/answer.txt does not exist."

    with open(answer_path, 'r') as f:
        content = f.read().strip()

    assert content == "41", f"Expected /home/user/answer.txt to contain '41', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
