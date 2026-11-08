#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess

SOURCE = '/home/user/analyze.cpp'
BINARY = '/home/user/analyze'
RESULTS = '/home/user/results.txt'
SEQ_A = '/home/user/seqA.txt'
SEQ_B = '/home/user/seqB.txt'

ORIGINAL_A = ['ACGT', 'ATAT', 'CGCG', 'ACGT', 'ACGT']
ORIGINAL_B = ['GGCC', 'CGCG', 'ACGT', 'CCCG', 'CCGC']


def write_sequences(path, sequences):
    with open(path, 'w') as f:
        f.write('\n'.join(sequences) + '\n')


def run_program(group_a, group_b):
    write_sequences(SEQ_A, group_a)
    write_sequences(SEQ_B, group_b)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    proc = subprocess.run(
        [BINARY], cwd='/home/user', capture_output=True, text=True, timeout=10
    )
    assert proc.returncode == 0, (
        f'analyze exited with status {proc.returncode}. '
        f'stdout: {proc.stdout!r}; stderr: {proc.stderr!r}'
    )
    assert os.path.exists(RESULTS), (
        f'File {RESULTS} does not exist. The C++ program must generate this file.'
    )


def parse_results():
    with open(RESULTS, 'r') as f:
        content = f.read().strip()
    lines = content.split('\n')
    assert len(lines) >= 2, f'Expected at least 2 lines in {RESULTS}, got {len(lines)}.'
    parsed = {}
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            parsed[key.strip()] = val.strip()
    assert 't_stat' in parsed, "Missing 't_stat' in results.txt"
    assert 'jc_p' in parsed, "Missing 'jc_p' in results.txt"
    return parsed


def expected_values(group_a, group_b):
    def gc_values(group):
        return [sum(ch in 'GC' for ch in seq) / len(seq) for seq in group]

    a = gc_values(group_a)
    b = gc_values(group_b)
    mean_a = sum(a) / len(a)
    mean_b = sum(b) / len(b)
    var_a = sum((x - mean_a) ** 2 for x in a) / (len(a) - 1)
    var_b = sum((x - mean_b) ** 2 for x in b) / (len(b) - 1)
    t_stat = (mean_a - mean_b) / math.sqrt(var_a / len(a) + var_b / len(b))
    distance = abs(mean_a - mean_b)
    jc_p = 0.75 * (1.0 - math.exp((-4.0 / 3.0) * distance))
    return f'{t_stat:.4f}', f'{jc_p:.4f}'


def random_group(rng, count, low_gc, high_gc):
    group = []
    for _ in range(count):
        length = rng.randrange(9, 38)
        probability = low_gc + rng.random() * (high_gc - low_gc)
        sequence = []
        for _ in range(length):
            if rng.random() < probability:
                sequence.append(rng.choice('GC'))
            else:
                sequence.append(rng.choice('AT'))
        group.append(''.join(sequence))
    return group


def test_cpp_file_exists():
    path = '/home/user/analyze.cpp'
    assert os.path.exists(path), f"Source file {path} is missing."
    assert os.path.isfile(path), f"Source file {path} is not a regular file."


def test_compile_and_execute_cpp_program():
    compile_proc = subprocess.run(
        ['g++', '-std=c++17', SOURCE, '-o', BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_proc.returncode == 0, (
        f'analyze.cpp did not compile as C++17. stdout: {compile_proc.stdout!r}; '
        f'stderr: {compile_proc.stderr!r}'
    )
    mode = os.stat(BINARY).st_mode
    assert stat.S_ISREG(mode) and os.access(BINARY, os.X_OK), (
        f'{BINARY} is not an executable regular file.'
    )
    run_program(ORIGINAL_A, ORIGINAL_B)


def test_results_file_exists_and_correct():
    path = '/home/user/results.txt'
    assert os.path.exists(path), f"File {path} does not exist. The C++ program must generate this file."

    with open(path, 'r') as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) >= 2, f"Expected at least 2 lines in {path}, got {len(lines)}."

    results = {}
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            results[key.strip()] = val.strip()

    assert 't_stat' in results, "Missing 't_stat' in results.txt"
    assert 'jc_p' in results, "Missing 'jc_p' in results.txt"

    expected_t_stat = "-2.1381"
    expected_jc_p = "0.3100"

    assert results['t_stat'] == expected_t_stat, f"Expected t_stat to be {expected_t_stat}, got {results['t_stat']}"
    assert results['jc_p'] == expected_jc_p, f"Expected jc_p to be {expected_jc_p}, got {results['jc_p']}"


def test_program_computes_results_for_unseen_inputs():
    rng = secrets.SystemRandom()
    try:
        for _ in range(3):
            group_a = random_group(rng, rng.randrange(4, 9), 0.08, 0.42)
            group_b = random_group(rng, rng.randrange(4, 9), 0.58, 0.92)
            expected_t, expected_p = expected_values(group_a, group_b)
            run_program(group_a, group_b)
            results = parse_results()
            assert results['t_stat'] == expected_t, (
                f"Expected t_stat {expected_t} for generated input, got {results['t_stat']}"
            )
            assert results['jc_p'] == expected_p, (
                f"Expected jc_p {expected_p} for generated input, got {results['jc_p']}"
            )
    finally:
        write_sequences(SEQ_A, ORIGINAL_A)
        write_sequences(SEQ_B, ORIGINAL_B)
        if os.path.exists(BINARY):
            run_program(ORIGINAL_A, ORIGINAL_B)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
