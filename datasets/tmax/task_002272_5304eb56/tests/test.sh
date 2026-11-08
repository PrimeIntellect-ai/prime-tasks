#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import struct
import zlib

import numpy as np
import pytest
from scipy.integrate import odeint

JSON_PATH = '/home/user/training_entry.json'
PLOT_PATH = '/home/user/kinetics_plot.png'
CSV_PATH = '/home/user/exp_data.csv'


def load_json():
    with open(JSON_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{JSON_PATH} is not a valid JSON file.')


def independently_compute_metrics():
    with open(CSV_PATH, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['time', 'A', 'B', 'C'], 'Experimental CSV has unexpected columns.'
        rows = list(reader)

    assert rows, 'Experimental CSV is empty.'
    times = np.array([float(row['time']) for row in rows], dtype=float)
    experimental = np.array(
        [[float(row['A']), float(row['B']), float(row['C'])] for row in rows],
        dtype=float,
    )

    def model(y, t):
        A, B, C = y
        return [-0.5 * A, 0.5 * A - 0.2 * B, 0.2 * B]

    simulated = odeint(model, [100.0, 0.0, 0.0], times)
    mse = np.mean((simulated - experimental) ** 2, axis=0)
    return {
        'mse_A': float(mse[0]),
        'mse_B': float(mse[1]),
        'mse_C': float(mse[2]),
        'max_B_simulated': float(np.max(simulated[:, 1])),
    }


def decode_png(path):
    with open(path, 'rb') as f:
        raw = f.read()
    assert raw.startswith(b'\x89PNG\r\n\x1a\n'), 'The plot is not a PNG file.'

    pos = 8
    ihdr = None
    palette = None
    idat = bytearray()
    saw_iend = False
    while pos < len(raw):
        assert pos + 12 <= len(raw), 'Truncated PNG chunk.'
        length = struct.unpack('>I', raw[pos:pos + 4])[0]
        kind = raw[pos + 4:pos + 8]
        end = pos + 12 + length
        assert end <= len(raw), 'Truncated PNG chunk data.'
        payload = raw[pos + 8:pos + 8 + length]
        expected_crc = struct.unpack('>I', raw[pos + 8 + length:end])[0]
        assert (zlib.crc32(kind + payload) & 0xffffffff) == expected_crc, 'Invalid PNG chunk CRC.'
        if kind == b'IHDR':
            ihdr = payload
        elif kind == b'PLTE':
            palette = payload
        elif kind == b'IDAT':
            idat.extend(payload)
        elif kind == b'IEND':
            saw_iend = True
            break
        pos = end

    assert ihdr is not None and len(ihdr) == 13, 'PNG has no valid IHDR.'
    assert saw_iend and idat, 'PNG is missing image data or IEND.'
    width, height, depth, color_type, compression, filtering, interlace = struct.unpack('>IIBBBBB', ihdr)
    assert width >= 50 and height >= 50, 'The plot image is implausibly small.'
    assert depth == 8, 'Plot PNG must use standard 8-bit samples.'
    assert compression == 0 and filtering == 0 and interlace == 0, 'Unsupported PNG encoding.'

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    assert channels is not None, 'Unsupported PNG color type.'
    packed = zlib.decompress(bytes(idat))
    stride = width * channels
    assert len(packed) == height * (stride + 1), 'PNG decompressed data has the wrong size.'

    rows = []
    offset = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = packed[offset]
        offset += 1
        encoded = packed[offset:offset + stride]
        offset += stride
        assert filter_type <= 4, 'Invalid PNG scanline filter.'
        row = bytearray(stride)
        for i, value in enumerate(encoded):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = up
            elif filter_type == 3:
                predictor = (left + up) // 2
            else:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else (up if pb <= pc else upper_left)
            row[i] = (value + predictor) & 255
        rows.append(row)
        previous = row

    if color_type == 3:
        assert palette is not None and len(palette) % 3 == 0, 'Indexed PNG has no valid palette.'
        colors = [tuple(palette[i:i + 3]) for i in range(0, len(palette), 3)]
        rgb_rows = [[colors[index] for index in row] for row in rows]
    else:
        rgb_rows = []
        for row in rows:
            converted = []
            for i in range(0, len(row), channels):
                if color_type in (0, 4):
                    converted.append((row[i], row[i], row[i]))
                else:
                    converted.append((row[i], row[i + 1], row[i + 2]))
            rgb_rows.append(converted)
    return width, height, rgb_rows


def test_files_exist():
    assert os.path.exists(JSON_PATH), f'The output JSON file {JSON_PATH} is missing.'
    assert os.path.isfile(JSON_PATH), f'{JSON_PATH} must be a file.'

    assert os.path.exists(PLOT_PATH), f'The plot file {PLOT_PATH} is missing.'
    assert os.path.isfile(PLOT_PATH), f'{PLOT_PATH} must be a file.'


def test_json_structure_and_graph_features():
    assert os.path.exists(JSON_PATH), f'Cannot test JSON structure because {JSON_PATH} is missing.'
    data = load_json()

    assert 'graph_features' in data, "Key 'graph_features' missing from JSON."
    gf = data['graph_features']

    expected_gf = {
        'A': {'in': 0, 'out': 1},
        'B': {'in': 1, 'out': 1},
        'C': {'in': 1, 'out': 0}
    }

    assert gf == expected_gf, f'Graph features are incorrect. Expected {expected_gf}, got {gf}.'


def test_json_max_b():
    assert os.path.exists(JSON_PATH), f'Cannot test max_B_simulated because {JSON_PATH} is missing.'
    data = load_json()

    assert 'max_B_simulated' in data, "Key 'max_B_simulated' missing from JSON."
    max_b = data['max_B_simulated']

    assert isinstance(max_b, (int, float)), f"'max_B_simulated' must be a number, got {type(max_b)}."

    expected_max_b = 46.5457
    assert math.isclose(max_b, expected_max_b, abs_tol=0.2), \
        f"'max_B_simulated' is incorrect. Expected around {expected_max_b}, got {max_b}."


def test_json_mses():
    assert os.path.exists(JSON_PATH), f'Cannot test MSE values because {JSON_PATH} is missing.'
    data = load_json()

    for key in ['mse_A', 'mse_B', 'mse_C']:
        assert key in data, f"Key '{key}' missing from JSON."
        assert isinstance(data[key], (int, float)), f"'{key}' must be a number."

    expected_mses = {
        'mse_A': 3.864,
        'mse_B': 3.829,
        'mse_C': 3.511
    }

    for key, expected_val in expected_mses.items():
        actual_val = data[key]
        assert math.isclose(actual_val, expected_val, abs_tol=0.5), \
            f"'{key}' is incorrect. Expected around {expected_val}, got {actual_val}."


def test_exact_schema_and_recomputed_values():
    data = load_json()
    assert set(data) == {'mse_A', 'mse_B', 'mse_C', 'max_B_simulated', 'graph_features'}, \
        'The JSON does not exactly follow the requested top-level schema.'

    expected = independently_compute_metrics()
    for key, expected_value in expected.items():
        actual = data[key]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"'{key}' must be numeric."
        assert math.isfinite(actual), f"'{key}' must be finite."
        assert math.isclose(actual, expected_value, rel_tol=1e-6, abs_tol=1e-4), \
            f"'{key}' was not computed correctly from {CSV_PATH}: expected {expected_value}, got {actual}."


def test_plot_is_a_valid_nontrivial_png():
    width, height, pixels = decode_png(PLOT_PATH)
    distinct = set()
    occupied_x = set()
    occupied_y = set()
    foreground = 0
    for y, row in enumerate(pixels):
        for x, color in enumerate(row):
            distinct.add(color)
            if min(color) < 245:
                foreground += 1
                occupied_x.add(min(7, (8 * x) // width))
                occupied_y.add(min(7, (8 * y) // height))

    assert len(distinct) >= 4, 'The PNG does not contain enough distinct colors for the requested plot.'
    assert foreground >= max(25, width * height // 1000), 'The PNG contains no substantial plotted content.'
    assert len(occupied_x) >= 3 and len(occupied_y) >= 3, 'Plotted content does not span the image.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
