#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess
from pathlib import Path

import pytest

CPP_PATH = Path('/home/user/bootstrap.cpp')
SH_PATH = Path('/home/user/run_analysis.sh')
DATA_PATH = Path('/home/user/data.txt')
INDICES_PATH = Path('/home/user/indices.txt')
CI_PATH = Path('/home/user/ci.txt')
EXE_PATH = Path('/home/user/bootstrap_calc')


def parse_ci(path):
    content = Path(path).read_text()
    lower_match = re.search(r"Lower CI:\s*([0-9.]+)", content)
    upper_match = re.search(r"Upper CI:\s*([0-9.]+)", content)
    assert lower_match, "Could not parse 'Lower CI: <value>' from ci.txt"
    assert upper_match, "Could not parse 'Upper CI: <value>' from ci.txt"
    return float(lower_match.group(1)), float(upper_match.group(1))


def test_bootstrap_cpp_exists_and_contains_openmp():
    assert CPP_PATH.is_file(), f'Missing file: {CPP_PATH}'
    assert stat.S_ISREG(CPP_PATH.stat().st_mode), f'{CPP_PATH} is not a regular file'
    content = CPP_PATH.read_text()
    assert '#pragma omp parallel for' in content, \
        "bootstrap.cpp does not contain OpenMP pragma '#pragma omp parallel for'."


def test_run_analysis_sh_exists_and_valid():
    assert SH_PATH.is_file(), f'Missing file: {SH_PATH}'
    assert stat.S_ISREG(SH_PATH.stat().st_mode), f'{SH_PATH} is not a regular file'
    content = SH_PATH.read_text()
    assert '-fopenmp' in content, 'run_analysis.sh does not compile with -fopenmp.'
    assert 'g++' in content, 'run_analysis.sh does not use g++ to compile.'
    assert '-O2' in content, 'run_analysis.sh does not compile with -O2.'
    assert re.search(r'(^|[^A-Za-z0-9_])sort([^A-Za-z0-9_]|$)', content), \
        'run_analysis.sh does not use sort to order the bootstrap means.'


def test_cpp_reads_inputs_and_emits_10000_ordered_means():
    candidate = Path('/tmp/bootstrap_candidate')
    compile_result = subprocess.run(
        ['g++', '-O2', '-fopenmp', str(CPP_PATH), '-o', str(candidate)],
        capture_output=True, text=True, timeout=60
    )
    assert compile_result.returncode == 0, \
        f'bootstrap.cpp failed to compile.\nStderr: {compile_result.stderr}'

    original_data = DATA_PATH.read_bytes()
    original_indices = INDICES_PATH.read_bytes()
    rng = random.SystemRandom()
    data = [round(rng.uniform(1.0, 100.0), 4) for _ in range(100)]
    expected = []

    try:
        DATA_PATH.write_text(''.join(f'{value:.4f}\n' for value in data))
        with INDICES_PATH.open('w') as index_file:
            for _ in range(10000):
                indices = [rng.randrange(100) for _ in range(100)]
                index_file.write(' '.join(map(str, indices)) + '\n')
                expected.append(sum(data[i] for i in indices) / 100.0)

        result = subprocess.run(
            [str(candidate)], cwd='/home/user', capture_output=True,
            text=True, timeout=60
        )
        assert result.returncode == 0, \
            f'Compiled bootstrap program failed.\nStderr: {result.stderr}'
        lines = result.stdout.splitlines()
        assert len(lines) == 10000, \
            f'Expected exactly 10000 output means, got {len(lines)}.'
        try:
            actual = [float(line.strip()) for line in lines]
        except ValueError as exc:
            pytest.fail(f'Bootstrap output contains a non-numeric line: {exc}')

        for position, (got, wanted) in enumerate(zip(actual, expected), 1):
            assert math.isclose(got, wanted, rel_tol=2e-5, abs_tol=2e-4), \
                f'Mean on output line {position} is wrong or out of order: expected {wanted}, got {got}'
    finally:
        DATA_PATH.write_bytes(original_data)
        INDICES_PATH.write_bytes(original_indices)


