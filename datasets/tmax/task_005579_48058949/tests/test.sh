#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import shutil
import subprocess

import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold, cross_val_score

HOME = '/home/user'
DATA_PATH = os.path.join(HOME, 'data.csv')
JSON_PATH = os.path.join(HOME, 'experiment.json')
ALPHAS = [0.1, 1.0, 10.0]


def calculate_expected(path):
    df = pd.read_csv(path)
    for column in ('age', 'clicks'):
        df[column] = df[column].fillna(df[column].median()).astype(int)

    X = df[['age', 'clicks', 'duration']]
    y = df['revenue']
    cv = KFold(n_splits=5, shuffle=True, random_state=42)

    means = [cross_val_score(Ridge(alpha=a), X, y, cv=cv, scoring='r2').mean()
             for a in ALPHAS]
    best_alpha = ALPHAS[int(np.argmax(means))]
    mean_original = means[int(np.argmax(means))]

    np.random.seed(42)
    bootstrap_scores = []
    for _ in range(100):
        indices = np.random.choice(len(df), size=len(df), replace=True)
        sample = df.iloc[indices]
        sample_X = sample[['age', 'clicks', 'duration']]
        sample_y = sample['revenue']
        score = cross_val_score(
            Ridge(alpha=best_alpha), sample_X, sample_y,
            cv=KFold(n_splits=5, shuffle=True, random_state=42),
            scoring='r2'
        ).mean()
        bootstrap_scores.append(score)

    # np.std is the usual interpretation; ddof=1 is also accepted because the
    # instruction does not specify population versus sample standard deviation.
    return {
        'best_alpha': best_alpha,
        'mean_cv_r2_original': round(float(mean_original), 4),
        'bootstrap_se_options': {
            round(float(np.std(bootstrap_scores, ddof=0)), 4),
            round(float(np.std(bootstrap_scores, ddof=1)), 4),
        },
    }


def output_matches(expected):
    if not os.path.isfile(JSON_PATH):
        return False
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False

    if set(data.keys()) != {'best_alpha', 'mean_cv_r2_original', 'bootstrap_se_r2'}:
        return False
    if any(isinstance(data[k], bool) or not isinstance(data[k], (int, float)) for k in data):
        return False
    return (
        data['best_alpha'] == expected['best_alpha'] and
        data['mean_cv_r2_original'] == expected['mean_cv_r2_original'] and
        data['bootstrap_se_r2'] in expected['bootstrap_se_options']
    )


def command_for(path):
    lower = path.lower()
    if lower.endswith('.py'):
        return ['python3', path]
    if lower.endswith(('.sh', '.bash')):
        return ['bash', path]
    if lower.endswith('.r') and shutil.which('Rscript'):
        return ['Rscript', path]
    if lower.endswith('.js') and shutil.which('node'):
        return ['node', path]
    if lower.endswith('.rb') and shutil.which('ruby'):
        return ['ruby', path]
    if lower.endswith('.pl') and shutil.which('perl'):
        return ['perl', path]

    try:
        with open(path, 'rb') as f:
            first = f.readline(512)
            rest = f.read(4096)
        if b'\x00' in first + rest:
            return None
        line = first.decode('utf-8', errors='ignore').strip()
    except OSError:
        return None

    if line.startswith('#!'):
        words = shlex.split(line[2:].strip())
        names = [os.path.basename(word) for word in words]
        if any('python' in name for name in names):
            return ['python3', path]
        if any(name in ('bash', 'sh') for name in names):
            return ['bash', path]
        if os.access(path, os.X_OK):
            return [path]

    # Also support extensionless Python scripts.
    if '.' not in os.path.basename(path):
        return ['python3', path]
    return None


def candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in ('.cache', '__pycache__', '.git')]
        for name in files:
            path = os.path.join(root, name)
            if path in (DATA_PATH, JSON_PATH) or not os.path.isfile(path):
                continue
            command = command_for(path)
            if command is not None:
                candidates.append((path, command))
    return sorted(candidates, key=lambda item: os.path.getmtime(item[0]), reverse=True)


def run_script(command):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    try:
        result = subprocess.run(
            command, cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=180
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def test_processing_script_recomputes_metrics():
    with open(DATA_PATH, 'rb') as f:
        original_bytes = f.read()

    expected_original = calculate_expected(DATA_PATH)

    altered = pd.read_csv(DATA_PATH)
    altered['revenue'] = np.roll(altered['revenue'].to_numpy(), 17)
    altered.loc[:6, 'age'] = np.nan
    altered.loc[7:13, 'clicks'] = np.nan
    altered.to_csv(DATA_PATH, index=False)
    expected_altered = calculate_expected(DATA_PATH)
    with open(DATA_PATH, 'wb') as f:
        f.write(original_bytes)

    scripts = candidate_scripts()
    assert scripts, 'No processing script was found under /home/user'

    accepted = False
    try:
        for _, command in scripts:
            with open(DATA_PATH, 'wb') as f:
                f.write(original_bytes)
            if not run_script(command) or not output_matches(expected_original):
                continue

            altered.to_csv(DATA_PATH, index=False)
            if not run_script(command) or not output_matches(expected_altered):
                continue

            with open(DATA_PATH, 'wb') as f:
                f.write(original_bytes)
            if run_script(command) and output_matches(expected_original):
                accepted = True
                break
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_bytes)
        if not accepted and os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)

    assert accepted, ('No submitted script regenerated correct rounded Ridge CV and '
                      'bootstrap metrics for both the original and an altered dataset')


def test_experiment_json_exists_and_valid():
    """Verify that experiment.json exists and contains the correct structure and types."""
    json_path = '/home/user/experiment.json'
    assert os.path.isfile(json_path), f"Expected results file missing at {json_path}"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    expected_keys = {"best_alpha", "mean_cv_r2_original", "bootstrap_se_r2"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, but got {set(data.keys())}"

    # Check types and valid ranges
    assert isinstance(data["best_alpha"], (int, float)), "best_alpha must be a number"
    assert data["best_alpha"] in [0.1, 1.0, 10.0], f"best_alpha must be one of [0.1, 1.0, 10.0], got {data['best_alpha']}"

    assert isinstance(data["mean_cv_r2_original"], (int, float)), "mean_cv_r2_original must be a number"
    assert -1.0 <= data["mean_cv_r2_original"] <= 1.0, "mean_cv_r2_original should be an R-squared value"

    assert isinstance(data["bootstrap_se_r2"], (int, float)), "bootstrap_se_r2 must be a number"
    assert data["bootstrap_se_r2"] >= 0.0, "bootstrap_se_r2 must be non-negative"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
