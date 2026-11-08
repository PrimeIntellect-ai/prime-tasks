#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

import pytest

SERVICE = '/home/user/service'
VIDEO = '/app/video.mp4'
URL = 'http://127.0.0.1:8080/api/peak_motion'
TOKEN = 'Bearer deploy_token_2024'
WIDTH = 320
HEIGHT = 240
FRAME_SIZE = WIDTH * HEIGHT


def compute_expected_peak_frame(video_path):
    cmd = [
        'ffmpeg', '-i', video_path,
        '-f', 'image2pipe', '-pix_fmt', 'gray',
        '-vcodec', 'rawvideo', '-'
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    prev_frame = None
    max_diff = -1
    peak_frame_idx = -1
    current_idx = 1

    while True:
        raw_frame = process.stdout.read(FRAME_SIZE)
        if not raw_frame or len(raw_frame) != FRAME_SIZE:
            break
        if prev_frame is not None:
            diff = sum(abs(raw_frame[i] - prev_frame[i]) for i in range(FRAME_SIZE))
            if diff > max_diff:
                max_diff = diff
                peak_frame_idx = current_idx
        prev_frame = raw_frame
        current_idx += 1

    process.stdout.close()
    process.wait(timeout=15)
    return peak_frame_idx


def make_video(path, frames):
    payload = b''.join(frames)
    cmd = [
        'ffmpeg', '-y', '-loglevel', 'error',
        '-f', 'rawvideo', '-pix_fmt', 'gray',
        '-s', f'{WIDTH}x{HEIGHT}', '-r', '10', '-i', '-',
        '-c:v', 'ffv1', path,
    ]
    subprocess.run(cmd, input=payload, check=True, timeout=60)


def request_peak(auth=TOKEN):
    request = urllib.request.Request(URL, headers={'Authorization': auth})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def decode_peak_response(body):
    try:
        data = json.loads(body.decode())
    except Exception as error:
        pytest.fail(f'Response is not valid JSON: {body!r}: {error}')
    assert 'peak_frame' in data, f"Response JSON missing 'peak_frame' key: {data}"
    assert isinstance(data['peak_frame'], int) and not isinstance(data['peak_frame'], bool)
    return data['peak_frame']


def load_analyzer(path):
    lib = ctypes.CDLL(path)
    function = lib.analyze_video
    function.restype = ctypes.c_int
    function.argtypes = [ctypes.c_char_p]
    return function


def test_service_response():
    assert os.path.exists(VIDEO), f'Video file missing at {VIDEO}'
    expected_peak = compute_expected_peak_frame(VIDEO)
    try:
        status, body = request_peak()
    except Exception as error:
        pytest.fail(f'Failed to connect to the service at {URL}: {error}')
    assert status == 200, f'Expected HTTP 200, got {status}. Response: {body!r}'
    actual_peak = decode_peak_response(body)
    assert actual_peak == expected_peak, (
        f'Expected peak_frame {expected_peak}, but got {actual_peak}'
    )


def test_unauthorized_access():
    try:
        status, _ = request_peak('Bearer wrong_token')
    except Exception as error:
        pytest.fail(f'Failed to connect to the service at {URL}: {error}')
    assert status == 401, f'Expected HTTP 401 for bad token, got {status}'


def test_makefile_builds_shared_library_and_source_builds_independently():
    analyzer = os.path.join(SERVICE, 'analyzer.c')
    makefile = os.path.join(SERVICE, 'Makefile')
    library = os.path.join(SERVICE, 'libanalyzer.so')
    for path in (analyzer, makefile):
        assert os.path.isfile(path) and not os.path.islink(path), f'Missing regular file: {path}'

    make_text = open(makefile, encoding='utf-8').read()
    assert re.search(r'-(?:fPIC|fpic)\b', make_text), 'Makefile must compile position-independent code'
    assert re.search(r'(?:^|\s)-shared\b|-Wl,[^\n]*-shared', make_text), 'Makefile must link a shared library'

    if os.path.lexists(library):
        os.unlink(library)
    built = subprocess.run(
        ['make'], cwd=SERVICE, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=60
    )
    assert built.returncode == 0, f'make failed:\n{built.stdout}'
    assert os.path.isfile(library) and not os.path.islink(library), 'make did not produce libanalyzer.so'
    with open(library, 'rb') as handle:
        assert handle.read(4) == b'\x7fELF', 'libanalyzer.so is not an ELF library'
    load_analyzer(library)

    independent = '/tmp/analyzer_under_test.so'
    compiled = subprocess.run(
        ['gcc', '-O2', '-Wall', '-Wextra', '-fPIC', '-shared', analyzer, '-o', independent],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert compiled.returncode == 0, f'analyzer.c does not independently compile as a shared library:\n{compiled.stdout}'
    load_analyzer(independent)


def test_compiled_c_library_on_derived_unseen_inputs(tmp_path):
    built_fn = load_analyzer(os.path.join(SERVICE, 'libanalyzer.so'))
    source_fn = load_analyzer('/tmp/analyzer_under_test.so')

    cases = [
        [bytes([0]) * FRAME_SIZE, bytes([17]) * FRAME_SIZE,
         bytes([240]) * FRAME_SIZE, bytes([241]) * FRAME_SIZE],
        [bytes([0]) * FRAME_SIZE, bytes([200]) * FRAME_SIZE,
         bytes([0]) * FRAME_SIZE, bytes([255]) * FRAME_SIZE],
        [
            bytes(((pixel * 13 + frame * frame * 29) & 255) for pixel in range(FRAME_SIZE))
            for frame in range(6)
        ],
    ]

    for index, frames in enumerate(cases):
        path = str(tmp_path / f'unseen_{index}.mkv')
        make_video(path, frames)
        expected = compute_expected_peak_frame(path)
        assert built_fn(os.fsencode(path)) == expected
        assert source_fn(os.fsencode(path)) == expected


def test_live_service_is_not_hardcoded_to_original_video(tmp_path):
    backup = str(tmp_path / 'original_video.mp4')
    shutil.copy2(VIDEO, backup)
    cases = [
        [bytes([0]) * FRAME_SIZE, bytes([10]) * FRAME_SIZE,
         bytes([250]) * FRAME_SIZE, bytes([251]) * FRAME_SIZE],
        [bytes([0]) * FRAME_SIZE, bytes([200]) * FRAME_SIZE,
         bytes([0]) * FRAME_SIZE, bytes([255]) * FRAME_SIZE],
    ]

    try:
        observed = []
        for index, frames in enumerate(cases):
            candidate = str(tmp_path / f'http_case_{index}.mkv')
            make_video(candidate, frames)
            expected = compute_expected_peak_frame(candidate)
            shutil.copyfile(candidate, VIDEO)
            status, body = request_peak()
            assert status == 200, f'Expected HTTP 200, got {status}: {body!r}'
            actual = decode_peak_response(body)
            assert actual == expected, f'Live service returned {actual}; expected {expected}'
            observed.append(actual)
        assert len(set(observed)) > 1, 'Dynamic service cases did not produce distinct results'
    finally:
        shutil.copyfile(backup, VIDEO)


def test_no_severe_per_frame_memory_leak(tmp_path):
    path = str(tmp_path / 'memory_test.mkv')
    frames = [os.urandom(FRAME_SIZE) for _ in range(120)]
    make_video(path, frames)
    expected = compute_expected_peak_frame(path)

    probe = r'''
import ctypes, os, sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.analyze_video
fn.restype = ctypes.c_int
fn.argtypes = [ctypes.c_char_p]
video = os.fsencode(sys.argv[2])
expected = int(sys.argv[3])
def rss():
    with open('/proc/self/status') as f:
        for line in f:
            if line.startswith('VmRSS:'):
                return int(line.split()[1])
    raise RuntimeError('VmRSS unavailable')
assert fn(video) == expected
before = rss()
for _ in range(8):
    assert fn(video) == expected
after = rss()
print(after - before)
'''
    result = subprocess.run(
        [sys.executable, '-c', probe, '/tmp/analyzer_under_test.so', path, str(expected)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=150
    )
    assert result.returncode == 0, f'Library memory probe failed:\n{result.stdout}\n{result.stderr}'
    growth_kib = int(result.stdout.strip().splitlines()[-1])
    assert growth_kib < 25 * 1024, f'Analyzer retained {growth_kib} KiB across repeated calls'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
