#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
from collections import Counter
from pathlib import Path

import pytest

HOME = Path('/home/user')
REF_PATH = HOME / 'reference.fasta'
SAMPLES_PATH = HOME / 'samples.fasta'
RESULT_PATH = HOME / 'analysis_result.json'
VENV_PYTHON = HOME / 'bio_env/bin/python'
if not VENV_PYTHON.is_file():
    VENV_PYTHON = HOME / 'bio_env/bin/python3'


def read_fasta(path):
    seqs = []
    seq = ''
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if seq:
                    seqs.append(seq)
                    seq = ''
            else:
                seq += line
        if seq:
            seqs.append(seq)
    return seqs


def compute_mismatches(ref, samples):
    return [sum(1 for a, b in zip(ref, sample) if a != b) for sample in samples]


def exact_posterior_expectation(counts):
    return (2 + sum(counts)) / (1 + len(counts))


def compute_longest_primer(ref, samples):
    max_len = 0
    best_primer = ''
    for i in range(len(ref)):
        for j in range(i + 1, len(ref) + 1):
            sub = ref[i:j]
            if all(sample[i:j] == sub for sample in samples):
                if j - i > max_len:
                    max_len = j - i
                    best_primer = sub
    return best_primer


def validate_result(result, ref, samples):
    assert isinstance(result, dict)
    assert 'mismatch_counts' in result, "Key 'mismatch_counts' missing from JSON."
    assert 'mcmc_posterior_mean' in result, "Key 'mcmc_posterior_mean' missing from JSON."
    assert 'conserved_primer' in result, "Key 'conserved_primer' missing from JSON."

    expected_counts = compute_mismatches(ref, samples)
    expected_primer = compute_longest_primer(ref, samples)
    assert result['mismatch_counts'] == expected_counts, (
        f"Mismatch counts are incorrect. Expected {expected_counts}, "
        f"got {result['mismatch_counts']}"
    )
    assert result['conserved_primer'] == expected_primer, (
        f"Conserved primer is incorrect. Expected '{expected_primer}', "
        f"got '{result['conserved_primer']}'"
    )

    mean = result['mcmc_posterior_mean']
    assert isinstance(mean, (int, float)) and not isinstance(mean, bool)
    assert math.isfinite(mean)
    assert abs(mean * 10 - round(mean * 10)) < 1e-9, (
        'mcmc_posterior_mean must be rounded to one decimal place'
    )
    # This is a stochastic sample statistic, so do not require equality with the
    # conjugate expectation. Fifty thousand draws should nevertheless put it close.
    target = exact_posterior_expectation(expected_counts)
    assert abs(mean - target) <= 0.2, (
        f'MCMC posterior mean {mean} is not plausibly close to posterior expectation {target:.3f}'
    )


def user_python_files():
    files = []
    for path in HOME.rglob('*.py'):
        text = str(path)
        if '/bio_env/' in text or '/.cache/' in text or '__pycache__' in text:
            continue
        if path.is_file() and path.stat().st_size <= 1_000_000:
            files.append(path)
    return sorted(files)


