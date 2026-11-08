#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import sys
import tempfile
import uuid

import cv2
import numpy as np

SERVICE_DIR = '/app/service'
FLASH_SCRIPT = os.path.join(SERVICE_DIR, 'flash_detector.py')
FLASH_OUTPUT = '/home/user/flash_count.txt'
SANITIZER = '/home/user/sanitizer.py'


def run_python(script, *args, timeout=30, cwd=None):
    return subprocess.run(
        [sys.executable, script, *args],
        cwd=cwd,
        capture_output=True,
        timeout=timeout,
    )


def test_requirements_resolve():
    requirements = os.path.join(SERVICE_DIR, 'requirements.txt')
    assert os.path.isfile(requirements), 'requirements.txt is missing.'

    with open(requirements, encoding='utf-8') as f:
        meaningful = [line.strip().lower() for line in f if line.strip() and not line.lstrip().startswith('#')]
    assert any(line.startswith(('numpy', 'numpy[', 'numpy ', 'numpy=', 'numpy<', 'numpy>', 'numpy~', 'numpy!')) for line in meaningful), 'requirements.txt must include numpy.'
    assert any(line.startswith(('opencv-python', 'opencv-python[', 'opencv-python ', 'opencv-python=', 'opencv-python<', 'opencv-python>', 'opencv-python~', 'opencv-python!')) for line in meaningful), 'requirements.txt must include opencv-python.'

    result = subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '--dry-run', '--disable-pip-version-check', '-r', requirements],
        cwd=SERVICE_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, 'requirements.txt does not resolve successfully:\n' + result.stdout + '\n' + result.stderr


def test_flash_detector_output():
    assert os.path.isfile(FLASH_SCRIPT), f'Expected flash detector {FLASH_SCRIPT} does not exist.'
    if os.path.exists(FLASH_OUTPUT):
        os.remove(FLASH_OUTPUT)

    result = run_python(FLASH_SCRIPT, '/app/cctv_feed.mp4', timeout=60, cwd=SERVICE_DIR)
    assert result.returncode == 0, f'flash_detector.py failed: {result.stderr.decode(errors="replace")}'
    assert os.path.isfile(FLASH_OUTPUT), f'Expected output file {FLASH_OUTPUT} does not exist. Did you run the flash detector script?'

    with open(FLASH_OUTPUT, 'r') as f:
        content = f.read().strip()
    assert content == '5', f"Expected flash count to be 5, but got '{content}'."


def test_flash_detector_uses_correct_luminance_on_unseen_video():
    rng = secrets.SystemRandom()
    expected = rng.randint(2, 8)
    if expected == 5:
        expected = 7
    decoy_groups = rng.randint(2, 6)

    with tempfile.TemporaryDirectory() as td:
        video_path = os.path.join(td, uuid.uuid4().hex + '.avi')
        writer = cv2.VideoWriter(video_path, cv2.VideoWriter_fourcc(*'FFV1'), 12, (48, 32))
        assert writer.isOpened(), 'Could not create synthetic verification video.'

        black = np.zeros((32, 48, 3), dtype=np.uint8)
        white = np.full((32, 48, 3), 255, dtype=np.uint8)
        # In BGR this has low correct RGB luminance, but the original 0.5*(B+G+R)
        # expression exceeds 200 and therefore incorrectly treats it as a flash.
        colored_decoy = np.empty((32, 48, 3), dtype=np.uint8)
        colored_decoy[:] = (255, 0, 180)

        events = ['flash'] * expected + ['decoy'] * decoy_groups
        rng.shuffle(events)
        for event in events:
            for _ in range(rng.randint(2, 4)):
                writer.write(black)
            frame = white if event == 'flash' else colored_decoy
            for _ in range(rng.randint(2, 4)):
                writer.write(frame)
        for _ in range(3):
            writer.write(black)
        writer.release()

        if os.path.exists(FLASH_OUTPUT):
            os.remove(FLASH_OUTPUT)
        result = run_python(FLASH_SCRIPT, video_path, timeout=60, cwd=SERVICE_DIR)
        assert result.returncode == 0, f'flash_detector.py failed on an unseen video: {result.stderr.decode(errors="replace")}'
        assert os.path.isfile(FLASH_OUTPUT), 'flash_detector.py did not create flash_count.txt.'
        with open(FLASH_OUTPUT, encoding='utf-8') as f:
            actual = f.read().strip()
        assert actual == str(expected), f'Expected {expected} flashes on the unseen video, got {actual!r}.'


