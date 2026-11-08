#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import h5py
import numpy as np
import pytest

HOME = '/home/user'
SIGNAL = os.path.join(HOME, 'signal.h5')
RESULT = os.path.join(HOME, 'result.txt')


def test_result_file_exists():
    result_file = '/home/user/result.txt'
    assert os.path.exists(result_file), f"The result file {result_file} does not exist."
    assert os.path.isfile(result_file), f"{result_file} is not a valid file."


def test_result_value():
    result_file = '/home/user/result.txt'
    with open(result_file, 'r') as f:
        content = f.read().strip()

    assert content == "12", f"Expected dominant frequency to be 12, but got '{content}'."


def files_under_home():
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for name in files:
            yield os.path.join(root, name)


def find_cpp_sources():
    sources = []
    for path in files_under_home():
        try:
            if os.path.getsize(path) > 2_000_000:
                continue
            with open(path, 'rb') as f:
                data = f.read()
            if data.startswith(b'\x7fELF') or b'\x00' in data:
                continue
            text = data.decode('utf-8', errors='ignore').lower()
            if ('#include' in text and 'fftw' in text and
                    ('hdf5' in text or 'h5cpp' in text or 'h5fopen' in text)):
                sources.append(path)
        except OSError:
            pass
    return sources


def find_executables():
    executables = []
    for path in files_under_home():
        try:
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            with open(path, 'rb') as f:
                if f.read(4) != b'\x7fELF':
                    continue
            linked = subprocess.run(
                ['ldd', path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, timeout=5, check=False).stdout.lower()
            if 'fftw3' in linked and 'hdf5' in linked:
                executables.append(path)
        except (OSError, subprocess.SubprocessError):
            pass
    return executables


def prescribed_answer(voltage):
    derivative = np.empty(1024, dtype=np.float64)
    dt = 1.0 / 1024.0
    derivative[0] = (voltage[1] - voltage[0]) / dt
    derivative[-1] = (voltage[-1] - voltage[-2]) / dt
    derivative[1:-1] = (voltage[2:] - voltage[:-2]) / (2.0 * dt)
    magnitudes = np.abs(np.fft.rfft(derivative))
    return int(np.argmax(magnitudes[:512]))


def make_hidden_cases(original):
    rng = secrets.SystemRandom()
    t = np.arange(1024, dtype=np.float64) / 1024.0
    cases = [(original.copy(), prescribed_answer(original))]

    for mode in range(4):
        low = rng.randrange(4, 20)
        high = rng.randrange(45, 181)
        while high == low:
            high = rng.randrange(45, 181)
        p1 = rng.random() * 2.0 * np.pi
        p2 = rng.random() * 2.0 * np.pi
        if mode % 2 == 0:
            low_amp, high_amp = 2.0, 1.0
        else:
            low_amp, high_amp = 12.0, 0.2
        voltage = (low_amp * np.sin(2.0 * np.pi * low * t + p1) +
                   high_amp * np.sin(2.0 * np.pi * high * t + p2))
        voltage = np.asarray(voltage, dtype=np.float64)
        cases.append((voltage, prescribed_answer(voltage)))
    return cases


def run_candidate(candidate, cases):
    for voltage, expected in cases:
        with h5py.File(SIGNAL, 'w') as f:
            f.create_dataset('/voltage', data=voltage, dtype='float64')
        try:
            os.remove(RESULT)
        except FileNotFoundError:
            pass

        completed = subprocess.run(
            [candidate], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=15, check=False)
        if completed.returncode != 0 or not os.path.isfile(RESULT):
            return False
        try:
            with open(RESULT, 'r', encoding='utf-8') as f:
                output = f.read()
        except (OSError, UnicodeError):
            return False
        if re.fullmatch(r'\s*[+-]?\d+\s*', output) is None:
            return False
        if int(output.strip()) != expected:
            return False
    return True


def test_cpp_program_is_present_and_processes_hidden_inputs():
    sources = find_cpp_sources()
    assert sources, 'No C++ source using both HDF5 and FFTW3 was found under /home/user.'

    executables = find_executables()
    assert executables, 'No executable ELF program linked to both HDF5 and FFTW3 was found.'

    with open(SIGNAL, 'rb') as f:
        original_signal_bytes = f.read()
    with h5py.File(SIGNAL, 'r') as f:
        original = np.asarray(f['/voltage'][:], dtype=np.float64)
    assert original.shape == (1024,)

    result_existed = os.path.isfile(RESULT)
    original_result_bytes = None
    if result_existed:
        with open(RESULT, 'rb') as f:
            original_result_bytes = f.read()

    cases = make_hidden_cases(original)
    try:
        assert any(run_candidate(candidate, cases) for candidate in executables), (
            'No submitted C++ executable produced the derived dominant frequencies '
            'for the original and hidden HDF5 signals.')
    finally:
        with open(SIGNAL, 'wb') as f:
            f.write(original_signal_bytes)
        if result_existed:
            with open(RESULT, 'wb') as f:
                f.write(original_result_bytes)
        else:
            try:
                os.remove(RESULT)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
