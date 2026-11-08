#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import subprocess

import numpy as np
import pytest
from scipy.io import wavfile

SCRIPT_PATH = '/home/user/normalize.py'
INPUT_PATH = '/app/input.wav'
OUTPUT_PATH = '/home/user/processed/output.wav'
EMAIL_PATH = '/home/user/reports/success.eml'
EXPECTED_SUBJECT = 'Subject: Audio Processed'


def calculate_peak_dbfs(filepath):
    samplerate, data = wavfile.read(filepath)
    # Convert to float
    if data.dtype == np.int16:
        data = data.astype(np.float32) / 32768.0
    elif data.dtype == np.int32:
        data = data.astype(np.float32) / 2147483648.0

    peak_amplitude = np.max(np.abs(data))
    if peak_amplitude == 0:
        return -float('inf')
    peak_dbfs = 20 * np.log10(peak_amplitude)
    return peak_dbfs


def as_float(data):
    if np.issubdtype(data.dtype, np.floating):
        return data.astype(np.float64)
    if data.dtype == np.uint8:
        return (data.astype(np.float64) - 128.0) / 128.0
    if np.issubdtype(data.dtype, np.signedinteger):
        return data.astype(np.float64) / float(2 ** (data.dtype.itemsize * 8 - 1))
    raise AssertionError(f'Unsupported WAV sample type: {data.dtype}')


def run_script():
    return subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def remove_generated_files():
    for path in (OUTPUT_PATH, EMAIL_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


@pytest.fixture(scope='session', autouse=True)
def verify_script_execution_and_error_handling():
    assert os.path.isfile(SCRIPT_PATH), f'Normalization script does not exist: {SCRIPT_PATH}'
    assert not os.path.islink(SCRIPT_PATH), 'normalize.py must be a regular script, not a symlink'
    py_compile.compile(SCRIPT_PATH, doraise=True)
    assert os.path.isdir('/home/user/processed'), 'Processed directory does not exist'
    assert os.path.isdir('/home/user/reports'), 'Reports directory does not exist'

    with open(INPUT_PATH, 'rb') as f:
        original_input = f.read()

    final_result = None
    try:
        # Use verifier-generated audio so a pre-fabricated output cannot pass.
        rng = np.random.default_rng()
        generated = rng.integers(-7000, 7001, size=8192, dtype=np.int16)
        generated[0] = 8000
        generated[1] = -7901
        wavfile.write(INPUT_PATH, 32000, generated)
        remove_generated_files()

        result = run_script()
        assert result.returncode == 0, (
            f'normalize.py failed on valid input. stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert os.path.isfile(OUTPUT_PATH), 'Script did not generate output.wav'
        assert os.path.isfile(EMAIL_PATH), 'Script did not generate success.eml'

        out_rate, output = wavfile.read(OUTPUT_PATH)
        assert out_rate == 32000, 'Output WAV did not preserve the generated input sample rate'
        assert output.shape == generated.shape, 'Output WAV did not preserve the input audio shape'
        assert abs(calculate_peak_dbfs(OUTPUT_PATH) - (-3.0)) <= 0.1

        input_float = as_float(generated)
        output_float = as_float(output)
        correlation = np.corrcoef(input_float.ravel(), output_float.ravel())[0, 1]
        assert np.isfinite(correlation) and correlation >= 0.999, (
            'Output audio does not match a normalized version of /app/input.wav'
        )

        with open(EMAIL_PATH, 'r') as f:
            email_content = f.read()
        assert email_content.strip() == EXPECTED_SUBJECT, (
            f'success.eml must contain exactly the required subject line; found {email_content!r}'
        )

        # A missing input must be handled as an error and must not report success.
        os.remove(INPUT_PATH)
        remove_generated_files()
        error_result = run_script()
        assert error_result.returncode != 0, 'Script reported success when /app/input.wav was missing'
        assert not os.path.exists(EMAIL_PATH), 'Script generated a success email after an input error'
        assert not os.path.exists(OUTPUT_PATH), 'Script generated output.wav after an input error'
        assert 'Traceback (most recent call last)' not in error_result.stderr, (
            'Missing-input failure was not handled robustly by the script'
        )
    finally:
        with open(INPUT_PATH, 'wb') as f:
            f.write(original_input)
        remove_generated_files()
        final_result = run_script()

    assert final_result.returncode == 0, (
        f'normalize.py failed on /app/input.wav. '
        f'stdout={final_result.stdout!r}, stderr={final_result.stderr!r}'
    )


def test_output_wav_peak_dbfs():
    output_path = '/home/user/processed/output.wav'
    assert os.path.exists(output_path), f"Output file does not exist: {output_path}"

    actual_dbfs = calculate_peak_dbfs(output_path)
    target_dbfs = -3.0
    metric_value = abs(actual_dbfs - target_dbfs)

    assert metric_value <= 0.1, (
        f"Peak dBFS is {actual_dbfs:.2f}, expected {target_dbfs}. "
        f"Difference {metric_value:.2f} is greater than tolerance 0.1."
    )


def test_success_eml():
    eml_path = '/home/user/reports/success.eml'
    assert os.path.exists(eml_path), f"Success email file does not exist: {eml_path}"

    with open(eml_path, 'r') as f:
        content = f.read()

    assert 'Subject: Audio Processed' in content, "Success email does not contain 'Subject: Audio Processed'."
    assert content.strip() == 'Subject: Audio Processed', (
        f"Success email must contain exactly the required subject line. Found: {content!r}"
    )


def test_virtual_fstab():
    fstab_path = '/home/user/virtual_fstab'
    assert os.path.exists(fstab_path), f"Virtual fstab file does not exist: {fstab_path}"

    with open(fstab_path, 'r') as f:
        content = f.read().strip()

    expected_line = 'none /home/user/reports tmpfs defaults 0 0'
    assert expected_line in content, f"Virtual fstab does not contain the expected line. Found: {content}"
    assert content == expected_line, f"Virtual fstab must contain exactly the expected line. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