def sanitizer_exit(path):
    try:
        return run_python(SANITIZER, path, timeout=10).returncode
    except subprocess.TimeoutExpired:
        return None


def test_sanitizer_adversarial_corpus():
    assert os.path.isfile(SANITIZER), f'Sanitizer script {SANITIZER} does not exist.'

    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'
    clean_files = glob.glob(os.path.join(clean_dir, '*'))
    evil_files = glob.glob(os.path.join(evil_dir, '*'))

    assert len(clean_files) > 0, 'No clean files found in corpus.'
    assert len(evil_files) > 0, 'No evil files found in corpus.'

    clean_failures = [os.path.basename(p) for p in clean_files if sanitizer_exit(p) != 0]
    evil_failures = [os.path.basename(p) for p in evil_files if sanitizer_exit(p) != 1]

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")
    assert not error_messages, ' | '.join(error_messages)


def test_sanitizer_on_generated_unseen_inputs():
    assert os.path.isfile(SANITIZER), f'Sanitizer script {SANITIZER} does not exist.'
    token = secrets.token_hex(12)

    valid_objects = [
        {'timestamp': f'2026-09-11T03:00:{i:02d}Z', 'sensor_data': {'reading': i, 'token': token}}
        for i in range(8)
    ]
    valid_objects += [
        {'timestamp': '', 'sensor_data': {}},
        {'timestamp': '測定-' + token, 'sensor_data': {'ok': True, 'nested': {'values': [1, 2, None]}}},
        {'timestamp': token, 'sensor_data': {'message': 'line one\nline two', 'value': -3.5}, 'extra': 'allowed'},
    ]

    invalid_payloads = []
    invalid_payloads.extend([
        json.dumps({'sensor_data': {'token': token}}).encode(),
        json.dumps({'timestamp': token}).encode(),
        json.dumps({'timestamp': 123, 'sensor_data': {}}).encode(),
        json.dumps({'timestamp': None, 'sensor_data': {}}).encode(),
        json.dumps({'timestamp': token, 'sensor_data': []}).encode(),
        json.dumps({'timestamp': token, 'sensor_data': None}).encode(),
        json.dumps([{'timestamp': token, 'sensor_data': {}}]).encode(),
        b'{"timestamp":"' + token.encode() + b'","sensor_data":',
        b'{"timestamp":"' + token.encode() + b'","sensor_data":{}} trailing',
        b'{"timestamp":"' + token.encode() + b'","sensor_data":{"bad":NaN}}',
        b'{"timestamp":"' + token.encode() + b'","sensor_data":{"bad":Infinity}}',
        b'{"timestamp":"' + token.encode() + b'","sensor_data":{"bad":"\xff\xfe"}}',
        b'\x80{"timestamp":"' + token.encode() + b'","sensor_data":{}}',
    ])

    with tempfile.TemporaryDirectory() as td:
        cases = []
        for obj in valid_objects:
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, 'w', encoding='utf-8', newline='') as f:
                json.dump(obj, f, ensure_ascii=False, separators=(',', ':'))
            cases.append((path, 0))
        for payload in invalid_payloads:
            path = os.path.join(td, uuid.uuid4().hex)
            with open(path, 'wb') as f:
                f.write(payload)
            cases.append((path, 1))

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = sanitizer_exit(path)
            if actual != expected:
                failures.append(f'{os.path.basename(path)} expected exit {expected}, got {actual}')
        assert not failures, 'Generated sanitizer cases failed: ' + '; '.join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
