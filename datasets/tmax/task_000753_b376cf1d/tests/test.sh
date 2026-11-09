#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'AUDIT_EOF' > /tmp/run_epidemic_audit.py
import os
import runpy
import numpy as np
import scipy.integrate as integrate
import scipy.stats as stats

script_path = '/home/user/analyze_epidemic.py'
events = []
solve_calls = []
wasserstein_calls = 0
percentile_qs = []

orig_seed = np.random.seed
orig_normal = np.random.normal
orig_choice = np.random.choice
orig_percentile = np.percentile
orig_solve_ivp = integrate.solve_ivp
orig_wasserstein = stats.wasserstein_distance

def seed(value=None):
    events.append(('seed', value))
    return orig_seed(value)

def normal(loc=0.0, scale=1.0, size=None):
    events.append(('normal', loc, scale, size))
    return orig_normal(loc, scale, size)

def choice(a, size=None, replace=True, p=None):
    events.append(('choice', a if np.isscalar(a) else len(a), size, replace))
    return orig_choice(a, size=size, replace=replace, p=p)

def percentile(a, q, *args, **kwargs):
    percentile_qs.extend(np.asarray(q).reshape(-1).astype(float).tolist())
    return orig_percentile(a, q, *args, **kwargs)

def solve_ivp(fun, t_span, y0, *args, **kwargs):
    solve_calls.append((fun, t_span, tuple(y0), kwargs.get('args', ()), kwargs.get('t_eval'), kwargs.get('method', 'RK45')))
    return orig_solve_ivp(fun, t_span, y0, *args, **kwargs)

def wasserstein_distance(*args, **kwargs):
    global wasserstein_calls
    wasserstein_calls += 1
    return orig_wasserstein(*args, **kwargs)

np.random.seed = seed
np.random.normal = normal
np.random.choice = choice
np.percentile = percentile
integrate.solve_ivp = solve_ivp
stats.wasserstein_distance = wasserstein_distance

runpy.run_path(script_path, run_name='__main__')

assert len(solve_calls) == 1000, f'Expected 1000 solve_ivp calls, observed {len(solve_calls)}'
expected_betas_rng = np.random.RandomState(42)
expected_betas = np.concatenate([
    expected_betas_rng.normal(0.30, 0.02, 500),
    expected_betas_rng.normal(0.28, 0.02, 500),
])
expected_t = np.linspace(0, 50, 100)
for index, (fun, t_span, y0, ode_args, t_eval, method) in enumerate(solve_calls):
    assert tuple(t_span) == (0, 50), f'Incorrect t_span in solve call {index}'
    assert y0 == (99.0, 1.0), f'Incorrect initial conditions in solve call {index}'
    assert method == 'RK45', f'Incorrect solver method in solve call {index}'
    assert t_eval is not None and np.array_equal(np.asarray(t_eval), expected_t), f'Incorrect t_eval in solve call {index}'
    assert len(ode_args) == 2, f'Expected beta and gamma arguments in solve call {index}'
    beta, gamma = ode_args
    assert np.isclose(beta, expected_betas[index], rtol=0, atol=1e-14), f'Incorrect beta in solve call {index}'
    assert np.isclose(gamma, 0.15, rtol=0, atol=1e-14), f'Incorrect gamma in solve call {index}'
    derivative = np.asarray(fun(0.0, [7.0, 3.0], *ode_args), dtype=float)
    expected_derivative = np.asarray([-beta * 7.0 * 3.0, beta * 7.0 * 3.0 - gamma * 3.0])
    assert np.allclose(derivative, expected_derivative), 'The supplied ODE does not implement the required SI equations'

assert events[:4] == [
    ('seed', 42),
    ('normal', 0.30, 0.02, 500),
    ('normal', 0.28, 0.02, 500),
    ('seed', 100),
], f'Incorrect random seeding or beta sampling sequence: {events[:4]}'
choice_events = [event for event in events if event[0] == 'choice']
assert len(choice_events) == 2000, f'Expected 2000 bootstrap resampling calls, observed {len(choice_events)}'
for event in choice_events:
    assert event[1:] == (500, 500, True), f'Incorrect bootstrap resampling call: {event}'
assert wasserstein_calls == 1001, f'Expected 1001 Wasserstein calculations, observed {wasserstein_calls}'
assert any(np.isclose(q, 2.5) for q in percentile_qs), 'The 2.5th percentile was not calculated'
assert any(np.isclose(q, 97.5) for q in percentile_qs), 'The 97.5th percentile was not calculated'
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import stat
import subprocess
import pytest

VENV_PYTHON = '/home/user/sim_env/bin/python'
SCRIPT_PATH = '/home/user/analyze_epidemic.py'
RESULTS_PATH = '/home/user/results.json'

