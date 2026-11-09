#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from sklearn.neighbors import KernelDensity

HOME = Path('/home/user')
REFERENCE_PATH = HOME / 'reference_data.npy'
CANDIDATE_PATH = HOME / 'candidate_data.npy'
OUTPUT_PATH = HOME / 'distribution_metrics.json'


def expected_metrics(reference, candidate):
    kde = KernelDensity(kernel='gaussian', bandwidth=0.5)
    kde.fit(reference)
    log_likelihoods = kde.score_samples(candidate)
    mean_ll = np.mean(log_likelihoods)

    np.random.seed(42)
    bootstrap_means = []
    for _ in range(1000):
        sample = np.random.choice(
            log_likelihoods, size=len(log_likelihoods), replace=True
        )
        bootstrap_means.append(np.mean(sample))

    ci_lower, ci_upper = np.percentile(bootstrap_means, [2.5, 97.5])
    return {
        'mean_ll': round(float(mean_ll), 4),
        'ci_lower': round(float(ci_lower), 4),
        'ci_upper': round(float(ci_upper), 4),
    }


def load_and_check_json(expected):
    # Preserve the original existence and file-type assertions.
    assert OUTPUT_PATH.exists(), f'File missing: {OUTPUT_PATH}'
    assert OUTPUT_PATH.is_file(), f'Not a file: {OUTPUT_PATH}'

    try:
        with OUTPUT_PATH.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError('The file distribution_metrics.json is not valid JSON.')

    expected_keys = {'mean_ll', 'ci_lower', 'ci_upper'}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, (
        f'JSON keys do not match. Expected {expected_keys}, found {actual_keys}'
    )

    for key in expected_keys:
        val = data[key]
        assert isinstance(val, (int, float)), f"Value for '{key}' is not a number."
        assert math.isfinite(float(val)), f"Value for '{key}' is not finite."
        assert math.isclose(val, expected[key], rel_tol=0.0, abs_tol=1e-4), (
            f"Value for '{key}' is incorrect. Expected approximately "
            f"{expected[key]}, got {val}"
        )
    return data


def run_script(script):
    if OUTPUT_PATH.lexists():
        if OUTPUT_PATH.is_dir() and not OUTPUT_PATH.is_symlink():
            shutil.rmtree(OUTPUT_PATH)
        else:
            OUTPUT_PATH.unlink()

    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(HOME),
        env={**os.environ, 'HOME': str(HOME)},
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'Script {script} exited with status {result.returncode}:\n{result.stdout}'
    )


def find_scripts():
    scripts = []
    for path in HOME.rglob('*.py'):
        if path.is_file():
            try:
                source = path.read_text(errors='replace')
            except OSError:
                continue
            score = sum(token in source for token in (
                'distribution_metrics.json', 'KernelDensity', 'score_samples'
            ))
            scripts.append((-score, str(path), path, source))

    assert scripts, 'No Python script was found under /home/user.'
    all_source = '\n'.join(item[3] for item in scripts)
    assert 'KernelDensity' in all_source, (
        'No submitted Python source uses sklearn.neighbors.KernelDensity.'
    )
    assert 'score_samples' in all_source, (
        'No submitted Python source calls score_samples.'
    )
    scripts.sort(key=lambda item: (item[0], item[1]))
    return [item[2] for item in scripts]


def main():
    scripts = find_scripts()

    original_reference = np.load(REFERENCE_PATH)
    original_candidate = np.load(CANDIDATE_PATH)
    original_expected = expected_metrics(original_reference, original_candidate)

    # Exercise the submitted artifact on verifier-generated data so a fixed JSON
    # containing the known answers cannot pass.
    rng = np.random.default_rng(917263)
    hidden_reference = rng.normal(
        loc=[0.35, -0.55, 0.8], scale=[1.2, 0.7, 1.5], size=(137, 3)
    )
    hidden_candidate = rng.normal(
        loc=[-0.2, 0.4, 1.1], scale=[0.8, 1.3, 0.9], size=(73, 3)
    )
    hidden_expected = expected_metrics(hidden_reference, hidden_candidate)

    backup_dir = Path(tempfile.mkdtemp(prefix='kde-verifier-'))
    ref_backup = backup_dir / 'reference_data.npy'
    cand_backup = backup_dir / 'candidate_data.npy'
    shutil.copy2(REFERENCE_PATH, ref_backup)
    shutil.copy2(CANDIDATE_PATH, cand_backup)

    selected_script = None
    failures = []
    try:
        for script in scripts:
            np.save(REFERENCE_PATH, hidden_reference)
            np.save(CANDIDATE_PATH, hidden_candidate)
            try:
                run_script(script)
                load_and_check_json(hidden_expected)
                selected_script = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert selected_script is not None, (
            'No submitted Python script produced correct metrics when executed '
            'on verifier-generated datasets.\n' + '\n'.join(failures)
        )
    finally:
        shutil.copy2(ref_backup, REFERENCE_PATH)
        shutil.copy2(cand_backup, CANDIDATE_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)

    # Execute the same artifact against the supplied datasets and preserve the
    # original fixed-dataset assertions as well as an independently derived check.
    run_script(selected_script)
    data = load_and_check_json(original_expected)

    expected_values = {
        'mean_ll': -3.8344,
        'ci_lower': -3.9452,
        'ci_upper': -3.7292,
    }
    for key in {'mean_ll', 'ci_lower', 'ci_upper'}:
        val = data[key]
        assert math.isclose(val, expected_values[key], abs_tol=1e-4), (
            f"Value for '{key}' is incorrect. Expected approximately "
            f"{expected_values[key]}, got {val}"
        )


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
