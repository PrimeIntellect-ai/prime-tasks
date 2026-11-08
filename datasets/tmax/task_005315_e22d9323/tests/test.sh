#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import sys
import tempfile

import h5py
import numpy as np

SCRIPT_PATH = '/home/user/analyze_stability.py'
REPORT_PATH = '/home/user/stability_report.txt'
V1_PATH = '/home/user/sim_v1.h5'
V2_PATH = '/home/user/sim_v2.h5'


def expected_ci(path1, path2):
    with h5py.File(path1, 'r') as f:
        data1 = f['features'][:]
    with h5py.File(path2, 'r') as f:
        data2 = f['features'][:]

    row_diffs = np.mean(np.abs(data1 - data2), axis=1)
    np.random.seed(42)
    bootstrap_means = [
        np.mean(np.random.choice(row_diffs, size=len(row_diffs), replace=True))
        for _ in range(1000)
    ]
    return tuple(np.percentile(bootstrap_means, [2.5, 97.5]))


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'analyze_stability.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def validate_report(expected_lower, expected_upper):
    assert os.path.isfile(REPORT_PATH), f'The expected output file {REPORT_PATH} is missing.'

    with open(REPORT_PATH, 'r') as f:
        content = f.read()

    lower_match = re.search(r'Lower CI:\s*([0-9.]+)', content)
    upper_match = re.search(r'Upper CI:\s*([0-9.]+)', content)
    assert lower_match is not None, "Could not find 'Lower CI: <value>' in the report."
    assert upper_match is not None, "Could not find 'Upper CI: <value>' in the report."

    lower_val = float(lower_match.group(1))
    upper_val = float(upper_match.group(1))
    tolerance = 2e-6
    assert abs(lower_val - expected_lower) <= tolerance, (
        f'Lower CI value {lower_val} is not within acceptable tolerance of expected {expected_lower}.'
    )
    assert abs(upper_val - expected_upper) <= tolerance, (
        f'Upper CI value {upper_val} is not within acceptable tolerance of expected {expected_upper}.'
    )

    expected_text = (
        f'Lower CI: {expected_lower:.6f}\n'
        f'Upper CI: {expected_upper:.6f}'
    )
    assert content.rstrip('\n') == expected_text, (
        'The report does not use the required two-line format or six-decimal rounding.\n'
        f'Expected:\n{expected_text}\nGot:\n{content}'
    )


def test_script_exists_and_computes_bootstrap_ci():
    assert os.path.isfile(SCRIPT_PATH), f'The script {SCRIPT_PATH} is missing.'

    old_report = None
    if os.path.isfile(REPORT_PATH):
        with open(REPORT_PATH, 'rb') as f:
            old_report = f.read()

    generated_original_report = None
    with tempfile.TemporaryDirectory() as backup_dir:
        backup_v1 = os.path.join(backup_dir, 'sim_v1.h5')
        backup_v2 = os.path.join(backup_dir, 'sim_v2.h5')
        shutil.copy2(V1_PATH, backup_v1)
        shutil.copy2(V2_PATH, backup_v2)

        original_expected = expected_ci(V1_PATH, V2_PATH)
        try:
            # Verify the required report is produced by actually running the script.
            run_script()
            validate_report(*original_expected)
            with open(REPORT_PATH, 'rb') as f:
                generated_original_report = f.read()

            # Exercise the script on verifier-generated data so hardcoded output cannot pass.
            rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'little'))
            data1 = rng.normal(0.0, 2.0, size=(1000, 50)).astype(np.float32)
            row_scales = rng.uniform(0.0002, 0.02, size=(1000, 1)).astype(np.float32)
            perturbation = rng.normal(0.0, 1.0, size=(1000, 50)).astype(np.float32) * row_scales
            data2 = (data1 + perturbation).astype(np.float32)

            with h5py.File(V1_PATH, 'w') as f:
                f.create_dataset('features', data=data1)
            with h5py.File(V2_PATH, 'w') as f:
                f.create_dataset('features', data=data2)

            challenge_expected = expected_ci(V1_PATH, V2_PATH)
            run_script()
            validate_report(*challenge_expected)
        finally:
            shutil.copy2(backup_v1, V1_PATH)
            shutil.copy2(backup_v2, V2_PATH)
            if generated_original_report is not None:
                with open(REPORT_PATH, 'wb') as f:
                    f.write(generated_original_report)
            elif old_report is not None:
                with open(REPORT_PATH, 'wb') as f:
                    f.write(old_report)
            elif os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
