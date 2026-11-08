#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_task.py
import ast
import math
import os
import runpy
import subprocess
import sys
import types

import numpy as np
import scipy.interpolate
import scipy.optimize

SIM = '/home/user/simulate.py'
FIT = '/home/user/fit_mu.py'
OUT = '/home/user/mu_solution.txt'

assert os.path.isfile(SIM), 'Missing /home/user/simulate.py'
assert os.path.isfile(FIT), 'Missing /home/user/fit_mu.py'

# Preserve the original source assertion, while requiring the executed error
# expression to actually be max(abs(y_h - y_e)), rather than accepting comments
# or an L2 norm.
sim_source = open(SIM, encoding='utf-8').read()
assert 'np.sum(y_h - y_e)' not in sim_source, 'The buggy error calculation is still present.'
sim_tree = ast.parse(sim_source, filename=SIM)

def names(node):
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}

def is_abs_call(node):
    if not isinstance(node, ast.Call):
        return False
    f = node.func
    return (isinstance(f, ast.Name) and f.id == 'abs') or (isinstance(f, ast.Attribute) and f.attr == 'abs')

def is_max_call(node):
    if not isinstance(node, ast.Call):
        return False
    f = node.func
    return (isinstance(f, ast.Name) and f.id == 'max') or (isinstance(f, ast.Attribute) and f.attr == 'max')

def has_required_error_expression(node):
    if not is_max_call(node):
        return False
    has_abs = any(is_abs_call(n) for n in ast.walk(node))
    has_diff = any(isinstance(n, ast.BinOp) and isinstance(n.op, ast.Sub)
                   and {'y_h', 'y_e'} <= names(n) for n in ast.walk(node))
    return has_abs and has_diff

error_values = []
for node in ast.walk(sim_tree):
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'error' for t in node.targets):
        error_values.append(node.value)
    elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == 'error':
        error_values.append(node.value)
assert any(has_required_error_expression(v) for v in error_values), \
    'error must be computed as the maximum absolute Heun/Euler state difference.'
assert not any(isinstance(n, ast.Attribute) and n.attr == 'norm' for n in ast.walk(sim_tree)), \
    'np.linalg.norm is not the required maximum absolute difference.'

# Import and execute the submitted integrator, then compare its behavior with an
# independent fixed implementation.
sys.path.insert(0, '/home/user')
import simulate

def reference(mu, t_end=20.0, dt0=0.1, tol=1e-3):
    t = 0.0
    y = np.array([2.0, 0.0])
    ts, ys = [t], [y.copy()]
    dt = dt0
    while t < t_end:
        if t + dt > t_end:
            dt = t_end - t
        k1 = np.array([y[1], mu * (1.0 - y[0] ** 2) * y[1] - y[0]])
        ye = y + dt * k1
        k2 = np.array([ye[1], mu * (1.0 - ye[0] ** 2) * ye[1] - ye[0]])
        yh = y + dt * (k1 + k2) / 2.0
        error = np.max(np.abs(yh - ye))
        if error < tol:
            t += dt
            y = yh
            ts.append(t)
            ys.append(y.copy())
            dt = min(dt * 1.5, 0.5)
        else:
            dt = max(dt * 0.5, 1e-4)
    return np.asarray(ts), np.asarray(ys)

for mu in (1.2, 1.8):
    got_t, got_y = simulate.adaptive_euler_heun(mu, t_end=20.0)
    ref_t, ref_y = reference(mu)
    assert got_t.shape == ref_t.shape and got_y.shape == ref_y.shape
    assert np.allclose(got_t, ref_t, rtol=0, atol=1e-12)
    assert np.allclose(got_y, ref_y, rtol=1e-11, atol=1e-12)

# Require executable pipeline calls in fit_mu.py, not keywords hidden in comments.
fit_source = open(FIT, encoding='utf-8').read()
fit_tree = ast.parse(fit_source, filename=FIT)
call_names = []
for node in ast.walk(fit_tree):
    if isinstance(node, ast.Call):
        if isinstance(node.func, ast.Name):
            call_names.append(node.func.id)
        elif isinstance(node.func, ast.Attribute):
            call_names.append(node.func.attr)
assert 'adaptive_euler_heun' in call_names, 'fit_mu.py must call adaptive_euler_heun.'
assert 'interp1d' in call_names, 'fit_mu.py must call scipy.interpolate.interp1d.'
assert 'rfft' in call_names, 'fit_mu.py must call np.fft.rfft.'

# Execute the script once against derived, instrumented data. This verifies that
# its live path simulates multiple mu values, linearly interpolates exactly the
# requested grid, performs rFFT peak analysis, invokes a root finder, and writes
# the returned fitted value.
calls = {'sim': 0, 'interp': 0, 'fft': 0, 'root': 0}
fake_sim = types.ModuleType('simulate')

def fake_adaptive(mu, *args, **kwargs):
    calls['sim'] += 1
    t = np.array([0.0, 73.0, 211.0, 417.0, 600.0])
    y = np.column_stack((np.full(t.size, float(mu)), np.arange(t.size, dtype=float)))
    return t, y
