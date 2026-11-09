#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'INSTRUMENT_EOF' > /tmp/instrument_process.py
import contextlib
import hashlib
import io
import os
import re
import runpy
import sys

seed = int(sys.argv[1])
script = '/home/user/ml_pipeline/process_data.py'
plot_path = '/home/user/ml_pipeline/pca_plot.png'

import matplotlib
matplotlib.use('Agg')
import matplotlib.image as mpimg
import matplotlib.pyplot as plt
from matplotlib.figure import Figure
import numpy as np
from scipy import stats
from sklearn.decomposition import PCA

# Independently derive the data, PCA projection, and statistics required by the
# unchanged statistical code.
np.random.seed(seed)
expected_g1 = np.random.randn(50, 20) + 0.5
expected_g2 = np.random.randn(50, 20) - 0.5
expected_data = np.vstack((expected_g1, expected_g2))
expected_reduced = PCA(n_components=2).fit_transform(expected_data)
expected_pc1_g1 = expected_reduced[:50, 0]
expected_pc1_g2 = expected_reduced[50:, 0]
_, expected_p = stats.ttest_ind(expected_pc1_g1, expected_pc1_g2)
expected_cm = np.mean(expected_pc1_g1) - np.mean(expected_pc1_g2)
expected_se = np.sqrt(np.var(expected_pc1_g1, ddof=1)/50 + np.var(expected_pc1_g2, ddof=1)/50)
expected_low = expected_cm - 1.96 * expected_se
expected_high = expected_cm + 1.96 * expected_se

calls = {'seed': False, 'pca': False, 'ttest': False, 'scatter': False, 'save': False}
saved_hash = [None]

orig_seed = np.random.seed
orig_fit_transform = PCA.fit_transform
orig_ttest = stats.ttest_ind
orig_scatter = plt.scatter
orig_fig_save = Figure.savefig

def checked_seed(value, *args, **kwargs):
    assert int(value) == seed, 'numpy was not seeded with the CLI seed'
    calls['seed'] = True
    return orig_seed(value, *args, **kwargs)

def checked_fit_transform(self, x, *args, **kwargs):
    x = np.asarray(x)
    assert getattr(self, 'n_components', None) == 2, 'PCA must use two components'
    assert x.shape == (100, 20) and np.array_equal(x, expected_data), 'PCA received incorrect synthetic data'
    result = orig_fit_transform(self, x, *args, **kwargs)
    assert np.allclose(result, expected_reduced, rtol=1e-11, atol=1e-11), 'PCA projection is incorrect'
    calls['pca'] = True
    return result

def checked_ttest(a, b, *args, **kwargs):
    assert np.allclose(a, expected_pc1_g1, rtol=1e-11, atol=1e-11)
    assert np.allclose(b, expected_pc1_g2, rtol=1e-11, atol=1e-11)
    calls['ttest'] = True
    return orig_ttest(a, b, *args, **kwargs)

def checked_scatter(x, y, *args, **kwargs):
    points = np.column_stack((np.asarray(x), np.asarray(y)))
    assert points.shape == (100, 2)
    assert np.allclose(points, expected_reduced, rtol=1e-11, atol=1e-11), 'scatter plot does not contain the PCA projection'
    calls['scatter'] = True
    return orig_scatter(x, y, *args, **kwargs)

def checked_savefig(self, fname, *args, **kwargs):
    assert os.path.abspath(os.fspath(fname)) == plot_path, 'figure was saved to the wrong path'
    found = False
    for ax in self.axes:
        for collection in ax.collections:
            try:
                offsets = np.asarray(collection.get_offsets(), dtype=float)
                if offsets.shape == expected_reduced.shape and np.allclose(offsets, expected_reduced, rtol=1e-11, atol=1e-11):
                    found = True
            except Exception:
                pass
    assert found, 'saved figure does not contain the expected PCA scatter points'
    result = orig_fig_save(self, fname, *args, **kwargs)
    with open(plot_path, 'rb') as f:
        saved_hash[0] = hashlib.sha256(f.read()).hexdigest()
    calls['save'] = True
    return result

np.random.seed = checked_seed
PCA.fit_transform = checked_fit_transform
stats.ttest_ind = checked_ttest
plt.scatter = checked_scatter
Figure.savefig = checked_savefig

