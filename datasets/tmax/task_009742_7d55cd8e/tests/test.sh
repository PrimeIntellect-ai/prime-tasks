#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
PRODUCTS = HOME / 'products.txt'
OUTPUT = HOME / 'duplicates.csv'
SOURCE = HOME / 'dedup.cpp'
EXECUTABLE = HOME / 'dedup'


def normalize(text):
    text = text.lower()
    text = re.sub(r'<[^>]*>', '', text)
    text = re.sub(r'[^a-z0-9 ]', '', text)
    text = re.sub(r' +', ' ', text).strip()
    return set(text.split()) if text else set()


def expected_pairs(data):
    products = []
    for raw_line in data.splitlines():
        if not raw_line:
            continue
        product_id, description = raw_line.split('|', 1)
        products.append((product_id, normalize(description)))

    result = []
    for i in range(len(products)):
        for j in range(i + 1, len(products)):
            id1, words1 = products[i]
            id2, words2 = products[j]
            union = words1 | words2
            similarity = len(words1 & words2) / len(union) if union else 1.0
            if similarity > 0.75:
                result.append(tuple(sorted((id1, id2))))
    return sorted(result)


def read_output():
    assert OUTPUT.exists(), f'The output file {OUTPUT} does not exist.'
    assert OUTPUT.is_file(), f'The path {OUTPUT} is not a file.'
    raw = OUTPUT.read_text()
    lines = raw.splitlines()
    assert all(line and line == line.strip() for line in lines), 'Output contains blank lines or surrounding whitespace.'
    assert all(re.fullmatch(r'[^,]+,[^,]+', line) for line in lines), 'Each output line must contain exactly two comma-separated IDs.'
    return lines


def run_case(program, data):
    PRODUCTS.write_text(data)
    if OUTPUT.exists():
        OUTPUT.unlink()
    completed = subprocess.run(
        [str(program)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert completed.returncode == 0, f'{program} failed: {completed.stderr}'
    actual = read_output()
    expected = [f'{a},{b}' for a, b in expected_pairs(data)]
    assert actual == expected, f'For exercised input, expected {expected}, but got {actual}.'


def test_duplicates_csv_exists():
    file_path = '/home/user/duplicates.csv'
    assert os.path.exists(file_path), f'The output file {file_path} does not exist.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'


def test_duplicates_csv_content():
    expected_lines = [
        'P003,P004',
        'P005,P007'
    ]
    file_path = '/home/user/duplicates.csv'
    assert os.path.exists(file_path), f'Cannot verify content, {file_path} is missing.'
    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == expected_lines, f'Expected output lines {expected_lines}, but got {lines}.'


def test_cpp_source_exists():
    file_path = '/home/user/dedup.cpp'
    assert os.path.exists(file_path), f'The C++ source file {file_path} does not exist.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'


def test_executable_exists():
    file_path = '/home/user/dedup'
    assert os.path.exists(file_path), f'The compiled executable {file_path} does not exist.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'
    assert os.access(file_path, os.X_OK), f'The file {file_path} is not executable. Did you compile it?'
    with open(file_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'The dedup executable is not a compiled ELF binary.'


def test_source_features_and_execution():
    source = SOURCE.read_text()
    without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'\b(?:std::)?regex(?:_replace)?\b|\bregcomp\b', without_comments), \
        'The C++ source does not use regular expressions for cleaning.'
    assert (re.search(r'#\s*pragma\s+omp\s+parallel', without_comments) or
            re.search(r'\b(?:std::)?(?:thread|async)\b', without_comments)), \
        'The C++ source does not contain a parallel pairwise implementation.'

    rebuilt = Path('/tmp/dedup_rebuilt')
    compilation = subprocess.run(
        ['g++', '-O3', '-std=c++17', '-fopenmp', '-pthread', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compilation.returncode == 0, f'dedup.cpp did not compile: {compilation.stderr}'

    original_data = PRODUCTS.read_text()
    nonce = secrets.token_hex(6)
    dynamic_data = '\n'.join([
        f'Z900|<b>{nonce}joy-con</b> {nonce}alpha {nonce}beta {nonce}gamma {nonce}delta',
        f'A100|{nonce}joycon   {nonce}alpha {nonce}beta {nonce}gamma {nonce}delta {nonce}extra',
        f'M400|{nonce}one {nonce}two {nonce}three',
        f'B300|{nonce}one {nonce}two {nonce}three {nonce}four',
        f'Y700|{nonce}cat {nonce}cat {nonce}dog {nonce}eel {nonce}fox',
        f'C200|<p>{nonce}cat {nonce}dog {nonce}eel {nonce}fox {nonce}yak</p>',
        f'Q500|{nonce}isolated {nonce}listing'
    ]) + '\n'

    try:
        run_case(EXECUTABLE, dynamic_data)
        run_case(rebuilt, dynamic_data)
        run_case(EXECUTABLE, original_data)
        run_case(rebuilt, original_data)
    finally:
        PRODUCTS.write_text(original_data)

    final_expected = [f'{a},{b}' for a, b in expected_pairs(original_data)]
    assert read_output() == final_expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
