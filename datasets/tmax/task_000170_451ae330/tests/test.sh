#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
from decimal import Decimal, InvalidOperation

import cv2
import numpy as np
import pandas as pd

OUTPUT_CSV = '/home/user/pipeline_output.csv'
INPUT_VIDEO = '/app/machine_feed.mp4'
INPUT_LOGS = '/app/machine_logs.csv'
PIPELINE_LOG = '/home/user/pipeline.log'
EXPECTED_COLUMNS = ['Second', 'Mean_Intensity', 'Operator', 'Notes', 'Is_Changepoint']


def decode_expected_video_values():
    cap = cv2.VideoCapture(INPUT_VIDEO)
    assert cap.isOpened(), f'Could not open input video: {INPUT_VIDEO}'

    frame_means = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        frame_means.append(float(np.mean(gray[0:50, 0:50])))
    cap.release()

    assert len(frame_means) == 600, f'Expected 600 decodable frames, got {len(frame_means)}'
    return [float(np.mean(frame_means[i:i + 10])) for i in range(0, 600, 10)], len(frame_means)


def parse_expected_logs():
    with open(INPUT_LOGS, 'r', newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))

    assert len(rows) == 60, f'Expected 60 source log rows, got {len(rows)}'
    expected = {}
    for row in rows:
        second = int(row['Second'])
        expected[second] = {
            'Operator': row['Operator'],
            'Notes': row['Notes'].replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' '),
        }
    assert sorted(expected) == list(range(60)), 'Source logs must contain Seconds 0 through 59'
    return expected, len(rows)


def parse_flag(value):
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    text = str(value).strip().lower()
    assert text in ('true', 'false'), f'Invalid Is_Changepoint value: {value!r}'
    return text == 'true'


def test_pipeline_output_csv():
    assert os.path.exists(OUTPUT_CSV), f'Output CSV file missing: {OUTPUT_CSV}'

    df_agent = pd.read_csv(OUTPUT_CSV)
    assert list(df_agent.columns) == EXPECTED_COLUMNS, \
        f'Expected columns {EXPECTED_COLUMNS}, got {list(df_agent.columns)}'
    assert len(df_agent) == 60, f'Expected 60 rows, got {len(df_agent)}'
    assert list(df_agent['Second']) == list(range(60)), \
        "The 'Second' column must be sorted from 0 to 59."

    df_agent = df_agent.sort_values('Second').reset_index(drop=True)

    # Preserve the original newline-cleansing assertion.
    assert not any('\n' in str(note) or '\r' in str(note) for note in df_agent['Notes']), \
        'Newlines were not stripped from the Notes column.'

    expected_intensities, _ = decode_expected_video_values()
    expected_logs, _ = parse_expected_logs()

    agent_intensities = pd.to_numeric(df_agent['Mean_Intensity'], errors='coerce').to_numpy(dtype=float)
    assert np.all(np.isfinite(agent_intensities)), 'Mean_Intensity contains non-numeric values'

    # Keep the original MAE assertion, but derive its target from frames actually
    # decoded from the lossy MP4 rather than from pre-encoding RNG arrays.
    mae = float(np.mean(np.abs(agent_intensities - np.asarray(expected_intensities))))
    assert mae <= 0.5, \
        f'MAE of Mean_Intensity is {mae:.4f}, which is greater than the threshold of 0.5.'

    # Verify that each reported value is the required two-decimal rounded result.
    with open(OUTPUT_CSV, 'r', newline='', encoding='utf-8') as f:
        raw_rows = list(csv.DictReader(f))
    assert len(raw_rows) == 60
    for second, row in enumerate(raw_rows):
        try:
            actual_decimal = Decimal(row['Mean_Intensity'].strip())
        except (InvalidOperation, AttributeError):
            raise AssertionError(f'Invalid Mean_Intensity at Second {second}: {row["Mean_Intensity"]!r}')
        expected_decimal = Decimal(f'{expected_intensities[second]:.2f}')
        assert actual_decimal.is_finite() and actual_decimal == expected_decimal, \
            f'Incorrect rounded Mean_Intensity at Second {second}: expected {expected_decimal}, got {actual_decimal}'

    expected_flags = [False]
    expected_flags.extend(
        abs(expected_intensities[i] - expected_intensities[i - 1]) > 15.0
        for i in range(1, 60)
    )
    actual_flags = [parse_flag(v) for v in df_agent['Is_Changepoint']]
    assert actual_flags == expected_flags, 'Is_Changepoint values are incorrect'

    for second in range(60):
        expected = expected_logs[second]
        assert str(df_agent.at[second, 'Operator']) == expected['Operator'], \
            f'Incorrect Operator at Second {second}'
        assert str(df_agent.at[second, 'Notes']) == expected['Notes'], \
            f'Incorrect cleansed Notes at Second {second}'


def test_pipeline_log_exists_and_has_required_entries():
    assert os.path.exists(PIPELINE_LOG), f'Log file missing: {PIPELINE_LOG}'
    assert os.path.isfile(PIPELINE_LOG), f'Path exists but is not a file: {PIPELINE_LOG}'

    with open(PIPELINE_LOG, 'r', encoding='utf-8') as f:
        content = f.read()
    assert len(content.strip()) > 0, 'The pipeline log file is empty.'

    _, frame_count = decode_expected_video_values()
    _, parsed_row_count = parse_expected_logs()
    lines = [line for line in content.splitlines() if line.strip()]
    timestamp = re.compile(r'(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}:\d{2}(?::\d{2})?)')

    assert any(re.search(r'(?i)start', line) and timestamp.search(line) for line in lines), \
        'The pipeline log must include a start time'
    assert any(re.search(r'(?i)extract', line) and re.search(r'(?i)frame', line)
               and re.search(rf'(?<!\d){frame_count}(?!\d)', line) for line in lines), \
        f'The pipeline log must report {frame_count} successfully extracted frames'
    assert any(re.search(r'(?i)pars', line) and re.search(r'(?i)(?:log|row)', line)
               and re.search(rf'(?<!\d){parsed_row_count}(?!\d)', line) for line in lines), \
        f'The pipeline log must report {parsed_row_count} successfully parsed log rows'
    assert any(re.search(r'(?i)(?:complet|finish|end)', line) and timestamp.search(line) for line in lines), \
        'The pipeline log must include a completion time'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
