#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile


def compute_expected_sv(filepath):
    if not os.path.exists(filepath):
        return None

    with open(filepath, 'r') as f:
        seqs = [line.strip() for line in f if line.strip()]

    if not seqs:
        return None

    n = len(seqs)
    m = len(seqs[0])
    if any(len(seq) != m for seq in seqs):
        return None

    M = [[0.0] * m for _ in range(n)]
    for i in range(n):
        for j in range(m):
            c = seqs[i][j]
            if c == 'A': M[i][j] = 1.0
            elif c == 'C': M[i][j] = -1.0
            elif c == 'G': M[i][j] = 2.0
            elif c == 'T': M[i][j] = -2.0

    A = [[0.0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            for k in range(n):
                A[i][j] += M[k][i] * M[k][j]

    v = [1.0] * m
    for _ in range(1000):
        u = [0.0] * m
        norm = 0.0
        for i in range(m):
            for j in range(m):
                u[i] += A[i][j] * v[j]
            norm += u[i] * u[i]
        norm = math.sqrt(norm)
        for i in range(m):
            v[i] = u[i] / norm

    lam = 0.0
    for i in range(m):
        Av_i = 0.0
        for j in range(m):
            Av_i += A[i][j] * v[j]
        lam += v[i] * Av_i

    return math.sqrt(lam)


def test_result_file_exists_and_correct():
    result_path = '/home/user/result.txt'
    primers_path = '/home/user/primers.txt'

    assert os.path.isfile(result_path), f'Missing file: {result_path}. Did you run the compiled program and save the output?'

    expected_sv = compute_expected_sv(primers_path)
    assert expected_sv is not None, f'Could not compute expected value from {primers_path}'
    expected_str = f'{expected_sv:.3f}'

    with open(result_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_str, f'Incorrect output in {result_path}. Expected {expected_str}, got {actual_content}.'


def test_code_was_fixed():
    cpp_path = '/home/user/spectral_align.cpp'
    assert os.path.isfile(cpp_path), f'Missing file: {cpp_path}'

    with open(cpp_path, 'r') as f:
        content = f.read()

    assert 'sqrt(' in content, 'It seems the bug in spectral_align.cpp was not fixed. The output should be the square root of the eigenvalue.'


def test_regression_and_compiled_program_behavior():
    cpp_path = '/home/user/spectral_align.cpp'
    binary_path = '/home/user/spectral_align'
    regression_path = '/home/user/test_regression.sh'

    assert os.path.isfile(cpp_path), f'Missing file: {cpp_path}'
    assert os.path.isfile(regression_path), f'Missing file: {regression_path}'

    regression = subprocess.run(
        ['/bin/bash', regression_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert regression.returncode == 0, (
        'The required regression test did not pass.\n'
        f'stdout:\n{regression.stdout}\nstderr:\n{regression.stderr}'
    )

    compiled = subprocess.run(
        ['g++', '-O3', cpp_path, '-o', binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f'Compilation failed:\n{compiled.stderr}'
    assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK)

    target_run = subprocess.run(
        [binary_path, '/home/user/primers.txt'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert target_run.returncode == 0, f'Program failed on primers.txt: {target_run.stderr}'
    assert re.fullmatch(r'-?\d+\.\d{3}', target_run.stdout.strip()), 'Program output must be one floating-point number with exactly 3 decimal places.'

    with open('/home/user/result.txt', 'r') as f:
        saved_result = f.read().strip()
    assert target_run.stdout.strip() == saved_result, 'result.txt does not match the output of the program compiled from spectral_align.cpp.'

    rng = random.SystemRandom()
    encoding = {'A': 1.0, 'C': -1.0, 'G': 2.0, 'T': -2.0}

    with tempfile.TemporaryDirectory(prefix='spectral_verify_') as tempdir:
        for case_index in range(4):
            length = rng.randint(7, 21)
            copies = rng.randint(2, 7)
            while True:
                sequence = ''.join(rng.choice('ACGT') for _ in range(length))
                if sum(encoding[c] for c in sequence) != 0.0:
                    break

            input_path = os.path.join(tempdir, f'case_{case_index}_{rng.getrandbits(64):016x}.txt')
            with open(input_path, 'w') as f:
                for _ in range(copies):
                    f.write(sequence + '\n')

            expected = compute_expected_sv(input_path)
            assert expected is not None
            expected_text = f'{expected:.3f}'

            run = subprocess.run(
                [binary_path, input_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert run.returncode == 0, f'Program failed on a verifier-generated input: {run.stderr}'
            actual = run.stdout.strip()
            assert re.fullmatch(r'-?\d+\.\d{3}', actual), 'Program output must be one floating-point number with exactly 3 decimal places.'
            assert actual == expected_text, f'Incorrect singular value on verifier-generated input: expected {expected_text}, got {actual}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
