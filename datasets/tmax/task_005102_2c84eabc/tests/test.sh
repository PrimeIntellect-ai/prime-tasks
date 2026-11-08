#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import math
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
import time

import pytest

TARGET_VALUE = 0.0452918
THRESHOLD = 1e-5
OUTPUT_FILE = Path('/home/user/posterior_mean.txt')
SCRIPT_FILE = Path('/home/user/run_estimation.py')
VENDORED_ROOT = Path('/app/bio_mcmc-1.2.3').resolve()
EXPECTED_SEQUENCES = ['ACGT', 'TGCA', 'CGTA', 'TACG']
FLOAT_RE = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')


def read_float_output():
    assert OUTPUT_FILE.is_file(), f'Expected output file {OUTPUT_FILE} does not exist.'
    content = OUTPUT_FILE.read_text().strip()
    assert content, f'File {OUTPUT_FILE} is empty.'
    assert FLOAT_RE.fullmatch(content), f'{OUTPUT_FILE} must contain only one float; got {content!r}'
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f'Could not parse the content of {OUTPUT_FILE} as a float. Content: {content!r}')
    assert math.isfinite(value), f'Posterior mean must be finite, got {value}'
    return value


def run_actual_script():
    assert SCRIPT_FILE.is_file(), f'Expected script {SCRIPT_FILE} does not exist.'
    OUTPUT_FILE.unlink(missing_ok=True)
    result = subprocess.run(
        [sys.executable, str(SCRIPT_FILE)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_FILE} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    return read_float_output(), OUTPUT_FILE.read_text()


def test_posterior_mean_file_exists():
    run_actual_script()
    assert OUTPUT_FILE.is_file(), f'Expected output file {OUTPUT_FILE} does not exist.'


def test_posterior_mean_value():
    agent_value, first_text = run_actual_script()
    error = abs(agent_value - TARGET_VALUE)
    assert error <= THRESHOLD, (
        f'Posterior mean absolute error is too high. Agent value: {agent_value}, '
        f'Target: {TARGET_VALUE}, Error: {error}, Threshold: {THRESHOLD}'
    )

    second_value, second_text = run_actual_script()
    assert second_value == agent_value and second_text == first_text, (
        'Running the estimation twice with seed 42 did not produce identical output.'
    )


def test_vendored_package_is_fixed_and_installed():
    import bio_mcmc
    from bio_mcmc.likelihood import LikelihoodCalculator

    package_file = Path(bio_mcmc.__file__).resolve()
    assert package_file.is_relative_to(VENDORED_ROOT), (
        f'Imported bio_mcmc from {package_file}, not from the modified vendored package {VENDORED_ROOT}'
    )
    assert importlib.metadata.version('bio_mcmc') == '1.2.3'

    likelihood_file = VENDORED_ROOT / 'bio_mcmc' / 'likelihood.py'
    source = likelihood_file.read_text()
    assert 'as_completed' not in source, (
        'The completion-order reduction is still present in the vendored likelihood implementation.'
    )

    sequences = [f'seq-{i}' for i in range(15)]
    calculator = LikelihoodCalculator(sequences)

    def adversarial_chunk(chunk):
        index = int(chunk[0].split('-')[1]) // 5
        values = [1.0e16, -1.0e16, 1.0]
        # Force completion in the reverse of input order. Input-order accumulation is 1.0;
        # completion-order accumulation loses the final unit and produces 0.0.
        time.sleep([0.04, 0.02, 0.0][index])
        return values[index]

    calculator._chunk_loglik = adversarial_chunk
    results = [calculator.compute_total_loglik() for _ in range(3)]
    assert results == [1.0, 1.0, 1.0], (
        'Log-likelihood reduction did not preserve deterministic chunk order: '
        f'{results}'
    )


def test_script_uses_fasta_sampler_iterations_and_burnin_mean():
    nonce = secrets.randbelow(400000) + 100000
    base = nonce / 1000000.0
    retained = [base + ((i * 37) % 101) / 10000.0 for i in range(8000)]
    expected_mean = sum(retained) / len(retained)

    with tempfile.TemporaryDirectory(prefix='verifier_fake_') as fake_dir:
        fake_path = Path(fake_dir)
        trace_path = fake_path / 'trace.json'
        module = f'''\nimport json\nimport os\n\nEXPECTED = {EXPECTED_SEQUENCES!r}\nBASE = {base!r}\nTRACE = {str(trace_path)!r}\n\nclass Sampler:\n    def __init__(self, sequences, seed=None):\n        seqs = list(sequences)\n        if seqs != EXPECTED:\n            raise AssertionError("Sampler did not receive the sequence strings parsed from the FASTA file: %r" % (seqs,))\n        if seed != 42:\n            raise AssertionError("Sampler seed must be exactly 42, got %r" % (seed,))\n        self.sequences = seqs\n        self.seed = seed\n\n    def run(self, iterations):\n        if iterations != 10000:\n            raise AssertionError("Sampler.run must be called with exactly 10000, got %r" % (iterations,))\n        if os.path.exists(TRACE):\n            raise AssertionError("Sampler.run was called more than once")\n        with open(TRACE, "w") as f:\n            json.dump({{"seed": self.seed, "iterations": iterations, "sequences": self.sequences}}, f)\n        burnin = [BASE + 1000.0] * 2000\n        retained = [BASE + ((i * 37) % 101) / 10000.0 for i in range(8000)]\n        return burnin + retained\n'''
        (fake_path / 'bio_mcmc.py').write_text(module)

        OUTPUT_FILE.unlink(missing_ok=True)
        env = os.environ.copy()
        env['PYTHONPATH'] = fake_dir
        result = subprocess.run(
            [sys.executable, str(SCRIPT_FILE)],
            cwd='/tmp',
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert result.returncode == 0, (
            f'Script failed under the instrumented sampler.\nstdout:\n{result.stdout}\n'
            f'stderr:\n{result.stderr}'
        )
        assert trace_path.is_file(), 'The script did not construct and run the required Sampler.'
        trace = json.loads(trace_path.read_text())
        assert trace == {
            'seed': 42,
            'iterations': 10000,
            'sequences': EXPECTED_SEQUENCES,
        }

        agent_value = read_float_output()
        assert math.isclose(agent_value, expected_mean, rel_tol=0.0, abs_tol=1e-12), (
            'The script did not calculate the mean after discarding exactly the first 2000 samples. '
            f'Got {agent_value}, expected {expected_mean}.'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
