#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "sklearn:scikit-learn"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import RidgeCV

DATA_PATH = Path('/home/user/data.csv')
OUTPUT_PATH = Path('/home/user/best_alpha.txt')


def read_alpha():
    assert OUTPUT_PATH.exists(), f'The output file is missing: {OUTPUT_PATH}'
    assert OUTPUT_PATH.is_file(), f'The path exists but is not a file: {OUTPUT_PATH}'
    content = OUTPUT_PATH.read_text().strip()
    assert content != '', 'The output file is empty.'
    try:
        return float(content)
    except ValueError:
        pytest.fail(f"The output file does not contain a valid float. Got: '{content}'")


def expected_alpha(df):
    filtered = df[df['target'] <= 1000].copy()
    filtered['f1'] = filtered['f1'].fillna(filtered['f1'].median())
    model = RidgeCV(alphas=[0.1, 1.0, 10.0])
    model.fit(filtered[['f1', 'f2']], filtered['target'])
    return float(model.alpha_)


def make_behavioral_cases():
    cases_by_alpha = {}
    for seed in range(100):
        rng = np.random.RandomState(seed)
        n = 24
        f1 = rng.normal(size=n)
        f2 = rng.normal(size=n)
        coef1 = [0.15, 1.5, 8.0][seed % 3]
        coef2 = [-2.0, 0.4, 3.0][(seed // 3) % 3]
        noise = [0.03, 0.5, 4.0, 15.0][(seed // 9) % 4]
        target = coef1 * f1 + coef2 * f2 + rng.normal(scale=noise, size=n)

        df = pd.DataFrame({'f1': f1, 'f2': f2, 'target': target})
        df.loc[[2, 7, 13], 'f1'] = np.nan
        # This row must be removed before the median is calculated.
        df.loc[len(df)] = [1.0e9, -1.0e9, 5000.0]
        alpha = expected_alpha(df)
        cases_by_alpha.setdefault(alpha, df)
        if len(cases_by_alpha) == 3:
            break

    assert len(cases_by_alpha) >= 2, 'Verifier could not construct discriminating RidgeCV cases.'
    assert any(alpha != 10.0 for alpha in cases_by_alpha), 'Verifier cases do not reject a hardcoded 10.0.'
    return list(cases_by_alpha.items())


def run_script(script, df):
    df.to_csv(DATA_PATH, index=False)
    if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ['python3', str(script)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    if result.returncode != 0:
        raise AssertionError(
            f'{script} exited with status {result.returncode}. '
            f'stdout={result.stdout!r} stderr={result.stderr!r}'
        )
    return read_alpha()


def test_best_alpha_file_exists():
    file_path = '/home/user/best_alpha.txt'
    assert os.path.exists(file_path), f'The output file is missing: {file_path}'
    assert os.path.isfile(file_path), f'The path exists but is not a file: {file_path}'


def test_best_alpha_content():
    alpha_val = read_alpha()
    assert alpha_val == 10.0, f'The best alpha value is incorrect. Expected 10.0, but got {alpha_val}'


def test_python_script_performs_requested_pipeline():
    scripts = sorted(Path('/home/user').glob('*.py'))
    assert scripts, 'No Python script was written in /home/user.'

    original_data = DATA_PATH.read_bytes()
    cases = make_behavioral_cases()
    accepted = None
    failures = []

    try:
        for script in scripts:
            try:
                for expected, df in cases:
                    actual = run_script(script, df)
                    assert actual == expected, (
                        f'{script} produced alpha {actual}, expected {expected} '
                        'after filtering and median imputation.'
                    )
                accepted = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert accepted is not None, (
            'No Python script correctly performed the requested pipeline on '
            'independently generated inputs. ' + ' | '.join(failures)
        )

        DATA_PATH.write_bytes(original_data)
        if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
            OUTPUT_PATH.unlink()
        result = subprocess.run(
            ['python3', str(accepted)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'{accepted} failed on the original dataset: '
            f'stdout={result.stdout!r} stderr={result.stderr!r}'
        )
        final_alpha = read_alpha()
        original_df = pd.read_csv(DATA_PATH)
        derived_alpha = expected_alpha(original_df)
        assert final_alpha == derived_alpha, (
            f'The final alpha is incorrect. Expected {derived_alpha}, got {final_alpha}'
        )
        assert final_alpha == 10.0, (
            f'The best alpha value is incorrect. Expected 10.0, but got {final_alpha}'
        )
    finally:
        DATA_PATH.write_bytes(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
