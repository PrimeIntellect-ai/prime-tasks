#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

CPP_PATH = '/home/user/process_data.cpp'
BIN_PATH = '/tmp/process_data_submission'
INPUT_PATH = '/home/user/data/dirty_records.jsonl'
OUTPUT_PATH = '/home/user/output/distances.csv'


def run_submission():
    result = subprocess.run(
        [BIN_PATH], capture_output=True, text=True, timeout=30,
        cwd='/home/user'
    )
    assert result.returncode == 0, (
        f'Program failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def normalized_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f.read().strip().split('\n')]


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def test_01_cpp_file_exists():
    assert os.path.isfile(CPP_PATH), f'C++ source file {CPP_PATH} is missing.'


def test_02_compile_and_run_program():
    result = subprocess.run(
        ['g++', '-std=c++17', CPP_PATH, '-o', BIN_PATH],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'Compilation failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    run_submission()


def test_03_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} is missing.'


def test_04_output_file_content():
    expected_content = (
        'id,distance\n'
        '1,0\n'
        '2,0\n'
        '3,15\n'
        '4,1\n'
        '5,0\n'
        '6,0\n'
        '7,2\n'
        '8,0\n'
        '9,12\n'
        '10,0\n'
    )
    expected_lines = [line.strip() for line in expected_content.strip().split('\n')]
    assert normalized_lines(OUTPUT_PATH) == expected_lines, (
        'The content of distances.csv does not match the expected output.'
    )


def test_05_program_handles_fresh_records():
    rng = random.SystemRandom()
    texts = [
        r'data \u202scientist',
        r'\udata scientist',
        r'data scientist\u12',
        r'dat\ua scientist',
        r'data \uFfFfscientist',
        r'plain analyst',
        r'DATA SCIENTIST',
        r'data \uscientist',
    ]

    alphabet = 'abcdefghijklmnopqrstuvwxyz '
    hex_digits = '0123456789abcdefABCDEF'
    for _ in range(5):
        value = list('data scientist')
        for _ in range(rng.randint(1, 4)):
            operation = rng.choice(('insert', 'delete', 'replace'))
            if operation == 'insert':
                value.insert(rng.randrange(len(value) + 1), rng.choice(alphabet))
            elif operation == 'delete' and value:
                del value[rng.randrange(len(value))]
            elif value:
                value[rng.randrange(len(value))] = rng.choice(alphabet)
        token = '\\u' + ''.join(rng.choice(hex_digits) for _ in range(rng.randint(0, 4)))
        value.insert(rng.randrange(len(value) + 1), token)
        texts.append(''.join(value))

    ids = rng.sample(range(1000, 9000), len(texts))
    records = list(zip(ids, texts))
    rng.shuffle(records)

    with open(INPUT_PATH, 'w') as f:
        for record_id, text in records:
            f.write(f'{{"id": {record_id}, "text": "{text}"}}\n')

    run_submission()
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} is missing.'

    expected = ['id,distance']
    for record_id, text in sorted(records):
        cleaned = re.sub(r'\\u[0-9a-fA-F]{0,4}', '', text)
        expected.append(f'{record_id},{levenshtein(cleaned, "data scientist")}')

    assert normalized_lines(OUTPUT_PATH) == expected, (
        'Program output for fresh records does not implement the required '
        'greedy cleaning, distance calculation, and id sorting.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
