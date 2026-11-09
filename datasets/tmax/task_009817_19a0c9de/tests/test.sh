#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
from pathlib import Path

DATA_PATH = Path('/home/user/observational_data.tsv')
OUTPUT_PATH = Path('/home/user/cholesky_diag.txt')


def compute_expected_cholesky_diagonals_from_magnitudes(M):
    S = [[M[i] * M[j] for j in range(4)] for i in range(4)]
    for i in range(4):
        S[i][i] += 0.1

    L = [[0.0] * 4 for _ in range(4)]
    for i in range(4):
        for j in range(i + 1):
            sum_k = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                L[i][j] = math.sqrt(S[i][i] - sum_k)
            else:
                L[i][j] = (S[i][j] - sum_k) / L[j][j]
    return [L[i][i] for i in range(4)]


def compute_expected_cholesky_diagonals():
    # Preserve the original verifier's assertion for the supplied dataset.
    M = [0.0, 40.0, 40.0, 0.0]
    return compute_expected_cholesky_diagonals_from_magnitudes(M)


def read_output_lines():
    assert OUTPUT_PATH.is_file(), (
        f'The expected output file {OUTPUT_PATH} does not exist. '
        'Make sure your C program writes to this exact path.'
    )
    with OUTPUT_PATH.open('r') as f:
        return [line.strip() for line in f.read().strip().split('\n') if line.strip()]


def test_original_output():
    assert OUTPUT_PATH.is_file(), f'The expected output file {OUTPUT_PATH} does not exist. Make sure your C program writes to this exact path.'
    expected_lines = [f'{val:.4f}' for val in compute_expected_cholesky_diagonals()]
    actual_lines = read_output_lines()
    assert len(actual_lines) == 4, f'Expected exactly 4 lines in {OUTPUT_PATH}, but found {len(actual_lines)}.'
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f'Mismatch on line {i+1} (Sequence {chr(ord("A")+i)}). Expected {expected}, got {actual}.'


def expected_for_rows(rows):
    arrays = [[0.0] * 8 for _ in range(4)]
    for seq, idx, value in rows:
        arrays[ord(seq) - ord('A')][idx] = value

    magnitudes = []
    for values in arrays:
        real = 0.0
        imag = 0.0
        for n, value in enumerate(values):
            angle = 2.0 * math.pi * n / 8.0
            real += value * math.cos(angle)
            imag -= value * math.sin(angle)
        magnitudes.append(math.hypot(real, imag))

    return [f'{x:.4f}' for x in compute_expected_cholesky_diagonals_from_magnitudes(magnitudes)]


def write_dataset(rows):
    with DATA_PATH.open('w') as f:
        f.write('seq_id\ttime_idx\tsignal\n')
        for seq, idx, value in rows:
            f.write(f'{seq}\t{idx}\t{value:.9f}\n')


def make_cases():
    rng = random.SystemRandom()
    cases = []

    dense = []
    for seq in 'ABCD':
        for idx in range(8):
            value = rng.randint(-900000, 900000) / 100003.0
            dense.append((seq, idx, float(f'{value:.9f}')))
    rng.shuffle(dense)
    cases.append(dense)

    sparse = []
    for seq in 'ABCD':
        count = rng.randint(2, 6)
        for idx in rng.sample(range(8), count):
            value = rng.randint(-700000, 700000) / 99991.0
            sparse.append((seq, idx, float(f'{value:.9f}')))
    rng.shuffle(sparse)
    cases.append(sparse)

    mixed = []
    for seq_index, seq in enumerate('ABCD'):
        indices = [0, 1, 3, 4, 6, 7] if seq_index % 2 == 0 else [0, 2, 3, 5, 7]
        for idx in indices:
            value = (rng.randint(-500000, 500000) + 137 * (seq_index + 1) * (idx + 1)) / 100019.0
            mixed.append((seq, idx, float(f'{value:.9f}')))
    rng.shuffle(mixed)
    cases.append(mixed)
    return cases


def candidate_source_sets():
    sources = sorted(
        str(p) for p in Path('/home/user').rglob('*')
        if p.is_file() and p.suffix.lower() == '.c'
    )
    assert sources, 'No C source file was found under /home/user.'

    candidates = [(source,) for source in sources]
    if len(sources) > 1:
        candidates.append(tuple(sources))
    return candidates


def compile_candidate(sources, executable):
    command = ['gcc', '-O2', *sources, '-lm', '-o', executable]
    try:
        result = subprocess.run(
            command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=20, check=False
        )
    except (subprocess.TimeoutExpired, OSError):
        return False
    return result.returncode == 0 and os.path.isfile(executable)


def candidate_passes(executable, cases):
    for rows in cases:
        write_dataset(rows)
        expected = expected_for_rows(rows)
        try:
            OUTPUT_PATH.unlink(missing_ok=True)
            result = subprocess.run(
                [executable], cwd='/home/user', stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=10, check=False
            )
        except (subprocess.TimeoutExpired, OSError):
            return False

        if result.returncode != 0 or not OUTPUT_PATH.is_file():
            return False
        actual = read_output_lines()
        if len(actual) != 4 or actual != expected:
            return False
    return True


def main():
    original_data = DATA_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.is_file() else None

    try:
        test_original_output()
        cases = make_cases()
        passed = False
        for number, sources in enumerate(candidate_source_sets()):
            executable = f'/tmp/submitted_cholesky_{number}'
            try:
                os.unlink(executable)
            except FileNotFoundError:
                pass
            if compile_candidate(sources, executable) and candidate_passes(executable, cases):
                passed = True
                break
        assert passed, 'No submitted C program compiled and correctly processed the supplied and randomized observational datasets.'
    finally:
        DATA_PATH.write_bytes(original_data)
        if original_output is None:
            OUTPUT_PATH.unlink(missing_ok=True)
        else:
            OUTPUT_PATH.write_bytes(original_output)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
