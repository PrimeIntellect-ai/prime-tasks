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
import hashlib
import os
import random
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

PROJECT = Path('/home/user/pipeline_service')
VIDEO = Path('/app/video.mp4')
CSV = Path('/app/telemetry.csv')
URL = 'http://127.0.0.1:9000/data'


def listener_pids(port=9000):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def stop_existing_service():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(process, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f'cargo run exited before opening port 9000 (status {process.returncode})')
        try:
            with socket.create_connection(('127.0.0.1', 9000), timeout=0.5):
                return
        except OSError:
            time.sleep(0.25)
    pytest.fail('Rust service did not listen on 127.0.0.1:9000 within 120 seconds')


@pytest.fixture(scope='session', autouse=True)
def rust_service():
    assert PROJECT.is_dir(), f'Missing Rust project directory: {PROJECT}'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Missing Cargo.toml in the required project directory'
    assert any(PROJECT.rglob('*.rs')), 'The project contains no Rust source files'

    original_video = VIDEO.read_bytes()
    original_csv = CSV.read_bytes()
    stop_existing_service()

    process = subprocess.Popen(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_port(process)
        yield
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stop_existing_service()
        VIDEO.write_bytes(original_video)
        CSV.write_bytes(original_csv)


def get_hash_for_timestamp(t):
    cmd = [
        'ffmpeg', '-y', '-ss', f'00:00:0{t}', '-i', str(VIDEO),
        '-frames:v', '1', '-s', '64x64', '-f', 'rawvideo',
        '-pix_fmt', 'rgb24', '-'
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f'ffmpeg failed for t={t}: {result.stderr.decode()}'
    assert len(result.stdout) == 64 * 64 * 3, f'Expected 12288 RGB24 bytes for t={t}, got {len(result.stdout)}'
    return hashlib.sha256(result.stdout).hexdigest()


def fetch_data():
    try:
        response = requests.get(URL, timeout=45)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to the service at {URL}: {exc}')
    assert response.status_code == 200, (
        f'Expected status code 200, got {response.status_code}. '
        f'Response body: {response.text}'
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {response.text}')
    assert isinstance(data, list), f'Response JSON must be a list of objects, got {type(data)}'
    return data


def expected(rows):
    return [
        {
            'timestamp': timestamp,
            'frame_hash': get_hash_for_timestamp(timestamp),
            'telemetry_value': value,
        }
        for timestamp, value in rows
    ]


def install_random_video():
    width = random.choice([288, 320, 352, 384])
    height = random.choice([216, 240, 264, 288])
    box_x = random.randint(5, width // 2)
    box_y = random.randint(5, height // 2)
    colors = ['red', 'green', 'blue', 'yellow', 'magenta', 'cyan']
    color = random.choice(colors)
    temporary = Path('/app/video.dynamic.mp4')
    cmd = [
        'ffmpeg', '-y', '-f', 'lavfi',
        '-i', f'testsrc2=duration=7:size={width}x{height}:rate=25',
        '-vf', f'drawbox=x={box_x}:y={box_y}:w=47:h=39:color={color}:t=fill',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(temporary),
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f'Failed to create changed video fixture: {result.stderr.decode()}'
    os.replace(temporary, VIDEO)


def test_01_original_fixture_response():
    data = fetch_data()
    assert len(data) == 2, (
        'Expected exactly 2 items in the response (t=1 and t=4 after '
        f'deduplication and cleaning), got {len(data)}. Data: {data}'
    )
    expected_data = expected([(1, 100), (4, 150)])
    assert data == expected_data, (
        f'Response JSON does not match expected output.\nExpected: {expected_data}\nActual: {data}'
    )


def test_02_processes_changed_video_and_csv_at_request_time():
    install_random_video()
    a, corrupt, c, d = random.sample(range(1000, 9000), 4)
    CSV.write_text(
        'timestamp,value,notes\n'
        f'1,{a},"first"\n'
        f'2,{corrupt},"embedded newline\nmust be dropped"\n'
        f'3,{a},"duplicate after cleaning"\n'
        f'4,{c},"new value"\n'
        f'5,{d},"another value"\n'
    )
    expected_data = expected([(1, a), (4, c), (5, d)])
    data = fetch_data()
    assert data == expected_data, (
        'Service did not process the changed video/CSV correctly at request time. '
        f'Expected: {expected_data}; actual: {data}'
    )


def test_03_reloads_csv_and_deduplicates_cleaned_sequence():
    x, y, corrupt = random.sample(range(10000, 50000), 3)
    CSV.write_text(
        'timestamp,value,notes\n'
        f'1,{x},"start"\n'
        f'2,{y},"changed"\n'
        f'3,{y},"duplicate"\n'
        f'4,{corrupt},"bad\nrow"\n'
        f'5,{y},"still duplicate after bad row is removed"\n'
    )
    expected_data = expected([(1, x), (2, y)])
    data = fetch_data()
    assert data == expected_data, (
        'Service did not reload, clean, synchronize, and deduplicate the second CSV. '
        f'Expected: {expected_data}; actual: {data}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
