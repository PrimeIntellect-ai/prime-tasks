#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import pytest

PYTHON_EXEC = '/home/user/sim_env/bin/python'


def run_in_student_env(script):
    proc = subprocess.run([PYTHON_EXEC, '-c', script], capture_output=True, text=True)
    assert proc.returncode == 0, (
        "Failed to run verification using the student's environment "
        f"(are numpy, scipy, and h5py installed?). Error: {proc.stderr}"
    )
    return proc.stdout


def expected_integral():
    script = r'''
import numpy as np
from scipy.integrate import solve_ivp, simpson

def rhs(t, y):
    T, C = y
    return [-0.05 * (T - 20.0),
            10.0 - 0.1 * np.exp((T - 20.0) / 10.0) * C]

t = np.linspace(0.0, 50.0, 500)
sol = solve_ivp(rhs, (0.0, 50.0), (37.0, 0.0), t_eval=t,
                method='DOP853', rtol=1e-11, atol=1e-13)
if not sol.success:
    raise RuntimeError(sol.message)
print(float(simpson(sol.y[1], x=t)))
'''
    return float(run_in_student_env(script).strip())


def test_virtual_environment_exists():
    """Verify that the virtual environment was created and contains python."""
    assert os.path.isfile(PYTHON_EXEC), (
        f"Virtual environment python executable not found at {PYTHON_EXEC}"
    )


