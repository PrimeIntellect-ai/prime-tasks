#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SRC_DIR = Path('/home/user/src')
EXECUTABLE = SRC_DIR / 'analyze_spectra'
RESULTS_FILE = Path('/home/user/results.h5')


def test_results_file_exists():
    """Check that the output HDF5 file was created."""
    assert RESULTS_FILE.exists(), f"The output file {RESULTS_FILE} does not exist."
    assert RESULTS_FILE.is_file(), f"{RESULTS_FILE} is not a file."


def test_executable_exists():
    """Check that the compiled executable exists."""
    assert EXECUTABLE.exists(), f"The executable {EXECUTABLE} does not exist."
    assert EXECUTABLE.is_file(), f"{EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with EXECUTABLE.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f"{EXECUTABLE} is not a compiled ELF executable."


def test_build_files_rebuild_and_execute_pipeline():
    """Rebuild from the supplied C++ project and require the binary to regenerate results."""
    cmake_file = SRC_DIR / 'CMakeLists.txt'
    make_file = SRC_DIR / 'Makefile'
    assert cmake_file.is_file() or make_file.is_file(), \
        "Neither /home/user/src/CMakeLists.txt nor /home/user/src/Makefile exists."

    cpp_sources = []
    for pattern in ('*.cpp', '*.cc', '*.cxx', '*.C'):
        cpp_sources.extend(SRC_DIR.rglob(pattern))
    assert any(p.is_file() for p in cpp_sources), "No C++ source file was supplied in /home/user/src."

    # The pre-existing executable was checked above. Remove it so the supplied build
    # files must actually recreate the program used for verification.
    EXECUTABLE.unlink()

    if cmake_file.is_file():
        build_dir = Path('/tmp/verifier-cmake-build')
        shutil.rmtree(build_dir, ignore_errors=True)
        configure = subprocess.run(
            ['cmake', '-S', str(SRC_DIR), '-B', str(build_dir)],
            capture_output=True, text=True, timeout=120
        )
        assert configure.returncode == 0, \
            f"CMake configuration failed.\nSTDOUT: {configure.stdout}\nSTDERR: {configure.stderr}"
        build = subprocess.run(
            ['cmake', '--build', str(build_dir), '--parallel', '2'],
            capture_output=True, text=True, timeout=240
        )
        assert build.returncode == 0, \
            f"CMake build failed.\nSTDOUT: {build.stdout}\nSTDERR: {build.stderr}"

        if not EXECUTABLE.is_file():
            candidates = [p for p in build_dir.rglob('analyze_spectra')
                          if p.is_file() and os.access(p, os.X_OK)]
            assert candidates, "CMake did not build an executable named analyze_spectra."
            shutil.copy2(candidates[0], EXECUTABLE)
            EXECUTABLE.chmod(EXECUTABLE.stat().st_mode | 0o111)
    else:
        build = subprocess.run(
            ['make', '-C', str(SRC_DIR)],
            capture_output=True, text=True, timeout=240
        )
        assert build.returncode == 0, \
            f"Make build failed.\nSTDOUT: {build.stdout}\nSTDERR: {build.stderr}"

    assert EXECUTABLE.is_file(), "The supplied build files did not create /home/user/src/analyze_spectra."
    assert os.access(EXECUTABLE, os.X_OK), "The rebuilt analyze_spectra is not executable."
    with EXECUTABLE.open('rb') as f:
        assert f.read(4) == b'\x7fELF', "The rebuilt analyze_spectra is not a compiled ELF executable."

    # Discard the agent's existing output and require the rebuilt artifact itself to
    # produce a fresh results file from sequences.h5.
    if RESULTS_FILE.exists():
        RESULTS_FILE.unlink()
    run = subprocess.run(
        [str(EXECUTABLE)], cwd=str(SRC_DIR), capture_output=True, text=True, timeout=120
    )
    assert run.returncode == 0, \
        f"analyze_spectra failed.\nSTDOUT: {run.stdout}\nSTDERR: {run.stderr}"
    assert RESULTS_FILE.is_file(), "analyze_spectra did not generate /home/user/results.h5."


def test_results_contents():
    """Verify the regenerated HDF5 datasets against independently computed results."""
    script = r'''
import h5py
import numpy as np
from scipy.fft import fft
import sys

try:
    with h5py.File('/home/user/sequences.h5', 'r') as f:
        if '/dna_signals' not in f:
            print('Missing /dna_signals in sequences.h5')
            sys.exit(1)
        signals = f['/dna_signals'][:]

    N, M = signals.shape
    mag_spectra = np.zeros_like(signals)
    for i in range(N):
        mag_spectra[i] = np.abs(fft(signals[i]))

    U, S, Vh = np.linalg.svd(mag_spectra, full_matrices=False)
    expected_s = S
    expected_v1 = Vh[0, :]

    with h5py.File('/home/user/results.h5', 'r') as f:
        if '/singular_values' not in f:
            print('Missing /singular_values in results.h5')
            sys.exit(1)
        if '/principal_spectrum' not in f:
            print('Missing /principal_spectrum in results.h5')
            sys.exit(1)

        s_ds = f['/singular_values']
        v_ds = f['/principal_spectrum']
        if s_ds.shape != (10,) or v_ds.shape != (1024,):
            print(f'Incorrect dataset shapes: {s_ds.shape}, {v_ds.shape}')
            sys.exit(1)
        if s_ds.dtype != np.dtype('float64') or v_ds.dtype != np.dtype('float64'):
            print(f'Incorrect dataset dtypes: {s_ds.dtype}, {v_ds.dtype}')
            sys.exit(1)
        agent_s = s_ds[:]
        agent_v1 = v_ds[:]

    if not np.allclose(expected_s, agent_s, rtol=1e-3, atol=1e-3):
        print(f'Singular values mismatch. Expected: {expected_s}, Got: {agent_s}')
        sys.exit(1)

    sign_flip = 1.0
    if np.sign(agent_v1[0]) != np.sign(expected_v1[0]) and agent_v1[0] != 0:
        sign_flip = -1.0

    if not np.allclose(expected_v1, agent_v1 * sign_flip, rtol=1e-3, atol=1e-3):
        print('Principal spectrum mismatch.')
        sys.exit(1)

    sys.exit(0)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
'''
    result = subprocess.run([sys.executable, '-c', script], capture_output=True, text=True)
    assert result.returncode == 0, \
        f"Verification script failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