def run_with_trace(script, trace_path):
    wrapper = Path('/tmp/run_user_analysis.py')
    wrapper.write_text(r'''
import json
import os
import runpy
import sys
from collections import Counter

script = os.path.abspath(sys.argv[1])
trace_path = sys.argv[2]
counts = Counter()

def tracer(frame, event, arg):
    if event == 'line':
        filename = os.path.abspath(frame.f_code.co_filename)
        if filename.startswith('/home/user/') and '/bio_env/' not in filename:
            counts[(filename, frame.f_lineno)] += 1
    return tracer

status = None
sys.settrace(tracer)
try:
    runpy.run_path(script, run_name='__main__')
except SystemExit as exc:
    if exc.code not in (None, 0):
        status = exc
finally:
    sys.settrace(None)
    with open(trace_path, 'w') as f:
        json.dump([[name, line, count] for (name, line), count in counts.items()], f)
if status is not None:
    raise status
''')
    env = os.environ.copy()
    env['PYTHONHASHSEED'] = '0'
    subprocess.run(
        [str(VENV_PYTHON), str(wrapper), str(script), str(trace_path)],
        cwd=str(script.parent), env=env, timeout=180, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    with open(trace_path, 'r') as f:
        entries = json.load(f)
    return {(os.path.abspath(name), int(line)): int(count) for name, line, count in entries}


def has_executed_mh_sampling(trace):
    rng_names = {
        'random', 'rand', 'randn', 'normal', 'uniform', 'gauss',
        'standard_normal', 'random_sample', 'exponential'
    }
    loop_sites = []
    rng_sites = []
    record_sites = []

    traced_files = {name for name, _ in trace}
    for filename in traced_files:
        path = Path(filename)
        if not path.is_file() or '/bio_env/' in filename:
            continue
        try:
            tree = ast.parse(path.read_text(), filename=filename)
        except (SyntaxError, UnicodeDecodeError):
            continue

        for node in ast.walk(tree):
            if isinstance(node, (ast.For, ast.While)):
                if any(isinstance(child, ast.If) for child in ast.walk(node)):
                    loop_sites.append((filename, node.lineno))

            if isinstance(node, ast.Call):
                func = node.func
                name = None
                if isinstance(func, ast.Name):
                    name = func.id
                elif isinstance(func, ast.Attribute):
                    name = func.attr
                if name in rng_names:
                    rng_sites.append((filename, node.lineno))
                if name == 'append':
                    record_sites.append((filename, node.lineno))

            if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
                if isinstance(node, ast.Assign):
                    targets = node.targets
                else:
                    targets = [node.target]
                if any(isinstance(target, ast.Subscript) for target in targets):
                    record_sites.append((filename, node.lineno))

    long_acceptance_loop = any(trace.get(site, 0) >= 50000 for site in loop_sites)
    repeated_rng = any(trace.get(site, 0) >= 50000 for site in rng_sites)
    recorded_samples = any(trace.get(site, 0) >= 50000 for site in record_sites)
    return long_acceptance_loop and repeated_rng and recorded_samples


def load_result():
    assert RESULT_PATH.is_file(), f'{RESULT_PATH} does not exist.'
    try:
        with open(RESULT_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'{RESULT_PATH} is not valid JSON: {exc}')


def write_fasta(path, records):
    with open(path, 'w') as f:
        for name, sequence in records:
            f.write(f'>{name}\n{sequence}\n')


def test_virtual_environment_exists():
    assert VENV_PYTHON.is_file(), 'Python virtual environment was not found at /home/user/bio_env'


def test_executable_analysis_and_result():
    scripts = user_python_files()
    assert scripts, 'No Python analysis implementation was found under /home/user.'

    original_ref_bytes = REF_PATH.read_bytes()
    original_samples_bytes = SAMPLES_PATH.read_bytes()
    original_result_bytes = RESULT_PATH.read_bytes() if RESULT_PATH.exists() else None

    alt_ref = 'ACGTACGTACGTACGTACGTACGT'
    mutation_sets = [set(), {0}, {3, 9}, {5, 11, 17}, {2, 7, 14, 22}]
    alt_samples = []
    for positions in mutation_sets:
        chars = list(alt_ref)
        for pos in positions:
            chars[pos] = 'A' if chars[pos] != 'A' else 'C'
        alt_samples.append(''.join(chars))

    selected = None
    try:
        write_fasta(REF_PATH, [('Reference', alt_ref)])
        write_fasta(SAMPLES_PATH, [(f'Sample_{i+1}', s) for i, s in enumerate(alt_samples)])

        failures = []
        for index, script in enumerate(scripts):
            if RESULT_PATH.exists():
                RESULT_PATH.unlink()
            trace_path = Path(f'/tmp/user_trace_{index}.json')
            try:
                trace = run_with_trace(script, trace_path)
                result = load_result()
                validate_result(result, alt_ref, alt_samples)
                assert has_executed_mh_sampling(trace), (
                    'The executed implementation did not perform and record at least '
                    '50,000 Metropolis-Hastings iterations.'
                )
                selected = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert selected is not None, (
            'No executable Python analysis implementation passed the alternate-input '
            'test and demonstrated at least 50,000 Metropolis-Hastings samples. ' +
            ' | '.join(failures[-3:])
        )
    finally:
        REF_PATH.write_bytes(original_ref_bytes)
        SAMPLES_PATH.write_bytes(original_samples_bytes)
        if original_result_bytes is None:
            if RESULT_PATH.exists():
                RESULT_PATH.unlink()
        else:
            RESULT_PATH.write_bytes(original_result_bytes)

    # Execute the demonstrated implementation on the actual task inputs and retain
    # the original verifier's checks for mismatch counts and conserved primer.
    if RESULT_PATH.exists():
        RESULT_PATH.unlink()
    final_trace = run_with_trace(selected, Path('/tmp/final_user_trace.json'))
    assert has_executed_mh_sampling(final_trace)
    result = load_result()

    ref_seqs = read_fasta(REF_PATH)
    assert len(ref_seqs) == 1, 'Reference FASTA should contain exactly one sequence.'
    samples = read_fasta(SAMPLES_PATH)
    assert len(samples) > 0, 'Samples FASTA must contain at least one sequence.'
    validate_result(result, ref_seqs[0], samples)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
