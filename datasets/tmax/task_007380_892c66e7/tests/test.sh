#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pathlib
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np
import pytest
from scipy.stats import wasserstein_distance

HOME = pathlib.Path('/home/user')
RESULTS = HOME / 'results.json'
PLOT = HOME / 'mcmc_fit.png'
HOOK_DIR = pathlib.Path('/tmp/verifier_hooks')
TRACE = pathlib.Path('/tmp/mcmc_trace.json')
CHAIN = pathlib.Path('/tmp/mcmc_trace.json.npy')

HOOK_SOURCE = r'''
import atexit
import inspect
import json
import os

import numpy as np
import scipy.stats as _stats
import emcee as _emcee
import matplotlib.axes as _maxes

_trace_path = os.environ.get('MCMC_TRACE_PATH', '/tmp/mcmc_trace.json')
_trace = {'seed_calls': [], 'samplers': [], 'runs': [], 'probes': [],
          'scatter_calls': [], 'plot_calls': [], 'wasserstein_calls': []}

_original_seed = np.random.seed
def _seed(*args, **kwargs):
    if args:
        try:
            _trace['seed_calls'].append(int(args[0]))
        except Exception:
            _trace['seed_calls'].append(repr(args[0]))
    else:
        _trace['seed_calls'].append(None)
    return _original_seed(*args, **kwargs)
np.random.seed = _seed

_OriginalSampler = _emcee.EnsembleSampler
_sampler_signature = inspect.signature(_OriginalSampler.__init__)

class TrackingSampler(_OriginalSampler):
    def __init__(self, nwalkers, ndim, log_prob_fn, *rest, **kw):
        _trace['samplers'].append({'nwalkers': int(nwalkers), 'ndim': int(ndim)})
        try:
            bound = _sampler_signature.bind_partial(self, nwalkers, ndim, log_prob_fn, *rest, **kw)
            lp_args = bound.arguments.get('args') or []
            lp_kwargs = bound.arguments.get('kwargs') or {}
            points = [
                [2.0, 1.0, 0.5], [2.1, 1.0, 0.5],
                [2.0, 1.1, 0.5], [2.0, 1.0, 0.6],
                [-0.1, 1.0, 0.5], [10.1, 1.0, 0.5],
                [2.0, -0.1, 0.5], [2.0, 10.1, 0.5],
                [2.0, 1.0, -0.1], [2.0, 1.0, 10.1]
            ]
            vals = []
            for point in points:
                value = log_prob_fn(np.asarray(point, dtype=float), *lp_args, **lp_kwargs)
                if isinstance(value, tuple):
                    value = value[0]
                vals.append(float(value))
            _trace['probes'].append({'points': points, 'values': vals})
        except Exception as exc:
            _trace['probes'].append({'error': repr(exc)})
        super().__init__(nwalkers, ndim, log_prob_fn, *rest, **kw)

    def run_mcmc(self, initial_state, nsteps, *args, **kwargs):
        try:
            initial = np.asarray(initial_state, dtype=float)
            initial_list = initial.tolist()
        except Exception:
            initial_list = None
        _trace['runs'].append({'nsteps': int(nsteps), 'initial': initial_list})
        result = super().run_mcmc(initial_state, nsteps, *args, **kwargs)
        try:
            chain = _OriginalSampler.get_chain(self)
            np.save(_trace_path + '.npy', np.asarray(chain, dtype=float))
        except Exception as exc:
            _trace['chain_error'] = repr(exc)
        return result

_emcee.EnsembleSampler = TrackingSampler

_original_wasserstein = _stats.wasserstein_distance
def _wasserstein(u_values, v_values, u_weights=None, v_weights=None, *args, **kwargs):
    result = _original_wasserstein(u_values, v_values, u_weights=u_weights,
                                   v_weights=v_weights, *args, **kwargs)
    try:
        _trace['wasserstein_calls'].append({
            'u_values': np.asarray(u_values, dtype=float).tolist(),
            'v_values': np.asarray(v_values, dtype=float).tolist(),
            'u_weights': None if u_weights is None else np.asarray(u_weights, dtype=float).tolist(),
            'v_weights': None if v_weights is None else np.asarray(v_weights, dtype=float).tolist(),
            'result': float(result)
        })
    except Exception:
        pass
    return result
_stats.wasserstein_distance = _wasserstein

_original_scatter = _maxes.Axes.scatter
def _scatter(self, x, y, *args, **kwargs):
    try:
        _trace['scatter_calls'].append({'x': np.asarray(x, dtype=float).tolist(),
                                        'y': np.asarray(y, dtype=float).tolist()})
    except Exception:
        pass
    return _original_scatter(self, x, y, *args, **kwargs)
_maxes.Axes.scatter = _scatter

_original_plot = _maxes.Axes.plot
def _plot(self, *args, **kwargs):
    if len(args) >= 2:
        try:
            x = np.asarray(args[0], dtype=float)
            y = np.asarray(args[1], dtype=float)
            if x.ndim == 1 and y.ndim == 1:
                _trace['plot_calls'].append({'x': x.tolist(), 'y': y.tolist()})
        except Exception:
            pass
    return _original_plot(self, *args, **kwargs)
_maxes.Axes.plot = _plot

@atexit.register
def _write_trace():
    try:
        with open(_trace_path, 'w') as handle:
            json.dump(_trace, handle)
    except Exception:
        pass
'''


