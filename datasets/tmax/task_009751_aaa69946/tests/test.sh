#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verifier_hooks
mkdir -p /tmp/verifier_hooks
cat <<'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os
import fcntl

TRACE = os.environ.get('SPECTRA_TRACE_FILE')

def emit(kind, **values):
    if not TRACE:
        return
    record = {'kind': kind, 'pid': os.getpid(), **values}
    with open(TRACE, 'a') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        f.write(json.dumps(record) + '\n')
        f.flush()
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)

try:
    import scipy.signal
    _savgol_filter = scipy.signal.savgol_filter
    def traced_savgol_filter(*args, **kwargs):
        window = kwargs.get('window_length', args[1] if len(args) > 1 else None)
        poly = kwargs.get('polyorder', args[2] if len(args) > 2 else None)
        emit('savgol_filter', window=int(window), poly=int(poly))
        return _savgol_filter(*args, **kwargs)
    scipy.signal.savgol_filter = traced_savgol_filter

    import scipy.optimize
    _curve_fit = scipy.optimize.curve_fit
    def traced_curve_fit(*args, **kwargs):
        p0 = kwargs.get('p0', args[3] if len(args) > 3 else None)
        try:
            p0 = [float(v) for v in p0]
        except Exception:
            p0 = None
        emit('curve_fit', p0=p0)
        return _curve_fit(*args, **kwargs)
    scipy.optimize.curve_fit = traced_curve_fit

    import multiprocessing
    _Pool = multiprocessing.Pool
    def traced_pool(*args, **kwargs):
        processes = kwargs.get('processes', args[0] if args else None)
        emit('Pool', processes=None if processes is None else int(processes))
        return _Pool(*args, **kwargs)
    multiprocessing.Pool = traced_pool
except Exception:
    pass
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import subprocess
import sys

import numpy as np
from scipy.optimize import curve_fit
from scipy.signal import savgol_filter

SCRIPT = '/home/user/process_spectra.py'
SPECTRA = '/home/user/spectra'
FEATURES = '/home/user/features.csv'
NAMES = [f'spec_{i:03d}.txt' for i in range(100)]

def gaussian(x, A, mu, sigma):
    return A * np.exp(-(x - mu) ** 2 / (2 * sigma ** 2))

def expected_features():
    grid = np.linspace(400.0, 800.0, 1000)
    expected = {}
    for name in NAMES:
        data = np.loadtxt(os.path.join(SPECTRA, name), delimiter=',')
        order = np.argsort(data[:, 0])
        x = data[order, 0]
        y = data[order, 1]
        regridded = np.interp(grid, x, y)
        smoothed = savgol_filter(regridded, 51, 3)
        params, _ = curve_fit(gaussian, grid, smoothed,
                              p0=[10.0, 600.0, 20.0])
        expected[name] = tuple(float(f'{v:.2f}') for v in params)
    return expected

def read_and_check_csv(expected=None):
    assert os.path.isfile(FEATURES), '/home/user/features.csv is missing.'
    with open(FEATURES, 'r', newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) == 101, (
        f'Expected 101 rows (header + 100 data rows), found {len(rows)}')
    header = rows[0]
    assert header == ['filename', 'A', 'mu', 'sigma'], (
        f'Incorrect header: {header}')

    data_rows = rows[1:]
    actual_filenames = [row[0] for row in data_rows]
    assert actual_filenames == NAMES, (
        'Filenames are not sorted or do not match the expected spec_XXX.txt format.')

    for row in data_rows:
        assert len(row) == 4, f'Row {row[0]} does not have exactly 4 columns.'
        filename, a_str, mu_str, sigma_str = row
        try:
            a = float(a_str)
            mu = float(mu_str)
            sigma = float(sigma_str)
        except ValueError:
            assert False, f'Non-numeric values found in row for {filename}: {row}'

        assert a_str == f'{a:.2f}' or a_str == str(round(a, 2)), (
            f'Value A ({a_str}) not rounded to 2 decimal places in {filename}.')
        assert mu_str == f'{mu:.2f}' or mu_str == str(round(mu, 2)), (
            f'Value mu ({mu_str}) not rounded to 2 decimal places in {filename}.')
        assert sigma_str == f'{sigma:.2f}' or sigma_str == str(round(sigma, 2)), (
            f'Value sigma ({sigma_str}) not rounded to 2 decimal places in {filename}.')

        assert 0 < a < 50, f'Value A ({a}) out of reasonable bounds for {filename}.'
        assert 400 <= mu <= 800, f'Value mu ({mu}) out of reasonable bounds for {filename}.'
        assert 0 < sigma < 100, (
            f'Value sigma ({sigma}) out of reasonable bounds for {filename}.')

        if expected is not None:
            got = (a, mu, sigma)
            want = expected[filename]
            assert got == want, (
                f'Incorrect fitted parameters for {filename}: got {got}, expected {want}')

