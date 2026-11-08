#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import secrets
import stat
import subprocess

import numpy as np
import pandas as pd
from PIL import Image
from scipy.stats import mannwhitneyu

DATA_PATH = '/home/user/server_metrics.csv'
JSON_PATH = '/home/user/analysis_results.json'
PLOT_PATH = '/home/user/latency_plot.png'


def test_latency_plot_exists_and_is_png():
    """Verify that the latency plot was created and is a valid PNG file."""
    plot_path = PLOT_PATH
    assert os.path.exists(plot_path), f"Plot file not found at {plot_path}"
    assert os.path.isfile(plot_path), f"Path {plot_path} is not a file"

    with open(plot_path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File {plot_path} is not a valid PNG image"

    # Decode the complete image rather than accepting only a fabricated header.
    with Image.open(plot_path) as image:
        image.verify()
    with Image.open(plot_path) as image:
        image.load()
        assert image.format == 'PNG'
        assert image.width >= 200 and image.height >= 150, "Plot is implausibly small"
        rgb = image.convert('RGB')
        extrema = rgb.getextrema()
        assert any(high - low >= 20 for low, high in extrema), "Plot image is blank"
        colors = rgb.getcolors(maxcolors=1000000)
        assert colors is None or len(colors) >= 16, "Plot lacks graphical content"


def test_analysis_results_json():
    """Verify that the analysis results JSON exists and contains the correct values."""
    json_path = JSON_PATH
    assert os.path.exists(json_path), f"JSON log file not found at {json_path}"
    assert os.path.isfile(json_path), f"Path {json_path} is not a file"

    with open(json_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON"

    assert "algo_A" in results, "Missing 'algo_A' in JSON"
    assert "algo_B" in results, "Missing 'algo_B' in JSON"
    assert "mann_whitney_p_value" in results, "Missing 'mann_whitney_p_value' in JSON"

    for algo in ["algo_A", "algo_B"]:
        for key in ["95th_percentile", "ci_lower", "ci_upper"]:
            assert key in results[algo], f"Missing '{key}' in '{algo}'"

    exp_p95_A = 239.389
    exp_ci_lower_A = 231.144
    exp_ci_upper_A = 247.962
    exp_p95_B = 213.916
    exp_ci_lower_B = 206.940
    exp_ci_upper_B = 221.758

    assert math.isclose(results["algo_A"]["95th_percentile"], exp_p95_A, abs_tol=0.5), \
        f"algo_A 95th_percentile {results['algo_A']['95th_percentile']} not within expected range of {exp_p95_A}"
    assert math.isclose(results["algo_A"]["ci_lower"], exp_ci_lower_A, abs_tol=1.0), \
        f"algo_A ci_lower {results['algo_A']['ci_lower']} not within expected range of {exp_ci_lower_A}"
    assert math.isclose(results["algo_A"]["ci_upper"], exp_ci_upper_A, abs_tol=1.0), \
        f"algo_A ci_upper {results['algo_A']['ci_upper']} not within expected range of {exp_ci_upper_A}"
    assert math.isclose(results["algo_B"]["95th_percentile"], exp_p95_B, abs_tol=0.5), \
        f"algo_B 95th_percentile {results['algo_B']['95th_percentile']} not within expected range of {exp_p95_B}"
    assert math.isclose(results["algo_B"]["ci_lower"], exp_ci_lower_B, abs_tol=1.0), \
        f"algo_B ci_lower {results['algo_B']['ci_lower']} not within expected range of {exp_ci_lower_B}"
    assert math.isclose(results["algo_B"]["ci_upper"], exp_ci_upper_B, abs_tol=1.0), \
        f"algo_B ci_upper {results['algo_B']['ci_upper']} not within expected range of {exp_ci_upper_B}"

    p_value = results["mann_whitney_p_value"]
    assert p_value < 0.001, f"mann_whitney_p_value {p_value} is not less than 0.001"
    return results


def discover_scripts():
    candidates = []
    skipped_dirs = {'.cache', '.local', '.config', '__pycache__', 'venv', '.venv'}
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in skipped_dirs]
        for name in files:
            path = os.path.join(root, name)
            if path in {DATA_PATH, JSON_PATH, PLOT_PATH} or os.path.islink(path):
                continue
            try:
                mode = os.stat(path).st_mode
                if not stat.S_ISREG(mode) or os.path.getsize(path) > 5_000_000:
                    continue
                suffix = os.path.splitext(name)[1].lower()
                with open(path, 'rb') as f:
                    first = f.readline(256)
                if suffix in {'.py', '.sh', '.r'} or first.startswith(b'#!'):
                    candidates.append(path)
            except OSError:
                continue
    return sorted(candidates)


def command_for(path):
    suffix = os.path.splitext(path)[1].lower()
    if suffix == '.py':
        return ['python3', path]
    if suffix == '.sh':
        return ['bash', path]
    if suffix == '.r':
        return ['Rscript', path]
    return [path]


def execute_script(path, timeout=240):
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    return subprocess.run(
        command_for(path), cwd=os.path.dirname(path), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )


def expected_results(frame):
    assert list(frame.columns) == ['algorithm', 'latency_ms']
    assert set(frame['algorithm']) == {'A', 'B'}
    values = {}
    arrays = {}
    for label in ('A', 'B'):
        data = frame.loc[frame['algorithm'] == label, 'latency_ms'].to_numpy(dtype=float)
        assert len(data) > 0 and np.isfinite(data).all()
        arrays[label] = data
        np.random.seed(42)
        boot = np.empty(10000, dtype=float)
        for i in range(10000):
            sample = np.random.choice(data, size=len(data), replace=True)
            boot[i] = np.percentile(sample, 95)
        lower, upper = np.percentile(boot, [2.5, 97.5])
        values[f'algo_{label}'] = {
            '95th_percentile': float(np.percentile(data, 95)),
            'ci_lower': float(lower),
            'ci_upper': float(upper),
        }
    values['mann_whitney_p_value'] = float(
        mannwhitneyu(arrays['A'], arrays['B'], alternative='two-sided').pvalue
    )
    return values


def assert_matches_derived(actual, expected, estimate_tol=0.02):
    for algo in ('algo_A', 'algo_B'):
        for key in ('95th_percentile', 'ci_lower', 'ci_upper'):
            value = actual[algo][key]
            assert isinstance(value, (int, float)) and math.isfinite(value)
            assert math.isclose(value, expected[algo][key], rel_tol=1e-8, abs_tol=estimate_tol), \
                f"{algo}.{key} was {value}, expected {expected[algo][key]}"
    p_value = actual['mann_whitney_p_value']
    assert isinstance(p_value, (int, float)) and math.isfinite(p_value)
    assert 0.0 <= p_value <= 1.0
    assert math.isclose(p_value, expected['mann_whitney_p_value'], rel_tol=1e-6, abs_tol=1e-15), \
        f"Mann-Whitney p-value was {p_value}, expected {expected['mann_whitney_p_value']}"


def make_challenge_frame():
    seed = secrets.randbits(64)
    rng = np.random.default_rng(seed)
    a = rng.gamma(shape=2.3, scale=31.0, size=137) + rng.normal(0, 0.15, 137)
    b = rng.gamma(shape=2.0, scale=35.0, size=149) + rng.normal(0, 0.15, 149)
    frame = pd.concat([
        pd.DataFrame({'algorithm': 'A', 'latency_ms': a}),
        pd.DataFrame({'algorithm': 'B', 'latency_ms': b}),
    ], ignore_index=True)
    return frame.iloc[rng.permutation(len(frame))].reset_index(drop=True)


def test_reproducible_pipeline():
    with open(DATA_PATH, 'rb') as f:
        original_csv = f.read()

    selected = None
    saved_json = None
    saved_plot = None
    try:
        # Outputs must be regenerated by a submitted computation script.
        for script in discover_scripts():
            with open(DATA_PATH, 'wb') as f:
                f.write(original_csv)
            for output in (JSON_PATH, PLOT_PATH):
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass
            try:
                proc = execute_script(script)
            except (OSError, subprocess.SubprocessError):
                continue
            if proc.returncode == 0 and os.path.isfile(JSON_PATH) and os.path.isfile(PLOT_PATH):
                selected = script
                break

        assert selected is not None, "No reproducible analysis script regenerated both required artifacts"

        # Preserve all original fixed assertions.
        test_latency_plot_exists_and_is_png()
        original_actual = test_analysis_results_json()

        # Also derive the answers from the supplied CSV instead of trusting constants.
        original_frame = pd.read_csv(DATA_PATH)
        assert_matches_derived(original_actual, expected_results(original_frame), estimate_tol=1.0)
        with open(PLOT_PATH, 'rb') as f:
            original_plot_hash = hashlib.sha256(f.read()).digest()
            f.seek(0)
            saved_plot = f.read()
        with open(JSON_PATH, 'rb') as f:
            saved_json = f.read()

        # Exercise the same script on an unpredictable replacement dataset.
        challenge = make_challenge_frame()
        challenge.to_csv(DATA_PATH, index=False)
        challenge_expected = expected_results(challenge)
        for output in (JSON_PATH, PLOT_PATH):
            os.remove(output)
        proc = execute_script(selected)
        assert proc.returncode == 0, proc.stderr.decode(errors='replace')
        assert os.path.isfile(JSON_PATH), "Script did not regenerate JSON for changed input"
        assert os.path.isfile(PLOT_PATH), "Script did not regenerate plot for changed input"
        test_latency_plot_exists_and_is_png()
        with open(JSON_PATH) as f:
            challenge_actual = json.load(f)
        assert_matches_derived(challenge_actual, challenge_expected)
        with open(PLOT_PATH, 'rb') as f:
            challenge_plot_hash = hashlib.sha256(f.read()).digest()
        assert challenge_plot_hash != original_plot_hash, "Plot does not respond to changed latency data"
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_csv)
        if saved_json is not None:
            with open(JSON_PATH, 'wb') as f:
                f.write(saved_json)
        if saved_plot is not None:
            with open(PLOT_PATH, 'wb') as f:
                f.write(saved_plot)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
