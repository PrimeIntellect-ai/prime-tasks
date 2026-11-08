#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrument
cat <<'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import os
import numpy as np

_counter = 0

def _is_heatmap_path(path):
    try:
        return os.path.abspath(os.fspath(path)) == '/home/user/heatmap.png'
    except (TypeError, ValueError):
        return False

def _record(array):
    global _counter
    try:
        if np.ma.isMaskedArray(array):
            array = array.filled(np.nan)
        array = np.asarray(array)
        if array.size and np.issubdtype(array.dtype, np.number):
            name = '/tmp/verifier_plot_%d_%d.npy' % (os.getpid(), _counter)
            _counter += 1
            np.save(name, array, allow_pickle=False)
    except Exception:
        pass

# Record the numerical data attached to the figure at the moment heatmap.png is saved.
try:
    from matplotlib.figure import Figure
    _original_savefig = Figure.savefig

    def _checked_savefig(self, fname, *args, **kwargs):
        if _is_heatmap_path(fname):
            for axis in self.axes:
                for image in axis.images:
                    _record(image.get_array())
                for collection in axis.collections:
                    try:
                        _record(collection.get_array())
                    except Exception:
                        pass
        return _original_savefig(self, fname, *args, **kwargs)

    Figure.savefig = _checked_savefig
except Exception:
    pass

# Also support scripts that use matplotlib.image.imsave directly.
try:
    import matplotlib.image as _mimage
    _original_imsave = _mimage.imsave

    def _checked_imsave(fname, arr, *args, **kwargs):
        if _is_heatmap_path(fname):
            _record(arr)
        return _original_imsave(fname, arr, *args, **kwargs)

    _mimage.imsave = _checked_imsave
except Exception:
    pass
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import glob
import math
import re
import stat
import subprocess

import numpy as np
import pytest


@pytest.fixture(scope='session', autouse=True)
def run_analysis_script():
    script = '/home/user/analyze.py'
    assert os.path.exists(script), f'{script} is missing.'
    mode = os.lstat(script).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(script), f'{script} must be a regular Python file.'

    for path in ['/home/user/correlation.csv', '/home/user/covariance.csv', '/home/user/heatmap.png']:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    for path in glob.glob('/tmp/verifier_plot_*.npy'):
        os.remove(path)

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = '/tmp/verifier_instrument' + (os.pathsep + old_pythonpath if old_pythonpath else '')
    try:
        result = subprocess.run(
            ['python3', script],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('analyze.py did not finish within 60 seconds.')

    assert result.returncode == 0, (
        'analyze.py failed when executed.\nSTDOUT:\n%s\nSTDERR:\n%s'
        % (result.stdout, result.stderr)
    )


def get_robust_cov_corr(csv_path):
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = {h: [] for h in header}
        for row in reader:
            if not row:
                continue
            for h, v in zip(header, row):
                data[h].append(float(v))

    def mean(x):
        return sum(x) / len(x)

    def cov(x, y):
        n = len(x)
        mx = mean(x)
        my = mean(y)
        # Two-pass algorithm is numerically stable enough for this offset
        return sum((xi - mx) * (yi - my) for xi, yi in zip(x, y)) / (n - 1)

    cov_matrix = {}
    corr_matrix = {}

    for c1 in header:
        cov_matrix[c1] = {}
        corr_matrix[c1] = {}
        for c2 in header:
            c = cov(data[c1], data[c2])
            vx = cov(data[c1], data[c1])
            vy = cov(data[c2], data[c2])
            r = c / math.sqrt(vx * vy)
            cov_matrix[c1][c2] = round(c, 4)
            corr_matrix[c1][c2] = round(r, 4)

    return header, cov_matrix, corr_matrix


def read_matrix_csv(csv_path):
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)[1:]  # First column is index
        matrix = {}
        for row in reader:
            if not row:
                continue
            idx = row[0]
            matrix[idx] = {}
            for h, v in zip(header, row[1:]):
                matrix[idx][h] = float(v)
    return header, matrix


