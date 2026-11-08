#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
from pathlib import Path
import subprocess

import numpy as np
import pytest

HOME = Path('/home/user')
MEASUREMENTS = HOME / 'measurements.txt'
RESULTS = HOME / 'results.csv'
SCRIPT = None
ORIGINAL_MEASUREMENTS = MEASUREMENTS.read_bytes()


def resolved_calls(source):
    tree = ast.parse(source)
    aliases = {}
    multiprocessing_imported = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                local = item.asname or item.name.split('.')[0]
                aliases[local] = item.name if item.asname else item.name.split('.')[0]
                if item.name == 'multiprocessing' or item.name.startswith('multiprocessing.'):
                    multiprocessing_imported = True
        elif isinstance(node, ast.ImportFrom) and node.module:
            for item in node.names:
                local = item.asname or item.name
                aliases[local] = node.module + '.' + item.name
            if node.module == 'multiprocessing' or node.module.startswith('multiprocessing.'):
                multiprocessing_imported = True

    def dotted(node):
        parts = []
        while isinstance(node, ast.Attribute):
            parts.append(node.attr)
            node = node.value
        if isinstance(node, ast.Name):
            parts.append(node.id)
        else:
            return ''
        parts.reverse()
        if parts and parts[0] in aliases:
            parts = aliases[parts[0]].split('.') + parts[1:]
        return '.'.join(parts)

    calls = [dotted(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)]
    return multiprocessing_imported, calls


def is_required_script(path):
    try:
        source = path.read_text(encoding='utf-8')
        mp_imported, calls = resolved_calls(source)
    except (OSError, UnicodeDecodeError, SyntaxError):
        return False

    has_fft = any(
        (name.startswith('numpy.fft.') or name.startswith('scipy.fft.') or
         name.startswith('scipy.fftpack.')) and name.rsplit('.', 1)[-1] in {'fft', 'rfft'}
        for name in calls
    )
    has_optimizer = any(
        name.startswith('scipy.optimize.') and name.rsplit('.', 1)[-1] in
        {'curve_fit', 'minimize', 'least_squares', 'differential_evolution'}
        for name in calls
    )
    has_root_solver = any(
        name.startswith('scipy.optimize.') and name.rsplit('.', 1)[-1] in
        {'fsolve', 'root', 'root_scalar', 'brentq', 'brenth', 'bisect', 'newton', 'ridder'}
        for name in calls
    )
    has_parallel_worker = mp_imported and any(
        name.startswith('multiprocessing.') and name.rsplit('.', 1)[-1] in {'Pool', 'Process'}
        for name in calls
    )
    return has_fft and has_optimizer and has_root_solver and has_parallel_worker


def find_script():
    candidates = [
        p for p in HOME.rglob('*.py')
        if p.is_file() and '.cache' not in p.parts and '__pycache__' not in p.parts
    ]
    qualifying = [p for p in candidates if is_required_script(p)]
    assert qualifying, (
        'No self-contained Python script under /home/user was found that uses a NumPy/SciPy '
        'DFT, multiprocessing, nonlinear optimization, and a SciPy root-finding routine.'
    )
    return max(qualifying, key=lambda p: p.stat().st_mtime_ns)


def run_script(script):
    if RESULTS.exists():
        RESULTS.unlink()
    try:
        completed = subprocess.run(
            ['python3', str(script)],
            cwd=str(HOME),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
            env={**os.environ, 'PYTHONUNBUFFERED': '1'},
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'{script} did not finish within 90 seconds')
    assert completed.returncode == 0, (
        f'{script} failed when executed.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert RESULTS.is_file(), (
        f'The file {RESULTS} is missing. Executing {script} did not create the output file.'
    )


def read_results():
    assert RESULTS.is_file(), f'The file {RESULTS} is missing. The script did not create the output file.'
    with RESULTS.open('r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f'The file {RESULTS} is empty.')
    assert header == ['sensor_id', 'f', 'root'], f'Incorrect header in {RESULTS}: {header}'

    parsed = {}
    with RESULTS.open('r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                sid = int(row['sensor_id'])
                f_val = float(row['f'])
                root_val = float(row['root'])
                parsed[sid] = (f_val, root_val)
            except (ValueError, KeyError) as exc:
                pytest.fail(f'Error parsing row {row}: {exc}')
    assert len(parsed) == 4, f'Expected 4 rows of data, got {len(parsed)}'
    return parsed


def test_01_execute_script_and_check_original_results():
    global SCRIPT
    SCRIPT = find_script()
    MEASUREMENTS.write_bytes(ORIGINAL_MEASUREMENTS)
    run_script(SCRIPT)
    results = read_results()

    expected_values = {
        0: {'f': 3.0, 'root': 0.1402},
        1: {'f': 5.0, 'root': 0.0064},
        2: {'f': 7.0, 'root': 0.0487},
        3: {'f': 9.0, 'root': 0.0141},
    }
    for sid, expected in expected_values.items():
        assert sid in results, f'Missing results for sensor_id {sid}'
        f_val, root_val = results[sid]
        assert math.isclose(f_val, expected['f'], abs_tol=0.1), \
            f"Sensor {sid}: Expected frequency ~{expected['f']}, got {f_val}"
        assert math.isclose(root_val, expected['root'], abs_tol=0.01), \
            f"Sensor {sid}: Expected root ~{expected['root']}, got {root_val}"


def test_02_script_handles_unseen_measurements():
    assert SCRIPT is not None
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
    times = np.linspace(0.0, 1.0, 1000)
    base_frequencies = np.array([3.0, 5.0, 7.0, 9.0])
    frequencies = base_frequencies + rng.uniform(-0.16, 0.16, 4)
    amplitudes = rng.uniform(1.2, 3.2, 4)
    phases = rng.uniform(-1.15, 1.15, 4)
    phases[np.abs(phases) < 0.15] += np.where(phases[np.abs(phases) < 0.15] >= 0, 0.25, -0.25)

    lines = []
    for sid, (freq, amplitude, phase) in enumerate(zip(frequencies, amplitudes, phases)):
        values = amplitude * np.sin(2 * np.pi * freq * times + phase)
        values += rng.normal(0.0, 0.005, len(times))
        lines.extend(
            f'{sid} {time:.6f} {value:.6f}\n'
            for time, value in zip(times, values)
        )
    rng.shuffle(lines)

    try:
        with MEASUREMENTS.open('w') as f:
            f.write('sensor_id timestamp measurement\n')
            f.writelines(lines)
        run_script(SCRIPT)
        results = read_results()

        for sid, (freq, phase) in enumerate(zip(frequencies, phases)):
            assert sid in results, f'Missing results for sensor_id {sid} on unseen data'
            fitted_f, fitted_root = results[sid]
            k = 1 if phase >= 0 else 0
            expected_root = (k * math.pi - phase) / (2 * math.pi * freq)
            assert math.isclose(fitted_f, freq, abs_tol=0.08), (
                f'Sensor {sid}: expected fitted frequency near {freq:.6f} on unseen data, got {fitted_f}'
            )
            assert fitted_root > 0, f'Sensor {sid}: root must be strictly positive, got {fitted_root}'
            assert math.isclose(fitted_root, expected_root, abs_tol=0.008), (
                f'Sensor {sid}: expected smallest positive root near {expected_root:.6f}, got {fitted_root}'
            )
    finally:
        MEASUREMENTS.write_bytes(ORIGINAL_MEASUREMENTS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
