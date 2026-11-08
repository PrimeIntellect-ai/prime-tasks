#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import math
import os
import re
import struct
import subprocess
import wave
import pytest

APP = '/app'


def extract_key():
    data = open('/app/memory.core', 'rb').read()
    matches = re.findall(rb'CALIB_KEY=([!-~]{16})(?![!-~])', data)
    assert len(matches) == 1, 'Could not uniquely extract the 16-character calibration key from memory.core.'
    return matches[0].decode('ascii')


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=20, **kwargs)


def test_executable_was_compiled_from_repaired_source_and_runs():
    source = '/app/nlms_filter.c'
    executable = '/app/nlms_filter'
    assert os.path.isfile(source), 'nlms_filter.c is missing.'
    assert os.path.isfile(executable), 'The compiled /app/nlms_filter executable is missing.'
    assert os.access(executable, os.X_OK), '/app/nlms_filter is not executable.'

    rebuilt = '/tmp/nlms_filter_rebuilt'
    result = run(['gcc', '-O2', source, '-o', rebuilt])
    assert result.returncode == 0, f'nlms_filter.c does not compile with gcc -O2:\n{result.stderr}'

    submitted_hash = hashlib.sha256(open(executable, 'rb').read()).digest()
    rebuilt_hash = hashlib.sha256(open(rebuilt, 'rb').read()).digest()
    assert submitted_hash == rebuilt_hash, (
        '/app/nlms_filter is not the gcc -O2 build of the submitted nlms_filter.c.'
    )

    if os.path.exists('/app/output.wav'):
        os.remove('/app/output.wav')
    result = run([executable, '/app/input.wav', '/app/output.wav', extract_key()])
    assert result.returncode == 0, f'The filter failed when run as instructed:\n{result.stderr}'


def make_probe(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(struct.pack(f'<{len(samples)}h', *samples))


def f32(value):
    return ctypes.c_float(value).value


def expected_nlms(samples):
    mu = f32(0.5)
    weight = f32(0.25)
    expected = []
    for sample in samples:
        x = f32(f32(sample) / f32(32768.0))
        y = f32(weight * x)
        error = f32(-y)
        numerator = f32(f32(mu * error) * x)
        denominator = f32(f32(x * x) + f32(1e-6))
        weight = f32(weight + f32(numerator / denominator))
        out_value = f32(error * f32(32768.0))
        out_value = min(32767.0, max(-32768.0, out_value))
        expected.append(int(out_value))
    return expected


def test_boundary_fix_and_nlms_rule_are_exercised():
    source_path = '/app/nlms_filter.c'
    source = open(source_path, 'r', encoding='utf-8').read()
    pattern = r'(float\s+w\s*=\s*)0\.0f?\s*;'
    instrumented, count = re.subn(pattern, r'\g<1>0.25f;', source, count=1)
    assert count == 1, 'Could not locate the adaptive weight initialization in nlms_filter.c.'

    instrumented_path = '/tmp/nlms_probe.c'
    with open(instrumented_path, 'w', encoding='utf-8') as f:
        f.write(instrumented)

    probe_exe = '/tmp/nlms_probe'
    result = run(['gcc', '-O1', '-fsanitize=address', '-fno-omit-frame-pointer',
                  instrumented_path, '-o', probe_exe])
    assert result.returncode == 0, f'Instrumented source did not compile:\n{result.stderr}'

    samples = [12000, -7000, 20000, -16000, 3000, 25000, -11000, 8000] * 32
    probe_in = '/tmp/probe_input.wav'
    probe_out = '/tmp/probe_output.wav'
    make_probe(probe_in, samples)

    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
    result = run([probe_exe, probe_in, probe_out, extract_key()], env=env)
    assert result.returncode == 0, (
        'The repaired source failed the boundary-safety probe (for example, an '
        f'off-by-one access remains):\n{result.stderr}'
    )

    with wave.open(probe_out, 'rb') as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        assert w.getnframes() == len(samples), 'The filter wrote the wrong number of samples.'
        actual = list(struct.unpack(f'<{len(samples)}h', w.readframes(len(samples))))

    expected = expected_nlms(samples)
    differences = [abs(a - e) for a, e in zip(actual, expected)]
    assert max(differences) <= 5, (
        'The adaptive weight update does not behave as NLMS normalized by '
        '(x * x + 1e-6).'
    )
    assert any(actual), 'The behavioral probe unexpectedly produced fabricated silence.'


def test_output_wav_exists():
    assert os.path.isfile('/app/output.wav'), "The output file '/app/output.wav' was not generated."


def test_output_wav_rms_convergence():
    wav_path = '/app/output.wav'
    assert os.path.isfile(wav_path), f"Cannot calculate RMS because {wav_path} does not exist."

    with wave.open(wav_path, 'rb') as w:
        n_frames = w.getnframes()
        assert n_frames > 0, "The output.wav file is empty."

        frames = w.readframes(n_frames)
        samples = struct.unpack(f'<{n_frames}h', frames)

        sq_sum = sum(s * s for s in samples)
        rms = math.sqrt(sq_sum / len(samples))

    threshold = 15000
    assert rms < threshold, (
        f"The filter failed to converge properly. "
        f"Expected RMS < {threshold}, but got {rms:.2f}. "
        f"This indicates the NLMS update rule was not implemented correctly."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