sys.argv = [script, str(seed)]
stdout = io.StringIO()
with contextlib.redirect_stdout(stdout):
    runpy.run_path(script, run_name='__main__')

assert all(calls.values()), 'process_data.py did not execute every required pipeline stage'
assert os.path.isfile(plot_path), 'plot file is missing after process_data.py completed'
with open(plot_path, 'rb') as f:
    final_bytes = f.read()
assert final_bytes.startswith(b'\x89PNG\r\n\x1a\n'), 'pca_plot.png is not a PNG image'
assert hashlib.sha256(final_bytes).hexdigest() == saved_hash[0], 'saved PCA figure was replaced after rendering'
image = mpimg.imread(plot_path)
assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
assert float(np.std(image)) > 0.01, 'pca_plot.png is blank'

text = stdout.getvalue()
def value(label):
    match = re.search(r'^' + re.escape(label) + r'\s*:\s*([-+0-9.eE]+)\s*$', text, re.MULTILINE)
    assert match, 'missing output field ' + label
    return float(match.group(1))

assert np.isclose(value('P-VALUE'), expected_p, rtol=1e-10, atol=1e-12)
assert np.isclose(value('CI_LOW'), expected_low, rtol=1e-10, atol=1e-12)
assert np.isclose(value('CI_HIGH'), expected_high, rtol=1e-10, atol=1e-12)
INSTRUMENT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import secrets
import subprocess

PIPELINE_DIR = '/home/user/ml_pipeline'
VENV_PYTHON = '/home/user/venv/bin/python'
PROCESS_SCRIPT = os.path.join(PIPELINE_DIR, 'process_data.py')
RUN_SCRIPT = os.path.join(PIPELINE_DIR, 'run.sh')
PLOT_FILE = os.path.join(PIPELINE_DIR, 'pca_plot.png')
SUMMARY_FILE = os.path.join(PIPELINE_DIR, 'summary.tsv')
EXPECTED_CACHE = {}


