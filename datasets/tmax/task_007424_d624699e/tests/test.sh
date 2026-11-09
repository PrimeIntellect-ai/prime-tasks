#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import secrets
import statistics
import subprocess

import pytest

SCRIPT_PATH = '/home/user/profile_gc.py'
DATASET_PATH = '/home/user/dataset.fasta'
REPORT_PATH = '/home/user/report.txt'


def run_script(timeout=60):
    return subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def read_report():
    with open(REPORT_PATH, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."


def test_script_structure():
    with open(SCRIPT_PATH, 'r') as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    constants = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    constants[target.id] = node.value.value

    multiprocessing_aliases = set()
    imported_pool_names = set()
    pvariance_names = set()
    statistics_aliases = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing':
                    multiprocessing_aliases.add(alias.asname or alias.name)
                if alias.name == 'statistics':
                    statistics_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module == 'multiprocessing':
                for alias in node.names:
                    if alias.name == 'Pool':
                        imported_pool_names.add(alias.asname or alias.name)
            if node.module == 'statistics':
                for alias in node.names:
                    if alias.name == 'pvariance':
                        pvariance_names.add(alias.asname or alias.name)

    def value_of(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Name):
            return constants.get(node.id)
        return None

    pool_calls = []
    sum_calls = []
    pvariance_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue

        is_pool = (
            isinstance(node.func, ast.Name)
            and node.func.id in imported_pool_names
        ) or (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == 'Pool'
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in multiprocessing_aliases
        )
        if is_pool:
            pool_calls.append(node)

        if isinstance(node.func, ast.Name) and node.func.id == 'sum':
            sum_calls.append(node)

        is_pvariance = (
            isinstance(node.func, ast.Name)
            and node.func.id in pvariance_names
        ) or (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == 'pvariance'
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in statistics_aliases
        )
        if is_pvariance:
            pvariance_calls.append(node)

    assert pool_calls, 'The script must use multiprocessing.Pool.'
    for call in pool_calls:
        process_value = value_of(call.args[0]) if call.args else None
        for keyword in call.keywords:
            if keyword.arg == 'processes':
                process_value = value_of(keyword.value)
        assert process_value == 4, 'Every multiprocessing.Pool must explicitly use exactly 4 worker processes.'

    assert sum_calls, 'The naive variance calculation must use built-in sum().' 
    assert pvariance_calls, 'The stable variance calculation must use statistics.pvariance().' 

    has_main_guard = False
    for node in tree.body:
        if not isinstance(node, ast.If) or not isinstance(node.test, ast.Compare):
            continue
        comparison = node.test
        if (
            isinstance(comparison.left, ast.Name)
            and comparison.left.id == '__name__'
            and len(comparison.ops) == 1
            and isinstance(comparison.ops[0], ast.Eq)
            and len(comparison.comparators) == 1
            and isinstance(comparison.comparators[0], ast.Constant)
            and comparison.comparators[0].value == '__main__'
        ):
            has_main_guard = True
    assert has_main_guard, 'The multiprocessing script must use an if __name__ == "__main__" guard.'


def test_script_executes():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = run_script()
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(REPORT_PATH), 'Executing the script did not create report.txt.'


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"The path {REPORT_PATH} is not a file."


def test_report_content():
    lines = read_report()

    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_PATH}, found {len(lines)}."

    naive_match = re.match(r'^Naive:\s*([+-]?\d*\.\d+e[+-]\d+)$', lines[0], re.IGNORECASE)
    assert naive_match, f"Line 1 does not match the expected format 'Naive: <value>': {lines[0]}"

    stable_match = re.match(r'^Stable:\s*([+-]?\d*\.\d+e[+-]\d+)$', lines[1], re.IGNORECASE)
    assert stable_match, f"Line 2 does not match the expected format 'Stable: <value>': {lines[1]}"

    naive_val = float(naive_match.group(1))
    stable_val = float(stable_match.group(1))

    assert naive_val == 0.0, f"Expected Naive variance to be 0.0, got {naive_val}"
    assert abs(stable_val - 9.99e-08) < 1e-10, f"Expected Stable variance to be approx 9.99e-08, got {stable_val}"

    # Also check the exact formatting to 10 decimal places in scientific notation
    assert "0.0000000000e+00" in lines[0] or "0.0000000000e-00" in lines[0] or naive_match.group(1) == "0.0000000000e+00", f"Naive value not formatted to 10 decimal places in scientific notation: {lines[0]}"
    assert "9.9900000000e-08" in lines[1], f"Stable value not formatted to 10 decimal places in scientific notation: {lines[1]}"


def test_script_computes_a_fresh_random_dataset():
    with open(DATASET_PATH, 'rb') as f:
        original_dataset = f.read()

    rng = random.Random(secrets.randbits(128))
    sequences = []
    fasta_parts = []
    alphabet = 'ACGT'
    for index in range(173):
        length = rng.randint(31, 229)
        sequence = ''.join(rng.choice(alphabet) for _ in range(length))
        sequences.append(sequence)
        fasta_parts.append(f'>random_{index}\n')
        position = 0
        while position < length:
            width = rng.randint(7, 41)
            fasta_parts.append(sequence[position:position + width] + '\n')
            position += width

    ratios = [(seq.count('G') + seq.count('C')) / len(seq) for seq in sequences]
    shifted = [ratio + 100000000.0 for ratio in ratios]
    expected_naive = sum(x * x for x in shifted) / len(shifted) - (sum(shifted) / len(shifted)) ** 2
    expected_stable = statistics.pvariance(shifted)
    expected_lines = [
        f'Naive: {expected_naive:.10e}',
        f'Stable: {expected_stable:.10e}',
    ]

    try:
        with open(DATASET_PATH, 'w') as f:
            f.writelines(fasta_parts)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        result = run_script()
        assert result.returncode == 0, (
            f'The script failed on a fresh FASTA dataset.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert os.path.isfile(REPORT_PATH), 'The script did not generate a fresh report.'
        assert read_report() == expected_lines, (
            'The report does not match variances derived from a fresh randomized, multiline FASTA dataset.'
        )
    finally:
        with open(DATASET_PATH, 'wb') as f:
            f.write(original_dataset)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
