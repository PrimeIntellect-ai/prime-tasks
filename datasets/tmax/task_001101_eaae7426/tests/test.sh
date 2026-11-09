#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import cv2
import pandas as pd
import numpy as np
import pytest

ALIGNED = '/home/user/aligned.csv'
VIDEO = '/app/experiment.mp4'
SENSOR = '/app/sensor.csv'
BASE_START = 1700000000


def normalize(values):
    values = np.asarray(values, dtype=float)
    lo = values.min()
    hi = values.max()
    assert np.isfinite(lo) and np.isfinite(hi) and hi > lo
    return (values - lo) / (hi - lo)


def correlation(a, b):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    if len(a) < 2 or np.std(a) == 0 or np.std(b) == 0:
        return float('-inf')
    return float(np.corrcoef(a, b)[0, 1])


def derive_reference():
    # Independently decode every video frame and average all frames in each
    # one-second interval.
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f'Could not open source video {VIDEO}'
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    assert np.isfinite(fps) and fps > 0

    buckets = {}
    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        second = int(frame_index / fps)
        buckets.setdefault(second, []).append(float(frame.mean()))
        frame_index += 1
    cap.release()
    assert frame_index > 0 and buckets, 'No frames decoded from source video'

    video_seconds = sorted(buckets)
    video_values = normalize([np.mean(buckets[s]) for s in video_seconds])
    video_by_second = dict(zip(video_seconds, video_values))

    sensor = pd.read_csv(SENSOR)
    assert list(sensor.columns) == ['timestamp_ms', 'luminosity_raw']
    sensor['timestamp_ms'] = pd.to_numeric(sensor['timestamp_ms'], errors='raise')
    sensor['luminosity_raw'] = pd.to_numeric(sensor['luminosity_raw'], errors='raise')
    assert np.isfinite(sensor[['timestamp_ms', 'luminosity_raw']].to_numpy(dtype=float)).all()
    sensor['timestamp_sec'] = np.floor(sensor['timestamp_ms'] / 1000.0).astype(np.int64)
    grouped = sensor.groupby('timestamp_sec', sort=True)['luminosity_raw'].mean()
    sensor_values = normalize(grouped.to_numpy(dtype=float))
    sensor_by_time = dict(zip(grouped.index.astype(int), sensor_values))

    # Evaluate every permitted integer shift and select the one that maximizes
    # Pearson correlation, as required by the task.
    candidates = []
    for shift in range(-15, 16):
        start = BASE_START + shift
        rows = []
        for video_second in video_seconds:
            timestamp = start + video_second
            if timestamp in sensor_by_time:
                rows.append((timestamp, video_by_second[video_second], sensor_by_time[timestamp]))
        if len(rows) >= 2:
            corr = correlation([r[1] for r in rows], [r[2] for r in rows])
            candidates.append((corr, shift, rows))

    assert candidates, 'No candidate alignment overlaps the source data'
    best_corr, best_shift, best_rows = max(candidates, key=lambda item: item[0])
    assert np.isfinite(best_corr)
    return best_shift, best_rows


