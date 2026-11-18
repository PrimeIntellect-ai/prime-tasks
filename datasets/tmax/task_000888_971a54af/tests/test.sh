#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
from pathlib import Path
import random
import re
import subprocess
import pytest

HOME = Path('/home/user')
PRIMER = 'ATGCGTACG'


def calculate_score(seq, primer):
    max_score = -len(primer)
    for i in range(len(seq) - len(primer) + 1):
        window = seq[i:i+len(primer)]
        matches = sum(1 for a, b in zip(window, primer) if a == b)
        mismatches = len(primer) - matches
        score = matches - mismatches
        if score > max_score:
            max_score = score
    return max_score


def get_scores(fasta_path, primer):
    scores = []
    with open(fasta_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('>'):
                scores.append(calculate_score(line, primer))
    return scores


def calc_stats(scores_A, scores_B):
    mean_A = sum(scores_A) / len(scores_A)
    mean_B = sum(scores_B) / len(scores_B)
    var_A = sum((x - mean_A)**2 for x in scores_A) / (len(scores_A) - 1) if len(scores_A) > 1 else 0
    var_B = sum((x - mean_B)**2 for x in scores_B) / (len(scores_B) - 1) if len(scores_B) > 1 else 0
    t_stat = (mean_A - mean_B) / math.sqrt(var_A / len(scores_A) + var_B / len(scores_B))
    return mean_A, mean_B, t_stat


def write_fasta(path, prefix, sequences):
    with open(path, 'w') as f:
        for i, sequence in enumerate(sequences):
            f.write(f'>{prefix}{i}\n{sequence}\n')


def random_case():
    rng = random.SystemRandom()
    while True:
        groups = []
        for _ in range(2):
            sequences = []
            for _ in range(rng.randint(4, 7)):
                length = rng.randint(len(PRIMER), 36)
                sequences.append(''.join(rng.choice('ACGT') for _ in range(length)))
            groups.append(sequences)
        scores_a = [calculate_score(s, PRIMER) for s in groups[0]]
        scores_b = [calculate_score(s, PRIMER) for s in groups[1]]
        mean_a = sum(scores_a) / len(scores_a)
        mean_b = sum(scores_b) / len(scores_b)
        var_a = sum((x - mean_a) ** 2 for x in scores_a) / (len(scores_a) - 1)
        var_b = sum((x - mean_b) ** 2 for x in scores_b) / (len(scores_b) - 1)
        if var_a / len(scores_a) + var_b / len(scores_b) > 0:
            return groups


def run_program_and_check(expected):
    result_path = HOME / 'analysis_result.txt'
    if result_path.exists():
        result_path.unlink()
    completed = subprocess.run(
        [str(HOME / 'primer_test')], cwd=str(HOME),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode == 0, f'primer_test failed: {completed.stderr}'
    assert result_path.is_file(), 'primer_test did not create analysis_result.txt'
    content = result_path.read_text()
    match = re.fullmatch(
        r'Mean A: (-?\d+\.\d{4})\nMean B: (-?\d+\.\d{4})\nt-statistic: (-?\d+\.\d{4})\n?',
        content
    )
    assert match is not None, 'Program output does not exactly follow the required three-line, four-decimal format'
    actual = tuple(float(value) for value in match.groups())
    for name, got, want in zip(('Mean A', 'Mean B', 't-statistic'), actual, expected):
        assert got == pytest.approx(want, abs=1e-3), f'{name} is incorrect: expected {want:.4f}, got {got}'


def test_00_build_and_execute_c_pipeline_on_unseen_inputs():
    makefile = HOME / 'Makefile'
    executable = HOME / 'primer_test'
    pop_a = HOME / 'pop_A.fasta'
    pop_b = HOME / 'pop_B.fasta'

    assert makefile.is_file(), f'Makefile not found at {makefile}'
    c_sources = [p for p in HOME.rglob('*.c') if p.is_file()]
    assert c_sources, 'No C source file was provided under /home/user'

    if executable.exists() or executable.is_symlink():
        executable.unlink()
    built = subprocess.run(
        ['make', '-B', '-C', str(HOME)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert built.returncode == 0, f'Makefile build failed:\n{built.stdout}\n{built.stderr}'
    assert executable.is_file(), 'Makefile did not build /home/user/primer_test'
    assert os.access(executable, os.X_OK), 'Built primer_test is not executable'
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'primer_test is not a compiled native executable'

    original_a = pop_a.read_bytes()
    original_b = pop_b.read_bytes()
    try:
        for round_number in range(2):
            sequences_a, sequences_b = random_case()
            write_fasta(pop_a, f'randomA{round_number}_', sequences_a)
            write_fasta(pop_b, f'randomB{round_number}_', sequences_b)
            expected = calc_stats(
                [calculate_score(s, PRIMER) for s in sequences_a],
                [calculate_score(s, PRIMER) for s in sequences_b]
            )
            run_program_and_check(expected)
    finally:
        pop_a.write_bytes(original_a)
        pop_b.write_bytes(original_b)
        subprocess.run([str(executable)], cwd=str(HOME), stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=15)


def test_makefile_and_executable_exist():
    """Test that the Makefile and compiled executable exist."""
    makefile_path = "/home/user/Makefile"
    executable_path = "/home/user/primer_test"

    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"
    assert os.path.isfile(executable_path), f"Executable not found at {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File at {executable_path} is not executable"


def test_analysis_result_exists():
    """Test that the analysis_result.txt file exists."""
    result_path = "/home/user/analysis_result.txt"
    assert os.path.isfile(result_path), f"Output file not found at {result_path}"


def test_analysis_result_content():
    """Test that the analysis_result.txt contains the correct computed values."""
    pop_a_path = "/home/user/pop_A.fasta"
    pop_b_path = "/home/user/pop_B.fasta"
    result_path = "/home/user/analysis_result.txt"
    primer = "ATGCGTACG"

    scores_A = get_scores(pop_a_path, primer)
    scores_B = get_scores(pop_b_path, primer)
    expected_mean_A, expected_mean_B, expected_t_stat = calc_stats(scores_A, scores_B)

    with open(result_path, 'r') as f:
        content = f.read()

    match_A = re.search(r"Mean A:\s*([-\d.]+)", content)
    match_B = re.search(r"Mean B:\s*([-\d.]+)", content)
    match_t = re.search(r"t-statistic:\s*([-\d.]+)", content)

    assert match_A is not None, "Could not find 'Mean A: [value]' in analysis_result.txt"
    assert match_B is not None, "Could not find 'Mean B: [value]' in analysis_result.txt"
    assert match_t is not None, "Could not find 't-statistic: [value]' in analysis_result.txt"

    actual_mean_A = float(match_A.group(1))
    actual_mean_B = float(match_B.group(1))
    actual_t_stat = float(match_t.group(1))

    assert actual_mean_A == pytest.approx(expected_mean_A, abs=1e-3), f"Mean A is incorrect. Expected {expected_mean_A:.4f}, got {actual_mean_A}"
    assert actual_mean_B == pytest.approx(expected_mean_B, abs=1e-3), f"Mean B is incorrect. Expected {expected_mean_B:.4f}, got {actual_mean_B}"
    assert actual_t_stat == pytest.approx(expected_t_stat, abs=1e-3), f"t-statistic is incorrect. Expected {expected_t_stat:.4f}, got {actual_t_stat}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
