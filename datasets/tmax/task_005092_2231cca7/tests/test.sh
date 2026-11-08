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
import csv
import json
import math
import os
import re
import sqlite3
import struct
import subprocess
from functools import lru_cache
from pathlib import Path

import pytest
import requests

FRAMES = Path('/app/processed/frames')
DB_PATH = Path('/app/processed/vector_store.db')
BENCHMARK = Path('/app/processed/benchmark.txt')
SRC = Path('/app/src')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def test_vector_store_db_exists():
    assert DB_PATH.is_file(), '/app/processed/vector_store.db is missing'
    assert DB_PATH.stat().st_size > 0, 'vector_store.db is empty'
    with DB_PATH.open('rb') as f:
        assert f.read(16) == b'SQLite format 3\x00', 'vector_store.db is not an SQLite database'


def test_benchmark_txt_exists():
    assert BENCHMARK.is_file(), '/app/processed/benchmark.txt is missing'
    text = BENCHMARK.read_text(errors='replace')
    assert text.strip(), 'benchmark.txt is empty'
    assert re.search(r'(?m)^BenchmarkEmbedding(?:-\d+)?\s+\d+\s+.*ns/op', text), \
        'benchmark.txt does not contain standard Go BenchmarkEmbedding results'


def test_frames_extracted_and_match_video():
    for i in range(10):
        frame_path = FRAMES / f'frame_{i}.jpg'
        assert frame_path.is_file(), f'Extracted frame {frame_path} is missing'
        assert frame_path.stat().st_size > 100, f'{frame_path} is empty or invalid'
        with frame_path.open('rb') as f:
            assert f.read(2) == b'\xff\xd8', f'{frame_path} is not a JPEG image'

    ref_dir = Path('/tmp/reference_frames')
    ref_dir.mkdir(exist_ok=True)
    run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-i', '/app/data/surveillance.mp4', '-vf', 'fps=1',
        '-start_number', '0', str(ref_dir / 'frame_%d.jpg')
    ], timeout=60)

    refs = sorted(ref_dir.glob('frame_*.jpg'))
    assert len(refs) == 10, f'Reference extraction produced {len(refs)} frames instead of 10'

    def dimensions(path):
        p = run([
            'ffprobe', '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height', '-of', 'csv=p=0:s=x', str(path)
        ], timeout=10)
        return p.stdout.decode().strip()

    def gray_pixels(path):
        return run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(path),
            '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'gray', '-'
        ], timeout=20).stdout

    for i in range(10):
        actual = FRAMES / f'frame_{i}.jpg'
        reference = ref_dir / f'frame_{i}.jpg'
        assert dimensions(actual) == dimensions(reference) == '640x480', \
            f'frame_{i}.jpg has incorrect dimensions'
        a = gray_pixels(actual)
        b = gray_pixels(reference)
        assert len(a) == len(b) == 640 * 480, f'frame_{i}.jpg could not be decoded correctly'
        mae = sum(abs(x - y) for x, y in zip(a, b)) / len(a)
        assert mae <= 6.0, \
            f'frame_{i}.jpg does not match video second {i} (grayscale MAE {mae:.3f})'


@lru_cache(maxsize=1)
def computed_embeddings():
    helper = r'''
package main
import (
  "encoding/json"
  "fmt"
  "image"
  "image/color"
  _ "image/jpeg"
  "os"
)
func embedding(path string) ([]float64, error) {
  f, err := os.Open(path); if err != nil { return nil, err }; defer f.Close()
  img, _, err := image.Decode(f); if err != nil { return nil, err }
  b := img.Bounds(); w, h := b.Dx(), b.Dy()
  if w < 4 || h < 4 { return nil, fmt.Errorf("image too small") }
  out := make([]float64, 0, 16)
  for gy := 0; gy < 4; gy++ {
    y0, y1 := gy*h/4, (gy+1)*h/4
    for gx := 0; gx < 4; gx++ {
      x0, x1 := gx*w/4, (gx+1)*w/4
      var sum float64
      var count int
      for y := y0; y < y1; y++ { for x := x0; x < x1; x++ {
        g := color.GrayModel.Convert(img.At(b.Min.X+x, b.Min.Y+y)).(color.Gray)
        sum += float64(g.Y); count++
      }}
      out = append(out, sum/float64(count)/255.0)
    }
  }
  return out, nil
}
func main() {
  enc := json.NewEncoder(os.Stdout)
  for _, p := range os.Args[1:] {
    v, err := embedding(p); if err != nil { panic(err) }
    if err := enc.Encode(v); err != nil { panic(err) }
  }
}
'''
    Path('/tmp/check_embedding.go').write_text(helper)
    paths = [str(FRAMES / f'frame_{i}.jpg') for i in range(10)]
    p = run(['go', 'run', '/tmp/check_embedding.go', *paths], timeout=120)
    values = [json.loads(line) for line in p.stdout.decode().splitlines() if line.strip()]
    assert len(values) == 10
    for v in values:
        assert len(v) == 16
        assert all(isinstance(x, (int, float)) and math.isfinite(x) and 0 <= x <= 1 for x in v)
    return values