def fixed_problem():
    x = np.linspace(0.0, 10.0, 100)
    f1 = np.exp(-((x - 2.0) ** 2) / (2.0 * 0.5 ** 2))
    f2 = np.exp(-((x - 6.0) ** 2) / (2.0 * 0.8 ** 2))
    f3 = np.exp(-((x - 6.1) ** 2) / (2.0 * 0.8 ** 2))
    y_true = 2.0 * f1 + 1.0 * f2 + 0.5 * f3
    rng = np.random.RandomState(42)
    y_noisy = y_true + rng.normal(0.0, 0.1, size=x.size)
    return x, f1, f2, f3, y_noisy


def run_submission():
    HOOK_DIR.mkdir(exist_ok=True)
    (HOOK_DIR / 'sitecustomize.py').write_text(HOOK_SOURCE)

    candidates = []
    for path in HOME.rglob('*.py'):
        if any(part.startswith('.') or part == '__pycache__' for part in path.parts):
            continue
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        score = sum(token in text for token in ('emcee', 'results.json', 'mcmc_fit.png', '5000'))
        candidates.append((-score, len(path.parts), str(path), path))
    candidates.sort()
    assert candidates, 'No Python script was created under /home/user'

    failures = []
    for _, _, _, script in candidates[:20]:
        for artifact in (RESULTS, PLOT, TRACE, CHAIN):
            try:
                artifact.unlink()
            except FileNotFoundError:
                pass
        env = os.environ.copy()
        env['PYTHONPATH'] = str(HOOK_DIR) + os.pathsep + env.get('PYTHONPATH', '')
        env['MCMC_TRACE_PATH'] = str(TRACE)
        env['MPLBACKEND'] = 'Agg'
        try:
            proc = subprocess.run([sys.executable, str(script)], cwd=str(script.parent),
                                  env=env, text=True, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, timeout=180)
        except subprocess.TimeoutExpired:
            failures.append(f'{script}: timed out')
            continue
        if proc.returncode == 0 and RESULTS.is_file() and PLOT.is_file() and TRACE.is_file() and CHAIN.is_file():
            return script
        failures.append(f'{script}: exit={proc.returncode}, output={proc.stdout[-1000:]}')
    pytest.fail('No submitted Python script successfully generated the required artifacts.\n' + '\n'.join(failures))


@pytest.fixture(scope='module', autouse=True)
def executed_submission():
    run_submission()


def load_results():
    with RESULTS.open() as handle:
        return json.load(handle)


def load_trace():
    with TRACE.open() as handle:
        return json.load(handle)


def test_plot_exists():
    """Keep the original plot existence assertions and validate the visualization."""
    plot_path = '/home/user/mcmc_fit.png'
    assert os.path.exists(plot_path), f'Plot file not found at {plot_path}'
    assert os.path.isfile(plot_path), f'{plot_path} is not a file'
    assert os.path.getsize(plot_path) > 5000, 'Plot is empty or implausibly small'
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert np.isfinite(image).all() and float(np.std(image)) > 0.01

    trace = load_trace()
    x, f1, f2, f3, y_noisy = fixed_problem()
    data = load_results()
    y_recon = data['A1_mean'] * f1 + data['A2_mean'] * f2 + data['A3_mean'] * f3
    assert any(np.allclose(c['x'], x, rtol=0, atol=1e-12) and
               np.allclose(c['y'], y_noisy, rtol=0, atol=1e-12)
               for c in trace['scatter_calls']), 'The noisy generated data was not plotted as scatter points'
    assert any(np.allclose(c['x'], x, rtol=0, atol=1e-12) and
               np.allclose(c['y'], y_recon, rtol=0, atol=1e-6)
               for c in trace['plot_calls']), 'The posterior-mean reconstruction was not plotted as a line'


