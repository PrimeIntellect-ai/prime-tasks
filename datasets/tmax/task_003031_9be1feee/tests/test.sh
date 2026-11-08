#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import os
import multiprocessing.process

_original_start = multiprocessing.process.BaseProcess.start

def _verified_start(self, *args, **kwargs):
    result = _original_start(self, *args, **kwargs)
    log_path = os.environ.get('VERIFIER_MP_LOG')
    if log_path:
        try:
            fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            try:
                os.write(fd, (str(getattr(self, 'pid', 'unknown')) + '\n').encode())
            finally:
                os.close(fd)
        except OSError:
            pass
    return result

multiprocessing.process.BaseProcess.start = _verified_start
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import subprocess
from pathlib import Path

import pytest


def parse_fasta(filepath):
    lengths = []
    gc_ratios = []
    with open(filepath, 'r') as f:
        seq = ""
        for line in f:
            if line.startswith(">"):
                if seq:
                    lengths.append(len(seq))
                    gc_ratios.append((seq.count('G') + seq.count('C')) / len(seq))
                    seq = ""
            else:
                seq += line.strip()
        if seq:
            lengths.append(len(seq))
            gc_ratios.append((seq.count('G') + seq.count('C')) / len(seq))
    return lengths, gc_ratios


def linear_regression(x, y):
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_x2 = sum(xi * xi for xi in x)
    sum_xy = sum(xi * yi for xi, yi in zip(x, y))

    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x ** 2)
    intercept = (sum_y - slope * sum_x) / n
    return slope, intercept


def python_sources():
    sources = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file():
            continue
        try:
            first_line = path.open('r', errors='ignore').readline()
        except OSError:
            continue
        if path.suffix == '.py' or (first_line.startswith('#!') and 'python' in first_line.lower()):
            sources.append(path)
    return sources


def imports_multiprocessing(path):
    try:
        tree = ast.parse(path.read_text(errors='ignore'), filename=str(path))
    except (OSError, SyntaxError):
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == 'multiprocessing' or alias.name.startswith('multiprocessing.') for alias in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == 'multiprocessing' or node.module.startswith('multiprocessing.')):
                return True
    return False


def result_is_correct():
    results_path = '/home/user/regression_results.txt'
    if not os.path.isfile(results_path):
        return False
    try:
        content = Path(results_path).read_text().strip()
    except OSError:
        return False
    lines = content.split('\n')
    if len(lines) != 2:
        return False
    slope_match = re.match(r'^slope:\s*(-?\d+\.\d{6})$', lines[0])
    intercept_match = re.match(r'^intercept:\s*(-?\d+\.\d{6})$', lines[1])
    if not slope_match or not intercept_match:
        return False
    lengths, gc_ratios = parse_fasta('/home/user/sequences.fasta')
    slope, intercept = linear_regression(lengths, gc_ratios)
    return (slope_match.group(1) == f'{slope:.6f}' and
            intercept_match.group(1) == f'{intercept:.6f}')


@pytest.fixture(scope='module', autouse=True)
def execute_user_script():
    sources = python_sources()
    assert sources, 'No Python script was found under /home/user.'
    assert any(imports_multiprocessing(path) for path in sources), \
        "The submitted Python source does not import the required multiprocessing module."

    results_path = Path('/home/user/regression_results.txt')
    mp_log = Path('/tmp/verifier_mp_starts.log')
    failures = []

    for script in sources:
        results_path.unlink(missing_ok=True)
        mp_log.unlink(missing_ok=True)
        env = os.environ.copy()
        env['PYTHONPATH'] = '/tmp/verifier_hook' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['VERIFIER_MP_LOG'] = str(mp_log)
        try:
            completed = subprocess.run(
                ['python3', str(script)],
                cwd='/home/user',
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=120,
                check=False,
            )
        except subprocess.TimeoutExpired:
            failures.append(f'{script}: timed out')
            continue

        try:
            starts = [line for line in mp_log.read_text().splitlines() if line.strip()]
        except OSError:
            starts = []

        if completed.returncode == 0 and len(starts) >= 2 and result_is_correct():
            return
        failures.append(f'{script}: exit={completed.returncode}, worker_starts={len(starts)}')

    pytest.fail('No submitted Python script both produced the correct result and started at least two multiprocessing workers. ' + '; '.join(failures))


def test_regression_results():
    fasta_path = '/home/user/sequences.fasta'
    results_path = '/home/user/regression_results.txt'

    assert os.path.exists(results_path), f"The file {results_path} does not exist."
    assert os.path.isfile(results_path), f"{results_path} is not a valid file."

    with open(results_path, 'r') as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) == 2, f"Expected exactly 2 lines in {results_path}, but found {len(lines)}."

    slope_match = re.match(r'^slope:\s*(-?\d+\.\d{6})$', lines[0])
    intercept_match = re.match(r'^intercept:\s*(-?\d+\.\d{6})$', lines[1])

    assert slope_match, f"The first line of {results_path} is not correctly formatted. Expected 'slope: <value>' with 6 decimal places, got '{lines[0]}'."
    assert intercept_match, f"The second line of {results_path} is not correctly formatted. Expected 'intercept: <value>' with 6 decimal places, got '{lines[1]}'."

    user_slope = slope_match.group(1)
    user_intercept = intercept_match.group(1)

    lengths, gc_ratios = parse_fasta(fasta_path)
    expected_slope_val, expected_intercept_val = linear_regression(lengths, gc_ratios)

    expected_slope = f"{expected_slope_val:.6f}"
    expected_intercept = f"{expected_intercept_val:.6f}"

    assert user_slope == expected_slope, f"Calculated slope is incorrect. Expected {expected_slope}, got {user_slope}."
    assert user_intercept == expected_intercept, f"Calculated intercept is incorrect. Expected {expected_intercept}, got {user_intercept}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