def assert_exact_csv_format(csv_path, expected_header):
    decimal = re.compile(r'^-?\d+\.\d{4}$')
    with open(csv_path, newline='') as f:
        rows = list(csv.reader(f))

    assert rows, f'{csv_path} is empty.'
    assert rows[0] == [''] + expected_header, f'{csv_path} must retain the sensor column headers.'
    assert len(rows) == len(expected_header) + 1, f'{csv_path} has the wrong number of matrix rows.'
    assert [row[0] for row in rows[1:]] == expected_header, f'{csv_path} must retain sensor row headers in order.'
    for row in rows[1:]:
        assert len(row) == len(expected_header) + 1, f'{csv_path} contains an incomplete matrix row.'
        for value in row[1:]:
            assert decimal.fullmatch(value), f'{csv_path} value {value!r} is not written with exactly four decimal places.'


def test_covariance_matrix():
    assert os.path.exists('/home/user/covariance.csv'), '/home/user/covariance.csv is missing.'

    header, expected_cov, _ = get_robust_cov_corr('/home/user/sensordata.csv')
    assert_exact_csv_format('/home/user/covariance.csv', header)
    out_header, out_cov = read_matrix_csv('/home/user/covariance.csv')

    assert out_header == header, 'Covariance CSV columns do not match sensor data.'

    for c1 in header:
        for c2 in header:
            expected = expected_cov[c1][c2]
            actual = out_cov[c1][c2]
            assert math.isclose(actual, expected, abs_tol=1e-4), f'Covariance mismatch for {c1}, {c2}: expected {expected}, got {actual}'


def test_correlation_matrix():
    assert os.path.exists('/home/user/correlation.csv'), '/home/user/correlation.csv is missing.'

    header, _, expected_corr = get_robust_cov_corr('/home/user/sensordata.csv')
    assert_exact_csv_format('/home/user/correlation.csv', header)
    out_header, out_corr = read_matrix_csv('/home/user/correlation.csv')

    assert out_header == header, 'Correlation CSV columns do not match sensor data.'

    for c1 in header:
        for c2 in header:
            expected = expected_corr[c1][c2]
            actual = out_corr[c1][c2]
            assert math.isclose(actual, expected, abs_tol=1e-4), f'Correlation mismatch for {c1}, {c2}: expected {expected}, got {actual}'


def test_heatmap_generated():
    heatmap_path = '/home/user/heatmap.png'
    assert os.path.exists(heatmap_path), f'{heatmap_path} is missing.'

    size = os.path.getsize(heatmap_path)
    assert size > 1000, f'{heatmap_path} is too small ({size} bytes), likely broken or blank.'

    with open(heatmap_path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f'{heatmap_path} is not a valid PNG file.'

    # Fully decode the PNG and reject blank or trivial images.
    import matplotlib.image as mpimg
    try:
        image = np.asarray(mpimg.imread(heatmap_path))
    except Exception as exc:
        pytest.fail(f'{heatmap_path} could not be fully decoded as a PNG: {exc}')

    assert image.ndim in (2, 3), 'The heatmap has an invalid pixel array.'
    assert image.shape[0] >= 50 and image.shape[1] >= 50, 'The heatmap is not a rendered plot of useful size.'
    assert np.isfinite(image).all(), 'The heatmap contains invalid pixel values.'
    visible = image[..., :3] if image.ndim == 3 and image.shape[2] >= 3 else image
    assert float(np.std(visible)) > 0.01, 'The heatmap is blank or visually constant.'
    pixels = visible.reshape(-1, visible.shape[-1]) if visible.ndim == 3 else visible.reshape(-1, 1)
    stride = max(1, len(pixels) // 10000)
    assert len(np.unique(pixels[::stride], axis=0)) > 8, 'The heatmap lacks meaningful plotted content.'

    # Confirm that the figure saved as heatmap.png actually contained the
    # recomputed correlation matrix, rather than unrelated non-blank artwork.
    sensor_header, _, expected_corr = get_robust_cov_corr('/home/user/sensordata.csv')
    expected = np.array([[expected_corr[r][c] for c in sensor_header] for r in sensor_header], dtype=float)
    matched = False
    for captured_path in glob.glob('/tmp/verifier_plot_*.npy'):
        try:
            candidate = np.asarray(np.load(captured_path, allow_pickle=False), dtype=float)
        except Exception:
            continue
        if candidate.size != expected.size:
            continue
        try:
            candidate = candidate.reshape(expected.shape)
        except ValueError:
            continue
        if np.allclose(candidate, expected, rtol=0, atol=1.1e-4, equal_nan=False):
            matched = True
            break
    assert matched, 'heatmap.png was not saved from the corrected correlation matrix.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
