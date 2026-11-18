#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import glob
import json
import math
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

SCRIPT = '/home/user/process_and_plot.py'
RESULTS = '/home/user/output/pca_results.csv'
PLOT = '/home/user/output/pca_plot.png'


def run_script(command=None):
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    return subprocess.run(
        command or [sys.executable, SCRIPT],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def assert_valid_png(path):
    assert os.path.isfile(path), f'The plot file {path} is missing.'
    assert os.path.getsize(path) > 0, f'The plot file {path} is empty.'
    with open(path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'The plot is not a valid PNG file.'
    image = mpimg.imread(path)
    assert image.ndim in (2, 3), 'The PNG does not contain a valid image array.'
    assert image.shape[0] > 10 and image.shape[1] > 10, 'The PNG is implausibly small.'
    assert np.isfinite(image).all(), 'The PNG contains invalid pixel values.'
    assert float(np.max(image) - np.min(image)) > 0.01, 'The PNG is blank or uniform.'


def test_00_script_exists_and_runs_headlessly():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} is missing.'
    assert not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular script, not a symlink.'
    os.makedirs('/home/user/output', exist_ok=True)
    for path in (RESULTS, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    completed = run_script()
    assert completed.returncode == 0, (
        'process_and_plot.py failed when executed headlessly.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )


def test_pca_plot_exists():
    plot_path = '/home/user/output/pca_plot.png'
    assert os.path.isfile(plot_path), f"The plot file {plot_path} is missing. Ensure the script correctly saves the plot."
    assert os.path.getsize(plot_path) > 0, f"The plot file {plot_path} is empty."
    assert_valid_png(plot_path)


def test_pca_results_exists_and_format():
    results_path = '/home/user/output/pca_results.csv'
    assert os.path.isfile(results_path), f"The results file {results_path} is missing."

    with open(results_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['server_id', 'pc1', 'pc2'], f"The header in {results_path} is incorrect. Expected ['server_id', 'pc1', 'pc2'], got {header}."

        rows = list(reader)
        assert len(rows) == 3, f"Expected 3 rows of data, got {len(rows)}."

        server_ids = [row[0] for row in rows]
        assert server_ids == ['srv_01', 'srv_02', 'srv_03'], f"The rows should be sorted ascending by server_id. Got {server_ids}."


def test_pca_results_values():
    results_path = '/home/user/output/pca_results.csv'
    assert os.path.isfile(results_path), "The results file is missing."

    expected_abs_pc1 = {
        'srv_01': 0.10177708307221651,
        'srv_02': 2.120353065099309,
        'srv_03': 2.2221301481715266
    }

    expected_abs_pc2 = {
        'srv_01': 0.06326694672051286,
        'srv_02': 0.021028741369766943,
        'srv_03': 0.08429568809028017
    }

    with open(results_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    for row in rows:
        server_id = row['server_id']
        pc1 = float(row['pc1'])
        pc2 = float(row['pc2'])

        # Check absolute values to account for PCA sign flips
        assert math.isclose(abs(pc1), expected_abs_pc1[server_id], rel_tol=1e-4), \
            f"PC1 value for {server_id} is incorrect. Expected abs value ~{expected_abs_pc1[server_id]}, got {pc1}."

        assert math.isclose(abs(pc2), expected_abs_pc2[server_id], rel_tol=1e-4), \
            f"PC2 value for {server_id} is incorrect. Expected abs value ~{expected_abs_pc2[server_id]}, got {pc2}."


def component_matches(actual, expected):
    actual = np.asarray(actual, dtype=float)
    expected = np.asarray(expected, dtype=float)
    return np.allclose(actual, expected, rtol=1e-7, atol=1e-9) or np.allclose(
        actual, -expected, rtol=1e-7, atol=1e-9
    )


def test_dynamic_pipeline_reproducibility_and_plot_contents():
    data_dir = '/home/user/data'
    for path in glob.glob(os.path.join(data_dir, '*.csv')):
        os.remove(path)

    day1 = '''server_id,cpu_usage,memory_usage,disk_io,network_tx,network_rx
node_d,73,44,880,910,310
node_b,21,76,330,240,810
node_a,48,35,610,530,460
node_c,91,63,1250,1320,720
'''
    day2 = '''server_id,cpu_usage,memory_usage,disk_io,network_tx,network_rx
node_a,52,39,670,590,500
node_c,87,69,1170,1260,780
node_d,68,49,940,850,350
node_b,27,72,390,300,750
'''
    day3 = '''server_id,cpu_usage,memory_usage,disk_io,network_tx,network_rx
node_c,95,66,1210,1380,750
node_a,45,42,640,560,550
node_b,24,79,360,270,840
node_d,76,46,910,880,290
'''
    for name, contents in [('sample_1.csv', day1), ('sample_2.csv', day2), ('sample_3.csv', day3)]:
        with open(os.path.join(data_dir, name), 'w') as f:
            f.write(contents)

    files = sorted(glob.glob(os.path.join(data_dir, '*.csv')))
    source = pd.concat([pd.read_csv(path) for path in files], ignore_index=True)
    metric_columns = ['cpu_usage', 'memory_usage', 'disk_io', 'network_tx', 'network_rx']
    aggregated = source.groupby('server_id', as_index=False)[metric_columns].mean()
    aggregated = aggregated.sort_values('server_id').reset_index(drop=True)
    standardized = StandardScaler().fit_transform(aggregated[metric_columns])
    expected = PCA(n_components=2, svd_solver='full', random_state=42).fit_transform(standardized)

    for path in (RESULTS, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    first_run = run_script()
    assert first_run.returncode == 0, f'Dynamic-data execution failed:\n{first_run.stderr}'
    first_results = pd.read_csv(RESULTS)
    assert_valid_png(PLOT)
    with open(PLOT, 'rb') as f:
        first_png = f.read()

    assert list(first_results.columns) == ['server_id', 'pc1', 'pc2']
    assert first_results['server_id'].tolist() == aggregated['server_id'].tolist()
    assert component_matches(first_results['pc1'], expected[:, 0]), 'Dynamic-data PC1 values are incorrect.'
    assert component_matches(first_results['pc2'], expected[:, 1]), 'Dynamic-data PC2 values are incorrect.'

    runner = '/tmp/instrumented_runner.py'
    capture_path = '/tmp/pipeline_capture.json'
    with open(runner, 'w') as f:
        f.write(r'''import json
import runpy
import numpy as np
import matplotlib.axes
import sklearn.decomposition

capture = {'scatter': [], 'pca_calls': []}
original_scatter = matplotlib.axes.Axes.scatter
original_pca = sklearn.decomposition.PCA

def tracked_scatter(self, x, y, *args, **kwargs):
    capture['scatter'].append({
        'x': np.asarray(x, dtype=float).reshape(-1).tolist(),
        'y': np.asarray(y, dtype=float).reshape(-1).tolist(),
    })
    return original_scatter(self, x, y, *args, **kwargs)

def tracked_pca(*args, **kwargs):
    capture['pca_calls'].append({
        'svd_solver': kwargs.get('svd_solver'),
        'random_state': kwargs.get('random_state'),
        'n_components': kwargs.get('n_components', args[0] if args else None),
    })
    return original_pca(*args, **kwargs)

matplotlib.axes.Axes.scatter = tracked_scatter
sklearn.decomposition.PCA = tracked_pca
runpy.run_path('/home/user/process_and_plot.py', run_name='__main__')
with open('/tmp/pipeline_capture.json', 'w') as out:
    json.dump(capture, out)
''')

    if os.path.exists(capture_path):
        os.remove(capture_path)
    second_run = run_script([sys.executable, runner])
    assert second_run.returncode == 0, f'Second dynamic-data execution failed:\n{second_run.stderr}'
    second_results = pd.read_csv(RESULTS)
    assert_valid_png(PLOT)
    with open(PLOT, 'rb') as f:
        second_png = f.read()

    pd.testing.assert_frame_equal(first_results, second_results, check_exact=True)
    assert first_png == second_png, 'The generated PNG differs between identical runs.'

    with open(capture_path) as f:
        capture = json.load(f)
    assert any(
        call.get('n_components') == 2 and
        call.get('svd_solver') == 'full' and
        call.get('random_state') == 42
        for call in capture['pca_calls']
    ), "PCA must be configured with n_components=2, svd_solver='full', and random_state=42."

    plotted_correctly = False
    for call in capture['scatter']:
        if len(call['x']) != len(second_results) or len(call['y']) != len(second_results):
            continue
        if np.allclose(call['x'], second_results['pc1'], rtol=1e-7, atol=1e-9) and \
           np.allclose(call['y'], second_results['pc2'], rtol=1e-7, atol=1e-9):
            plotted_correctly = True
            break
    assert plotted_correctly, 'The saved visualization was not generated from the computed pc1 and pc2 coordinates.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
