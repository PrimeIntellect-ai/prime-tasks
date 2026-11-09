#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = Path('/home/user/analyze.py')
JSON_PATH = Path('/home/user/tracking.json')
DATASETS_PATH = Path('/home/user/datasets')


def run_analyzer():
    try:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT_PATH)],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('analyze.py did not finish within 20 seconds.')
    assert completed.returncode == 0, (
        f'analyze.py exited with status {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )


def test_analyze_script_exists():
    script_path = '/home/user/analyze.py'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_tracking_json_exists_and_correct():
    # Remove any precomputed answer and require the submitted script to produce it.
    if JSON_PATH.exists() or JSON_PATH.is_symlink():
        JSON_PATH.unlink()
    run_analyzer()

    json_path = '/home/user/tracking.json'
    assert os.path.isfile(json_path), f"The output file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert "prior_alpha" in data, "Missing 'prior_alpha' in JSON."
    assert "prior_beta" in data, "Missing 'prior_beta' in JSON."
    assert data["prior_alpha"] == 2, f"Expected prior_alpha to be 2, got {data['prior_alpha']}."
    assert data["prior_beta"] == 2, f"Expected prior_beta to be 2, got {data['prior_beta']}."

    assert "results" in data, "Missing 'results' in JSON."
    assert isinstance(data["results"], list), "'results' should be a list."

    expected_results = [
        {"dataset_id": "alpha", "posterior_mean": 0.5862},
        {"dataset_id": "beta", "posterior_mean": 0.7083},
        {"dataset_id": "gamma", "posterior_mean": 0.8704}
    ]

    assert len(data["results"]) == len(expected_results), f"Expected {len(expected_results)} results, got {len(data['results'])}."

    for i, expected in enumerate(expected_results):
        actual = data["results"][i]
        assert "dataset_id" in actual, f"Result {i} missing 'dataset_id'."
        assert "posterior_mean" in actual, f"Result {i} missing 'posterior_mean'."
        assert actual["dataset_id"] == expected["dataset_id"], f"Expected dataset_id {expected['dataset_id']}, got {actual['dataset_id']}."
        assert actual["posterior_mean"] == expected["posterior_mean"], f"Expected posterior_mean {expected['posterior_mean']} for {expected['dataset_id']}, got {actual['posterior_mean']}."


def test_results_sorted():
    json_path = '/home/user/tracking.json'
    if not os.path.isfile(json_path):
        pytest.skip("tracking.json not found")

    with open(json_path, 'r') as f:
        data = json.load(f)

    dataset_ids = [r["dataset_id"] for r in data.get("results", []) if "dataset_id" in r]
    assert dataset_ids == sorted(dataset_ids), "The 'results' list is not sorted alphabetically by 'dataset_id'."


def test_script_aggregates_fresh_csv_inputs():
    token = secrets.token_hex(8)
    ids = [f'{token}_zeta', f'{token}_alpha', f'{token}_middle']

    rows_by_file = [
        [(ids[0], 13 + secrets.randbelow(20), 4), (ids[1], 21 + secrets.randbelow(20), 9)],
        [(ids[0], 17 + secrets.randbelow(20), 11), (ids[2], 31 + secrets.randbelow(20), 20)],
        [(ids[1], 9 + secrets.randbelow(20), 3), (ids[2], 15 + secrets.randbelow(20), 8)],
    ]
    # Ensure each generated successes count is valid for its generated trial count.
    rows_by_file = [
        [(dataset_id, trials, min(successes, trials)) for dataset_id, trials, successes in rows]
        for rows in rows_by_file
    ]

    totals = {}
    for rows in rows_by_file:
        for dataset_id, trials, successes in rows:
            totals.setdefault(dataset_id, [0, 0])
            totals[dataset_id][0] += trials
            totals[dataset_id][1] += successes

    expected_results = [
        {
            'dataset_id': dataset_id,
            'posterior_mean': round((2 + totals[dataset_id][1]) / (4 + totals[dataset_id][0]), 4),
        }
        for dataset_id in sorted(totals)
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        backup = Path(tmpdir) / 'datasets'
        shutil.copytree(DATASETS_PATH, backup)
        original_tracking = JSON_PATH.read_bytes() if JSON_PATH.is_file() else None

        try:
            shutil.rmtree(DATASETS_PATH)
            DATASETS_PATH.mkdir(parents=True)
            for index, rows in enumerate(rows_by_file):
                csv_path = DATASETS_PATH / f'{token}_{index}.csv'
                with csv_path.open('w', newline='') as f:
                    writer = csv.writer(f)
                    writer.writerow(['dataset_id', 'trials', 'successes'])
                    writer.writerows(rows)

            if JSON_PATH.exists() or JSON_PATH.is_symlink():
                JSON_PATH.unlink()
            run_analyzer()

            assert JSON_PATH.is_file(), 'analyze.py did not create tracking.json for fresh inputs.'
            with JSON_PATH.open() as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError:
                    pytest.fail('tracking.json produced for fresh inputs is not valid JSON.')

            assert data.get('prior_alpha') == 2
            assert data.get('prior_beta') == 2
            assert isinstance(data.get('results'), list)
            assert data['results'] == expected_results, (
                'analyze.py did not correctly aggregate and calculate results for fresh CSV inputs.'
            )
        finally:
            shutil.rmtree(DATASETS_PATH, ignore_errors=True)
            shutil.copytree(backup, DATASETS_PATH)
            if JSON_PATH.exists() or JSON_PATH.is_symlink():
                JSON_PATH.unlink()
            if original_tracking is not None:
                JSON_PATH.write_bytes(original_tracking)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
