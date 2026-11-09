#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import sqlite3
import string
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/etl_tool')
BINARY = PROJECT / 'target/debug/etl_tool'
VIDEO = '/app/drone_footage.mp4'
DB = '/home/user/pipeline.db'
SUMMARY = Path('/home/user/summary.json')


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=180, **kwargs)


def ffmpeg_reference():
    duration_result = run([
        'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', VIDEO
    ])
    assert duration_result.returncode == 0, duration_result.stderr
    duration = float(duration_result.stdout.strip())

    rate_result = run([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=avg_frame_rate',
        '-of', 'default=noprint_wrappers=1:nokey=1', VIDEO
    ])
    assert rate_result.returncode == 0, rate_result.stderr
    num, den = rate_result.stdout.strip().split('/')
    fps = float(num) / float(den)

    scene_result = run([
        'ffprobe', '-v', 'error', '-f', 'lavfi',
        '-i', r'movie=/app/drone_footage.mp4,select=gt(scene\,0)',
        '-show_entries', 'frame=best_effort_timestamp_time:frame_tags=lavfi.scene_score',
        '-of', 'json'
    ])
    assert scene_result.returncode == 0, scene_result.stderr
    frames = json.loads(scene_result.stdout).get('frames', [])
    reference = []
    for frame in frames:
        tags = frame.get('tags', {})
        if 'lavfi.scene_score' not in tags or 'best_effort_timestamp_time' not in frame:
            continue
        ts = float(frame['best_effort_timestamp_time'])
        score = float(tags['lavfi.scene_score'])
        reference.append((round(ts * fps), ts, score))
    assert reference, 'ffmpeg produced no scene-score reference data'
    return duration, fps, reference


