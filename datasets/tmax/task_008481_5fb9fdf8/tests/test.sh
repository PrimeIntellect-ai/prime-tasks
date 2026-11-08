#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import re
import subprocess
from scipy import stats

PROJECT_DIR = '/home/user/ab_test_pipeline'
RESULTS_PATH = '/home/user/results.json'
DATA_PATH = '/home/user/data.csv'


def test_results_json_exists():
    """Test that the agent compiled and ran the pipeline before verification."""
    assert os.path.isfile(RESULTS_PATH), f"The file {RESULTS_PATH} does not exist."


def test_cargo_tests_and_pipeline_run():
    """Test that the Rust project has a real unit test, passes tests, and generates results."""
    assert os.path.isdir(PROJECT_DIR), f"The directory {PROJECT_DIR} does not exist."

    cargo_toml = os.path.join(PROJECT_DIR, 'Cargo.toml')
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {PROJECT_DIR}."

    try:
        result = subprocess.run(
            ['cargo', 'test'],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=60
        )
        assert result.returncode == 0, f"'cargo test' failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

        listed = subprocess.run(
            ['cargo', 'test', '--bins', '--', '--list'],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=60
        )
        assert listed.returncode == 0, f"Could not list Rust unit tests.\nSTDOUT:\n{listed.stdout}\nSTDERR:\n{listed.stderr}"
        listed_tests = [line for line in listed.stdout.splitlines() if line.strip().endswith(': test')]
        assert listed_tests, "No executable Rust unit test was found in the binary target."

        rust_sources = []
        for root, _, files in os.walk(os.path.join(PROJECT_DIR, 'src')):
            for name in files:
                if name.endswith('.rs'):
                    with open(os.path.join(root, name), 'r', encoding='utf-8') as f:
                        rust_sources.append(f.read())
        assert any(re.search(r'#\s*\[\s*test\s*\]', source) for source in rust_sources), \
            "Rust source does not contain the required #[test] unit test."

        os.remove(RESULTS_PATH)
        run = subprocess.run(
            ['cargo', 'run', '--quiet'],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=60
        )
        assert run.returncode == 0, f"'cargo run' failed.\nSTDOUT:\n{run.stdout}\nSTDERR:\n{run.stderr}"
        assert os.path.isfile(RESULTS_PATH), "Running the Rust pipeline did not generate /home/user/results.json."
    except FileNotFoundError:
        assert False, "cargo command not found. Is Rust installed?"


def test_results_json_values():
    """Test all Welch statistics and confidence interval against independently derived values."""
    assert os.path.isfile(DATA_PATH), f"Data file {DATA_PATH} missing."

    group_a_scores = []
    group_b_scores = []

    with open(DATA_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            duration = float(row['session_duration'])
            items = float(row['items_viewed'])
            score = (duration * 0.5) + (items * 2.5)
            if row['group'] == 'A':
                group_a_scores.append(score)
            elif row['group'] == 'B':
                group_b_scores.append(score)

    n_a = len(group_a_scores)
    n_b = len(group_b_scores)
    assert n_a > 1 and n_b > 1

    mean_a = sum(group_a_scores) / n_a
    mean_b = sum(group_b_scores) / n_b
    var_a = sum((x - mean_a) ** 2 for x in group_a_scores) / (n_a - 1)
    var_b = sum((x - mean_b) ** 2 for x in group_b_scores) / (n_b - 1)

    term_a = var_a / n_a
    term_b = var_b / n_b
    se = math.sqrt(term_a + term_b)
    diff = mean_b - mean_a
    t_stat = diff / se
    degrees_freedom = ((term_a + term_b) ** 2) / (
        (term_a ** 2) / (n_a - 1) + (term_b ** 2) / (n_b - 1)
    )
    p_value = 2.0 * stats.t.sf(abs(t_stat), degrees_freedom)
    critical_t = stats.t.ppf(0.975, degrees_freedom)
    ci_lower = diff - critical_t * se
    ci_upper = diff + critical_t * se

    with open(RESULTS_PATH, 'r', encoding='utf-8') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, "results.json is not a valid JSON file."

    expected_keys = {"mean_a", "mean_b", "t_statistic", "p_value", "ci_lower", "ci_upper"}
    missing_keys = expected_keys - set(results.keys())
    assert not missing_keys, f"results.json is missing keys: {missing_keys}"
    assert set(results.keys()) == expected_keys, f"results.json must have exactly these keys: {sorted(expected_keys)}"

    for key in expected_keys:
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), \
            f"{key} must be numeric"
        assert math.isfinite(results[key]), f"{key} must be finite"

    # Preserve the original checks.
    assert math.isclose(results['mean_a'], mean_a, abs_tol=1e-3), f"mean_a expected ~{mean_a:.4f}, got {results['mean_a']}"
    assert math.isclose(results['mean_b'], mean_b, abs_tol=1e-3), f"mean_b expected ~{mean_b:.4f}, got {results['mean_b']}"
    assert math.isclose(results['t_statistic'], t_stat, abs_tol=1e-3), f"t_statistic expected ~{t_stat:.4f}, got {results['t_statistic']}"
    assert 0.0 <= results['p_value'] <= 1.0, f"p_value {results['p_value']} is out of bounds [0, 1]"
    assert results['ci_lower'] < results['ci_upper'], "ci_lower must be less than ci_upper"
    assert results['ci_lower'] < diff < results['ci_upper'], "Difference in means must be within the confidence interval"

    # Require every reported value to equal the independently calculated value rounded to 4 places.
    expected = {
        'mean_a': round(mean_a, 4),
        'mean_b': round(mean_b, 4),
        't_statistic': round(t_stat, 4),
        'p_value': round(float(p_value), 4),
        'ci_lower': round(float(ci_lower), 4),
        'ci_upper': round(float(ci_upper), 4),
    }
    for key, value in expected.items():
        assert math.isclose(results[key], value, rel_tol=0.0, abs_tol=1e-9), \
            f"{key} expected {value:.4f}, got {results[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