def test_sim_env_exists():
    """Verify that a genuine Python virtual environment and dependencies exist."""
    assert os.path.exists(VENV_PYTHON), f"Virtual environment python not found at {VENV_PYTHON}. Make sure you created it."
    assert os.path.isfile('/home/user/sim_env/pyvenv.cfg'), 'sim_env is missing pyvenv.cfg'

    target = os.path.realpath(VENV_PYTHON)
    assert not target.startswith('/home/user/'), 'The virtual-environment Python must resolve to a system Python executable'
    target_stat = os.stat(target)
    assert target_stat.st_uid == 0 and stat.S_ISREG(target_stat.st_mode), 'The Python interpreter is not a trusted system executable'
    with open(target, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'The virtual-environment Python target is not an ELF executable'

    probe = '''
import json, os, sys, numpy, scipy
print(json.dumps({
    "prefix": os.path.realpath(sys.prefix),
    "numpy": os.path.realpath(numpy.__file__),
    "scipy": os.path.realpath(scipy.__file__)
}))
'''
    proc = subprocess.run([VENV_PYTHON, '-I', '-c', probe], capture_output=True, text=True, check=True, timeout=30)
    info = json.loads(proc.stdout)
    venv_root = os.path.realpath('/home/user/sim_env') + os.sep
    assert info['prefix'] == os.path.realpath('/home/user/sim_env'), 'Python is not running as the required virtual environment'
    assert info['numpy'].startswith(venv_root), 'numpy is not installed in sim_env'
    assert info['scipy'].startswith(venv_root), 'scipy is not installed in sim_env'
    assert glob.glob('/home/user/sim_env/lib/python*/site-packages/numpy/**/*.so', recursive=True), 'numpy binary modules are missing'
    assert glob.glob('/home/user/sim_env/lib/python*/site-packages/scipy/**/*.so', recursive=True), 'scipy binary modules are missing'

def test_analysis_script_exists_and_executes():
    """Execute the requested artifact and audit that it performs the specified analysis."""
    assert os.path.isfile(SCRIPT_PATH), f'The required script {SCRIPT_PATH} does not exist.'
    assert not os.path.islink(SCRIPT_PATH), f'{SCRIPT_PATH} must be a regular script, not a symbolic link.'
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    proc = subprocess.run([VENV_PYTHON, '-I', '/tmp/run_epidemic_audit.py'], capture_output=True, text=True, timeout=300)
    assert proc.returncode == 0, f'The analysis script failed behavioral verification.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    assert os.path.exists(RESULTS_PATH), 'Executing analyze_epidemic.py did not generate results.json.'

def test_results_json_structure_and_values():
    """Verify that results.json exists, has the correct keys, and correct values."""
    assert os.path.exists(RESULTS_PATH), f"The output file {RESULTS_PATH} does not exist."

    with open(RESULTS_PATH, 'r') as f:
        try:
            student_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_PATH} is not valid JSON.")

    expected_keys = {"wasserstein_distance", "ci_lower", "ci_upper"}
    assert set(student_results.keys()) == expected_keys, f"Keys in results.json must be exactly {expected_keys}"

    for key in expected_keys:
        assert isinstance(student_results[key], (int, float)), f"Value for {key} must be a number."

    script = '''
import numpy as np
from scipy.integrate import solve_ivp
from scipy.stats import wasserstein_distance
import json

def epidemic_model(t, y, beta, gamma):
    S, I = y
    dSdt = -beta * S * I
    dIdt = beta * S * I - gamma * I
    return [dSdt, dIdt]

gamma = 0.15
y0 = [99.0, 1.0]
t_span = (0, 50)
t_eval = np.linspace(0, 50, 100)
np.random.seed(42)
beta_group1 = np.random.normal(0.30, 0.02, 500)
beta_group2 = np.random.normal(0.28, 0.02, 500)
D1 = np.array([np.max(solve_ivp(epidemic_model, t_span, y0, args=(b, gamma), t_eval=t_eval).y[1]) for b in beta_group1])
D2 = np.array([np.max(solve_ivp(epidemic_model, t_span, y0, args=(b, gamma), t_eval=t_eval).y[1]) for b in beta_group2])
w_dist = wasserstein_distance(D1, D2)
np.random.seed(100)
boot_dists = []
for _ in range(1000):
    idx1 = np.random.choice(len(D1), len(D1), replace=True)
    idx2 = np.random.choice(len(D2), len(D2), replace=True)
    boot_dists.append(wasserstein_distance(D1[idx1], D2[idx2]))
print(json.dumps({
    "wasserstein_distance": round(float(w_dist), 4),
    "ci_lower": round(float(np.percentile(boot_dists, 2.5)), 4),
    "ci_upper": round(float(np.percentile(boot_dists, 97.5)), 4)
}))
'''
    try:
        proc = subprocess.run([VENV_PYTHON, '-I', '-c', script], capture_output=True, text=True, check=True, timeout=300)
        expected_results = json.loads(proc.stdout)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        pytest.fail(f"Failed to compute expected results using the virtual environment: {e}")

    for key in expected_keys:
        expected_val = expected_results[key]
        student_val = student_results[key]
        assert abs(student_val - expected_val) <= 0.0001, f"Value for '{key}' is incorrect. Expected {expected_val}, got {student_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
