#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import time
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/translation_filter.py')
EXPECTED_FIELDS = ['id', 'locale', 'updated_at', 'translation', 'lang_primary']


def run_filter(input_path, output_path):
    assert SCRIPT.exists(), f'Script not found at {SCRIPT}'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a regular file'

    try:
        result = subprocess.run(
            ['python3', str(SCRIPT), str(input_path), str(output_path)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('translation_filter.py timed out')

    assert result.returncode == 0, (
        f'translation_filter.py returned {result.returncode}\n'
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert output_path.exists(), 'Output CSV not created'
    assert output_path.is_file(), 'Output CSV is not a regular file'

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert lines, 'No JSON summary was printed to STDOUT'
    try:
        stats = json.loads(lines[-1])
    except json.JSONDecodeError as exc:
        pytest.fail(f'Last non-empty STDOUT line is not JSON: {exc}')

    assert isinstance(stats, dict), 'Summary must be a JSON object'
    assert set(stats) == {
        'total_input_rows', 'valid_rows_kept', 'invalid_rows_dropped'
    }, f'Incorrect summary schema: {stats}'
    for key in stats:
        assert isinstance(stats[key], int) and not isinstance(stats[key], bool), (
            f'{key} must be an integer'
        )
        assert stats[key] >= 0, f'{key} must not be negative'
    assert stats['total_input_rows'] == (
        stats['valid_rows_kept'] + stats['invalid_rows_dropped']
    ), 'Summary counts are inconsistent'

    with output_path.open('r', encoding='utf-8', newline='') as handle:
        reader = csv.DictReader(handle, strict=True)
        assert reader.fieldnames == EXPECTED_FIELDS, (
            f'Unexpected output columns: {reader.fieldnames}'
        )
        rows = list(reader)
    assert all(None not in row for row in rows), 'Output contains malformed CSV rows'
    return stats, rows


def test_multi_service_integration(tmp_path):
    clean_csv_path = tmp_path / 'integration.csv'
    clean_csv_path.write_text(
        'id,locale,updated_at,translation\n'
        'integration-token,en-US,2023-10-04T15:30:00Z,Hello\n',
        encoding='utf-8',
    )
    stats_file = Path('/home/user/processed_stats.json')
    if stats_file.exists():
        stats_file.unlink()

    started = time.time()
    try:
        result = subprocess.run(
            [
                'curl', '--fail-with-body', '-sS', '-X', 'POST',
                '-F', f'file=@{clean_csv_path}',
                'http://127.0.0.1:8080/upload',
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Upload request to Nginx timed out')

    assert result.returncode == 0, (
        f'Upload failed with Nginx/FastAPI: {result.stderr}\n{result.stdout}'
    )
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Upload endpoint did not return JSON: {exc}; body={result.stdout!r}')
    assert response == {'status': 'queued'}, f'Unexpected upload response: {response}'

    for _ in range(20):
        if stats_file.is_file() and stats_file.stat().st_mtime >= started:
            try:
                with stats_file.open('r', encoding='utf-8') as handle:
                    worker_result = json.load(handle)
                if worker_result == {'status': 'done'}:
                    break
            except (OSError, json.JSONDecodeError):
                pass
        time.sleep(0.5)
    else:
        pytest.fail(
            'Celery worker did not produce a fresh, valid processed_stats.json'
        )


def test_translation_filter_preserves_and_transforms_clean_rows(tmp_path):
    input_path = tmp_path / 'clean.csv'
    output_path = tmp_path / 'clean-output.csv'
    source_rows = [
        {
            'id': '1', 'locale': 'en-US',
            'updated_at': '2023-10-04T15:30:00Z',
            'translation': 'Hello',
        },
        {
            'id': '2', 'locale': 'es-ES',
            'updated_at': '2023-10-04T11:30:00-04:00',
            'translation': 'Line 1\nLine 2',
        },
        {
            'id': '3', 'locale': 'ja-JP',
            'updated_at': '1696433400',
            'translation': 'She said "hello"',
        },
        {
            'id': '4', 'locale': 'fr-FR',
            'updated_at': '10/04/2023',
            'translation': 'Bonjour, monde',
        },
    ]
    with input_path.open('w', encoding='utf-8', newline='') as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=['id', 'locale', 'updated_at', 'translation'],
        )
        writer.writeheader()
        writer.writerows(source_rows)

    stats, rows = run_filter(input_path, output_path)
    assert stats == {
        'total_input_rows': 4,
        'valid_rows_kept': 4,
        'invalid_rows_dropped': 0,
    }
    assert rows == [
        {
            'id': '1', 'locale': 'en-US',
            'updated_at': '2023-10-04T15:30:00Z',
            'translation': 'Hello', 'lang_primary': 'en',
        },
        {
            'id': '2', 'locale': 'es-ES',
            'updated_at': '2023-10-04T15:30:00Z',
            'translation': 'Line 1\nLine 2', 'lang_primary': 'es',
        },
        {
            'id': '3', 'locale': 'ja-JP',
            'updated_at': '2023-10-04T15:30:00Z',
            'translation': 'She said "hello"', 'lang_primary': 'ja',
        },
        {
            'id': '4', 'locale': 'fr-FR',
            'updated_at': '2023-10-04T00:00:00Z',
            'translation': 'Bonjour, monde', 'lang_primary': 'fr',
        },
    ]


def test_translation_filter_drops_structurally_invalid_rows(tmp_path):
    input_path = tmp_path / 'evil.csv'
    output_path = tmp_path / 'evil-output.csv'
    input_path.write_bytes(
        b'id,locale,updated_at,translation\n'
        b'1,en-US,2023-10-04T15:30:00Z,keep one\n'
        b'2,es-ES,2023-10-04T15:30:00Z,bad\\x00value\n'.replace(b'\\x00', b'\x00')
        + b'3,fr-FR,2023-10-04T15:30:00Z,too,many\n'
        + b'4,de-DE,2023-10-04T15:30:00Z,"bad"junk\n'
        + b'5,it-IT,2023-10-04T15:30:00Z\n'
        + b'6,pt-BR,2023-10-04T15:30:00Z,"keep\nembedded"\n'
    )

    stats, rows = run_filter(input_path, output_path)
    assert stats == {
        'total_input_rows': 6,
        'valid_rows_kept': 2,
        'invalid_rows_dropped': 4,
    }
    assert rows == [
        {
            'id': '1', 'locale': 'en-US',
            'updated_at': '2023-10-04T15:30:00Z',
            'translation': 'keep one', 'lang_primary': 'en',
        },
        {
            'id': '6', 'locale': 'pt-BR',
            'updated_at': '2023-10-04T15:30:00Z',
            'translation': 'keep\nembedded', 'lang_primary': 'pt',
        },
    ]
    assert b'\x00' not in output_path.read_bytes(), 'Null byte leaked into output'


def test_translation_filter_handles_unterminated_quote_block(tmp_path):
    input_path = tmp_path / 'unterminated.csv'
    output_path = tmp_path / 'unterminated-output.csv'
    input_path.write_text(
        'id,locale,updated_at,translation\n'
        '7,en-US,2023-10-04T15:30:00Z,safe\n'
        '8,es-ES,2023-10-04T15:30:00Z,"unterminated\ncontinued',
        encoding='utf-8',
    )

    stats, rows = run_filter(input_path, output_path)
    assert stats == {
        'total_input_rows': 2,
        'valid_rows_kept': 1,
        'invalid_rows_dropped': 1,
    }
    assert rows == [{
        'id': '7', 'locale': 'en-US',
        'updated_at': '2023-10-04T15:30:00Z',
        'translation': 'safe', 'lang_primary': 'en',
    }]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