def test_aligned_csv_and_correlation():
    aligned_file = ALIGNED

    assert os.path.exists(aligned_file), f"Aligned CSV file not found at {aligned_file}."
    assert os.path.isfile(aligned_file), f"Path {aligned_file} is not a file."

    try:
        df = pd.read_csv(aligned_file)
    except Exception as e:
        pytest.fail(f"Failed to read {aligned_file} as CSV: {e}")

    expected_columns = ['timestamp_sec', 'normalized_brightness', 'normalized_sensor']
    for col in expected_columns:
        assert col in df.columns, f"Missing expected column '{col}' in {aligned_file}. Found: {list(df.columns)}"

    assert len(df) > 0, f"The aligned CSV {aligned_file} is empty."

    # Preserve the original correlation assertion.
    corr = df['normalized_brightness'].corr(df['normalized_sensor'])
    assert not np.isnan(corr), "Pearson correlation is NaN. Check if the normalized columns have zero variance or missing data."
    assert corr >= 0.90, f"Pearson correlation between normalized_brightness and normalized_sensor is {corr:.4f}, which is below the required threshold of 0.90."

    # Verify the submitted rows actually come from the supplied video and
    # sensor data, rather than accepting an arbitrary correlated table.
    assert list(df.columns) == expected_columns, f'CSV header must be exactly {expected_columns}'
    for col in expected_columns:
        df[col] = pd.to_numeric(df[col], errors='raise')
    actual = df[expected_columns].to_numpy(dtype=float)
    assert np.isfinite(actual).all(), 'Aligned CSV contains non-finite values'
    assert ((df['normalized_brightness'] >= -1e-6) & (df['normalized_brightness'] <= 1.000001)).all()
    assert ((df['normalized_sensor'] >= -1e-6) & (df['normalized_sensor'] <= 1.000001)).all()
    assert np.allclose(df['timestamp_sec'], np.round(df['timestamp_sec']), atol=0, rtol=0), 'Timestamps must be integer seconds'
    assert df['timestamp_sec'].is_unique, 'Aligned CSV contains duplicate timestamps'
    assert df['timestamp_sec'].is_monotonic_increasing, 'Aligned CSV timestamps must be sorted'

    _, expected_rows = derive_reference()
    expected_timestamps = np.asarray([r[0] for r in expected_rows], dtype=np.int64)
    expected_brightness = np.asarray([r[1] for r in expected_rows], dtype=float)
    expected_sensor = np.asarray([r[2] for r in expected_rows], dtype=float)

    submitted_timestamps = df['timestamp_sec'].to_numpy(dtype=np.int64)
    assert len(df) == len(expected_rows), f'Expected all {len(expected_rows)} overlapping timestamps, found {len(df)}'
    assert np.array_equal(submitted_timestamps, expected_timestamps), 'Timestamps do not represent the optimal source-data alignment'
    assert np.allclose(df['normalized_sensor'].to_numpy(dtype=float), expected_sensor, atol=0.0025, rtol=0), 'normalized_sensor does not match one-second bucketing and min-max normalization of sensor.csv'

    submitted_brightness = df['normalized_brightness'].to_numpy(dtype=float)
    brightness_rmse = float(np.sqrt(np.mean((submitted_brightness - expected_brightness) ** 2)))
    brightness_corr = correlation(submitted_brightness, expected_brightness)
    # Small tolerance accommodates valid ffmpeg/OpenCV luminance and 1 FPS
    # extraction choices while still requiring the actual video signal.
    assert brightness_rmse <= 0.08, f'normalized_brightness does not match the video signal (RMSE {brightness_rmse:.4f})'
    assert brightness_corr >= 0.97, f'normalized_brightness does not track the decoded video (correlation {brightness_corr:.4f})'


def test_cron_job_configuration():
    cron_file = '/home/user/crontab.txt'

    assert os.path.exists(cron_file), f"Cron configuration file not found at {cron_file}."
    assert os.path.isfile(cron_file), f"Path {cron_file} is not a file."

    with open(cron_file, 'r') as f:
        cron_content = f.read().strip()

    # Preserve the original checks.
    assert '15 * * * *' in cron_content, f"Cron expression '15 * * * *' not found in {cron_file}. Content: {cron_content}"
    assert '/home/user/process_latest.sh' in cron_content, f"Command '/home/user/process_latest.sh' not found in {cron_file}. Content: {cron_content}"

    # Also require both pieces to form one valid, non-comment crontab entry.
    active_lines = [line.strip() for line in cron_content.splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]
    pattern = re.compile(r'^15\s+\*\s+\*\s+\*\s+\*\s+/home/user/process_latest\.sh\s*$')
    assert any(pattern.fullmatch(line) for line in active_lines), 'No valid hourly crontab entry at minute 15 was found'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
