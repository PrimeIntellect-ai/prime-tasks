#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pytest

HOME = Path('/home/user')
OUTPUT = HOME / 'posterior_mean.txt'


def get_analytical_posterior():
    data_path = '/app/sequence_features.csv'
    assert os.path.isfile(data_path), f"Data file {data_path} is missing."

    data = np.loadtxt(data_path, delimiter=',', skiprows=1)
    N = len(data)
    x_bar = np.mean(data, axis=0)

    Sigma = np.array([[2.0, 0.8], [0.8, 3.0]])
    Lambda = np.linalg.inv(Sigma)

    mu_0 = np.array([0.0, 0.0])
    Lambda_0 = np.linalg.inv(np.array([[10.0, 0.0], [0.0, 10.0]]))

    Lambda_n = Lambda_0 + N * Lambda
    mu_n = np.linalg.inv(Lambda_n).dot(Lambda_0.dot(mu_0) + N * Lambda.dot(x_bar))
    return mu_n


def find_and_validate_cpp():
    cpp_files = sorted(
        p for p in HOME.rglob('*')
        if p.is_file() and p.suffix.lower() in {'.cpp', '.cc', '.cxx'}
    )
    assert cpp_files, 'No C++ sampler source was found under /home/user.'

    mains = []
    for path in cpp_files:
        text = path.read_text(errors='ignore')
        if re.search(r'\b(?:int|auto)\s+main\s*\(', text):
            mains.append(path)
    assert mains, 'No C++ source containing a main() entry point was found.'

    failures = []
    for main in mains:
        directory_sources = [p for p in cpp_files if p.parent == main.parent]
        auxiliary = []
        for path in directory_sources:
            if path == main:
                continue
            text = path.read_text(errors='ignore')
            if not re.search(r'\b(?:int|auto)\s+main\s*\(', text):
                auxiliary.append(path)

        build_sources = [main] + auxiliary
        combined = '\n'.join(p.read_text(errors='ignore') for p in build_sources)
        lowered = combined.lower()

        required = {
            'Metropolis-Hastings implementation': ('metropolis' in lowered and 'accept' in lowered),
            'C++ random sampling': ('<random>' in lowered and re.search(r'normal_distribution|uniform_real_distribution', lowered)),
            'four-chain configuration': bool(re.search(r'(?:num_?chains|n_?chains|chains?)\s*(?:=|\()\s*4\b|\[\s*4\s*\]', lowered)),
            'Gelman-Rubin/R-hat calculation': (('rhat' in lowered or 'r_hat' in lowered or 'gelman' in lowered) and 'sqrt' in lowered),
            'R-hat threshold 1.02': ('1.02' in combined),
            'iterative convergence loop': bool(re.search(r'\bwhile\s*\(', lowered)),
            'burn-in handling': ('burn' in lowered),
        }
        missing = [name for name, present in required.items() if not present]
        if missing:
            failures.append(f"{main}: missing {', '.join(missing)}")
            continue

        executable = Path('/tmp/agent_mcmc_sampler')
        try:
            subprocess.run(
                ['g++', '-std=c++17', '-O2', '-pthread', *map(str, build_sources), '-o', str(executable)],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90
            )
            return main, executable
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            detail = getattr(exc, 'stderr', '') or str(exc)
            failures.append(f"{main}: compilation failed: {detail[-1000:]}")

    pytest.fail('No valid C++ MCMC program could be compiled.\n' + '\n'.join(failures))


def validate_ocr_evidence():
    evidence_files = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path == OUTPUT:
            continue
        if path.suffix.lower() not in {'.cpp', '.cc', '.cxx', '.h', '.hpp', '.py', '.sh'} and path.name.lower() not in {'makefile'}:
            continue
        text = path.read_text(errors='ignore').lower()
        if 'target_cov.png' in text and re.search(r'tesseract|pytesseract|\bocr\b', text):
            evidence_files.append(path)
    assert evidence_files, (
        'No OCR pipeline evidence was found. Preserve source or a helper script that reads '
        '/app/target_cov.png using OCR (for example, tesseract or pytesseract).'
    )


def test_cpp_sampler_and_posterior_mean():
    validate_ocr_evidence()
    source, executable = find_and_validate_cpp()

    if OUTPUT.exists():
        OUTPUT.unlink()

    try:
        result = subprocess.run(
            [str(executable)], cwd=str(source.parent),
            env={**os.environ, 'HOME': str(HOME)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180
        )
    except subprocess.TimeoutExpired:
        pytest.fail('The compiled C++ sampler did not finish within 180 seconds.')

    assert result.returncode == 0, (
        f'Compiled C++ sampler exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout[-2000:]}\nstderr:\n{result.stderr[-2000:]}'
    )
    assert OUTPUT.is_file(), 'Executing the compiled C++ sampler did not create /home/user/posterior_mean.txt.'

    try:
        content = OUTPUT.read_text().strip().split()
        assert len(content) == 2, 'Output must contain exactly two space-separated values.'
        agent_mu = np.array([float(content[0]), float(content[1])])
        assert np.all(np.isfinite(agent_mu)), 'Output values must be finite.'
    except Exception as e:
        pytest.fail(f'Failed to read or parse {OUTPUT}. Ensure it contains two space-separated floats. Error: {e}')

    true_mu_n = get_analytical_posterior()
    dist = np.linalg.norm(agent_mu - true_mu_n)

    threshold = 0.05
    assert dist <= threshold, (
        f"Euclidean distance between estimated posterior mean and analytical posterior mean is too large.\n"
        f"Distance: {dist:.6f}\n"
        f"Threshold: {threshold}\n"
        f"Agent estimate: {agent_mu}\n"
        f"Analytical truth: {true_mu_n}"
    )
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