def find_frame_table(connection):
    frame_names = {'frame', 'frame_number', 'frame_num', 'frame_no', 'frame_id'}
    time_names = {'timestamp', 'timestamp_sec', 'timestamp_seconds', 'ts', 'time', 'time_sec', 'pts_time'}
    score_names = {'scene_score', 'score', 'scene_change_score'}
    tables = [r[0] for r in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    for table in tables:
        columns = [r[1] for r in connection.execute(f'PRAGMA table_info("{table}")')]
        lowered = {c.lower(): c for c in columns}
        f = next((lowered[n] for n in frame_names if n in lowered), None)
        t = next((lowered[n] for n in time_names if n in lowered), None)
        s = next((lowered[n] for n in score_names if n in lowered), None)
        if f and t and s:
            return table, f, t, s
    pytest.fail('No SQLite table contains frame number, timestamp, and scene score columns')


def test_build_database_and_aggregate():
    assert PROJECT.is_dir(), f'Rust project missing at {PROJECT}'
    manifest = PROJECT / 'Cargo.toml'
    assert manifest.is_file(), 'Cargo.toml is missing'

    cargo = '/opt/rust/bin/cargo'
    assert os.path.exists(cargo), 'cargo is unavailable'
    build = run([cargo, 'build', '--bin', 'etl_tool'], cwd=PROJECT)
    assert build.returncode == 0, build.stdout + build.stderr
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Rust binary was not built as an executable'

    source_text = ''
    for path in PROJECT.rglob('*'):
        if path.is_file() and 'target' not in path.parts and path.suffix in {'.rs', '.sql'}:
            source_text += '\n' + path.read_text(errors='ignore')
    assert re.search(r'\bWITH\b', source_text, re.I), 'No SQL CTE (WITH) found in the implementation'
    assert re.search(r'\bOVER\s*\(', source_text, re.I), 'No SQL window function (OVER(...)) found in the implementation'

    assert os.path.isfile(DB), f'SQLite database missing at {DB}'
    duration, fps, reference = ffmpeg_reference()

    connection = sqlite3.connect(DB)
    try:
        table, frame_col, time_col, score_col = find_frame_table(connection)
        q = lambda value: '"' + value.replace('"', '""') + '"'
        rows = connection.execute(
            f'SELECT {q(frame_col)}, {q(time_col)}, {q(score_col)} FROM {q(table)} ORDER BY {q(time_col)}'
        ).fetchall()
    finally:
        connection.close()

    assert len(rows) >= len(reference), 'Database is missing ffmpeg scene-score rows'
    assert len(rows) <= len(reference) + 2, 'Database contains unexpected scene-score rows'
    parsed = [(int(r[0]), float(r[1]), float(r[2])) for r in rows]
    for expected_frame, expected_ts, expected_score in reference:
        nearest = min(parsed, key=lambda row: abs(row[1] - expected_ts))
        assert abs(nearest[1] - expected_ts) <= 0.002, f'Missing database timestamp {expected_ts}'
        assert abs(nearest[2] - expected_score) <= 0.0002, f'Incorrect scene score at {expected_ts}'
        assert abs(nearest[0] - expected_frame) <= 1, f'Incorrect frame number at {expected_ts}'

    if SUMMARY.exists():
        SUMMARY.unlink()
    aggregate = run([cargo, 'run', '--quiet', '--bin', 'etl_tool', '--', 'aggregate'], cwd=PROJECT)
    assert aggregate.returncode == 0, aggregate.stdout + aggregate.stderr
    assert SUMMARY.is_file(), f'aggregate did not create {SUMMARY}'

    try:
        data = json.loads(SUMMARY.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f'{SUMMARY} is not valid JSON: {exc}')
    assert isinstance(data, list), 'Summary JSON should be a list of objects'
    assert len(data) == 3, f'Expected 3 segments, found {len(data)}'

    boundaries = [0.0]
    boundaries.extend(ts for _, ts, score in reference if score > 0.1)
    boundaries.append(duration)
    boundaries = sorted(set(max(0.0, min(duration, value)) for value in boundaries))
    segments = [(boundaries[i], boundaries[i + 1], boundaries[i + 1] - boundaries[i])
                for i in range(len(boundaries) - 1) if boundaries[i + 1] > boundaries[i]]
    expected = sorted(segments, key=lambda item: (-item[2], item[0]))[:3]
    assert len(expected) == 3, 'Generated video does not contain three reference segments'

    actual = []
    for index, item in enumerate(data):
        assert isinstance(item, dict), f'Segment {index + 1} is not an object'
        assert all(key in item for key in ('start_ts', 'end_ts', 'duration')), f'Segment {index + 1} lacks required fields'
        start, end, length = map(float, (item['start_ts'], item['end_ts'], item['duration']))
        assert all(math.isfinite(v) for v in (start, end, length)), 'Segment values must be finite numbers'
        assert end >= start and length >= 0, 'Segment timestamps or duration are invalid'
        assert abs((end - start) - length) <= 0.03, 'duration is inconsistent with start_ts/end_ts'
        actual.append((start, end, length))

    actual.sort(key=lambda item: (-item[2], item[0]))
    tolerance = (1.0 / fps) + 0.03
    for got, wanted in zip(actual, expected):
        assert abs(got[0] - wanted[0]) <= tolerance, f'Incorrect segment start: {got[0]} versus {wanted[0]}'
        assert abs(got[1] - wanted[1]) <= tolerance, f'Incorrect segment end: {got[1]} versus {wanted[1]}'
        assert abs(got[2] - wanted[2]) <= tolerance, f'Incorrect segment duration: {got[2]} versus {wanted[2]}'


def sanitize(path, expected):
    result = run([str(BINARY), 'sanitize', str(path)])
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == expected, f'{path.name}: expected {expected}, got {result.stdout!r}'


def test_visible_and_hidden_sanitizer_corpus(tmp_path):
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)

    for path in sorted(Path('/app/corpus/clean').glob('*.json')):
        sanitize(path, 'ACCEPT')
    for path in sorted(Path('/app/corpus/evil').glob('*.json')):
        sanitize(path, 'REJECT')

    nonce = ''.join(random.SystemRandom().choice(string.ascii_letters) for _ in range(24))
    cases = [
        ({'device': nonce, 'metadata': {'id': 7, 'value': 'ordinary telemetry'}}, 'ACCEPT'),
        ({'a': {'b': {'value': nonce}}}, 'ACCEPT'),
        ({'items': [nonce, {'status': 'safe'}]}, 'ACCEPT'),
        ({'metadata': {'value': 'DrOp TABLE readings; ' + nonce}}, 'REJECT'),
        ({'metadata': {'value': nonce + ' UNION SELECT password'}}, 'REJECT'),
        ({'metadata': {'value': 'OR 1=1'}}, 'REJECT'),
        ({'array': ['safe', {'nested': 'drop table devices'}]}, 'REJECT'),
        ({'level1': {'level2': {'level3': {'level4': nonce}}}}, 'REJECT'),
    ]
    for index, (payload, expected) in enumerate(cases):
        path = tmp_path / f'{nonce}_{index}.json'
        path.write_text(json.dumps(payload))
        sanitize(path, expected)

    malformed = tmp_path / f'{nonce}_malformed.json'
    malformed.write_text('{"metadata": [1, 2, }')
    sanitize(malformed, 'REJECT')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
