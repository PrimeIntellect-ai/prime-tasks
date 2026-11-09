#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
import tempfile

import numpy as np
import pandas as pd

DATASET_PATH = '/home/user/dataset.tsv'
SCRIPT_PATH = '/home/user/build_manifest.sh'
AUDIO_PATH = '/app/interview.wav'
MODEL_PATH = '/app/ggml-tiny.en.bin'


def find_whisper_binary():
    candidates = [
        '/app/whisper/build/bin/whisper-cli',
        '/app/whisper/build/bin/main',
        '/app/whisper/whisper-cli',
        '/app/whisper/main',
    ]
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            with open(path, 'rb') as f:
                if f.read(4) == b'\x7fELF':
                    return path
    raise AssertionError('No built Whisper ELF executable was found in /app/whisper.')


def read_whisper_csv(path):
    with open(path, newline='', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, 'Whisper CSV has no header.'
        assert {'start', 'end', 'text'}.issubset(reader.fieldnames), (
            f'Unexpected Whisper CSV columns: {reader.fieldnames}'
        )
        rows = []
        for row in reader:
            rows.append((int(row['start'].strip()),
                         int(row['end'].strip()),
                         row['text'].strip()))
    assert rows, 'Whisper produced no speech segments.'
    return rows


def test_pipeline_against_fresh_whisper_output():
    assert os.path.isfile(SCRIPT_PATH), f'Pipeline script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(AUDIO_PATH), f'Input audio {AUDIO_PATH} does not exist.'
    assert os.path.isfile(MODEL_PATH), f'Model {MODEL_PATH} does not exist.'

    whisper_binary = find_whisper_binary()

    with tempfile.TemporaryDirectory(prefix='manifest_verify_') as tmpdir:
        output_prefix = os.path.join(tmpdir, 'whisper_segments')
        result = subprocess.run(
            [whisper_binary, '-m', MODEL_PATH, '-f', AUDIO_PATH,
             '-ocsv', '-of', output_prefix],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
        )
        assert result.returncode == 0, (
            f'Whisper execution failed with status {result.returncode}:\n{result.stdout}'
        )

        csv_path = output_prefix + '.csv'
        assert os.path.isfile(csv_path), 'Whisper did not create the requested CSV output.'
        expected_rows = read_whisper_csv(csv_path)

        if os.path.exists(DATASET_PATH):
            os.remove(DATASET_PATH)
        env = os.environ.copy()
        env['WHISPER_CSV'] = csv_path
        pipeline = subprocess.run(
            ['bash', SCRIPT_PATH, csv_path],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
        assert pipeline.returncode == 0, (
            f'build_manifest.sh failed with status {pipeline.returncode}:\n{pipeline.stdout}'
        )

    assert os.path.isfile(DATASET_PATH), f'Output file {DATASET_PATH} does not exist.'

    try:
        df_agent = pd.read_csv(DATASET_PATH, sep='\t')
    except Exception as e:
        assert False, f'Failed to read {DATASET_PATH} as TSV: {e}'

    expected_cols = ['segment_id', 'start_ms', 'end_ms', 'duration_ms', 'transcript']
    for c in expected_cols:
        assert c in df_agent.columns, f"Missing expected column '{c}' in {DATASET_PATH}."
    assert list(df_agent.columns) == expected_cols, (
        f'TSV columns or order are incorrect: {list(df_agent.columns)}'
    )

    try:
        start_ms = df_agent['start_ms'].astype(float)
        end_ms = df_agent['end_ms'].astype(float)
        actual_duration = df_agent['duration_ms'].astype(float)
    except ValueError as e:
        assert False, f'Numeric columns contain non-numeric data (likely CSV parsing error): {e}'

    expected_duration = end_ms - start_ms
    mae = np.mean(np.abs(expected_duration - actual_duration))

    assert not df_agent['duration_ms'].isna().any(), 'duration_ms contains NaN values.'
    assert not df_agent['transcript'].isna().any(), 'transcript contains NaN values.'
    assert len(df_agent) > 0, 'The dataset is empty.'
    assert mae <= 1.0, (
        f'MAE of duration_ms vs (end_ms - start_ms) is {mae}, which exceeds threshold of 1.0.'
    )

    assert len(df_agent) == len(expected_rows), (
        f'Expected {len(expected_rows)} segments from Whisper, got {len(df_agent)}.'
    )

    for index, (expected_start, expected_end, expected_text) in enumerate(expected_rows):
        row = df_agent.iloc[index]
        expected_id = index + 1
        expected_ms = expected_end - expected_start

        assert int(row['segment_id']) == expected_id and float(row['segment_id']) == expected_id, (
            f'Row {index + 1} has invalid segment_id {row["segment_id"]}.'
        )
        assert int(row['start_ms']) == expected_start and float(row['start_ms']) == expected_start, (
            f'Row {index + 1} start_ms does not match Whisper output.'
        )
        assert int(row['end_ms']) == expected_end and float(row['end_ms']) == expected_end, (
            f'Row {index + 1} end_ms does not match Whisper output.'
        )
        assert int(row['duration_ms']) == expected_ms and float(row['duration_ms']) == expected_ms, (
            f'Row {index + 1} duration_ms is not the exact timestamp difference.'
        )
        assert str(row['transcript']) == expected_text, (
            f'Row {index + 1} transcript does not match trimmed Whisper text.'
        )
        assert str(row['transcript']) == str(row['transcript']).strip(), (
            f'Row {index + 1} transcript has leading or trailing whitespace.'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
