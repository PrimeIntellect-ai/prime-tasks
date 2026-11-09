#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import secrets
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd

SCRIPT_PATH = '/home/user/etl_benchmark.py'
CSV_PATH = '/home/user/data/batch_stats.csv'
JSON_PATH = '/home/user/benchmark_results.json'
PLOT_PATH = '/home/user/benchmark_plot.png'


def validate_plot():
    assert os.path.isfile(PLOT_PATH), f"Plot file {PLOT_PATH} does not exist. Did you run the script?"
    assert os.path.getsize(PLOT_PATH) > 0, f"Plot file {PLOT_PATH} is empty."
    with open(PLOT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', "benchmark_plot.png is not a PNG file."
    try:
        image = mpimg.imread(PLOT_PATH)
    except Exception as exc:
        raise AssertionError(f"benchmark_plot.png cannot be decoded: {exc}")
    assert image.ndim in (2, 3), "Decoded plot has an invalid shape."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Plot is implausibly small."
    assert np.isfinite(image).all(), "Plot contains invalid pixel data."
    assert float(np.std(image)) > 0.005, "Plot appears to be blank or uniform."


def load_and_validate_results(expected_corr, expected_cov):
    assert os.path.isfile(JSON_PATH), f"Results file {JSON_PATH} does not exist. Did you run the script?"
    with open(JSON_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {JSON_PATH} is not valid JSON: {exc}")

    assert set(results.keys()) == {'correlation', 'covariance'}, \
        "Results JSON must contain exactly the keys 'correlation' and 'covariance'."
    assert isinstance(results['correlation'], (int, float)) and not isinstance(results['correlation'], bool)
    assert isinstance(results['covariance'], (int, float)) and not isinstance(results['covariance'], bool)
    assert results['correlation'] == expected_corr, \
        f"Expected correlation {expected_corr}, got {results['correlation']}."
    assert results['covariance'] == expected_cov, \
        f"Expected covariance {expected_cov}, got {results['covariance']}."


def run_script():
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    env['HOME'] = '/tmp/benchmark-test-home'
    os.makedirs(env['HOME'], exist_ok=True)
    completed = subprocess.run(
        ['python3', SCRIPT_PATH], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, \
        f"Benchmark script failed in a headless environment.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"


def test_benchmark_plot_exists_and_not_empty():
    validate_plot()


def test_benchmark_results_json():
    # Preserve the original fixed-data assertions as well as exact-key validation.
    load_and_validate_results(0.9998, 3060.7143)


def test_script_modifications():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    assert "plt.show()" not in content, "plt.show() should be removed from the script to fix headless execution."
    tree = ast.parse(content, filename=SCRIPT_PATH)

    show_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'show'
    ]
    assert not show_calls, "The script must not call an interactive show() function."

    has_headless_backend = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in {'use', 'switch_backend'} and node.args:
                arg = node.args[0]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str) and arg.value.lower() == 'agg':
                    has_headless_backend = True
            if node.func.attr == 'setdefault' and len(node.args) >= 2:
                key, value = node.args[:2]
                if (isinstance(key, ast.Constant) and key.value == 'MPLBACKEND' and
                        isinstance(value, ast.Constant) and isinstance(value.value, str) and
                        value.value.lower() == 'agg'):
                    has_headless_backend = True
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Subscript):
                    key = target.slice
                    if (isinstance(key, ast.Constant) and key.value == 'MPLBACKEND' and
                            isinstance(node.value, ast.Constant) and
                            isinstance(node.value.value, str) and node.value.value.lower() == 'agg'):
                        has_headless_backend = True

    assert has_headless_backend, "The script must explicitly select the non-interactive Agg backend."


def test_pipeline_on_unseen_inputs():
    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()

    rng = secrets.SystemRandom()
    plot_hashes = []
    try:
        for case in range(2):
            shift = rng.randint(1, 5000)
            scale = rng.uniform(0.07, 0.31)
            rows = [
                {'batch_id': 1, 'record_count': shift + 31,  'inference_time_ms': scale * (shift + 31) + 1.3},
                {'batch_id': 2, 'record_count': shift + 127, 'inference_time_ms': np.nan},
                {'batch_id': 3, 'record_count': shift + 263, 'inference_time_ms': scale * (shift + 263) - 2.1},
                {'batch_id': 4, 'record_count': shift + 389, 'inference_time_ms': 10000.0},
                {'batch_id': 5, 'record_count': shift + 521, 'inference_time_ms': 10000.01 + rng.random() * 900000},
                {'batch_id': 6, 'record_count': shift + 677, 'inference_time_ms': scale * (shift + 677) + 4.7 + case},
                {'batch_id': 7, 'record_count': shift + 811, 'inference_time_ms': scale * (shift + 811) - 3.4},
            ]
            frame = pd.DataFrame(rows)
            frame.to_csv(CSV_PATH, index=False)
            clean = frame[
                frame['inference_time_ms'].notna() &
                (frame['inference_time_ms'] <= 10000)
            ]
            expected_corr = round(clean['record_count'].corr(clean['inference_time_ms']), 4)
            expected_cov = round(clean['record_count'].cov(clean['inference_time_ms']), 4)

            for path in (JSON_PATH, PLOT_PATH):
                if os.path.exists(path):
                    os.remove(path)
            run_script()
            load_and_validate_results(expected_corr, expected_cov)
            validate_plot()
            with open(PLOT_PATH, 'rb') as f:
                plot_hashes.append(hashlib.sha256(f.read()).hexdigest())

        assert plot_hashes[0] != plot_hashes[1], \
            "The generated plot did not respond to different input datasets."
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        try:
            run_script()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
