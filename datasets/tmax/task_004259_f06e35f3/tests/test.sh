#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import runpy
import sys
import numpy as np
import pandas as pd
import scipy.integrate

SCRIPT_PATH = '/home/user/sim_kinetics.py'
CSV_PATH = '/home/user/trajectory.csv'
PDB_PATH = '/home/user/protein.pdb'


def test_trajectory_mse(monkeypatch):
    """Execute the repaired simulation and verify its implementation and output."""
    assert os.path.isfile(SCRIPT_PATH), f"Simulation script {SCRIPT_PATH} is missing."

    # Track supported adaptive SciPy integrators and the tolerances actually used.
    adaptive_calls = []
    adaptive_names = (
        'solve_ivp', 'odeint', 'RK23', 'RK45', 'DOP853',
        'Radau', 'BDF', 'LSODA'
    )
    for name in adaptive_names:
        if not hasattr(scipy.integrate, name):
            continue
        original = getattr(scipy.integrate, name)

        def make_wrapper(func, integrator_name):
            def wrapper(*args, **kwargs):
                adaptive_calls.append((integrator_name, dict(kwargs)))
                return func(*args, **kwargs)
            return wrapper

        monkeypatch.setattr(
            scipy.integrate, name, make_wrapper(original, name)
        )

    def execute_script():
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        old_cwd = os.getcwd()
        try:
            os.chdir('/home/user')
            try:
                runpy.run_path(SCRIPT_PATH, run_name='__main__')
            except SystemExit as exc:
                assert exc.code in (None, 0), f"Simulation exited with status {exc.code}."
        finally:
            os.chdir(old_cwd)
        assert os.path.isfile(CSV_PATH), \
            f"Executing {SCRIPT_PATH} did not generate {CSV_PATH}."
        return pd.read_csv(CSV_PATH)

    # Prove that Y0 is derived from the PDB rather than hardcoded to 42.
    with open(PDB_PATH, 'rb') as f:
        original_pdb = f.read()
    extra_residue = (
        b'ATOM     43  CA  ALA A  43      11.639   6.071  -5.147  1.00  0.00           C  \n'
    )
    try:
        with open(PDB_PATH, 'wb') as f:
            f.write(original_pdb)
            if original_pdb and not original_pdb.endswith(b'\n'):
                f.write(b'\n')
            f.write(extra_residue)
        altered_df = execute_script()
    finally:
        with open(PDB_PATH, 'wb') as f:
            f.write(original_pdb)

    assert 't' in altered_df.columns and 'y' in altered_df.columns, \
        "Simulation output for the modified PDB must contain t and y columns."
    assert len(altered_df) > 0, "Simulation output for the modified PDB is empty."
    assert np.isclose(float(altered_df['y'].iloc[0]), 43.0), \
        "Y0 was not dynamically updated when the PDB residue count changed to 43."

    # Restore the real input and execute the submitted artifact to produce the final CSV.
    execute_script()

    assert adaptive_calls, \
        "The simulation did not execute a supported adaptive SciPy integrator."

    def tolerance_is_1e5(value):
        try:
            return bool(np.all(np.isclose(
                np.asarray(value, dtype=float), 1e-5, rtol=1e-12, atol=0.0
            )))
        except Exception:
            return False

    assert any(
        tolerance_is_1e5(kwargs.get('rtol')) and
        tolerance_is_1e5(kwargs.get('atol'))
        for _, kwargs in adaptive_calls
    ), "The adaptive integrator must be executed with both rtol=1e-5 and atol=1e-5."

    csv_path = '/home/user/trajectory.csv'
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        assert False, f"Failed to read {csv_path} as a CSV: {e}"

    assert 't' in df.columns, "CSV must contain a 't' column."
    assert 'y' in df.columns, "CSV must contain a 'y' column."
    assert list(df.columns) == ['t', 'y'], \
        "CSV must contain exactly two columns in the order 't', 'y'."

    t = df['t'].values
    y_agent = df['y'].values

    assert len(t) == 100, f"Expected exactly 100 points in the trajectory, but got {len(t)}."

    # Verify the time span
    assert np.isclose(t[0], 0.0), f"Expected start time t=0.0, got t={t[0]}"
    assert np.isclose(t[-1], 10.0), f"Expected end time t=10.0, got t={t[-1]}"
    expected_t = np.linspace(0.0, 10.0, 100)
    assert np.allclose(t, expected_t, rtol=1e-10, atol=1e-12), \
        "The t values must be exactly 100 evenly spaced points from 0 to 10."

    # Analytical solution: dy/dt = -0.5 * y, Y0 = 42
    Y0 = 42.0
    y_true = Y0 * np.exp(-0.5 * t)

    mse = np.mean((y_agent - y_true)**2)

    assert mse <= 0.01, f"MSE is {mse}, which is above the maximum allowed threshold of 0.01."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
