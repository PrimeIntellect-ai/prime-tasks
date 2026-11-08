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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import signal
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests

FRAMES_DIR = Path('/home/user/frames')
CSV_PATH = Path('/home/user/distances.csv')
PROJECT_DIR = Path('/home/user/video_analyzer')
SOURCE_VIDEO = '/app/source_video.mp4'
API_URL = 'http://127.0.0.1:8000'


def listening_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def stop_port(port):
    pids = listening_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.1)
    for pid in listening_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.1)
    assert not listening_pids(port), 'Could not stop the pre-existing service on port 8000'


def decode_rgb(path):
    result = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', str(path), '-frames:v', '1',
         '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f'{path} is not a valid decodable PNG: {result.stderr.decode(errors="replace")}'
    assert len(result.stdout) == 640 * 480 * 3, f'{path} has incorrect dimensions or pixel data'
    return result.stdout


def grayscale_variants(rgb):
    variants = [bytearray() for _ in range(4)]
    for i in range(0, len(rgb), 3):
        r, g, b = rgb[i], rgb[i + 1], rgb[i + 2]
        variants[0].append((299 * r + 587 * g + 114 * b) // 1000)
        variants[1].append((299 * r + 587 * g + 114 * b + 500) // 1000)
        variants[2].append((2126 * r + 7152 * g + 722 * b) // 10000)
        variants[3].append((2126 * r + 7152 * g + 722 * b + 5000) // 10000)
    return variants


def mad(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


@pytest.fixture(scope='session', autouse=True)
def built_rust_service():
    assert PROJECT_DIR.is_dir(), f'Rust project {PROJECT_DIR} does not exist'
    assert (PROJECT_DIR / 'Cargo.toml').is_file(), 'Cargo.toml is missing'
    rust_sources = list(PROJECT_DIR.rglob('*.rs'))
    assert rust_sources, 'The project contains no Rust source files'

    env = os.environ.copy()
    env['CARGO_NET_OFFLINE'] = 'true'
    build = subprocess.run(
        ['cargo', 'build', '--offline'], cwd=PROJECT_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180
    )
    assert build.returncode == 0, 'The submitted Rust project does not build:\n' + build.stdout

    metadata = subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1'],
        cwd=PROJECT_DIR, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert metadata.returncode == 0, metadata.stderr
    meta = json.loads(metadata.stdout)
    bins = []
    for package in meta['packages']:
        for target in package['targets']:
            if 'bin' in target['kind']:
                bins.append(target['name'])
    assert bins, 'Cargo project has no executable Rust binary target'
    assert len(bins) == 1, 'Cargo project must identify a single server binary'
    executable = Path(meta['target_directory']) / 'debug' / bins[0]
    assert executable.is_file() and os.access(executable, os.X_OK), 'Cargo did not produce an executable binary'

    stop_port(8000)
    proc = subprocess.Popen(
        [str(executable)], cwd=PROJECT_DIR, env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 30
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f'Freshly built Rust binary exited with status {proc.returncode}')
        try:
            if requests.get(API_URL + '/api/distances', timeout=0.5).status_code == 200:
                break
        except requests.RequestException:
            pass
        time.sleep(0.25)
    else:
        proc.terminate()
        pytest.fail('Freshly built Rust binary did not start its server on 127.0.0.1:8000')

    yield

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()


@pytest.fixture(scope='session')
def expected_data(tmp_path_factory):
    ref_dir = tmp_path_factory.mktemp('reference_frames')
    result = subprocess.run(
        ['ffmpeg', '-v', 'error', '-y', '-i', SOURCE_VIDEO, '-vf', 'fps=1',
         '-start_number', '1', str(ref_dir / 'frame_%04d.png')],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    refs = sorted(ref_dir.glob('frame_*.png'))
    assert refs, 'Verifier failed to derive reference frames'

    submitted = sorted(FRAMES_DIR.glob('*.png')) if FRAMES_DIR.exists() else []
    assert len(submitted) == len(refs), f'Expected exactly {len(refs)} one-frame-per-second PNGs, found {len(submitted)}'

    submitted_grays = []
    for i, (actual, reference) in enumerate(zip(submitted, refs), 1):
        assert actual.name == f'frame_{i:04d}.png', f'Expected frame name frame_{i:04d}.png, found {actual.name}'
        assert actual.stat().st_size > 0, f'Frame {actual.name} is empty'
        actual_rgb = decode_rgb(actual)
        reference_rgb = decode_rgb(reference)
        assert actual_rgb == reference_rgb, f'{actual.name} is not the frame extracted at the required one-second cadence'
        submitted_grays.append(grayscale_variants(actual_rgb))

    expected_mads = []
    for i in range(len(submitted_grays) - 1):
        expected_mads.append([
            mad(submitted_grays[i][variant], submitted_grays[i + 1][variant])
            for variant in range(4)
        ])
    return submitted, expected_mads


def matches_expected(value, candidates):
    return any(abs(value - candidate) <= 0.06 for candidate in candidates)


def test_frames_extracted(expected_data):
    frames, _ = expected_data
    assert FRAMES_DIR.exists(), f'Directory {FRAMES_DIR} does not exist'
    assert len(frames) > 0, 'No PNG frames found in the frames directory'


def test_csv_output(expected_data):
    _, expected_mads = expected_data
    assert CSV_PATH.exists(), f'CSV file {CSV_PATH} does not exist'
    with CSV_PATH.open(newline='') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == ['start_frame', 'end_frame', 'mad'], f'Incorrect CSV headers: {headers}'
        rows = list(reader)

    assert len(rows) > 0, 'CSV file contains no data rows'
    assert len(rows) == len(expected_mads), f'Expected {len(expected_mads)} CSV rows, found {len(rows)}'
    for i, row in enumerate(rows, 1):
        assert len(row) == 3, f'Row {i} does not have exactly 3 columns'
        assert int(row[0]) == i, f'Expected start_frame {i}, got {row[0]}'
        assert int(row[1]) == i + 1, f'Expected end_frame {i + 1}, got {row[1]}'
        assert re.fullmatch(r'\d+\.\d{2}', row[2]), f'MAD value {row[2]!r} is not formatted to exactly two decimal places'
        value = float(row[2])
        assert math.isfinite(value) and matches_expected(value, expected_mads[i - 1]), f'Incorrect MAD for frames {i} and {i + 1}: {value}'


def test_api_distances(expected_data):
    _, expected_mads = expected_data
    try:
        response = requests.get(API_URL + '/api/distances', timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to API: {e}')
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
    try:
        data = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail('API response is not valid JSON')
    assert isinstance(data, list), 'API response should be a JSON array'
    assert len(data) > 0, 'API response array is empty'
    assert len(data) == len(expected_mads), f'Expected {len(expected_mads)} API entries, found {len(data)}'

    with CSV_PATH.open(newline='') as f:
        csv_rows = list(csv.DictReader(f))
    for i, item in enumerate(data, 1):
        assert isinstance(item, dict)
        assert 'start_frame' in item, "Missing 'start_frame' in API response"
        assert 'end_frame' in item, "Missing 'end_frame' in API response"
        assert 'mad' in item, "Missing 'mad' in API response"
        assert item['start_frame'] == i, f'Expected start_frame {i}, got {item["start_frame"]}'
        assert item['end_frame'] == i + 1, f'Expected end_frame {i + 1}, got {item["end_frame"]}'
        assert isinstance(item['mad'], (int, float)) and not isinstance(item['mad'], bool), f'MAD value {item["mad"]} is not a number'
        value = float(item['mad'])
        assert math.isfinite(value) and matches_expected(value, expected_mads[i - 1]), f'API returned incorrect MAD for frames {i} and {i + 1}'
        assert abs(value - float(csv_rows[i - 1]['mad'])) <= 0.011, 'API MAD does not agree with distances.csv'


def test_api_frames(expected_data):
    frames, _ = expected_data
    for frame_id, expected_frame_path in enumerate(frames, 1):
        assert expected_frame_path.exists(), f'Frame file {expected_frame_path} missing'
        try:
            response = requests.get(f'{API_URL}/api/frames/{frame_id}', timeout=5)
        except requests.RequestException as e:
            pytest.fail(f'Failed to connect to API: {e}')
        assert response.status_code == 200, f'Expected status code 200, got {response.status_code}'
        assert response.headers.get('Content-Type') == 'image/png', f'Expected Content-Type image/png, got {response.headers.get("Content-Type")}'
        assert response.content == expected_frame_path.read_bytes(), 'API response content does not match the actual frame file'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
