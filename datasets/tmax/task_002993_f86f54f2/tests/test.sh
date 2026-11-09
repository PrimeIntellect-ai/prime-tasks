#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/mcmc')
OUTPUT = PROJECT / 'cov.json'
BINARY = Path('/tmp/mcmc_submission')


@pytest.fixture(scope='session', autouse=True)
def verify_and_run_go_project():
    assert PROJECT.is_dir(), f'Missing Go project directory: {PROJECT}'

    go_files = sorted(PROJECT.rglob('*.go'))
    assert go_files, 'The project must contain Go source files.'
    assert all(path.is_file() for path in go_files), 'Every discovered Go source path must be a regular file.'

    source = '\n'.join(path.read_text(errors='replace') for path in go_files)
    clean = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    clean = re.sub(r'//[^\n]*', '', clean)
    lower = clean.lower()

    assert re.search(r'\bpackage\s+main\b', clean), 'A runnable Go main package is required.'
    assert re.search(r'\bfunc\s+main\s*\(', clean), 'A Go main function is required.'
    assert re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_])', clean), 'The sampler must launch chains with a Go goroutine.'
    assert re.search(r'(?:chain\w*|nchains|numchains)[^\n]{0,80}\b4\b|\b4\s*(?:chains?)', lower), \
        'The source must configure exactly four chains.'

    numeric_literals = [int(token.replace('_', '')) for token in re.findall(r'\b[0-9][0-9_]*\b', clean)]
    assert any(value >= 500000 for value in numeric_literals), \
        'The source must configure at least 500,000 samples per chain.'
    assert re.search(r'\b(sample|samples|draw|draws|iteration|iterations)\w*\b', lower), \
        'The configured sample count must be part of sampler code.'
    assert re.search(r'\bburn(?:in)?\w*\b', lower), 'The sampler must implement a burn-in period.'
    assert re.search(r'\bfor\s+', clean), 'The sampler must contain an iterative sampling loop.'

    assert ('math/rand' in source or 'math/rand/v2' in source), 'Use a standard-library random generator for MCMC.'
    assert re.search(r'\b(?:normfloat64|float64)\s*\(', lower), 'The sampler must draw random proposal or acceptance values.'
    assert re.search(r'\b(?:rand\.)?newsource\s*\(|\brand\.new\s*\(', lower), \
        'Independent chains must use independently constructed random generators.'
    assert re.search(r'\bseed\w*\b', lower), 'Independent deterministic chain seeds are required.'
    assert re.search(r'\bmath\.(?:exp|log)\s*\(', lower), \
        'Metropolis-Hastings acceptance must use the target density or log density.'

    stable_terms = r'\b(?:welford|kahan|neumaier|compens\w*|pairwise|twopass|two_pass|fixedorder|fixed_order|m2\w*)\b'
    assert re.search(stable_terms, lower), \
        'The covariance reduction must use a deterministic, numerically stable method such as Welford, Kahan, or pairwise/two-pass reduction.'

    if (PROJECT / 'go.mod').is_file():
        modules = subprocess.run(
            ['go', 'list', '-m', 'all'], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert modules.returncode == 0, f'Unable to inspect Go module dependencies:\n{modules.stdout}'
        module_lines = [line for line in modules.stdout.splitlines() if line.strip()]
        assert len(module_lines) == 1, 'Only the Go standard library may be used; external module dependencies were found.'
        build_cmd = ['go', 'build', '-trimpath', '-o', str(BINARY), '.']
    else:
        top_level = sorted(str(path) for path in PROJECT.glob('*.go') if not path.name.endswith('_test.go'))
        assert top_level, 'A module file or buildable top-level Go main package is required.'
        build_cmd = ['go', 'build', '-trimpath', '-o', str(BINARY)] + top_level

    build = subprocess.run(
        build_cmd, cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert build.returncode == 0, f'The Go project does not build:\n{build.stdout}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Go build did not produce an executable artifact.'

    results = []
    for run_number in (1, 2):
        if OUTPUT.exists():
            OUTPUT.unlink()
        run = subprocess.run(
            [str(BINARY)], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240
        )
        assert run.returncode == 0, f'MCMC executable failed on run {run_number}:\n{run.stdout}'
        assert OUTPUT.is_file(), f'MCMC executable did not create {OUTPUT} on run {run_number}.'
        try:
            with OUTPUT.open() as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            pytest.fail(f'Executable produced invalid JSON on run {run_number}: {exc}')
        results.append((data.get('var_x'), data.get('var_y'), data.get('cov_xy')))

    assert results[0] == results[1], \
        f'Repeated executions were not deterministic: first={results[0]}, second={results[1]}'


def test_cov_json_exists():
    """Check that the output JSON file exists."""
    output_file = '/home/user/mcmc/cov.json'
    assert os.path.exists(output_file), f'Missing required output file: {output_file}'
    assert os.path.isfile(output_file), f'Expected a file at {output_file}'


def test_cov_json_format_and_keys():
    """Check that the JSON file has the correct keys and numeric values."""
    output_file = '/home/user/mcmc/cov.json'

    try:
        with open(output_file, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {output_file} is not valid JSON.')

    expected_keys = {'var_x', 'var_y', 'cov_xy'}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f'JSON file is missing keys: {missing_keys}'

    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f'Value for {key} must be a number, got {type(data[key])}'


def test_covariance_accuracy():
    """Evaluate the accuracy of the estimated covariance matrix using SSE."""
    output_file = '/home/user/mcmc/cov.json'

    with open(output_file, 'r') as f:
        data = json.load(f)

    true_var_x = 5.0 / 14.0
    true_var_y = 3.0 / 14.0
    true_cov_xy = 1.0 / 14.0

    sse = (data['var_x'] - true_var_x)**2 + \
          (data['var_y'] - true_var_y)**2 + \
          (data['cov_xy'] - true_cov_xy)**2

    threshold = 0.001

    assert sse <= threshold, (
        f'Sum of Squared Errors (SSE) is too high. '
        f'Got SSE={sse:.6f}, expected <={threshold}. '
        f'Estimated: var_x={data["var_x"]}, var_y={data["var_y"]}, cov_xy={data["cov_xy"]}. '
        f'True: var_x={true_var_x}, var_y={true_var_y}, cov_xy={true_cov_xy}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
