#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

JSON_PATH = '/home/user/energy_totals.json'
SOURCE_PATH = '/home/user/pipeline.go'
BINARY_PATH = '/tmp/agent_pipeline'
VIDEO_PATH = '/app/telemetry_backup.mp4'

FLOAT = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)'
LINE_RE = re.compile(
    rf'^\s*\[TELEMETRY\]\s+NODE:\s*([A-Za-z0-9]{{4}})'
    rf'\s+P:\s*({FLOAT})\s+V:\s*({FLOAT})\s+A:\s*({FLOAT})\s*$'
)


def load_output():
    assert os.path.isfile(JSON_PATH), f'Output file missing: {JSON_PATH}'
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to load JSON from {JSON_PATH}: {e}')
    assert isinstance(data, dict), 'Output JSON must be a single dictionary'
    return data


def assert_totals(actual, expected):
    assert set(actual) == set(expected), (
        f'NODE set differs: got {sorted(actual)}, expected {sorted(expected)}'
    )
    for node, wanted in expected.items():
        try:
            got = float(actual[node])
        except (TypeError, ValueError):
            pytest.fail(f'Value for {node} is not numeric: {actual[node]!r}')
        assert math.isfinite(got), f'Value for {node} is not finite'
        assert math.isclose(got, wanted, rel_tol=1e-8, abs_tol=1e-6), (
            f'Incorrect total for {node}: got {got}, expected {wanted}'
        )


def expected_from_text(text):
    totals = {}
    for line in text.splitlines():
        match = LINE_RE.fullmatch(line)
        if not match:
            continue
        node, p, v, a = match.groups()
        p, v, a = float(p), float(v), float(a)
        totals[node] = totals.get(node, 0.0) + p * (v ** 2) + math.sqrt(a)
    return totals


def run_pipeline(raw_text, timeout=45):
    try:
        os.remove(JSON_PATH)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [BINARY_PATH],
        input=raw_text,
        text=True,
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f'pipeline exited with {result.returncode}\nstdout:\n{result.stdout[-2000:]}'
        f'\nstderr:\n{result.stderr[-4000:]}'
    )
    return load_output()


def test_energy_totals_mae():
    json_path = '/home/user/energy_totals.json'
    assert os.path.isfile(json_path), f"Output file missing: {json_path}"

    try:
        with open(json_path, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to load JSON from {json_path}: {e}")

    truth = {
        "ALPH": 420.0,
        "BETA": 720.0,
        "GAMM": 820.0
    }

    mae = 0.0
    count = len(truth)

    for node, expected_val in truth.items():
        agent_val = agent_data.get(node, 0.0)
        try:
            agent_val = float(agent_val)
        except (ValueError, TypeError):
            agent_val = 0.0
        mae += abs(expected_val - agent_val)

    mae = mae / count

    assert mae <= 50.0, f"MAE is {mae}, which is greater than the threshold of 50.0"


def test_go_artifact_builds():
    assert os.path.isfile(SOURCE_PATH), f'Missing Go source: {SOURCE_PATH}'
    result = subprocess.run(
        ['go', 'build', '-o', BINARY_PATH, SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f'pipeline.go does not build:\n{result.stderr}'
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)


def test_randomized_streaming_parser_and_math():
    rng = random.Random(secrets.randbits(128))
    alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    nodes = set()
    while len(nodes) < 7:
        nodes.add(''.join(rng.choice(alphabet) for _ in range(4)))

    valid = []
    for node in nodes:
        for _ in range(rng.randint(2, 6)):
            p = rng.randint(1, 300) / 10.0
            v = rng.randint(1, 150) / 10.0
            a_root = rng.randint(1, 20)
            a = float(a_root * a_root)
            spacing = rng.choice([' ', '  ', '\t'])
            valid.append(
                f'{spacing}[TELEMETRY]{spacing}NODE:{node}{spacing}'
                f'P:{p:.1f}{spacing}V:{v:.1f}{spacing}A:{a:.1f}{spacing}'
            )

    invalid = [
        '[TELEMETRY] NODE:BAD P:1.0 V:2.0 A:4.0',
        '[TELEMETRY] NODE:TOOLONG P:1.0 V:2.0 A:4.0',
        'artifact [TELEMETRY] NODE:FAKE P:9.0 V:9.0 A:9.0',
        '[TELEMETRY] NODE:FAK2 P:9.0 V:9.0 A:9.0 trailing OCR',
        '[TELEMETRY] NODE:FAK3 P:not-a-float V:2.0 A:4.0',
        '[TELEMETRY] NODE:FAK4 P:1.0 V:2.0',
        '[TELEMETRY NODE:FAK5 P:1.0 V:2.0 A:4.0',
    ]
    records = valid + invalid
    rng.shuffle(records)

    # A large amount of irrelevant OCR text ensures the program consumes a stream
    # rather than only inspecting a small fixed prefix.
    garbage = ('unrecognizable OCR pixels !@#$%^&*()\n' * 120000)
    raw = garbage + '\n'.join(records) + '\n'
    expected = expected_from_text(raw)
    assert_totals(run_pipeline(raw), expected)


def test_real_two_fps_extraction_and_ocr_stream():
    assert os.path.isfile(VIDEO_PATH), f'Missing input video: {VIDEO_PATH}'
    with tempfile.TemporaryDirectory(prefix='telemetry_frames_') as frame_dir:
        frame_pattern = os.path.join(frame_dir, 'frame_%04d.png')
        extraction = subprocess.run(
            ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', VIDEO_PATH,
             '-vf', 'fps=2', frame_pattern],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert extraction.returncode == 0, f'2 FPS frame extraction failed: {extraction.stderr}'
        frames = sorted(glob.glob(os.path.join(frame_dir, 'frame_*.png')))
        assert len(frames) >= 55, f'Expected approximately 60 frames at 2 FPS, got {len(frames)}'

        chunks = []
        for frame in frames:
            ocr = subprocess.run(
                ['tesseract', frame, 'stdout', '--psm', '6'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=20,
            )
            assert ocr.returncode == 0, f'Tesseract failed for {frame}'
            chunks.append(ocr.stdout)

        raw_ocr = '\n'.join(chunks)
        expected = expected_from_text(raw_ocr)
        assert expected, 'OCR from the supplied video yielded no strictly valid telemetry lines'
        assert_totals(run_pipeline(raw_ocr, timeout=60), expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
