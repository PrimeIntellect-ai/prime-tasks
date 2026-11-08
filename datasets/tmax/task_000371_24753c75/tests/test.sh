#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import time
from pathlib import Path

import cv2
import pytest
import requests
from scipy import stats


def get_video_dimensions(video_path):
    cmd = [
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height', '-of', 'csv=s=x:p=0', video_path
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, check=True)
    w, h = map(int, result.stdout.strip().split('x'))
    return w, h


def compute_expected_stats(video_path):
    w, h = get_video_dimensions(video_path)
    frame_size = w * h

    cmd = [
        'ffmpeg', '-i', video_path, '-vf', 'fps=1',
        '-f', 'image2pipe', '-pix_fmt', 'gray', '-vcodec', 'rawvideo', '-'
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    out, _ = process.communicate()
    assert process.returncode == 0, 'ffmpeg failed while reading the video'

    means = []
    for i in range(0, len(out), frame_size):
        frame = out[i:i + frame_size]
        if len(frame) == frame_size:
            means.append(sum(frame) / frame_size)

    n = len(means)
    assert n >= 3, 'Not enough 1 fps frames for a correlation hypothesis test'
    x = list(range(1, n + 1))
    y = means

    sum_x = sum(x)
    sum_y = sum(y)
    sum_x2 = sum(xi * xi for xi in x)
    sum_y2 = sum(yi * yi for yi in y)
    sum_xy = sum(xi * yi for xi, yi in zip(x, y))

    numerator = n * sum_xy - sum_x * sum_y
    denominator = math.sqrt((n * sum_x2 - sum_x**2) *
                            (n * sum_y2 - sum_y**2))
    r = 0.0 if denominator == 0 else numerator / denominator

    if abs(r) == 1.0:
        p_value = 0.0
    else:
        t_stat = r * math.sqrt((n - 2) / (1.0 - r * r))
        p_value = float(2.0 * stats.t.sf(abs(t_stat), df=n - 2))

    return r, p_value, x, means, (w, h)


def natural_key(path):
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r'(\d+)', path.name)]


def find_matching_extracted_frames(expected_means, dimensions):
    extensions = {'.png', '.jpg', '.jpeg', '.bmp', '.tif', '.tiff',
                  '.pgm', '.ppm', '.webp'}
    groups = {}
    for root in ('/app', '/home/user'):
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            candidates = [Path(directory) / name for name in files
                          if Path(name).suffix.lower() in extensions]
            if candidates:
                groups.setdefault(directory, []).extend(candidates)

    n = len(expected_means)
    expected_w, expected_h = dimensions
    for paths in groups.values():
        paths = sorted(paths, key=natural_key)
        for start in range(0, len(paths) - n + 1):
            window = paths[start:start + n]
            actual_means = []
            valid = True
            for path in window:
                image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
                if image is None or image.shape != (expected_h, expected_w):
                    valid = False
                    break
                mean = float(image.mean())
                if not math.isfinite(mean):
                    valid = False
                    break
                actual_means.append(mean)
            if valid and all(math.isclose(a, e, abs_tol=2.0)
                             for a, e in zip(actual_means, expected_means)):
                return window, actual_means
    return None, None


def fetch_stats():
    url = 'http://127.0.0.1:8080/stats'
    response = None
    for _ in range(5):
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            time.sleep(1)

    assert response is not None, f'Failed to connect to {url}'
    assert response.status_code == 200, \
        f'Expected HTTP 200, got {response.status_code}'
    try:
        return response.json()
    except ValueError:
        pytest.fail('Response is not valid JSON')


def test_api_response_and_pipeline_outputs():
    expected_r, expected_p, indices, means, dimensions = \
        compute_expected_stats('/app/traffic.mp4')

    # Confirm that a real 1 fps frame sequence was left by the pipeline and that
    # its derived records have finite brightness values and integer indices.
    frames, extracted_means = find_matching_extracted_frames(means, dimensions)
    assert frames is not None, \
        'No extracted 1 fps frame sequence matching /app/traffic.mp4 was found'
    records = list(zip(indices, extracted_means))
    assert len(records) == len(means)
    assert all(type(index) is int for index, _ in records), \
        'Frame indices must remain integers'
    assert all(math.isfinite(value) for _, value in records), \
        'Extracted brightness data contains NaN or infinity'

    first = fetch_stats()

    # Keep the original field assertions and additionally enforce the requested
    # exact response shape and numeric types.
    assert 'correlation' in first, "Missing 'correlation' in JSON response"
    assert 'p_value' in first, "Missing 'p_value' in JSON response"
    assert 'reproducible' in first, "Missing 'reproducible' in JSON response"
    assert set(first) == {'correlation', 'p_value', 'reproducible'}, \
        'JSON response must have exactly the requested fields'
    assert first['reproducible'] is True, "'reproducible' must be true"
    assert type(first['correlation']) is float, 'correlation must be a float'
    assert type(first['p_value']) is float, 'p_value must be a float'
    assert math.isfinite(first['correlation']), 'correlation must be finite'
    assert math.isfinite(first['p_value']), 'p_value must be finite'
    assert 0.0 <= first['p_value'] <= 1.0, 'p_value must be between 0 and 1'

    assert math.isclose(first['correlation'], expected_r, abs_tol=1e-3), \
        f"Correlation mismatch: expected {expected_r}, got {first['correlation']}"
    assert math.isclose(first['p_value'], expected_p, rel_tol=1e-6, abs_tol=1e-8), \
        f"p-value mismatch: expected {expected_p}, got {first['p_value']}"

    # A second independent request must return the same statistics, rather than
    # relying solely on the self-reported reproducible flag.
    second = fetch_stats()
    assert second == first, 'Repeated /stats requests are not reproducible'


if __name__ == '__main__':
    raise SystemExit(pytest.main([__file__, '-x', '--tb=short']))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