def parse_vector(value):
    if isinstance(value, str):
        text = value.strip()
        try:
            parsed = json.loads(text)
        except Exception:
            parsed = [x.strip() for x in text.strip('[](){}').split(',') if x.strip()]
        if isinstance(parsed, dict):
            parsed = parsed.get('embedding', parsed.get('vector'))
        if isinstance(parsed, list):
            return [float(x) for x in parsed]
    if isinstance(value, (bytes, bytearray)):
        raw = bytes(value)
        try:
            return parse_vector(raw.decode())
        except Exception:
            if len(raw) == 16 * 8:
                return list(struct.unpack('<16d', raw))
            if len(raw) == 16 * 4:
                return [float(x) for x in struct.unpack('<16f', raw)]
    if isinstance(value, (list, tuple)):
        return [float(x) for x in value]
    raise ValueError('unsupported vector representation')


def qident(name):
    return '"' + name.replace('"', '""') + '"'


def natural_key(name):
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r'(\d+)', name)]


@lru_cache(maxsize=1)
def load_store():
    expected_meta = {}
    with open('/app/data/events.csv', newline='') as f:
        for row in csv.DictReader(f):
            expected_meta[int(row['timestamp_sec'])] = (row['event_name'], row['camera_id'])

    conn = sqlite3.connect(f'file:{DB_PATH}?mode=ro', uri=True)
    try:
        integrity = conn.execute('PRAGMA integrity_check').fetchone()[0]
        assert integrity == 'ok', f'SQLite integrity check failed: {integrity}'
        tables = [r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )]
        chosen = None
        for table in tables:
            info = conn.execute(f'PRAGMA table_info({qident(table)})').fetchall()
            cols = [r[1] for r in info]
            lower = {c.lower(): c for c in cols}
            ts = lower.get('timestamp') or lower.get('timestamp_sec')
            event = lower.get('event_name')
            camera = lower.get('camera_id')
            if ts and event and camera:
                chosen = (table, info, cols, ts, event, camera)
                break
        assert chosen is not None, \
            'No table contains timestamp/timestamp_sec, event_name, and camera_id columns'
        table, info, cols, ts_col, event_col, camera_col = chosen
        rows = conn.execute(f'SELECT * FROM {qident(table)}').fetchall()
        assert len(rows) == 10, f'Expected exactly 10 joined records, found {len(rows)}'
        index = {c: i for i, c in enumerate(cols)}
        lower = {c.lower(): c for c in cols}

        packed_col = lower.get('embedding') or lower.get('vector') or lower.get('embeddings')
        vector_cols = None
        if packed_col is None:
            candidates = [c for c in cols if c not in (ts_col, event_col, camera_col)
                          and re.search(r'(embedding|vector|dim|feature|^e|^v|^f)[_ -]*\d+$', c, re.I)]
            if len(candidates) >= 16:
                vector_cols = sorted(candidates, key=natural_key)[:16]
            else:
                numeric = [r[1] for r in info
                           if r[1] not in (ts_col, event_col, camera_col)
                           and r[1].lower() != 'id'
                           and any(t in (r[2] or '').upper() for t in ('REAL', 'FLOA', 'DOUB', 'NUM'))]
                if len(numeric) == 16:
                    vector_cols = sorted(numeric, key=natural_key)
        assert packed_col is not None or vector_cols is not None, \
            'Could not find a packed embedding/vector column or 16 vector component columns'

        records = {}
        for row in rows:
            timestamp = row[index[ts_col]]
            assert isinstance(timestamp, (int, float)) and int(timestamp) == timestamp
            timestamp = int(timestamp)
            assert timestamp in expected_meta, f'Unexpected timestamp {timestamp}'
            assert timestamp not in records, f'Duplicate timestamp {timestamp}'
            event = row[index[event_col]]
            camera = row[index[camera_col]]
            assert (event, camera) == expected_meta[timestamp], \
                f'Incorrect CSV join for timestamp {timestamp}'
            if packed_col is not None:
                vector = parse_vector(row[index[packed_col]])
            else:
                vector = [float(row[index[c]]) for c in vector_cols]
            assert len(vector) == 16, f'Timestamp {timestamp} embedding has {len(vector)} dimensions'
            assert all(math.isfinite(x) and 0.0 <= x <= 1.0 for x in vector), \
                f'Timestamp {timestamp} embedding contains invalid values'
            records[timestamp] = (event, camera, vector)
        assert set(records) == set(range(10)), 'Database timestamps must be exactly 0 through 9'
    finally:
        conn.close()

    expected_embeddings = computed_embeddings()
    for timestamp in range(10):
        actual = records[timestamp][2]
        expected = expected_embeddings[timestamp]
        max_error = max(abs(a - b) for a, b in zip(actual, expected))
        assert max_error <= 1e-5, \
            f'Incorrect 4x4 grayscale embedding for timestamp {timestamp}; max error {max_error}'
    return records