def run_script(env=None):
    result = subprocess.run(
        [sys.executable, SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180)
    assert result.returncode == 0, (
        f'process_spectra.py failed with exit code {result.returncode}:\n'
        f'{result.stdout}\n{result.stderr}')

def write_challenge_spectra():
    rng = np.random.default_rng(8675309)
    for i, name in enumerate(NAMES):
        inner = rng.uniform(400.0, 800.0, 298)
        x = np.sort(np.concatenate(([400.0], inner, [800.0])))
        A = 5.5 + (i % 20) * 0.43
        mu = 505.0 + (i * 17 % 185)
        sigma = 11.0 + (i % 17) * 0.91
        y = gaussian(x, A, mu, sigma) + rng.normal(0.0, 0.18, x.size)
        with open(os.path.join(SPECTRA, name), 'w') as f:
            for xx, yy in zip(x, y):
                f.write(f'{xx:.8f},{yy:.8f}\n')

def test_script_and_original_output():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} is missing.'
    assert os.path.getsize(SCRIPT) > 0, f'{SCRIPT} is empty.'
    with open(SCRIPT, 'r') as f:
        ast.parse(f.read(), filename=SCRIPT)

    original_expected = expected_features()
    read_and_check_csv(original_expected)

    originals = {}
    for name in NAMES:
        with open(os.path.join(SPECTRA, name), 'rb') as f:
            originals[name] = f.read()

    challenge_error = None
    try:
        write_challenge_spectra()
        challenge_expected = expected_features()
        if os.path.exists(FEATURES):
            os.remove(FEATURES)
        trace = '/tmp/spectra_trace.jsonl'
        if os.path.exists(trace):
            os.remove(trace)
        env = os.environ.copy()
        env['PYTHONPATH'] = '/tmp/verifier_hooks' + (
            os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['SPECTRA_TRACE_FILE'] = trace
        run_script(env)
        read_and_check_csv(challenge_expected)

        assert os.path.isfile(trace), 'No required processing calls were observed.'
        with open(trace, 'r') as f:
            events = [json.loads(line) for line in f if line.strip()]

        pools = [e for e in events if e['kind'] == 'Pool']
        assert pools, 'multiprocessing.Pool was not used.'
        assert any(e.get('processes') == 4 for e in pools), (
            'multiprocessing.Pool was not created with exactly 4 workers.')

        smooth = [e for e in events if e['kind'] == 'savgol_filter'
                  and e.get('window') == 51 and e.get('poly') == 3]
        assert len(smooth) >= 100, (
            'savgol_filter(window_length=51, polyorder=3) was not used for every spectrum.')

        fits = [e for e in events if e['kind'] == 'curve_fit'
                and e.get('p0') == [10.0, 600.0, 20.0]]
        assert len(fits) >= 100, (
            'curve_fit with p0=[10.0, 600.0, 20.0] was not used for every spectrum.')
        worker_pids = {e['pid'] for e in smooth + fits}
        assert len(worker_pids) >= 2, (
            'Spectrum processing was not distributed among worker processes.')
    except BaseException as exc:
        challenge_error = exc
    finally:
        for name, content in originals.items():
            with open(os.path.join(SPECTRA, name), 'wb') as f:
                f.write(content)
        try:
            run_script()
            read_and_check_csv(original_expected)
        except BaseException as restore_exc:
            if challenge_error is None:
                challenge_error = restore_exc

    if challenge_error is not None:
        raise challenge_error
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