def test_summary_json_structure_and_integral():
    """Verify the existence and structure of summary.json, and the integral value."""
    summary_path = '/home/user/results/summary.json'
    assert os.path.isfile(summary_path), f"Summary JSON file not found at {summary_path}"

    with open(summary_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not a valid JSON file.")

    expected_keys = {"integral_yield", "forward_primer", "reverse_primer", "forward_gc", "reverse_gc"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"summary.json is missing keys: {missing_keys}"

    integral = data['integral_yield']
    assert isinstance(integral, (int, float)), "integral_yield must be a number"
    reference = expected_integral()
    assert abs(integral - reference) < 1.0, (
        f"Expected integral_yield around {reference:.2f}, got {integral}"
    )


def test_hdf5_and_primers_via_student_env():
    """Verify all saved simulation arrays, the yield, and the primer results."""
    assert os.path.isfile(PYTHON_EXEC), (
        "Cannot test HDF5: Student's virtual environment python not found."
    )

    script = r'''
import h5py
import json
import numpy as np
import sys
from scipy.integrate import solve_ivp, simpson

out = {}
try:
    def rhs(t, y):
        T, C = y
        return [-0.05 * (T - 20.0),
                10.0 - 0.1 * np.exp((T - 20.0) / 10.0) * C]

    expected_time = np.linspace(0.0, 50.0, 500)
    solution = solve_ivp(
        rhs, (0.0, 50.0), (37.0, 0.0), t_eval=expected_time,
        method='DOP853', rtol=1e-11, atol=1e-13
    )
    if not solution.success:
        raise RuntimeError(solution.message)
    expected_temperature = solution.y[0]
    expected_concentration = solution.y[1]
    expected_yield = float(simpson(expected_concentration, x=expected_time))

    with h5py.File('/home/user/results/simulation.h5', 'r') as f:
        out['time_len'] = len(f['time'])
        out['has_temperature'] = 'temperature' in f
        out['has_concentration'] = 'concentration' in f
        out['total_yield'] = float(f.attrs['total_yield'])

        time = np.asarray(f['time'][...], dtype=float)
        temperature = np.asarray(f['temperature'][...], dtype=float)
        concentration = np.asarray(f['concentration'][...], dtype=float)

    out['time_shape'] = list(time.shape)
    out['temperature_shape'] = list(temperature.shape)
    out['concentration_shape'] = list(concentration.shape)
    out['arrays_finite'] = bool(
        np.all(np.isfinite(time)) and
        np.all(np.isfinite(temperature)) and
        np.all(np.isfinite(concentration))
    )

    if time.shape == (500,):
        out['time_max_error'] = float(np.max(np.abs(time - expected_time)))
    else:
        out['time_max_error'] = float('inf')

    if temperature.shape == (500,):
        out['temperature_max_error'] = float(
            np.max(np.abs(temperature - expected_temperature))
        )
    else:
        out['temperature_max_error'] = float('inf')

    if concentration.shape == (500,):
        out['concentration_max_error'] = float(
            np.max(np.abs(concentration - expected_concentration))
        )
    else:
        out['concentration_max_error'] = float('inf')

    if time.shape == (500,) and concentration.shape == (500,):
        out['saved_data_yield'] = float(simpson(concentration, x=time))
    else:
        out['saved_data_yield'] = float('inf')
    out['expected_yield'] = expected_yield

    with h5py.File('/home/user/data/reference.h5', 'r') as f:
        raw = f['sequence'][()]
        seq = raw.decode('utf-8') if isinstance(raw, bytes) else str(raw)

    target = seq[300:500]
    out['fwd'] = target[:20]
    comp = {'A':'T', 'T':'A', 'C':'G', 'G':'C'}
    out['rev'] = ''.join(comp[b] for b in reversed(target[-20:]))

    print(json.dumps(out))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
'''

    out = json.loads(run_in_student_env(script))

    # Preserve the original HDF5 assertions.
    assert out['time_len'] == 500, (
        f"Expected 500 time points in simulation.h5, got {out['time_len']}"
    )
    assert out['has_temperature'], "Missing 'temperature' dataset in simulation.h5"
    assert out['has_concentration'], "Missing 'concentration' dataset in simulation.h5"
    assert abs(out['total_yield'] - out['expected_yield']) < 1.0, (
        f"total_yield attribute in simulation.h5 is incorrect, got {out['total_yield']}"
    )

    # Verify the actual numerical datasets, not merely their existence.
    assert out['time_shape'] == [500], f"time dataset has wrong shape: {out['time_shape']}"
    assert out['temperature_shape'] == [500], (
        f"temperature dataset has wrong shape: {out['temperature_shape']}"
    )
    assert out['concentration_shape'] == [500], (
        f"concentration dataset has wrong shape: {out['concentration_shape']}"
    )
    assert out['arrays_finite'], "Simulation datasets contain non-finite values"
    assert out['time_max_error'] < 1e-10, "time dataset is not the required 500-point grid"
    assert out['temperature_max_error'] < 0.05, "temperature dataset does not solve the specified ODE"
    assert out['concentration_max_error'] < 0.2, "concentration dataset does not solve the specified ODE"
    assert abs(out['total_yield'] - out['saved_data_yield']) < 0.05, (
        "total_yield attribute does not match Simpson integration of the saved concentration"
    )

    summary_path = '/home/user/results/summary.json'
    with open(summary_path, 'r') as f:
        data = json.load(f)

    assert data['forward_primer'] == out['fwd'], (
        f"Forward primer mismatch. Expected {out['fwd']}, got {data['forward_primer']}"
    )
    assert data['reverse_primer'] == out['rev'], (
        f"Reverse primer mismatch. Expected {out['rev']}, got {data['reverse_primer']}"
    )

    def calc_gc(s):
        if not s:
            return 0.0
        return sum(1 for b in s if b in 'GC') / len(s) * 100.0

    expected_fwd_gc = calc_gc(out['fwd'])
    expected_rev_gc = calc_gc(out['rev'])

    assert abs(data['forward_gc'] - expected_fwd_gc) < 0.1, (
        f"Forward GC mismatch. Expected {expected_fwd_gc}, got {data['forward_gc']}"
    )
    assert abs(data['reverse_gc'] - expected_rev_gc) < 0.1, (
        f"Reverse GC mismatch. Expected {expected_rev_gc}, got {data['reverse_gc']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
