#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim

PIPELINE = '/home/user/data_pipeline/process.sh'
OUTPUT = '/home/user/final_output.png'
REGRESSION = '/home/user/test_regression.sh'


def expected_height(width):
    return int((width * 0.65) + 22.5)


def assert_correct_image(path, width):
    assert os.path.isfile(path), f'Output {path} not found.'
    image = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    assert image is not None, f'Failed to read {path}'

    expected = np.zeros((expected_height(width), 100), dtype=np.uint8)
    assert image.shape == expected.shape, (
        f'Incorrect output dimensions: got {image.shape}, expected {expected.shape}'
    )
    score, _ = ssim(image, expected, full=True)
    assert score >= 0.98, f'SSIM score {score:.4f} is below the threshold of 0.98'


def run_pipeline(width):
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.dat', delete=False) as f:
        f.write(f'WIDTH={width}\n')
        f.write('LABEL=café\n')
        input_path = f.name

    try:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = subprocess.run(
            [PIPELINE, input_path],
            cwd='/home/user/data_pipeline',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f'Pipeline failed for WIDTH={width}: stdout={result.stdout!r}, '
            f'stderr={result.stderr!r}'
        )
        assert 'invalid byte sequence' not in result.stderr.lower()
        assert_correct_image(OUTPUT, width)

        encoded_cfg = '/home/user/data_pipeline/temp_enc.cfg'
        assert os.path.isfile(encoded_cfg), 'Pipeline did not create temp_enc.cfg'
        data = open(encoded_cfg, 'rb').read()
        assert b'\x00' not in data, 'Intermediate config contains UTF-16-style NUL bytes'
        decoded = data.decode('utf-8')
        assert f'WIDTH={width}' in decoded
        assert 'LABEL=café' in decoded
    finally:
        os.unlink(input_path)


def test_final_output_ssim():
    assert os.path.isfile(OUTPUT), f'Student output {OUTPUT} not found.'
    assert_correct_image(OUTPUT, 100)


def test_pipeline_formula_and_encoding():
    assert os.path.isfile(PIPELINE), f'Pipeline script {PIPELINE} not found.'
    assert os.access(PIPELINE, os.X_OK), f'Pipeline script {PIPELINE} is not executable.'
    for width in (37, 143, 218):
        run_pipeline(width)


def test_regression_script_exists_and_runs():
    assert os.path.isfile(REGRESSION), f'Regression test script {REGRESSION} not found.'
    assert os.access(REGRESSION, os.X_OK), f'Regression test script {REGRESSION} is not executable.'

    width = 131
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.dat', delete=False) as f:
        f.write(f'WIDTH={width}\n')
        valid_input = f.name
    try:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = subprocess.run(
            [REGRESSION, valid_input],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f'Regression script rejected valid input: stdout={result.stdout!r}, '
            f'stderr={result.stderr!r}'
        )
        assert_correct_image(OUTPUT, width)
    finally:
        os.unlink(valid_input)

    missing_input = '/tmp/verifier-definitely-missing-input.dat'
    if os.path.exists(missing_input):
        os.remove(missing_input)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [REGRESSION, missing_input],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode != 0, 'Regression script accepted a nonexistent input file'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
