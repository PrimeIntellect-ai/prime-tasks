#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

PROJECT = Path('/home/user/loc_pipeline')
INPUT_DIR = Path('/home/user/inputs')
TEMP_DIR = Path('/home/user/temp')
FINAL = Path('/home/user/final_output.json')
REGIONS = ('us', 'de', 'jp')


def clean_outputs():
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    for region in REGIONS:
        for phase in ('decoded', 'aligned'):
            path = TEMP_DIR / f'{phase}_{region}.csv'
            if path.exists() or path.is_symlink():
                path.unlink()
    if FINAL.exists() or FINAL.is_symlink():
        FINAL.unlink()


def write_inputs(lines_by_region):
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    encodings = {'us': 'utf-8', 'de': 'iso-8859-1', 'jp': 'shift_jis'}
    for region in REGIONS:
        text = ''.join(','.join(row) + '\n' for row in lines_by_region[region])
        (INPUT_DIR / f'{region}_feedback.csv').write_bytes(text.encode(encodings[region]))


def run_pipeline():
    clean_outputs()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=120
    )
    assert result.returncode == 0, f'Pipeline execution failed:\n{result.stdout}\n{result.stderr}'


def assert_intermediates(lines_by_region, aligned_by_region):
    for region in REGIONS:
        decoded = TEMP_DIR / f'decoded_{region}.csv'
        assert decoded.is_file(), f'Phase 1 failed: Expected intermediate file {decoded} is missing.'
        decoded_text = decoded.read_text(encoding='utf-8')
        expected_lines = [','.join(row) for row in lines_by_region[region]]
        assert decoded_text.splitlines() == expected_lines, f'{decoded} was not correctly decoded to UTF-8.'

    for region in REGIONS:
        aligned = TEMP_DIR / f'aligned_{region}.csv'
        assert aligned.is_file(), f'Phase 2 failed: Expected intermediate file {aligned} is missing.'
        with aligned.open('r', encoding='utf-8', newline='') as f:
            actual_rows = list(csv.reader(f))
        expected_rows = aligned_by_region[region]
        assert Counter(map(tuple, actual_rows)) == Counter(map(tuple, expected_rows)), \
            f'{aligned} does not contain the correctly UTC-aligned rows.'


def load_and_check_final():
    assert FINAL.is_file(), f'Phase 3 failed: Final output file {FINAL} is missing.'
    content = FINAL.read_text(encoding='utf-8')
    assert content.strip() != '', f'Final output file {FINAL} is empty.'
    assert '\n' not in content.strip(), f'Final output file {FINAL} must be minified (no extra whitespace or newlines).'
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f'Final output file {FINAL} is not valid JSON.')
    assert isinstance(data, list), f'Final output must be a JSON array, got {type(data).__name__}.'
    return data


def original_fixture():
    lines = {
        'us': [
            ['12/31/2023 04:30:00 PM', 'login_btn', 'Login is confusing'],
            ['01/01/2024 09:15:00 AM', 'logout_btn', 'Works well'],
        ],
        'de': [
            ['31.12.2023 22:00:00', 'login_btn', 'Anmelden ist verwirrend'],
            ['01.01.2024 10:00:00', 'logout_btn', 'Funktioniert gut'],
        ],
        'jp': [
            ['2024/01/01 07:00:00', 'login_btn', 'ログインがわかりにくい'],
            ['2024/01/01 18:30:00', 'logout_btn', 'よく機能する'],
        ],
    }
    aligned = {
        'us': [
            ['2024-01-01T00:30:00Z', 'login_btn', 'Login is confusing'],
            ['2024-01-01T17:15:00Z', 'logout_btn', 'Works well'],
        ],
        'de': [
            ['2023-12-31T21:00:00Z', 'login_btn', 'Anmelden ist verwirrend'],
            ['2024-01-01T09:00:00Z', 'logout_btn', 'Funktioniert gut'],
        ],
        'jp': [
            ['2023-12-31T22:00:00Z', 'login_btn', 'ログインがわかりにくい'],
            ['2024-01-01T09:30:00Z', 'logout_btn', 'よく機能する'],
        ],
    }
    expected = [
        {'timestamp': '2023-12-31T21:00:00Z', 'key': 'login_btn', 'comment': 'Anmelden ist verwirrend'},
        {'timestamp': '2023-12-31T22:00:00Z', 'key': 'login_btn', 'comment': 'ログインがわかりにくい'},
        {'timestamp': '2024-01-01T00:30:00Z', 'key': 'login_btn', 'comment': 'Login is confusing'},
        {'timestamp': '2024-01-01T09:00:00Z', 'key': 'logout_btn', 'comment': 'Funktioniert gut'},
        {'timestamp': '2024-01-01T09:30:00Z', 'key': 'logout_btn', 'comment': 'よく機能する'},
        {'timestamp': '2024-01-01T17:15:00Z', 'key': 'logout_btn', 'comment': 'Works well'},
    ]
    return lines, aligned, expected