fake_sim.adaptive_euler_heun = fake_adaptive
sys.modules['simulate'] = fake_sim

real_interp1d = scipy.interpolate.interp1d
real_rfft = np.fft.rfft
root_names = ('brentq', 'bisect', 'ridder', 'toms748')
real_roots = {name: getattr(scipy.optimize, name) for name in root_names}
real_root_scalar = scipy.optimize.root_scalar

def fake_interp1d(x, y, *args, **kwargs):
    calls['interp'] += 1
    assert kwargs.get('kind', 'linear') == 'linear', 'Interpolation must use kind=linear.'
    x = np.asarray(x)
    y = np.asarray(y)
    assert x[0] <= 100.0 and x[-1] >= 600.0
    mu = float(y[0])
    def evaluate(grid):
        grid = np.asarray(grid, dtype=float)
        expected = 100.0 + 0.1 * np.arange(5001)
        assert grid.shape == (5001,), 'Uniform grid must contain 5001 inclusive points.'
        assert np.allclose(grid, expected, rtol=0, atol=1e-10), 'Incorrect uniform interpolation grid.'
        return np.full(grid.shape, mu)
    return evaluate

def fake_rfft(values, *args, **kwargs):
    calls['fft'] += 1
    values = np.asarray(values)
    assert values.shape == (5001,), 'rfft must receive the uniformly sampled segment.'
    out = np.zeros(2501, dtype=complex)
    # Produce endpoint objective values of opposite signs. The marker threshold
    # is deliberately unrelated to the real answer.
    out[60 if float(values[0]) < 1.731 else 80] = 1000.0
    return out

def fake_bracket_root(func, a, b, *args, **kwargs):
    calls['root'] += 1
    assert abs(float(a) - 1.0) < 1e-12 and abs(float(b) - 2.0) < 1e-12
    fa, fb = float(func(1.0)), float(func(2.0))
    assert fa < 0 < fb or fb < 0 < fa, 'Root objective must bracket zero on [1, 2].'
    return 1.731

def fake_root_scalar(func, *args, **kwargs):
    bracket = kwargs.get('bracket')
    if bracket is None and args:
        bracket = args[0]
    assert bracket is not None
    value = fake_bracket_root(func, bracket[0], bracket[1])
    return types.SimpleNamespace(root=value, converged=True)

scipy.interpolate.interp1d = fake_interp1d
np.fft.rfft = fake_rfft
for name in root_names:
    setattr(scipy.optimize, name, fake_bracket_root)
scipy.optimize.root_scalar = fake_root_scalar

if os.path.exists(OUT):
    os.remove(OUT)
runpy.run_path(FIT, run_name='__main__')
assert calls['sim'] >= 2 and calls['interp'] >= 2 and calls['fft'] >= 2, \
    'fit_mu.py did not execute the simulation/interpolation/FFT objective.'
assert calls['root'] >= 1, 'fit_mu.py did not execute a nonlinear root finder.'
assert os.path.isfile(OUT), 'fit_mu.py did not create mu_solution.txt.'
assert open(OUT, encoding='utf-8').read().strip() == '1.731', \
    'fit_mu.py did not save the fitted root rounded to three decimals.'

# Restore libraries, remove the instrumented result, and execute the real script.
scipy.interpolate.interp1d = real_interp1d
np.fft.rfft = real_rfft
for name, value in real_roots.items():
    setattr(scipy.optimize, name, value)
scipy.optimize.root_scalar = real_root_scalar
sys.modules['simulate'] = simulate
os.remove(OUT)
subprocess.run([sys.executable, FIT], cwd='/home/user', check=True, timeout=300)
assert os.path.exists(OUT), 'The real fit_mu.py execution did not create mu_solution.txt.'

# Preserve the original independent final-value assertion.
def ref_dom_freq(mu):
    times, states = reference(mu, t_end=600.0)
    grid = 100.0 + 0.1 * np.arange(5001)
    uniform = np.interp(grid, times, states[:, 0])
    spectrum = np.fft.rfft(uniform)
    peak = int(np.argmax(np.abs(spectrum[1:250])) + 1)
    return peak / (len(grid) * 0.1)

def objective(mu):
    return ref_dom_freq(mu) - 0.140

def bisection(a, b, tol=1e-4):
    fa, fb = objective(a), objective(b)
    if fa * fb > 0:
        return a
    while (b - a) / 2.0 > tol:
        c = (a + b) / 2.0
        fc = objective(c)
        if fc == 0:
            return c
        if fa * fc < 0:
            b, fb = c, fc
        else:
            a, fa = c, fc
    return (a + b) / 2.0

expected = f'{bisection(1.0, 2.0):.3f}'
actual = open(OUT, encoding='utf-8').read().strip()
assert actual == expected, f'Expected mu to be {expected}, but got {actual}.'
assert len(actual) == 5 and actual[1] == '.' and actual.replace('.', '').isdigit(), \
    'mu_solution.txt must contain exactly three decimal places.'
PY

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