def get_file_hash(filepath):
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def expected_stats(seed):
    if seed not in EXPECTED_CACHE:
        code = r'''import json, sys
import numpy as np
from scipy import stats
from sklearn.decomposition import PCA
seed = int(sys.argv[1])
np.random.seed(seed)
g1 = np.random.randn(50, 20) + 0.5
g2 = np.random.randn(50, 20) - 0.5
data = np.vstack((g1, g2))
reduced = PCA(n_components=2).fit_transform(data)
a, b = reduced[:50, 0], reduced[50:, 0]
_, p = stats.ttest_ind(a, b)
cm = np.mean(a) - np.mean(b)
se = np.sqrt(np.var(a, ddof=1)/50 + np.var(b, ddof=1)/50)
print(json.dumps([float(p), float(cm - 1.96*se), float(cm + 1.96*se)]))'''
        result = subprocess.run([VENV_PYTHON, '-c', code, str(seed)], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        EXPECTED_CACHE[seed] = json.loads(result.stdout)
    return EXPECTED_CACHE[seed]


def assert_row(line, seed):
    fields = line.split('\t')
    assert len(fields) == 4, 'summary row must contain exactly four tab-separated fields'
    assert fields[0] == str(seed), 'summary row contains the wrong seed'
    try:
        actual = [float(x) for x in fields[1:]]
    except ValueError as exc:
        raise AssertionError('summary statistics must be numeric') from exc
    expected = expected_stats(seed)
    for got, want in zip(actual, expected):
        assert math.isfinite(got)
        assert math.isclose(got, want, rel_tol=1e-10, abs_tol=1e-12), (got, want)


def direct_process(seed):
    result = subprocess.run([VENV_PYTHON, PROCESS_SCRIPT, str(seed)], cwd=PIPELINE_DIR,
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(PLOT_FILE)
    assert_row_from_stdout(result.stdout, seed)
    with open(PLOT_FILE, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n'
    return get_file_hash(PLOT_FILE)


def assert_row_from_stdout(text, seed):
    values = {}
    for line in text.splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            if key.strip() in ('P-VALUE', 'CI_LOW', 'CI_HIGH'):
                values[key.strip()] = float(value.strip())
    assert set(values) == {'P-VALUE', 'CI_LOW', 'CI_HIGH'}
    actual = [values['P-VALUE'], values['CI_LOW'], values['CI_HIGH']]
    for got, want in zip(actual, expected_stats(seed)):
        assert math.isclose(got, want, rel_tol=1e-10, abs_tol=1e-12)


def test_packages_installed():
    assert os.path.exists(VENV_PYTHON), 'Virtual environment python not found.'
    result = subprocess.run([VENV_PYTHON, '-c', 'import numpy, scipy, sklearn, matplotlib'], capture_output=True)
    assert result.returncode == 0, 'Not all required packages are installed in the virtual environment.'


def test_process_data_modifications():
    with open(PROCESS_SCRIPT, 'r') as f:
        content = f.read()
    assert 'plt.show()' not in content, 'plt.show() should be removed from process_data.py'
    assert 'pca_plot.png' in content, 'process_data.py should save the plot to pca_plot.png'
    assert 'sys.argv' in content, 'process_data.py should read the seed from command line arguments'

    seed = secrets.randbelow(2_000_000_000) + 1000
    result = subprocess.run([VENV_PYTHON, '/tmp/instrument_process.py', str(seed)],
                            cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, 'Instrumented pipeline validation failed:\n' + result.stdout + result.stderr


def test_run_sh_execution_and_reproducibility():
    for path in (PLOT_FILE, SUMMARY_FILE):
        if os.path.exists(path):
            os.remove(path)

    result1 = subprocess.run(['bash', RUN_SCRIPT, '42'], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result1.returncode == 0, f'run.sh failed with seed 42. stderr: {result1.stderr}'
    assert os.path.exists(PLOT_FILE), 'pca_plot.png was not generated.'
    hash_42_1 = get_file_hash(PLOT_FILE)
    assert os.path.exists(SUMMARY_FILE), 'summary.tsv was not generated.'
    with open(SUMMARY_FILE) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 2
    assert lines[0] == 'Seed\tP-Value\tCI_Lower\tCI_Upper'
    assert lines[1].startswith('42\t')
    assert_row(lines[1], 42)
    assert direct_process(42) == hash_42_1, 'run.sh plot differs from process_data.py output'

    os.remove(PLOT_FILE)
    result2 = subprocess.run(['bash', RUN_SCRIPT, '42'], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result2.returncode == 0, 'run.sh failed on second run.'
    hash_42_2 = get_file_hash(PLOT_FILE)
    assert hash_42_1 == hash_42_2, 'pca_plot.png is not reproducible for the same seed.'
    with open(SUMMARY_FILE) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 3
    assert lines[1] == lines[2]
    assert_row(lines[2], 42)

    os.remove(PLOT_FILE)
    result3 = subprocess.run(['bash', RUN_SCRIPT, '99'], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result3.returncode == 0, 'run.sh failed with seed 99.'
    hash_99 = get_file_hash(PLOT_FILE)
    assert hash_99 != hash_42_1, 'pca_plot.png should change when a different seed is used.'
    with open(SUMMARY_FILE) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 4
    assert lines[3].startswith('99\t')
    assert_row(lines[3], 99)
    assert direct_process(99) == hash_99, 'run.sh did not preserve the generated PCA plot'

    # Unpredictable challenge closes fixed-seed/fixed-output implementations.
    seed = secrets.randbelow(2_000_000_000) + 1000
    while seed in (42, 99):
        seed += 1
    result4 = subprocess.run(['bash', RUN_SCRIPT, str(seed)], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result4.returncode == 0, result4.stderr
    challenged_hash = get_file_hash(PLOT_FILE)
    with open(SUMMARY_FILE) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 5
    assert_row(lines[-1], seed)
    assert direct_process(seed) == challenged_hash, 'dynamic-seed plot was not generated by process_data.py'


def test_run_sh_default_seed():
    if os.path.exists(PLOT_FILE):
        os.remove(PLOT_FILE)
    result = subprocess.run(['bash', RUN_SCRIPT], cwd=PIPELINE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, 'run.sh failed when no arguments were provided.'
    default_hash = get_file_hash(PLOT_FILE)
    with open(SUMMARY_FILE) as f:
        lines = f.read().strip().split('\n')
    last_line = lines[-1]
    assert last_line.startswith('42\t')
    assert_row(last_line, 42)
    assert direct_process(42) == default_hash, 'default run did not generate the seed-42 PCA plot'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