def randomized_fixture():
    token = secrets.token_hex(5)
    offsets = {'us': -8, 'de': 1, 'jp': 9}
    formats = {'us': '%m/%d/%Y %I:%M:%S %p', 'de': '%d.%m.%Y %H:%M:%S', 'jp': '%Y/%m/%d %H:%M:%S'}
    prefixes = {'us': 'US challenge ', 'de': 'Grüße ', 'jp': '確認'}
    lines = {r: [] for r in REGIONS}
    aligned = {r: [] for r in REGIONS}
    expected = []

    used_seconds = set()
    for region_index, region in enumerate(REGIONS):
        for row_index in range(3):
            while True:
                second = secrets.randbelow(300 * 24 * 60 * 60)
                if second not in used_seconds:
                    used_seconds.add(second)
                    break
            utc_dt = datetime(2025, 1, 15, tzinfo=timezone.utc) + timedelta(seconds=second)
            local_dt = utc_dt + timedelta(hours=offsets[region])
            key = f'{region}_{token}_{row_index}'
            comment = f'{prefixes[region]}{token}-{row_index}'
            timestamp = utc_dt.strftime('%Y-%m-%dT%H:%M:%SZ')
            lines[region].append([local_dt.strftime(formats[region]), key, comment])
            aligned[region].append([timestamp, key, comment])
            expected.append({'timestamp': timestamp, 'key': key, 'comment': comment})

    expected.sort(key=lambda row: row['timestamp'])
    return lines, aligned, expected


def test_rust_pipeline_builds_and_processes_inputs():
    assert PROJECT.is_dir(), '/home/user/loc_pipeline does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'loc_pipeline is not a Cargo project.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'loc_pipeline is missing src/main.rs.'

    build = subprocess.run(
        ['cargo', 'build', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=120
    )
    assert build.returncode == 0, f'Rust project failed to build:\n{build.stdout}\n{build.stderr}'

    lines, aligned, expected = original_fixture()
    write_inputs(lines)
    run_pipeline()
    assert_intermediates(lines, aligned)
    data = load_and_check_final()

    assert len(data) == len(expected), f'Expected {len(expected)} records in final output, but found {len(data)}.'
    for i, (actual, wanted) in enumerate(zip(data, expected)):
        assert actual.get('timestamp') == wanted['timestamp'], f'Record {i} timestamp mismatch. Expected {wanted["timestamp"]}, got {actual.get("timestamp")}.'
        assert actual.get('key') == wanted['key'], f'Record {i} key mismatch. Expected {wanted["key"]}, got {actual.get("key")}.'
        assert actual.get('comment') == wanted['comment'], f'Record {i} comment mismatch. Expected {wanted["comment"]}, got {actual.get("comment")}.'

    lines, aligned, expected = randomized_fixture()
    write_inputs(lines)
    run_pipeline()
    assert_intermediates(lines, aligned)
    data = load_and_check_final()
    assert data == expected, 'Pipeline output does not match the dynamically derived decoded, UTC-aligned, and sorted records.'
    for row in data:
        assert set(row) == {'timestamp', 'key', 'comment'}, 'Each JSON object must contain exactly timestamp, key, and comment.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
