#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import stat
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd

BASE = '/home/user'
SCRIPT = os.path.join(BASE, 'run_analysis.py')
CSV_OUT = os.path.join(BASE, 'correlation_matrix.csv')
PNG_OUT = os.path.join(BASE, 'heatmap.png')
INPUTS = [
    os.path.join(BASE, 'sensor_A.csv'),
    os.path.join(BASE, 'sensor_B.csv'),
    os.path.join(BASE, 'sensor_C.csv'),
]
NAMES = ['temp', 'pressure', 'humidity', 'vibration', 'light']


def expected_matrix():
    a = pd.read_csv(INPUTS[0])
    b = pd.read_csv(INPUTS[1]).rename(columns={'timestamp': 'time'})
    c = pd.read_csv(INPUTS[2])
    merged = a.merge(b, on='time', how='inner').merge(c, on='time', how='inner')
    for name in NAMES:
        merged[name] = pd.to_numeric(merged[name], errors='coerce')
    merged = merged.dropna(subset=NAMES)
    assert len(merged) >= 3, 'Test data did not leave enough valid joined rows'
    return merged[NAMES].corr(method='pearson')


def run_analysis():
    for path in (CSV_OUT, PNG_OUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    assert os.path.exists(SCRIPT), '/home/user/run_analysis.py is missing'
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(SCRIPT), 'run_analysis.py must be a regular file'

    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', SCRIPT], cwd=BASE, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=30
    )
    assert result.returncode == 0, 'run_analysis.py failed:\n' + result.stdout


def check_outputs(expected, check_original_pair=False):
    assert os.path.exists(CSV_OUT), '/home/user/correlation_matrix.csv is missing'
    assert os.path.exists(PNG_OUT), '/home/user/heatmap.png is missing'
    assert os.path.isfile(CSV_OUT), 'correlation_matrix.csv is not a regular file'
    assert os.path.isfile(PNG_OUT), 'heatmap.png is not a regular file'

    size = os.path.getsize(PNG_OUT)
    assert size > 2000, f'/home/user/heatmap.png seems empty/blank (size: {size} bytes)'

    with open(CSV_OUT, newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header[1:] == NAMES, 'Columns in correlation_matrix.csv are incorrect'
        rows = {}
        for row in reader:
            assert len(row) == 6, 'Every matrix row must contain all five correlations'
            rows[row[0]] = [float(x) for x in row[1:]]

    for idx in NAMES:
        assert idx in rows, f'Row {idx} is missing from correlation_matrix.csv'
    assert len(rows) == 5, 'correlation_matrix.csv must contain exactly five sensor rows'

    actual = pd.read_csv(CSV_OUT, index_col=0)
    assert list(actual.columns) == NAMES, 'Correlation columns are not in the required order'
    assert list(actual.index) == NAMES, 'Correlation row index is not in the required order'
    assert actual.shape == (5, 5), 'Correlation matrix must be 5 by 5'

    values = actual.to_numpy(dtype=float)
    wanted = expected.loc[NAMES, NAMES].to_numpy(dtype=float)
    assert np.isfinite(values).all(), 'Correlation matrix contains non-finite values'
    assert np.allclose(values, wanted, rtol=1e-6, atol=1e-7), \
        f'Full correlation matrix is incorrect.\nExpected:\n{expected}\nActual:\n{actual}'

    if check_original_pair:
        temp = [20.5, 21.5, 22.0, 22.5, 23.0]
        light = [100.0, 110.0, 105.0, 120.0, 130.0]
        mean_temp = sum(temp) / len(temp)
        mean_light = sum(light) / len(light)
        num = sum((t - mean_temp) * (l - mean_light) for t, l in zip(temp, light))
        den_t = sum((t - mean_temp) ** 2 for t in temp)
        den_l = sum((l - mean_light) ** 2 for l in light)
        expected_corr = num / math.sqrt(den_t * den_l)
        actual_corr = rows['temp'][NAMES.index('light')]
        assert math.isclose(actual_corr, expected_corr, rel_tol=1e-4, abs_tol=1e-4), \
            f'Expected correlation between temp and light to be {expected_corr}, but got {actual_corr}'

    with open(PNG_OUT, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'heatmap.png is not a PNG file'
    image = np.asarray(mpimg.imread(PNG_OUT))
    assert image.ndim in (2, 3), 'heatmap.png could not be decoded as an image'
    assert image.shape[0] >= 100 and image.shape[1] >= 100, 'heatmap.png is too small to be a usable heatmap'
    pixels = image[..., :3] if image.ndim == 3 else image
    pixels = pixels.astype(float)
    if pixels.size and pixels.max() > 1.0:
        pixels /= 255.0
    assert np.isfinite(pixels).all(), 'heatmap.png contains invalid pixel values'
    assert np.ptp(pixels) > 0.05 and np.std(pixels) > 0.01, 'heatmap.png is blank or effectively uniform'


def write_dynamic_inputs():
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    with open(INPUTS[0], 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['time', 'temp', 'pressure'])
        for t in range(1, 10):
            w.writerow([t, 15 + 0.7 * t + rng.uniform(-1.5, 1.5),
                        970 + rng.uniform(-18, 18) + 0.35 * t * t])
    with open(INPUTS[1], 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['timestamp', 'humidity', 'vibration'])
        for t in range(1, 10):
            humidity = 'N/A' if t == 4 else 35 + rng.uniform(-8, 8) + 0.4 * t
            w.writerow([t, humidity, 0.05 + rng.uniform(0.01, 0.5)])
    with open(INPUTS[2], 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['time', 'light'])
        for t in range(1, 10):
            if t != 2:
                w.writerow([t, 60 + rng.uniform(-25, 25) + 2.2 * t])


def test_analysis_and_outputs():
    backups = {}
    for path in INPUTS:
        with open(path, 'rb') as f:
            backups[path] = f.read()

    original_expected = expected_matrix()
    try:
        run_analysis()
        check_outputs(original_expected, check_original_pair=True)

        write_dynamic_inputs()
        dynamic_expected = expected_matrix()
        run_analysis()
        check_outputs(dynamic_expected)
    finally:
        for path, content in backups.items():
            with open(path, 'wb') as f:
                f.write(content)
        final_expected = expected_matrix()
        run_analysis()
        check_outputs(final_expected, check_original_pair=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
