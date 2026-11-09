#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

from PIL import Image


SENSOR_PATH = '/home/user/sensor_data.csv'
WEIGHTS_PATH = '/home/user/model_weights.json'

CANONICAL_SENSOR_ROWS = [
    {'device_id': 'D1', 'timestamp': '1', 'sensor_A': '0.5', 'sensor_B': '0.6'},
    {'device_id': 'D1', 'timestamp': '2', 'sensor_A': '0.7', 'sensor_B': '0.8'},
    {'device_id': 'D1', 'timestamp': '3', 'sensor_A': '0.9', 'sensor_B': '0.9'},
    {'device_id': 'D1', 'timestamp': '4', 'sensor_A': '1.0', 'sensor_B': '0.8'},
    {'device_id': 'D2', 'timestamp': '1', 'sensor_A': '0.2', 'sensor_B': '0.1'},
    {'device_id': 'D2', 'timestamp': '2', 'sensor_A': '0.3', 'sensor_B': '0.3'},
    {'device_id': 'D2', 'timestamp': '3', 'sensor_A': '0.1', 'sensor_B': '0.2'},
    {'device_id': 'D2', 'timestamp': '4', 'sensor_A': '0.5', 'sensor_B': '0.4'},
]


def sample_covariance(window):
    mean_a = sum(row['sensor_A'] for row in window) / len(window)
    mean_b = sum(row['sensor_B'] for row in window) / len(window)
    return sum(
        (row['sensor_A'] - mean_a) * (row['sensor_B'] - mean_b)
        for row in window
    ) / (len(window) - 1)


def test_processed_data_csv():
    path = '/home/user/processed_data.csv'
    assert os.path.isfile(path), f"File {path} is missing. Did you save the processed data?"

    with open(SENSOR_PATH, newline='') as f:
        source_rows = list(csv.DictReader(f))
    assert source_rows == CANONICAL_SENSOR_ROWS, 'The provided sensor_data.csv was modified.'

    with open(WEIGHTS_PATH) as f:
        model = json.load(f)
    assert model == {'bias': -0.5, 'weights': [1.2, -0.8, 0.5]}, \
        'The provided model_weights.json was modified.'

    rows = [
        {
            'device_id': row['device_id'],
            'timestamp': int(row['timestamp']),
            'sensor_A': float(row['sensor_A']),
            'sensor_B': float(row['sensor_B']),
        }
        for row in source_rows
    ]
    rows.sort(key=lambda row: (row['device_id'], row['timestamp']))

    expected_rows = [['device_id', 'timestamp', 'anomaly_prob']]
    histories = {}
    bias = float(model['bias'])
    w1, w2, w3 = map(float, model['weights'])

    for row in rows:
        history = histories.setdefault(row['device_id'], [])
        history.append(row)
        rolling_cov = sample_covariance(history[-3:]) if len(history) >= 3 else 0.0
        z = bias + w1 * row['sensor_A'] + w2 * row['sensor_B'] + w3 * rolling_cov
        probability = 1.0 / (1.0 + math.exp(-z))
        expected_rows.append([
            row['device_id'],
            str(row['timestamp']),
            f'{probability:.4f}',
        ])

    with open(path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if row]

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in {path}, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def run_heatmap_script():
    script = '/home/user/plot_heatmap.py'
    output = '/home/user/heatmap.png'
    assert os.path.isfile(script), f'File {script} is missing.'
    if os.path.exists(output):
        os.remove(output)

    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    result = subprocess.run(
        ['python3', script],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f'plot_heatmap.py failed in a headless environment:\n{result.stdout}\n{result.stderr}'
    assert os.path.isfile(output), \
        f"File {output} is missing. Did you fix and run the plotting script?"
    with open(output, 'rb') as f:
        return f.read()


def validate_png(path):
    with open(path, 'rb') as f:
        header = f.read(4)
    assert header == b'\x89PNG', f"File {path} is not a valid PNG image."

    with Image.open(path) as image:
        assert image.format == 'PNG', f'File {path} is not a decodable PNG image.'
        image.verify()

    with Image.open(path) as image:
        rgb = image.convert('RGB')
        width, height = rgb.size
        assert width >= 200 and height >= 150, 'The generated heatmap is unexpectedly small.'
        pixels = list(rgb.getdata())
        chromatic = sum(1 for pixel in pixels if max(pixel) - min(pixel) >= 20)
        assert chromatic / len(pixels) > 0.05, \
            'The generated PNG appears blank or does not contain the heatmap.'


def test_heatmap_png_generated():
    path = '/home/user/heatmap.png'
    original_sensor_bytes = open(SENSOR_PATH, 'rb').read()

    original_png = run_heatmap_script()
    validate_png(path)

    alternate_data = (
        'device_id,timestamp,sensor_A,sensor_B\n'
        'X,1,0.0,0.0\n'
        'X,2,1.0,1.0\n'
        'X,3,2.0,2.0\n'
        'X,4,3.0,3.0\n'
    ).encode()

    try:
        with open(SENSOR_PATH, 'wb') as f:
            f.write(alternate_data)
        alternate_png = run_heatmap_script()
        validate_png(path)
        assert alternate_png != original_png, \
            'The generated image does not respond to changes in the sensor correlation data.'
    finally:
        with open(SENSOR_PATH, 'wb') as f:
            f.write(original_sensor_bytes)
        run_heatmap_script()

    validate_png(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
