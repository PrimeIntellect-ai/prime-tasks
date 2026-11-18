#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_mcmc_task.py
import ast
import json
import math
import os
import stat
import subprocess
import sys
import tempfile

SCRIPT = '/home/user/validate_mcmc.py'
RESULTS = '/home/user/results.json'
PNG = '/home/user/posterior.png'

assert os.path.exists(SCRIPT), f'{SCRIPT} not found'
st = os.stat(SCRIPT)
assert stat.S_ISREG(st.st_mode), f'{SCRIPT} is not a regular file'
assert st.st_size > 0, f'{SCRIPT} is empty'
with open(SCRIPT, 'r', encoding='utf-8') as f:
    source = f.read()
ast.parse(source, filename=SCRIPT)

# Outputs must be produced by this execution, not left behind beforehand.
for path in (RESULTS, PNG):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

fd, telemetry_path = tempfile.mkstemp(prefix='mcmc_telemetry_', suffix='.json')
os.close(fd)
os.remove(telemetry_path)

runner = r'''
import atexit
import json
import os
import random
import runpy
import sys

import numpy as np
import scipy.stats

telemetry = {'normal_draws': 0, 'acceptance_draws': 0}
out_path = sys.argv[2]

def count_values(value):
    try:
        return int(np.asarray(value).size)
    except Exception:
        return 1

def record_normal(fn):
    def wrapped(*args, **kwargs):
        value = fn(*args, **kwargs)
        telemetry['normal_draws'] += count_values(value)
        return value
    return wrapped

def record_acceptance(fn):
    def wrapped(*args, **kwargs):
        value = fn(*args, **kwargs)
        telemetry['acceptance_draws'] += count_values(value)
        return value
    return wrapped

# Cover the standard NumPy module-level APIs.
for name in ('normal', 'randn', 'standard_normal'):
    if hasattr(np.random, name):
        setattr(np.random, name, record_normal(getattr(np.random, name)))
for name in ('random', 'random_sample', 'rand', 'uniform', 'binomial'):
    if hasattr(np.random, name):
        setattr(np.random, name, record_acceptance(getattr(np.random, name)))

# Cover Generator and RandomState instances without changing their results.
class RNGProxy:
    def __init__(self, obj):
        self._obj = obj
    def __getattr__(self, name):
        value = getattr(self._obj, name)
        if name in ('normal', 'standard_normal'):
            return record_normal(value)
        if name in ('random', 'random_sample', 'rand', 'uniform', 'binomial'):
            return record_acceptance(value)
        return value

_original_default_rng = np.random.default_rng
np.random.default_rng = lambda *a, **k: RNGProxy(_original_default_rng(*a, **k))
_original_random_state = np.random.RandomState
np.random.RandomState = lambda *a, **k: RNGProxy(_original_random_state(*a, **k))

# Cover common SciPy and Python-standard-library implementations.
scipy.stats.norm.rvs = record_normal(scipy.stats.norm.rvs)
scipy.stats.uniform.rvs = record_acceptance(scipy.stats.uniform.rvs)
scipy.stats.bernoulli.rvs = record_acceptance(scipy.stats.bernoulli.rvs)
random.gauss = record_normal(random.gauss)
random.normalvariate = record_normal(random.normalvariate)
random.random = record_acceptance(random.random)
random.uniform = record_acceptance(random.uniform)

def save_telemetry():
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(telemetry, f)

atexit.register(save_telemetry)
runpy.run_path(sys.argv[1], run_name='__main__')
'''

try:
    completed = subprocess.run(
        [sys.executable, '-c', runner, SCRIPT, telemetry_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
        env={**os.environ, 'MPLBACKEND': 'Agg'},
    )
except subprocess.TimeoutExpired as e:
    raise AssertionError(f'{SCRIPT} did not finish within 240 seconds') from e

assert completed.returncode == 0, (
    f'{SCRIPT} failed with exit code {completed.returncode}\n'
    f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
)
assert os.path.exists(telemetry_path), 'Sampler execution telemetry was not produced'
with open(telemetry_path, 'r', encoding='utf-8') as f:
    telemetry = json.load(f)
os.remove(telemetry_path)

# A 100,000-iteration random-walk MH run requires approximately one Normal
# proposal per transition and random acceptance decisions throughout the run.
assert telemetry.get('normal_draws', 0) >= 90000, (
    'The executed script did not generate enough Normal proposals for the required '
    '100,000-iteration Metropolis-Hastings chain'
)
assert telemetry.get('acceptance_draws', 0) >= 10000, (
    'The executed script did not perform stochastic Metropolis-Hastings acceptance decisions'
)

# Preserve the original existence checks.
assert os.path.exists(RESULTS), f'{RESULTS} not found'
assert os.path.exists(PNG), f'{PNG} not found'
assert os.path.getsize(PNG) > 0, f'{PNG} is empty'

with open(RESULTS, 'r', encoding='utf-8') as f:
    try:
        results = json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError('results.json is not valid JSON') from e

required_keys = ['analytical_mean', 'analytical_var', 'mcmc_mean', 'mcmc_var']
for key in required_keys:
    assert key in results, f"Key '{key}' missing from results.json"
assert set(results) == set(required_keys), 'results.json must contain exactly the required keys'
for key in required_keys:
    assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), f'{key} is not numeric'
    assert math.isfinite(results[key]), f'{key} is not finite'

expected_mean = 17 / 24
expected_var = 119 / 14400
assert math.isclose(results['analytical_mean'], expected_mean, abs_tol=1e-4), \
    f"Analytical mean incorrect: expected ~{expected_mean}, got {results['analytical_mean']}"
assert math.isclose(results['analytical_var'], expected_var, abs_tol=1e-4), \
    f"Analytical variance incorrect: expected ~{expected_var}, got {results['analytical_var']}"
assert math.isclose(results['mcmc_mean'], expected_mean, abs_tol=0.01), \
    f"MCMC mean out of bounds: expected ~{expected_mean}, got {results['mcmc_mean']}"
assert math.isclose(results['mcmc_var'], expected_var, abs_tol=0.002), \
    f"MCMC variance out of bounds: expected ~{expected_var}, got {results['mcmc_var']}"

# Decode the artifact as an actual PNG and reject blank/trivial images.
with open(PNG, 'rb') as f:
    assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'posterior.png is not a PNG file'
import matplotlib.image as mpimg
import numpy as np
try:
    image = np.asarray(mpimg.imread(PNG))
except Exception as e:
    raise AssertionError('posterior.png could not be decoded') from e
assert image.ndim in (2, 3), 'posterior.png has invalid image dimensions'
assert image.shape[0] >= 100 and image.shape[1] >= 100, 'posterior.png is too small to contain the required plot'
assert np.all(np.isfinite(image)), 'posterior.png contains invalid pixel values'
assert float(np.std(image.astype(float))) > 0.01, 'posterior.png appears blank or uniform'
quantized = np.clip(image.astype(float) * 255, 0, 255).astype(np.uint8)
assert np.unique(quantized.reshape(-1, quantized.shape[-1] if quantized.ndim == 3 else 1), axis=0).shape[0] > 10, \
    'posterior.png does not contain enough visual detail for the required overlaid plot'
PY_EOF

if python3 /tmp/verify_mcmc_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
