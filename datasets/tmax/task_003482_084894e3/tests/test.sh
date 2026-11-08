#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import string
import subprocess
import tempfile

EXTRACTOR = '/home/user/extractor'
SOURCE = '/home/user/extractor.c'
OUTPUT = '/home/user/unique_product_codes.csv'
EXPECTED_CODES = [
    'abc-1234',
    'def-5678',
    'lmn-0000',
    'qwe-1111',
    'xyz-9999',
    'zzz-9999',
]


def test_extractor_c_exists():
    path = SOURCE
    assert os.path.isfile(path), f"The C source file {path} was not found."


def test_extractor_executable_exists():
    path = EXTRACTOR
    assert os.path.isfile(path), f"The compiled executable {path} was not found."

    # Check if it's executable
    st = os.stat(path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"The file {path} is not executable."


def test_extractor_is_compiled_program():
    with open(EXTRACTOR, 'rb') as f:
        magic = f.read(4)
    assert magic == b'\x7fELF', 'The extractor must be a compiled native executable, not a script.'


def test_unique_product_codes_csv():
    path = OUTPUT
    assert os.path.isfile(path), f"The output file {path} was not found."

    expected_codes = EXPECTED_CODES

    with open(path, 'r') as f:
        content = f.read().strip().splitlines()

    assert content == expected_codes, (
        f"The content of {path} does not match the expected output.\n"
        f"Expected: {expected_codes}\n"
        f"Got:      {content}"
    )


def run_extractor(path, text):
    result = subprocess.run(
        [path], input=text, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, check=False
    )
    assert result.returncode == 0, (
        f'{path} exited with status {result.returncode}: {result.stderr}'
    )
    return result.stdout.splitlines()


def make_behavior_case():
    rng = random.SystemRandom()
    valid_re = re.compile(r'[A-Z]{3}-[0-9]{4}')
    valid = []
    while len(valid) < 18:
        code = ''.join(rng.choice(string.ascii_uppercase) for _ in range(3))
        code += '-' + ''.join(rng.choice(string.digits) for _ in range(4))
        if code not in valid:
            valid.append(code)

    words = list(valid)
    for code in valid[:8]:
        words.extend([
            'X' + code,
            code + 'X',
            code + rng.choice(string.digits),
            code[:-1],
            code.lower(),
        ])
    words.extend(['ABC-12A4', 'AB-1234', 'ABCD-1234', '---', 'nothing'])
    rng.shuffle(words)

    # Answers are derived from the generated whitespace-separated input.
    expected = [word.lower() for word in words if valid_re.fullmatch(word)]
    text = ''
    for i in range(0, len(words), 7):
        text += '\t '.join(words[i:i + 7]) + '\n'
    return text, expected


def test_extractor_behavior_and_source():
    text, expected = make_behavior_case()
    assert run_extractor(EXTRACTOR, text) == expected

    rebuilt = '/tmp/extractor_rebuilt'
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', SOURCE, '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=20, check=False
    )
    assert result.returncode == 0, f'extractor.c did not compile: {result.stderr}'
    assert run_extractor(rebuilt, text) == expected


def test_parallel_raw_log_pipeline():
    # Exercise the submitted extractor on every raw log using the required
    # parallel xargs form, then check the deduplicated and sorted result.
    command = r'''find /home/user/raw_logs -type f -name '*.log' -print0 | xargs -0 -r -n 1 -P 4 /bin/sh -c 'exec /home/user/extractor < "$1"' _'''
    result = subprocess.run(
        ['/bin/bash', '-o', 'pipefail', '-c', command],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=20, check=False
    )
    assert result.returncode == 0, f'Parallel extraction failed: {result.stderr}'
    actual = sorted(set(result.stdout.splitlines()))
    assert actual == EXPECTED_CODES, (
        f'Parallel processing of the raw logs produced {actual}, expected {EXPECTED_CODES}'
    )

    with open(OUTPUT, 'r') as f:
        saved = f.read().strip().splitlines()
    assert saved == actual, 'The saved CSV does not match the extractor pipeline output.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
