#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import stat
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/kmer_kl')
MANIFEST = PROJECT / 'Cargo.toml'
READS = Path('/home/user/reads.fasta')
OUTPUT = Path('/home/user/features.json')
PRIMER = 'ATGCGTAC'
KMERS = [a + b + c for a in 'ACGT' for b in 'ACGT' for c in 'ACGT']
NUMBER_RE = re.compile(r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?')

ORIGINAL_FASTA = '''>read_1_perfect_match
ATGCGTACACGTACGTACGT
>read_2_1_mismatch_G_to_A
ATGCATACCCCGGGGAAAA
>read_3_perfect
ATGCGTACGGGGCC
>read_4_no_primer
NNNNNNN
>read_5_perfect_with_prefix
TTTATGCGTACAAAAAGGGG
>read_6_extra
ATGCGTACCCCCC
'''


def find_truncated(sequence):
    for i in range(len(sequence) - len(PRIMER) + 1):
        window = sequence[i:i + len(PRIMER)]
        mismatches = sum(a != b for a, b in zip(window, PRIMER))
        if mismatches <= 1:
            return sequence[i + len(PRIMER):]
    return None


def expected_matrix(sequences):
    truncated = []
    for sequence in sequences:
        result = find_truncated(sequence)
        if result is not None:
            truncated.append(result)
        if len(truncated) == 4:
            break
    assert len(truncated) == 4

    vecs = []
    for sequence in truncated:
        counts = {kmer: 1e-8 for kmer in KMERS}
        for i in range(len(sequence) - 2):
            kmer = sequence[i:i + 3]
            if kmer in counts:
                counts[kmer] += 1
        total = sum(counts.values())
        vecs.append([counts[kmer] / total for kmer in KMERS])

    matrix = []
    for p in vecs:
        row = []
        for q in vecs:
            kl = sum(p[k] * math.log(p[k] / q[k]) for k in range(64))
            row.append(round(kl, 4))
        matrix.append(row)
    return matrix


def write_fasta(records, multiline=False):
    with READS.open('w') as handle:
        for index, sequence in enumerate(records):
            handle.write(f'>record_{index}\n')
            if multiline and len(sequence) > 5:
                cut = len(sequence) // 2
                handle.write(sequence[:cut] + '\n' + sequence[cut:] + '\n')
            else:
                handle.write(sequence + '\n')


def assert_output(expected):
    path = '/home/user/features.json'
    assert os.path.exists(path), f'File {path} does not exist. The Rust program must write the output here.'

    raw = OUTPUT.read_text()
    try:
        student_matrix = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail('features.json is not valid JSON.')

    assert isinstance(student_matrix, list), 'features.json must contain a JSON array (list of lists).'
    assert len(student_matrix) == 4, f'features.json must be a 4x4 matrix, but has {len(student_matrix)} rows.'

    tokens = NUMBER_RE.findall(raw)
    assert len(tokens) == 16, 'features.json must contain exactly 16 numeric matrix elements.'
    assert all(re.fullmatch(r'-?(?:0|[1-9]\d*)\.\d{4}', token) for token in tokens), \
        'Every matrix value must be written with exactly four digits after the decimal point.'

    for i in range(4):
        assert isinstance(student_matrix[i], list), f'Row {i} in features.json is not a list.'
        assert len(student_matrix[i]) == 4, f'Row {i} in features.json does not have 4 elements.'
        for j in range(4):
            student_val = student_matrix[i][j]
            expected_val = expected[i][j]
            assert isinstance(student_val, (int, float)), f'Element at ({i},{j}) is not a number.'
            assert not isinstance(student_val, bool), f'Element at ({i},{j}) is not a number.'
            assert math.isclose(student_val, expected_val, rel_tol=1e-3, abs_tol=1e-3), \
                f'Value at ({i},{j}) is {student_val}, expected {expected_val}.'


@pytest.fixture(scope='module')
def rust_binary():
    assert PROJECT.is_dir(), 'The Rust project /home/user/kmer_kl does not exist.'
    assert MANIFEST.is_file(), 'The Rust project must contain Cargo.toml.'

    metadata_result = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', str(MANIFEST)],
        capture_output=True, text=True, timeout=60
    )
    assert metadata_result.returncode == 0, f'Cargo metadata failed:\n{metadata_result.stderr}'
    metadata = json.loads(metadata_result.stdout)
    manifest_real = str(MANIFEST.resolve())
    packages = [p for p in metadata['packages'] if str(Path(p['manifest_path']).resolve()) == manifest_real]
    assert packages, 'Cargo.toml does not define a valid Rust package.'
    package = packages[0]
    binary_targets = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
    assert binary_targets, 'The Rust project does not define an executable binary target.'

    default_name = package.get('default_run')
    target = next((t for t in binary_targets if t['name'] == default_name), binary_targets[0])
    build = subprocess.run(
        ['cargo', 'build', '--quiet', '--manifest-path', str(MANIFEST), '--bin', target['name']],
        capture_output=True, text=True, timeout=120
    )
    assert build.returncode == 0, f'The Rust executable failed to build:\n{build.stderr}'

    executable = Path(metadata['target_directory']) / 'debug' / target['name']
    assert executable.is_file(), f'Cargo did not produce the expected executable {executable}.'
    assert executable.stat().st_mode & stat.S_IXUSR, 'The built Rust binary is not executable.'
    return target['name']


def run_program(binary_name):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST), '--bin', binary_name],
        cwd=PROJECT, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, f'The Rust executable failed:\n{result.stderr}'


def test_original_features_json_exists_and_correct(rust_binary):
    READS.write_text(ORIGINAL_FASTA)
    run_program(rust_binary)
    sequences = [
        'ATGCGTACACGTACGTACGT',
        'ATGCATACCCCGGGGAAAA',
        'ATGCGTACGGGGCC',
        'NNNNNNN',
        'TTTATGCGTACAAAAAGGGG',
        'ATGCGTACCCCCC',
    ]
    assert_output(expected_matrix(sequences))


def test_program_parses_and_computes_fresh_input(rust_binary):
    rng = random.SystemRandom()

    def dna(length):
        return ''.join(rng.choice('ACGT') for _ in range(length))

    mismatch_pos = rng.randrange(len(PRIMER))
    replacement = rng.choice([base for base in 'ACGT' if base != PRIMER[mismatch_pos]])
    mismatched_primer = PRIMER[:mismatch_pos] + replacement + PRIMER[mismatch_pos + 1:]

    records = [
        'NNNNNNNNNNNN',
        'CCCCCC' + PRIMER + dna(11),
        'TTTTT' + mismatched_primer + dna(13),
        'GG' + PRIMER + dna(7) + PRIMER + dna(5),
        'CCCC' + PRIMER + dna(9),
        PRIMER + dna(15),  # fifth successful read must be ignored
    ]
    write_fasta(records, multiline=True)
    run_program(rust_binary)
    assert_output(expected_matrix(records))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