def test_database_schema_metadata_and_embeddings():
    load_store()


def test_go_benchmark_really_executes():
    go_files = list(SRC.rglob('*.go'))
    test_files = list(SRC.rglob('*_test.go'))
    assert go_files, 'No Go source files found under /app/src'
    assert test_files, 'No Go _test.go benchmark file found under /app/src'
    assert any(re.search(r'func\s+BenchmarkEmbedding\s*\(', p.read_text(errors='replace'))
               for p in test_files), 'BenchmarkEmbedding is not defined in a _test.go file'
    p = run([
        'go', 'test', '-run', '^$', '-bench', '^BenchmarkEmbedding$',
        '-benchtime=1x', './...'
    ], cwd=str(SRC), timeout=180)
    output = (p.stdout + p.stderr).decode(errors='replace')
    assert re.search(r'(?m)^BenchmarkEmbedding(?:-\d+)?\s+1\s+.*ns/op', output), \
        f'Go test did not execute BenchmarkEmbedding:\n{output}'


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    assert na > 0 and nb > 0
    return dot / (na * nb)


def authorized_search(vector):
    text = ','.join(format(x, '.17g') for x in vector)
    response = requests.get(
        'http://127.0.0.1:8080/search', params={'vector': text},
        headers={'Authorization': 'Bearer ds-api-token'}, timeout=5)
    assert response.status_code == 200, \
        f'Expected 200 OK, got {response.status_code}. Response: {response.text}'
    assert response.headers.get('Content-Type', '').lower().startswith('application/json'), \
        'Authorized response is not application/json'
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON. Response text: {response.text}')
    assert 'timestamp' in data, "Response JSON missing 'timestamp' key"
    assert 'event_name' in data, "Response JSON missing 'event_name' key"
    assert 'camera_id' in data, "Response JSON missing 'camera_id' key"
    assert isinstance(data['timestamp'], int) and not isinstance(data['timestamp'], bool)
    assert isinstance(data['event_name'], str)
    assert isinstance(data['camera_id'], str)
    return data


def assert_correct_search(query):
    records = load_store()
    scores = {ts: cosine(query, rec[2]) for ts, rec in records.items()}
    best = max(scores.values())
    acceptable = {ts for ts, score in scores.items() if abs(score - best) <= 1e-10}
    data = authorized_search(query)
    assert data['timestamp'] in acceptable, \
        f'API returned timestamp {data["timestamp"]}, but cosine search requires one of {sorted(acceptable)}'
    event, camera, _ = records[data['timestamp']]
    assert data['event_name'] == event, 'API returned event_name from the wrong record'
    assert data['camera_id'] == camera, 'API returned camera_id from the wrong record'


def test_api_unauthorized():
    vector = ','.join(['0.5'] * 16)
    try:
        response = requests.get(f'http://127.0.0.1:8080/search?vector={vector}', timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to API: {e}')
    assert response.status_code == 401, \
        f'Expected 401 Unauthorized without token, got {response.status_code}'
    wrong = requests.get(f'http://127.0.0.1:8080/search?vector={vector}',
                         headers={'Authorization': 'Bearer wrong-token'}, timeout=5)
    assert wrong.status_code == 401, \
        f'Expected 401 Unauthorized with incorrect token, got {wrong.status_code}'


def test_api_authorized_search():
    # Preserve the original fixed-vector request, but validate its actual cosine result.
    assert_correct_search([0.5] * 16)
    records = load_store()
    # Exact validated frame embeddings give independently derived, nonconstant searches.
    for timestamp in (0, 3, 6, 9):
        assert_correct_search(records[timestamp][2])
    assert_correct_search([0.05 + 0.055 * i for i in range(16)])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
