#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import h5py
import numpy as np
import pytest
import requests

N = 10000
DT = 0.001
SOURCE = Path('/home/user/sim.c')
EXECUTABLE = Path('/home/user/run_sim')


def expected_signal(f0, decay):
    return np.array([
        math.exp(-decay * (i * DT)) * math.sin(2 * math.pi * f0 * (i * DT))
        for i in range(N)
    ], dtype=np.float64)


def run_and_check(executable, f0, decay, threads, workdir):
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = str(threads)
    env['OMP_DYNAMIC'] = 'FALSE'
    env['OMP_SCHEDULE'] = 'dynamic,1'
    result = subprocess.run(
        [str(executable), repr(f0), repr(decay)],
        cwd=workdir,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    match = re.search(r'Energy\s*:\s*([-+0-9.eE]+)', result.stdout)
    assert match, f'Executable did not print an Energy value: {result.stdout!r}'

    h5_path = Path(workdir) / 'signal.h5'
    assert h5_path.is_file(), 'Running the simulation did not generate signal.h5'
    with h5py.File(h5_path, 'r') as h5:
        assert 'signal' in h5, "signal.h5 has no 'signal' dataset"
        values = np.asarray(h5['signal'][:])
    assert values.shape == (N,), f'Expected 10000 signal samples, got {values.shape}'

    expected = expected_signal(f0, decay)
    assert np.allclose(values, expected, rtol=2e-13, atol=2e-13), 'Generated signal is incorrect'
    return match.group(1), values


def test_simulation_artifacts_and_reproducibility():
    assert SOURCE.is_file(), '/home/user/sim.c is missing'
    assert EXECUTABLE.is_file(), '/home/user/run_sim is missing'
    assert os.access(EXECUTABLE, os.X_OK), '/home/user/run_sim is not executable'
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', '/home/user/run_sim is not a compiled executable'

    source_text = SOURCE.read_text(errors='replace')
    # Build an instrumented copy that prints enough digits to reveal changes in
    # floating-point accumulation order, even if the submitted program uses %f.
    lines = source_text.splitlines(True)
    changed = False
    for i, line in enumerate(lines):
        if 'printf' in line and 'Energy' in line:
            new_line = re.sub(r'%(?!%)[-+ #0]*\d*(?:\.\d+)?[fFeEgG]', '%.17g', line)
            changed = changed or new_line != line
            lines[i] = new_line
    assert any('printf' in line and 'Energy' in line for line in lines), 'sim.c does not print its computed energy'

    with tempfile.TemporaryDirectory() as build_dir:
        instrumented_source = Path(build_dir) / 'sim_instrumented.c'
        instrumented_binary = Path(build_dir) / 'sim_instrumented'
        instrumented_source.write_text(''.join(lines))
        compiler = shutil.which('h5cc')
        assert compiler, 'h5cc is unavailable'
        built = subprocess.run(
            [compiler, '-O2', '-fopenmp', str(instrumented_source), '-lm', '-o', str(instrumented_binary)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert built.returncode == 0, f'sim.c does not compile:\n{built.stdout}\n{built.stderr}'

        # Runtime-generated challenge parameters prevent an executable that only
        # recognizes the image's fixed values from satisfying the simulation test.
        f0 = float(secrets.randbelow(61) + 17) + 0.37
        decay = float(secrets.randbelow(70) + 10) / 1000.0

        submitted_outputs = []
        instrumented_outputs = []
        for threads in (1, 2, 3, 4):
            for _ in range(2):
                with tempfile.TemporaryDirectory() as run_dir:
                    output, _ = run_and_check(EXECUTABLE, f0, decay, threads, run_dir)
                    submitted_outputs.append(output)
                with tempfile.TemporaryDirectory() as run_dir:
                    output, _ = run_and_check(instrumented_binary, f0, decay, threads, run_dir)
                    instrumented_outputs.append(output)

        assert len(set(submitted_outputs)) == 1, 'run_sim energy is not reproducible across runs/thread counts'
        assert len(set(instrumented_outputs)) == 1, 'sim.c energy accumulation is not reproducible across runs/thread counts'


def locate_generated_signal():
    candidates = [Path('/home/user/signal.h5'), Path('/app/signal.h5')]
    try:
        server_cwd = Path('/proc') / str(find_server_pid()) / 'cwd' / 'signal.h5'
        candidates.append(server_cwd)
    except Exception:
        pass
    for candidate in candidates:
        try:
            if candidate.is_file():
                return candidate.resolve()
        except OSError:
            pass
    pytest.fail('No signal.h5 generated by the requested simulation run was found')


def find_server_pid():
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmdline = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
            if '8080' in cmdline or 'flask' in cmdline.lower():
                return int(proc.name)
        except OSError:
            continue
    raise RuntimeError('server process not found')


def test_fft_analysis_script_exists():
    scripts = []
    for root in (Path('/home/user'), Path('/app')):
        scripts.extend(root.rglob('*.py'))
    suitable = []
    for script in scripts:
        try:
            text = script.read_text(errors='replace').lower()
        except OSError:
            continue
        if 'h5py' in text and 'signal' in text and 'fft' in text:
            suitable.append(script)
    assert suitable, 'No Python FFT analysis script reading the HDF5 signal was found'


def test_api_report():
    url = 'http://127.0.0.1:8080/api/report'
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to the web server at {url}: {e}')

    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}. Response: {response.text}'

    try:
        data = response.json()
    except Exception as e:
        pytest.fail(f'Failed to parse JSON response: {e}. Response text: {response.text}')

    assert 'energy' in data, f"JSON response missing 'energy' key. Keys found: {list(data.keys())}"
    assert 'dominant_freq' in data, f"JSON response missing 'dominant_freq' key. Keys found: {list(data.keys())}"

    expected_energy = 0.0
    for i in range(N):
        t = i * DT
        val = math.exp(-0.02 * t) * math.sin(2 * math.pi * 50.0 * t)
        expected_energy += abs(val)

    try:
        actual_energy = float(data['energy'])
    except (ValueError, TypeError):
        pytest.fail(f"Could not convert 'energy' to float. Value: {data['energy']}")
    try:
        actual_freq = float(data['dominant_freq'])
    except (ValueError, TypeError):
        pytest.fail(f"Could not convert 'dominant_freq' to float. Value: {data['dominant_freq']}")

    # Preserve the original report assertions.
    assert math.isclose(actual_freq, 50.0, rel_tol=1e-3), f'Expected dominant_freq to be ~50.0, got {actual_freq}'
    assert math.isclose(actual_energy, expected_energy, rel_tol=1e-5), f'Expected energy to be ~{expected_energy}, got {actual_energy}'

    # Also derive the report from the HDF5 artifact that the workflow produced.
    signal_path = locate_generated_signal()
    with h5py.File(signal_path, 'r') as h5:
        assert 'signal' in h5, "Generated signal.h5 lacks the 'signal' dataset"
        signal = np.asarray(h5['signal'][:], dtype=np.float64)
    assert signal.shape == (N,), f'Expected 10000 samples in generated signal.h5, got {signal.shape}'

    frequencies = np.fft.rfftfreq(N, d=DT)
    magnitudes = np.abs(np.fft.rfft(signal))
    magnitudes[0] = -np.inf
    derived_freq = float(frequencies[int(np.argmax(magnitudes))])
    derived_energy = math.fsum(abs(float(x)) for x in signal)
    assert math.isclose(actual_freq, derived_freq, rel_tol=1e-3, abs_tol=1e-9), 'API frequency does not match FFT of generated signal.h5'
    assert math.isclose(actual_energy, derived_energy, rel_tol=1e-5), 'API energy does not match generated signal.h5'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