def test_results_json_exists_and_valid():
    """Keep the original result assertions, then independently verify every value."""
    results_path = '/home/user/results.json'
    assert os.path.exists(results_path), f'Results file not found at {results_path}'
    assert os.path.isfile(results_path), f'{results_path} is not a file'
    try:
        data = load_results()
    except json.JSONDecodeError:
        pytest.fail(f'File {results_path} is not valid JSON')

    expected_keys = {'A1_mean', 'A2_mean', 'A3_mean', 'wasserstein_distance'}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), f'Missing keys in results.json. Expected: {expected_keys}, Found: {actual_keys}'
    assert actual_keys == expected_keys, 'results.json must have exactly the required keys'

    a1_mean = data['A1_mean']
    assert isinstance(a1_mean, (int, float)), 'A1_mean must be a float'
    assert abs(a1_mean - 2.0) < 0.1, f'A1_mean ({a1_mean}) is not within 0.1 of 2.0'

    a2_mean = data['A2_mean']
    a3_mean = data['A3_mean']
    assert isinstance(a2_mean, (int, float)), 'A2_mean must be a float'
    assert isinstance(a3_mean, (int, float)), 'A3_mean must be a float'
    a2_a3_sum = a2_mean + a3_mean
    assert abs(a2_a3_sum - 1.5) < 0.2, f'Sum of A2_mean and A3_mean ({a2_a3_sum}) is not within 0.2 of 1.5'

    distance = data['wasserstein_distance']
    assert isinstance(distance, (int, float)), 'wasserstein_distance must be a float'
    assert 0.0 <= distance < 0.05, f'wasserstein_distance ({distance}) is not in range [0.0, 0.05)'
    assert all(type(data[k]) is float and math.isfinite(data[k]) for k in expected_keys), 'All result values must be finite standard floats'

    trace = load_trace()
    assert trace['seed_calls'] and trace['seed_calls'][0] == 42, 'The script must begin its random generation with np.random.seed(42)'
    assert any(s['nwalkers'] == 10 and s['ndim'] == 3 for s in trace['samplers']), 'Expected an emcee sampler with 10 walkers and 3 dimensions'

    chain = np.load(CHAIN)
    assert chain.shape == (5000, 10, 3), f'Expected a (5000, 10, 3) emcee chain, got {chain.shape}'
    initial = np.asarray(trace['runs'][0]['initial'], dtype=float)
    assert initial.shape == (10, 3)
    assert np.max(np.abs(initial - np.array([2.0, 1.0, 0.5]))) < 0.01, 'Walkers were not tightly initialized around the true values'
    assert np.all((chain > 0.0) & (chain < 10.0)), 'MCMC samples violate the strict positivity/uniform prior bounds'

    posterior_means = chain[1000:].reshape(-1, 3).mean(axis=0)
    reported = np.array([a1_mean, a2_mean, a3_mean])
    assert np.allclose(reported, posterior_means, rtol=0, atol=1e-6), 'Reported amplitudes are not the means of the post-burn-in emcee samples'

    x, f1, f2, f3, y_noisy = fixed_problem()
    y_recon = reported[0] * f1 + reported[1] * f2 + reported[2] * f3
    noisy_weights = np.clip(y_noisy, 0, None)
    noisy_weights /= noisy_weights.sum()
    recon_weights = y_recon / y_recon.sum()
    expected_distance = wasserstein_distance(x, x, u_weights=noisy_weights, v_weights=recon_weights)
    assert math.isclose(distance, expected_distance, rel_tol=0, abs_tol=1e-10), 'Reported Wasserstein distance was not recomputed from the required distributions'

    assert any(np.allclose(c['u_values'], x, atol=1e-12) and
               np.allclose(c['v_values'], x, atol=1e-12) and
               np.allclose(c['u_weights'], noisy_weights, atol=1e-12) and
               np.allclose(c['v_weights'], recon_weights, atol=1e-12)
               for c in trace['wasserstein_calls']), 'scipy.stats.wasserstein_distance was not called with the required grid and normalized weights'


def test_log_posterior_matches_required_model():
    trace = load_trace()
    assert trace['probes'] and 'values' in trace['probes'][0], 'Could not exercise the submitted emcee log posterior'
    values = np.asarray(trace['probes'][0]['values'], dtype=float)
    assert np.isfinite(values[:4]).all(), 'Prior rejected valid amplitudes'
    assert np.isneginf(values[4:]).all(), 'Prior must reject amplitudes outside [0, 10]'

    x, f1, f2, f3, y = fixed_problem()
    basis = np.column_stack((f1, f2, f3))
    points = np.array([[2.0, 1.0, 0.5], [2.1, 1.0, 0.5],
                       [2.0, 1.1, 0.5], [2.0, 1.0, 0.6]])
    expected = np.array([-0.5 * np.sum(((y - basis @ p) / 0.1) ** 2) for p in points])
    assert np.allclose(values[1:4] - values[0], expected[1:4] - expected[0], rtol=0, atol=1e-6), 'The sampled log posterior does not use the required generated data and Gaussian likelihood'
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
