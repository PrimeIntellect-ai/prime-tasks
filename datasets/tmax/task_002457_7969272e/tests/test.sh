#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import wave

import numpy as np
from scipy.io import wavfile
from scipy.stats import wasserstein_distance

SOURCE = '/home/user/src/wav_extract.c'
EXECUTABLE = '/home/user/bin/wav_extract'
SCRIPT = '/home/user/analyze_noise.sh'
SIGNAL = '/app/signal.wav'
OUTPUT = '/home/user/distance.txt'


def compute_reference(path=SIGNAL):
    sample_rate, data = wavfile.read(path)
    if len(data.shape) > 1:
        data = data[:, 0]
    normalized_data = data.astype(np.float32) / 32768.0
    np.random.seed(42)
    ideal_samples = np.random.normal(0, 0.1, len(normalized_data))
    return wasserstein_distance(normalized_data, ideal_samples)


def make_wav(path, samples):
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(44100)
        f.writeframes(np.asarray(samples, dtype='<i2').tobytes())


def check_extractor(path):
    samples = np.array([-32768, -16384, -1, 0, 1, 16384, 32767], dtype=np.int16)
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        wav_path = tmp.name
    try:
        make_wav(wav_path, samples)
        result = subprocess.run([path, wav_path], text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, f'{path} failed: {result.stderr}'
        lines = result.stdout.splitlines()
        assert len(lines) == len(samples), f'{path} emitted {len(lines)} samples, expected {len(samples)}.'
        try:
            values = np.array([float(line) for line in lines])
        except ValueError as exc:
            raise AssertionError(f'{path} emitted non-numeric sample data.') from exc
        expected = samples.astype(np.float64) / 32768.0
        assert np.allclose(values, expected, rtol=0, atol=5.1e-7), f'{path} did not normalize 16-bit samples correctly.'
    finally:
        os.unlink(wav_path)


def read_distance():
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} is missing.'
    with open(OUTPUT, 'r') as f:
        content = f.read().strip()
    assert re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', content), \
        f'Content of {OUTPUT} is not only a valid floating-point number: {content!r}'
    value = float(content)
    assert math.isfinite(value), f'Content of {OUTPUT} must be finite.'
    return value


def test_c_source_exists():
    assert os.path.isfile(SOURCE), 'C source file /home/user/src/wav_extract.c is missing.'
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'wav_extract')
        result = subprocess.run(['gcc', SOURCE, '-o', rebuilt], text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, f'C source does not compile: {result.stderr}'
        check_extractor(rebuilt)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), 'Executable /home/user/bin/wav_extract is missing.'
    assert os.access(EXECUTABLE, os.X_OK), '/home/user/bin/wav_extract is not executable.'
    check_extractor(EXECUTABLE)


def test_bash_script_exists():
    assert os.path.isfile(SCRIPT), 'Bash script /home/user/analyze_noise.sh is missing.'
    assert os.access(SCRIPT, os.X_OK), '/home/user/analyze_noise.sh is not executable.'
    with open(SCRIPT, 'r', errors='replace') as f:
        script_text = f.read()
    assert '/home/user/bin/wav_extract' in script_text, 'The pipeline does not reference the required extraction tool.'
    assert re.search(r'python', script_text, re.IGNORECASE), 'The pipeline does not invoke a Python snippet.'


def test_distance_output():
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} is missing.'

    with open(SIGNAL, 'rb') as f:
        original_signal = f.read()

    saved_executable = tempfile.mktemp(prefix='wav_extract_original_')
    invocation_log = tempfile.mktemp(prefix='wav_extract_invocations_')
    shutil.move(EXECUTABLE, saved_executable)
    wrapper = '#!/bin/sh\necho invoked >> {log}\nexec {real} "$@"\n'.format(
        log=shlex.quote(invocation_log), real=shlex.quote(saved_executable))
    with open(EXECUTABLE, 'w') as f:
        f.write(wrapper)
    os.chmod(EXECUTABLE, 0o755)

    n = 88200
    cases = [
        np.zeros(n, dtype=np.int16),
        np.resize(np.array([-6554, 6554], dtype=np.int16), n),
        None,
    ]

    try:
        for samples in cases:
            if samples is None:
                with open(SIGNAL, 'wb') as f:
                    f.write(original_signal)
            else:
                make_wav(SIGNAL, samples)

            if os.path.exists(invocation_log):
                os.unlink(invocation_log)
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)

            result = subprocess.run([SCRIPT], text=True, capture_output=True, timeout=120)
            assert result.returncode == 0, f'Pipeline failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
            assert os.path.isfile(invocation_log) and os.path.getsize(invocation_log) > 0, \
                'The pipeline did not run /home/user/bin/wav_extract.'

            agent_val = read_distance()
            ref_val = compute_reference()
            error = abs(agent_val - ref_val)
            assert error <= 0.001, \
                f'Predicted distance {agent_val} differs from reference {ref_val} by {error}, which is > 0.001 threshold.'
    finally:
        with open(SIGNAL, 'wb') as f:
            f.write(original_signal)
        if os.path.exists(EXECUTABLE):
            os.unlink(EXECUTABLE)
        shutil.move(saved_executable, EXECUTABLE)
        os.chmod(EXECUTABLE, 0o755)
        if os.path.exists(invocation_log):
            os.unlink(invocation_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
