#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pathlib
import re
import signal
import subprocess
import tempfile

import pytest
import requests
from PIL import Image
from scipy.optimize import curve_fit

SEARCH_ROOTS = [pathlib.Path('/app'), pathlib.Path('/home/user'), pathlib.Path('/workspace')]


def project_sources():
    files = []
    for root in SEARCH_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob('*'):
            try:
                if (path.is_file() and path.stat().st_size <= 2_000_000
                        and path.suffix.lower() not in {'.mp4', '.png', '.jpg', '.jpeg', '.pyc'}):
                    text = path.read_text(errors='ignore')
                    files.append((path, text))
            except (OSError, UnicodeError):
                pass
    return files


def test_required_processing_and_fitting_scripts_exist_and_processing_script_runs():
    sources = project_sources()
    shell_candidates = []
    for path, text in sources:
        is_shell = path.suffix == '.sh' or text.startswith('#!/bin/bash') or text.startswith('#!/usr/bin/env bash')
        uses_parallel = re.search(r'\bparallel\b', text) or re.search(r'\bxargs\b[^\n]*\s-P(?:\s*\d+)?', text)
        handles_frames = re.search(r'frame|png|jpe?g|ffmpeg', text, re.I)
        if is_shell and uses_parallel and handles_frames:
            shell_candidates.append(path)

    assert shell_candidates, 'No Bash frame-analysis script using GNU parallel or xargs -P was found'

    combined = '\n'.join(text for _, text in sources)
    assert re.search(r'grayscale|convert\s*\(?.*["\']L["\']|cvtColor|gray', combined, re.I | re.S), \
        'No grayscale density calculation was found in the submitted processing code'
    assert re.search(r'>\s*128|threshold\s*[:=]?\s*128|-threshold\s+128', combined, re.I), \
        'Processing code does not implement the required strict intensity threshold of 128'

    fit_sources = []
    for path, text in sources:
        if (path.suffix == '.py' or 'python' in text[:100].lower()):
            if all(re.search(rf'\b{name}\b', text) for name in ('K', 'D0', 'r')) and re.search(r'\bexp\s*\(', text):
                fit_sources.append(path)
    assert fit_sources, 'No script implementing the K, D0, r logistic model was found'

    # The required parallel-processing artifact must be a runnable script, not merely
    # text containing the requested keywords. Try candidates until one completes.
    errors = []
    ran = False
    for script in shell_candidates:
        syntax = subprocess.run(['bash', '-n', str(script)], capture_output=True, text=True)
        if syntax.returncode != 0:
            errors.append(f'{script}: syntax error: {syntax.stderr[-300:]}')
            continue
        try:
            result = subprocess.run(
                ['bash', str(script)], cwd=str(script.parent),
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                text=True, timeout=180, start_new_session=True,
            )
            if result.returncode == 0:
                ran = True
                break
            errors.append(f'{script}: exit {result.returncode}: {result.stderr[-300:]}')
        except subprocess.TimeoutExpired:
            errors.append(f'{script}: timed out')
    assert ran, 'No parallel frame-analysis script ran successfully. ' + ' | '.join(errors)


def independently_fit_video():
    video = pathlib.Path('/app/bacteria_growth.mp4')
    assert video.is_file(), f'Missing input video: {video}'
    with tempfile.TemporaryDirectory() as td:
        pattern = os.path.join(td, 'frame_%06d.png')
        proc = subprocess.run(
            ['ffmpeg', '-v', 'error', '-i', str(video), '-vsync', '0', pattern],
            capture_output=True, text=True, timeout=120,
        )
        assert proc.returncode == 0, f'Could not decode input video: {proc.stderr}'
        frames = sorted(pathlib.Path(td).glob('frame_*.png'))
        assert len(frames) == 50, f'Expected 50 decoded frames, got {len(frames)}'
        densities = []
        for frame in frames:
            image = Image.open(frame).convert('L')
            pixels = list(image.getdata())
            densities.append(sum(value > 128 for value in pixels) / len(pixels))

    def logistic(t, K, D0, r):
        import numpy as np
        return K / (1.0 + ((K - D0) / D0) * np.exp(-r * t))

    import numpy as np
    times = np.arange(len(densities), dtype=float)
    params, _ = curve_fit(
        logistic, times, np.asarray(densities), p0=(0.8, densities[0], 0.15),
        bounds=([0.0, 1e-9, 0.0], [1.0, 1.0, 10.0]), maxfev=100000,
    )
    return tuple(float(x) for x in params)


def test_api_response_and_parameters():
    expected_K, expected_D0, expected_r = independently_fit_video()
    url = 'http://127.0.0.1:8080/model'
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f'Failed to connect to the API at {url} or make a request: {e}')

    assert response.status_code == 200, f'Expected HTTP status code 200, but got {response.status_code}'

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response body is not valid JSON. Response text: {response.text}')

    for key in ['K', 'D0', 'r']:
        assert key in data, f"Key '{key}' is missing from the JSON response"
    assert set(data) == {'K', 'D0', 'r'}, f'JSON payload has unexpected keys: {set(data)}'

    K = data['K']
    D0 = data['D0']
    r = data['r']

    assert isinstance(K, (int, float)), f'K must be a number, got {type(K)}'
    assert isinstance(D0, (int, float)), f'D0 must be a number, got {type(D0)}'
    assert isinstance(r, (int, float)), f'r must be a number, got {type(r)}'
    assert all(math.isfinite(float(x)) for x in (K, D0, r)), 'Model parameters must be finite'

    # Preserve the original assertions.
    assert 0.76 <= K <= 0.84, f'K value {K} is out of expected range [0.76, 0.84]'
    assert 0.04 <= D0 <= 0.06, f'D0 value {D0} is out of expected range [0.04, 0.06]'
    assert 0.13 <= r <= 0.17, f'r value {r} is out of expected range [0.13, 0.17]'

    # Compare the served model with a fit independently derived from the actual video.
    assert abs(float(K) - expected_K) <= 0.01, f'K={K} disagrees with video-derived fit {expected_K}'
    assert abs(float(D0) - expected_D0) <= 0.003, f'D0={D0} disagrees with video-derived fit {expected_D0}'
    assert abs(float(r) - expected_r) <= 0.005, f'r={r} disagrees with video-derived fit {expected_r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
