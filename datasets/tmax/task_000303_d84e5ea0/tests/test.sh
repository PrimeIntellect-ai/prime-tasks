#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import runpy
import tempfile

import matplotlib.image as mpimg
import numpy as np
import pytest

ANALYZE_PATH = '/home/user/analyze.py'
JSON_PATH = '/home/user/top_anomalies.json'
PNG_PATH = '/home/user/anomaly_plot.png'

CANONICAL_ROWS = [
    ('2023-01-01T00:00', 1.0, 2.0, 0.5),
    ('2023-01-01T01:00', 1.2, 2.1, 0.6),
    ('2023-01-01T02:00', 0.9, 1.9, 0.7),
    ('2023-01-01T04:00', 3.0, 4.0, 0.9),
    ('2023-01-01T05:00', 3.5, 4.5, 1.0),
    ('2023-01-01T06:00', 4.0, 5.0, 1.1),
    ('2023-01-01T07:00', 3.8, 4.1, 1.5),
    ('2023-01-01T09:00', 1.0, 1.0, 0.5),
    ('2023-01-01T10:00', 5.0, 1.0, 2.0),
    ('2023-01-01T11:00', 1.0, 5.0, 0.1),
]


def rolling_sample_cov(rows):
    result = []
    for i in range(len(rows)):
        if i < 2:
            result.append(0.0)
            continue
        window = rows[i - 2:i + 1]
        xs = [row[1] for row in window]
        ys = [row[2] for row in window]
        x_mean = sum(xs) / 3.0
        y_mean = sum(ys) / 3.0
        result.append(sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys)) / 2.0)
    return result


def expected_top_timestamps(rows):
    covariances = rolling_sample_cov(rows)
    scored = [
        (2.5 * row[3] + 1.5 * covariance, row[0])
        for row, covariance in zip(rows, covariances)
    ]
    return [timestamp for _, timestamp in sorted(scored, key=lambda item: item[0], reverse=True)[:3]]


def test_pipeline_functions_on_independent_input():
    namespace = runpy.run_path(ANALYZE_PATH, run_name='analyze_under_test')
    for name in ('load_and_clean_data', 'calculate_rolling_cov', 'apply_model'):
        assert name in namespace and callable(namespace[name]), f'Missing callable function: {name}'

    with tempfile.TemporaryDirectory() as temp_dir:
        csv_path = os.path.join(temp_dir, 'input.csv')
        with open(csv_path, 'w', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['timestamp', 'sensor_a', 'sensor_b', 'sensor_c'])
            writer.writerows([
                ['t0', '1.0', '2.0', '0.5'],
                ['bad_a', 'ERR', '3.0', '0.8'],
                ['t1', '2.0', '1.0', '1.0'],
                ['bad_c', '4.0', '5.0', 'not-a-number'],
                ['t2', '4.0', '3.0', '1.5'],
                ['t3', '3.0', '7.0', '2.0'],
                ['t4', '8.0', '4.0', '0.25'],
            ])

        df = namespace['load_and_clean_data'](csv_path)
        assert list(df['timestamp']) == ['t0', 't1', 't2', 't3', 't4']
        for column in ('sensor_a', 'sensor_b', 'sensor_c'):
            assert np.issubdtype(df[column].dtype, np.number), f'{column} was not converted to numeric values'

        df = namespace['calculate_rolling_cov'](df)
        independent_rows = [
            ('t0', 1.0, 2.0, 0.5),
            ('t1', 2.0, 1.0, 1.0),
            ('t2', 4.0, 3.0, 1.5),
            ('t3', 3.0, 7.0, 2.0),
            ('t4', 8.0, 4.0, 0.25),
        ]
        expected_cov = rolling_sample_cov(independent_rows)
        assert np.allclose(df['rolling_cov_a_b'].to_numpy(dtype=float), expected_cov, rtol=1e-10, atol=1e-10)

        df = namespace['apply_model'](df)
        expected_scores = [2.5 * row[3] + 1.5 * cov for row, cov in zip(independent_rows, expected_cov)]
        assert np.allclose(df['anomaly_score'].to_numpy(dtype=float), expected_scores, rtol=1e-10, atol=1e-10)


def test_top_anomalies_json():
    assert os.path.exists(JSON_PATH), f'Missing file: {JSON_PATH}. The script did not create the output JSON.'
    with open(JSON_PATH, 'r') as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f'The file {JSON_PATH} does not contain valid JSON.')

    expected = expected_top_timestamps(CANONICAL_ROWS)
    assert isinstance(data, list), f'Expected {JSON_PATH} to contain a list, got {type(data).__name__}.'
    assert data == expected, f'The top anomalies list is incorrect. Expected {expected}, but got {data}.'


def test_anomaly_plot_png():
    assert os.path.exists(PNG_PATH), f'Missing file: {PNG_PATH}. The script did not save the plot.'
    with open(PNG_PATH, 'rb') as handle:
        header = handle.read(8)
    expected_magic = b'\x89PNG\r\n\x1a\n'
    assert header == expected_magic, f'The file {PNG_PATH} is not a valid PNG image. Ensure matplotlib saves correctly using a headless backend.'

    try:
        image = mpimg.imread(PNG_PATH)
    except Exception as exc:
        pytest.fail(f'The plot is not a decodable PNG image: {exc}')
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, 'The saved plot has invalid dimensions.'
    assert np.isfinite(image).all(), 'The saved plot contains invalid pixel values.'
    assert float(np.max(image) - np.min(image)) > 0.05, 'The saved plot is blank or visually empty.'
TEST_EOF

rm -f /home/user/top_anomalies.json /home/user/anomaly_plot.png

if timeout 30s python3 /home/user/analyze.py >/tmp/analyze.stdout 2>/tmp/analyze.stderr && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/analyze.stdout 2>/dev/null || true
    cat /tmp/analyze.stderr 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