def test_script_compiles_runs_and_sorts_program_output():
    original_source = CPP_PATH.read_bytes()
    probe_source = r'''#include <iostream>
#include <vector>
int main() {
    std::vector<int> values(10000);
#pragma omp parallel for
    for (int i = 0; i < 10000; ++i) {
        values[i] = (i * 7919) % 10000;
    }
    for (int value : values) {
        std::cout << value << "\n";
    }
    return 0;
}
'''
    expected_raw = [(i * 7919) % 10000 for i in range(10000)]

    try:
        CPP_PATH.write_text(probe_source)
        result = subprocess.run(
            ['bash', str(SH_PATH)], cwd='/home/user', capture_output=True,
            text=True, timeout=60
        )
        assert result.returncode == 0, \
            f'run_analysis.sh failed on controlled program output.\nStderr: {result.stderr}'
        assert CI_PATH.is_file(), f'run_analysis.sh did not create {CI_PATH}.'

        lower, upper = parse_ci(CI_PATH)
        assert math.isclose(lower, 249.0, abs_tol=1e-9), \
            f'Script did not numerically sort/extract the 250th program value; got {lower}.'
        assert math.isclose(upper, 9749.0, abs_tol=1e-9), \
            f'Script did not numerically sort/extract the 9750th program value; got {upper}.'

        assert EXE_PATH.is_file() and os.access(EXE_PATH, os.X_OK), \
            'run_analysis.sh did not create an executable /home/user/bootstrap_calc.'
        linked = subprocess.run(['ldd', str(EXE_PATH)], capture_output=True, text=True)
        assert linked.returncode == 0 and 'libgomp' in linked.stdout, \
            'The executable produced by run_analysis.sh is not linked with OpenMP.'

        found_saved_means = False
        excluded = {CPP_PATH, SH_PATH, DATA_PATH, INDICES_PATH, CI_PATH, EXE_PATH}
        for path in Path('/home/user').rglob('*'):
            if path in excluded or not path.is_file():
                continue
            try:
                if path.stat().st_size > 1000000:
                    continue
                tokens = path.read_text().split()
                if len(tokens) != 10000:
                    continue
                values = [float(token) for token in tokens]
            except (OSError, UnicodeError, ValueError):
                continue
            if all(value == expected for value, expected in zip(values, expected_raw)):
                found_saved_means = True
                break
        assert found_saved_means, \
            'run_analysis.sh did not save the executable\'s 10000 means in their emitted order.'
    finally:
        CPP_PATH.write_bytes(original_source)


def test_run_analysis_and_check_ci():
    result = subprocess.run(
        ['bash', str(SH_PATH)], cwd='/home/user', capture_output=True,
        text=True, timeout=120
    )
    assert result.returncode == 0, \
        f'run_analysis.sh failed with return code {result.returncode}.\nStderr: {result.stderr}'
    assert CI_PATH.is_file(), f'run_analysis.sh did not create {CI_PATH}.'

    with DATA_PATH.open() as f:
        data = [float(line.strip()) for line in f if line.strip()]

    means = []
    with INDICES_PATH.open() as f:
        for line in f:
            if not line.strip():
                continue
            indices = [int(x) for x in line.strip().split()]
            means.append(sum(data[i] for i in indices) / len(indices))

    means.sort()
    expected_lower = means[249]
    expected_upper = means[9749]
    actual_lower, actual_upper = parse_ci(CI_PATH)

    assert math.isclose(actual_lower, expected_lower, rel_tol=1e-4), \
        f'Lower CI mismatch. Expected ~{expected_lower}, got {actual_lower}'
    assert math.isclose(actual_upper, expected_upper, rel_tol=1e-4), \
        f'Upper CI mismatch. Expected ~{expected_upper}, got {actual_upper}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
