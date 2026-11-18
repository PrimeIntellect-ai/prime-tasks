#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import sqlite3
import subprocess
import tempfile

VIDEO = '/app/sync_dashboard.mp4'
JSON_PATH = '/home/user/rolling_stats.json'
DB_PATH = '/home/user/config.db'


def build_reference():
    assert os.path.isfile(VIDEO), f"Input video missing at {VIDEO}"
    with tempfile.TemporaryDirectory() as frame_dir:
        pattern = os.path.join(frame_dir, 'frame_%03d.png')
        subprocess.run(
            ['ffmpeg', '-loglevel', 'error', '-y', '-i', VIDEO, '-vf', 'fps=1', pattern],
            check=True,
        )
        frames = sorted(glob.glob(os.path.join(frame_dir, 'frame_*.png')))
        assert frames, 'No frames could be extracted from the input video'

        intensities = []
        reference = []
        for second, frame in enumerate(frames, 1):
            result = subprocess.run(
                ['convert', frame, '-colorspace', 'gray', '-format', '%[fx:mean]', 'info:'],
                check=True,
                capture_output=True,
                text=True,
            )
            intensity = float(result.stdout.strip())
            intensities.append(intensity)
            window = intensities[max(0, len(intensities) - 5):]
            reference.append({
                'second': second,
                'intensity': intensity,
                'moving_avg': sum(window) / len(window),
            })
        return reference


def numeric(value, description):
    try:
        result = float(value)
    except (TypeError, ValueError):
        assert False, f'{description} is not numeric'
    assert math.isfinite(result), f'{description} is not finite'
    return result


def validate_rows(rows, reference, source):
    assert len(rows) == len(reference), (
        f'{source} has {len(rows)} rows; expected {len(reference)}'
    )

    sq_err = 0.0
    for index, (row, expected) in enumerate(zip(rows, reference), 1):
        assert isinstance(row, dict), f'{source} row {index} is not an object'
        for key in ('second', 'intensity', 'moving_avg'):
            assert key in row, f'{source} row {index} is missing {key}'

        second = numeric(row['second'], f'{source} row {index} second')
        intensity = numeric(row['intensity'], f'{source} row {index} intensity')
        moving_avg = numeric(row['moving_avg'], f'{source} row {index} moving_avg')

        assert second == expected['second'], (
            f'{source} row {index} has second={second}, expected {expected["second"]}'
        )
        assert abs(intensity - expected['intensity']) <= 0.005, (
            f'{source} row {index} intensity differs from the extracted-frame value'
        )
        sq_err += (moving_avg - expected['moving_avg']) ** 2

    mse = sq_err / len(reference)
    threshold = 0.005
    assert mse <= threshold, (
        f'MSE of moving_avg in {source} is {mse:.6f}, '
        f'which exceeds the threshold of {threshold}'
    )


def test_final_outputs():
    reference = build_reference()

    assert os.path.exists(JSON_PATH), f'Agent output file missing at {JSON_PATH}'
    try:
        with open(JSON_PATH, 'r') as handle:
            agent_data = json.load(handle)
    except json.JSONDecodeError:
        assert False, f'Agent output at {JSON_PATH} is not valid JSON'

    assert isinstance(agent_data, list), 'Agent output JSON must be an array'
    assert len(agent_data) > 0, 'Agent output JSON array is empty'
    validate_rows(agent_data, reference, 'rolling_stats.json')

    assert os.path.isfile(DB_PATH), f'SQLite database missing at {DB_PATH}'
    connection = sqlite3.connect(DB_PATH)
    try:
        table = connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_history'"
        ).fetchone()
        assert table is not None, 'sync_history table is missing from config.db'

        columns = [row[1] for row in connection.execute('PRAGMA table_info(sync_history)')]
        for required in ('second', 'intensity', 'moving_avg'):
            assert required in columns, f'sync_history is missing column {required}'

        db_values = connection.execute(
            'SELECT second, intensity, moving_avg FROM sync_history ORDER BY second'
        ).fetchall()
    finally:
        connection.close()

    db_rows = [
        {'second': row[0], 'intensity': row[1], 'moving_avg': row[2]}
        for row in db_values
    ]
    validate_rows(db_rows, reference, 'config.db sync_history')

    for index, (json_row, db_row) in enumerate(zip(agent_data, db_rows), 1):
        for key in ('second', 'intensity', 'moving_avg'):
            json_value = numeric(json_row[key], f'JSON row {index} {key}')
            db_value = numeric(db_row[key], f'database row {index} {key}')
            assert abs(json_value - db_value) <= 1e-9, (
                f'JSON row {index} field {key} does not match config.db'
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
