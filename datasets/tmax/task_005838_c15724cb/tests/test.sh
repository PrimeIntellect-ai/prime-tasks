#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_pipeline.py
import os
import re
import subprocess
import sys
import numpy as np

PIPELINE = '/home/user/pipeline'
SCRIPT = os.path.join(PIPELINE, 'process_spectra.py')
SPECTRA = os.path.join(PIPELINE, 'spectra.csv')
TARGET = os.path.join(PIPELINE, 'target.csv')
RESULTS = os.path.join(PIPELINE, 'results.log')


def run_script():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    subprocess.run(
        [sys.executable, SCRIPT],
        cwd=PIPELINE,
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(RESULTS), f'The file {RESULTS} does not exist after running the script.'
    with open(RESULTS, 'r') as f:
        return f.read()


def parse_exact(content):
    match = re.fullmatch(
        r'Mean: (-?(?:\d+)\.\d{4})\nStdDev: (-?(?:\d+)\.\d{4})\n?',
        content,
    )
    assert match is not None, (
        'results.log must contain exactly two lines in the required format, '
        'with both values rounded to exactly four decimal places.'
    )
    return float(match.group(1)), float(match.group(2))


def expected_output(X, y):
    C = np.cov(X, rowvar=False)
    U, singular_values, Vt = np.linalg.svd(C, full_matrices=False)
    tolerance = np.finfo(float).eps * max(C.shape) * singular_values[0]
    inverse_values = np.zeros_like(singular_values)
    inverse_values[singular_values > tolerance] = 1.0 / singular_values[singular_values > tolerance]
    C_pinv = (Vt.T * inverse_values) @ U.T
    w = C_pinv @ y
    projection = X @ w
    return f'Mean: {np.mean(projection):.4f}\nStdDev: {np.std(projection):.4f}\n'


def save_state(path):
    if not os.path.exists(path):
        return None
    with open(path, 'rb') as f:
        return f.read()


def restore_state(path, data):
    if data is None:
        if os.path.exists(path):
            os.remove(path)
    else:
        with open(path, 'wb') as f:
            f.write(data)


assert os.path.isfile(SCRIPT), f'File {SCRIPT} does not exist.'
with open(SCRIPT, 'r') as f:
    source = f.read()
source_lower = source.lower()
assert 'cholesky' not in source_lower, (
    "The script still contains 'cholesky'. The failing Cholesky decomposition must be removed."
)
assert 'svd' in source_lower or 'pinv' in source_lower, (
    'The script does not contain an SVD or pseudo-inverse implementation.'
)

saved = {path: save_state(path) for path in (SPECTRA, TARGET, RESULTS)}
try:
    # Preserve the original verifier's checks on the supplied data, but execute
    # the submitted artifact rather than trusting a pre-created results.log.
    original_content = run_script()
    original_mean, original_std = parse_exact(original_content)
    assert abs(original_mean - 0.1693) < 0.0002, (
        f'Expected Mean to be approximately 0.1693, got {original_mean}'
    )
    assert abs(original_std - 83.1843) < 0.0002, (
        f'Expected StdDev to be approximately 83.1843, got {original_std}'
    )

    # Exercise the script on rank-deficient data unknown to the submission.
    # Expected answers are independently derived from an SVD pseudo-inverse.
    rng = np.random.default_rng(90210)
    base = rng.normal(size=(57, 6))
    X1 = np.column_stack((base, base[:, 0] - 1.75 * base[:, 2] + 0.4 * base[:, 5]))
    y1 = rng.normal(size=X1.shape[1])
    np.savetxt(SPECTRA, X1, delimiter=',')
    np.savetxt(TARGET, y1, delimiter=',')
    content1 = run_script()
    parse_exact(content1)
    assert content1 == expected_output(X1, y1), (
        'Incorrect result for dynamically generated rank-deficient spectral data.'
    )

    rng = np.random.default_rng(481516)
    base = rng.normal(loc=0.3, scale=1.7, size=(43, 5))
    X2 = np.column_stack((base, 2.0 * base[:, 1], base[:, 3] + base[:, 4]))
    y2 = rng.normal(size=X2.shape[1])
    np.savetxt(SPECTRA, X2, delimiter=',')
    np.savetxt(TARGET, y2, delimiter=',')
    content2 = run_script()
    parse_exact(content2)
    assert content2 == expected_output(X2, y2), (
        'Incorrect result for the second dynamically generated spectral dataset.'
    )
finally:
    for path, data in saved.items():
        restore_state(path, data)
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
