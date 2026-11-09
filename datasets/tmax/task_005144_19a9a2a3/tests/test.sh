#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
from pathlib import Path

import netCDF4 as nc
import numpy as np

OUTPUT_FILE = Path('/home/user/analysis_output.txt')


def calculate_expected():
    with nc.Dataset('/home/user/data.nc', 'r') as ds:
        x = np.asarray(ds.variables['x'][:], dtype=np.float64)
        y = np.asarray(ds.variables['y'][:], dtype=np.float64)

    assert x.ndim == 1 and y.ndim == 1 and len(x) == len(y)

    y_integral = float(np.trapz(y, x))
    p = y / y_integral

    x_peak = float(x[int(np.argmax(y))])
    lam = 1.0 / x_peak

    q_unnorm = x * np.exp(-lam * x)
    a = 1.0 / float(np.trapz(q_unnorm, x))
    q = a * q_unnorm

    dkl = float(np.trapz(p * np.log(p / q), x))

    alpha = 1.0
    for _ in range(100):
        f = alpha - math.sin(alpha) - dkl
        derivative = 1.0 - math.cos(alpha)
        next_alpha = alpha - f / derivative
        if abs(next_alpha - alpha) < 1e-14:
            alpha = next_alpha
            break
        alpha = next_alpha

    return {
        'lambda': lam,
        'A': a,
        'DKL': dkl,
        'alpha': alpha,
    }


def assert_output_correct(expected):
    assert OUTPUT_FILE.is_file(), f'The file {OUTPUT_FILE} does not exist.'
    text = OUTPUT_FILE.read_text()

    for key, expected_val in expected.items():
        match = re.search(rf'{key}:\s*([0-9\.]+)', text)
        assert match is not None, f"Missing '{key}' in output file."
        val = float(match.group(1))
        assert abs(val - expected_val) <= 0.0005, (
            f'Value for {key} is {val}, expected {expected_val} '
            '(within 0.0005 tolerance)'
        )


def test_analysis_output_exists_and_correct():
    expected = calculate_expected()

    # Preserve the original assertion that the requested output already exists
    # and contains correct results.
    assert_output_correct(expected)

    # Verify that a C implementation exists and can itself regenerate the output.
    sources = sorted(Path('/home/user').rglob('*.c'))
    assert sources, 'No C source program was found under /home/user.'

    source_groups = [sources]
    if len(sources) > 1:
        source_groups.extend([[source] for source in sources])

    errors = []
    for index, group in enumerate(source_groups):
        executable = Path(f'/tmp/analysis_verifier_{index}')
        compile_cmd = [
            'gcc', '-O2', *map(str, group), '-o', str(executable),
            '-lnetcdf', '-lm'
        ]
        try:
            compiled = subprocess.run(
                compile_cmd, cwd='/home/user', capture_output=True,
                text=True, timeout=60
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f'compile {group}: {exc}')
            continue

        if compiled.returncode != 0:
            errors.append(f'compile {group}: {compiled.stderr[-1000:]}')
            continue

        try:
            OUTPUT_FILE.unlink(missing_ok=True)
            executed = subprocess.run(
                [str(executable)], cwd='/home/user', capture_output=True,
                text=True, timeout=60
            )
            if executed.returncode != 0:
                errors.append(f'run {group}: {executed.stderr[-1000:]}')
                continue
            assert_output_correct(expected)
            return
        except (OSError, subprocess.TimeoutExpired, AssertionError) as exc:
            errors.append(f'run {group}: {exc}')

    raise AssertionError(
        'No submitted C program could be compiled and run to regenerate the '
        'correct analysis output.\n' + '\n'.join(errors)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
