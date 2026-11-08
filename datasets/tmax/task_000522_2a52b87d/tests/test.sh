#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3

import cv2
import numpy as np
import pandas as pd
import pytest
import requests

DB_PATH = '/home/user/tracking.db'
VIDEO_PATH = '/app/experiment.mp4'
API_URL = 'http://127.0.0.1:8000/api/stats'


def get_expected_data():
    """Extract expected values from the actual video supplied to the agent."""
    capture = cv2.VideoCapture(VIDEO_PATH)
    assert capture.isOpened(), f'Could not open {VIDEO_PATH}'

    y_coords = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break

        if frame.ndim == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        if float(frame.max()) < 100:
            y_coords.append(np.nan)
        else:
            row, _ = np.unravel_index(np.argmax(frame), frame.shape)
            y_coords.append(float(row))

    capture.release()
    assert y_coords, 'No frames were decoded from the experiment video'

    raw = pd.Series(y_coords, dtype=float)
    imputed = raw.interpolate(method='linear')
    rolling = imputed.rolling(window=5, center=True).mean()
    return imputed, rolling


@pytest.fixture(scope='module')
def expected_data():
    return get_expected_data()


def request_frame(frame_idx):
    try:
        return requests.get(API_URL, params={'frame': frame_idx}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to the API: {exc}')


def assert_api_value(frame_idx, expected_imputed, expected_rolling):
    response = request_frame(frame_idx)
    assert response.status_code == 200, (
        f'Expected status code 200 for frame {frame_idx}, got '
        f'{response.status_code}. Response: {response.text}'
    )

    data = response.json()
    assert 'frame' in data, "Response JSON missing 'frame' key."
    assert 'y_imputed' in data, "Response JSON missing 'y_imputed' key."
    assert 'y_rolling_avg' in data, "Response JSON missing 'y_rolling_avg' key."
    assert data['frame'] == frame_idx, (
        f"Expected frame {frame_idx}, got {data['frame']}"
    )
    assert np.isclose(data['y_imputed'], expected_imputed, atol=0.1), (
        f"Frame {frame_idx}: expected y_imputed ~{expected_imputed}, "
        f"got {data['y_imputed']}"
    )
    assert np.isclose(data['y_rolling_avg'], expected_rolling, atol=0.1), (
        f"Frame {frame_idx}: expected y_rolling_avg ~{expected_rolling}, "
        f"got {data['y_rolling_avg']}"
    )


def test_database_exists():
    assert os.path.isfile(DB_PATH), f'Database file is missing at {DB_PATH}'


def test_database_schema():
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='trajectory';"
        )
        assert cursor.fetchone() is not None, (
            "Table 'trajectory' does not exist in the database."
        )

        cursor.execute('PRAGMA table_info(trajectory);')
        columns = {row[1]: row[2] for row in cursor.fetchall()}
        assert 'frame' in columns, "Column 'frame' missing from trajectory table."
        assert 'y_imputed' in columns, (
            "Column 'y_imputed' missing from trajectory table."
        )
        assert 'y_rolling_avg' in columns, (
            "Column 'y_rolling_avg' missing from trajectory table."
        )
    finally:
        conn.close()


def test_database_contains_complete_processed_trajectory(expected_data):
    imputed, rolling = expected_data
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            'SELECT frame, y_imputed, y_rolling_avg '
            'FROM trajectory ORDER BY frame'
        ).fetchall()
    finally:
        conn.close()

    expected_frames = list(range(len(imputed)))
    actual_frames = [row[0] for row in rows]
    assert actual_frames == expected_frames, (
        'trajectory must contain exactly one row for every decoded video frame; '
        f'expected frames {expected_frames}, got {actual_frames}'
    )

    for frame_idx, actual_imputed, actual_rolling in rows:
        expected_imputed = imputed.iloc[frame_idx]
        expected_rolling = rolling.iloc[frame_idx]

        assert actual_imputed is not None and np.isclose(
            actual_imputed, expected_imputed, atol=0.1
        ), (
            f'Frame {frame_idx}: expected database y_imputed '
            f'~{expected_imputed}, got {actual_imputed}'
        )

        if pd.isna(expected_rolling):
            assert actual_rolling is None or pd.isna(actual_rolling), (
                f'Frame {frame_idx}: expected null/NaN rolling average, '
                f'got {actual_rolling}'
            )
        else:
            assert actual_rolling is not None and np.isclose(
                actual_rolling, expected_rolling, atol=0.1
            ), (
                f'Frame {frame_idx}: expected database y_rolling_avg '
                f'~{expected_rolling}, got {actual_rolling}'
            )


def test_api_valid_frame(expected_data):
    imputed, rolling = expected_data
    assert_api_value(5, imputed.iloc[5], rolling.iloc[5])


def test_api_imputed_frame(expected_data):
    imputed, rolling = expected_data
    assert_api_value(10, imputed.iloc[10], rolling.iloc[10])


def test_api_serves_all_frames_with_full_rolling_windows(expected_data):
    imputed, rolling = expected_data
    for frame_idx in range(2, len(imputed) - 2):
        assert_api_value(
            frame_idx, imputed.iloc[frame_idx], rolling.iloc[frame_idx]
        )


def test_api_fetches_values_from_database(expected_data):
    """Reject an API that merely hardcodes expected frame responses."""
    frame_idx = len(expected_data[0]) // 2
    replacement_imputed = 12.3456
    replacement_rolling = 23.4567

    conn = sqlite3.connect(DB_PATH, timeout=5)
    original = conn.execute(
        'SELECT y_imputed, y_rolling_avg FROM trajectory WHERE frame = ?',
        (frame_idx,),
    ).fetchone()
    assert original is not None, f'Frame {frame_idx} is absent from trajectory'

    try:
        conn.execute(
            'UPDATE trajectory SET y_imputed = ?, y_rolling_avg = ? '
            'WHERE frame = ?',
            (replacement_imputed, replacement_rolling, frame_idx),
        )
        conn.commit()

        response = request_frame(frame_idx)
        assert response.status_code == 200, (
            f'Expected status code 200 after database update, got '
            f'{response.status_code}. Response: {response.text}'
        )
        data = response.json()
        assert data.get('frame') == frame_idx
        assert np.isclose(data.get('y_imputed'), replacement_imputed, atol=1e-4), (
            'API did not fetch y_imputed from the trajectory database'
        )
        assert np.isclose(
            data.get('y_rolling_avg'), replacement_rolling, atol=1e-4
        ), 'API did not fetch y_rolling_avg from the trajectory database'
    finally:
        conn.execute(
            'UPDATE trajectory SET y_imputed = ?, y_rolling_avg = ? '
            'WHERE frame = ?',
            (original[0], original[1], frame_idx),
        )
        conn.commit()
        conn.close()


def test_api_not_found():
    response = request_frame(999)
    assert response.status_code == 404, (
        f'Expected status code 404 for missing frame, got {response.status_code}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
