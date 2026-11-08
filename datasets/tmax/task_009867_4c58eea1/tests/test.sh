#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import pathlib
import re
import shutil
import subprocess

import numpy as np
import pytest
from scipy.optimize import least_squares

HOME = pathlib.Path('/home/user')
OUTPUT = HOME / 'posterior_means.json'
SEQUENCES = HOME / 'sequences.csv'


def read_output():
    assert OUTPUT.is_file(), f"Required output file {OUTPUT} is missing."
    raw = OUTPUT.read_text()
    assert re.fullmatch(r'\s*\{\s*"alpha"\s*:\s*-?\d+\.\d{2}\s*,\s*"beta"\s*:\s*-?\d+\.\d{2}\s*\}\s*', raw), \
        "posterior_means.json must contain exactly alpha and beta, each written with two decimal places."
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {OUTPUT} is not valid JSON: {exc}")
    assert set(data) == {'alpha', 'beta'}
    assert isinstance(data['alpha'], (int, float)) and not isinstance(data['alpha'], bool)
    assert isinstance(data['beta'], (int, float)) and not isinstance(data['beta'], bool)
    assert math.isfinite(data['alpha']) and math.isfinite(data['beta'])
    return data


def test_original_output_format_and_values():
    data = read_output()
    alpha = data['alpha']
    beta = data['beta']
    assert 1.80 <= alpha <= 2.20, f"Alpha value {alpha} is out of the expected range [1.80, 2.20]."
    assert 0.05 <= beta <= 0.15, f"Beta value {beta} is out of the expected range [0.05, 0.15]."


def make_synthetic_data(path):
    reference = 'A' * 50
    rows = []
    for day in range(1, 31):
        target = (3.0 / 0.20) * (1.0 - math.exp(-0.20 * day))
        base = int(math.floor(target))
        frac = target - base
        high_count = int(round(5 * frac))
        counts = [base + 1] * high_count + [base] * (5 - high_count)
        for count in counts:
            rows.append((day, 'T' * count + reference[count:]))
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Day', 'Sequence'])
        writer.writerows(rows)


def expected_fit(path):
    by_day = {}
    with open(path, newline='') as f:
        for row in csv.DictReader(f):
            day = float(row['Day'])
            distance = sum(a != b for a, b in zip(row['Sequence'], 'A' * 50))
            by_day.setdefault(day, []).append(distance)
    days = np.array(sorted(by_day), dtype=float)
    observed = np.array([np.mean(by_day[d]) for d in days], dtype=float)

    def residuals(p):
        alpha, beta = p
        predicted = (alpha / beta) * (1.0 - np.exp(-beta * days))
        return observed - predicted

    fit = least_squares(residuals, np.array([3.0, 0.2]), bounds=([1e-8, 1e-8], [10.0, 1.0]))
    return float(fit.x[0]), float(fit.x[1])


def compile_source(source, destination):
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(source), '-o', str(destination)],
        cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=60
    )
    return result.returncode == 0


def test_artifacts_execute_and_use_observations():
    cpp_files = sorted(p for p in HOME.rglob('*.cpp') if p.is_file())
    py_files = sorted(p for p in HOME.rglob('*.py') if p.is_file())
    assert cpp_files, "No C++ source file implementing the required MCMC was found."

    cpp_text = {p: p.read_text(errors='ignore') for p in cpp_files}
    py_text = {p: p.read_text(errors='ignore') for p in py_files}

    mcmc_sources = []
    for path, text in cpp_text.items():
        lower = text.lower()
        if ('100000' in text and '10000' in text and '0.05' in text and
                'alpha' in lower and 'beta' in lower and 'exp' in lower and
                ('sigma' in lower or 'likelihood' in lower) and
                ('mt19937' in lower or 'random' in lower)):
            mcmc_sources.append(path)
    assert mcmc_sources, "The C++ source does not contain the specified 100,000-iteration Metropolis-Hastings implementation."

    processing_sources = [
        p for p, text in {**cpp_text, **py_text}.items()
        if 'sequences.csv' in text and 'Day' in text and 'Sequence' in text
    ]
    assert processing_sources, "No submitted program that processes sequences.csv by Day and Sequence was found."

    original_sequences = SEQUENCES.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        make_synthetic_data(SEQUENCES)
        expected_alpha, expected_beta = expected_fit(SEQUENCES)

        # Run submitted Python reshaping scripts that target the required input.
        for path, text in py_text.items():
            if 'sequences.csv' in text and 'Day' in text and 'Sequence' in text:
                try:
                    subprocess.run(['python3', str(path)], cwd=HOME, timeout=60,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                except (subprocess.SubprocessError, OSError):
                    pass

        # Compile and run non-MCMC C++ data-processing programs first.
        for index, path in enumerate(cpp_files):
            if path in mcmc_sources:
                continue
            text = cpp_text[path]
            if 'sequences.csv' not in text:
                continue
            binary = pathlib.Path(f'/tmp/reshape_submission_{index}')
            if compile_source(path, binary):
                try:
                    subprocess.run([str(binary)], cwd=HOME, timeout=60,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                except (subprocess.SubprocessError, OSError):
                    pass

        valid_execution = False
        errors = []
        for index, source in enumerate(mcmc_sources):
            binary = pathlib.Path(f'/tmp/mcmc_submission_{index}')
            if not compile_source(source, binary):
                errors.append(f'{source} did not compile')
                continue
            if OUTPUT.exists():
                OUTPUT.unlink()
            try:
                result = subprocess.run([str(binary)], cwd=HOME, timeout=120,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            except (subprocess.SubprocessError, OSError) as exc:
                errors.append(f'{source} did not execute: {exc}')
                continue
            if result.returncode != 0 or not OUTPUT.exists():
                errors.append(f'{source} did not successfully create posterior_means.json')
                continue
            try:
                data = read_output()
            except AssertionError as exc:
                errors.append(f'{source} produced invalid output: {exc}')
                continue

            # The hidden dataset has a separately derived nonlinear least-squares/posterior center.
            # Tolerances allow ordinary Monte Carlo error from the required 90,000 retained draws.
            if (abs(data['alpha'] - expected_alpha) <= 0.25 and
                    abs(data['beta'] - expected_beta) <= 0.03):
                valid_execution = True
                break
            errors.append(
                f"{source} output ({data['alpha']}, {data['beta']}) is inconsistent with "
                f"the supplied observations (center approximately {expected_alpha:.3f}, {expected_beta:.3f})"
            )

        assert valid_execution, '; '.join(errors) or "No MCMC implementation executed successfully."
    finally:
        SEQUENCES.write_bytes(original_sequences)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
