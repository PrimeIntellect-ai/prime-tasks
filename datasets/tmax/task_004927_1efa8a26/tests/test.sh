#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import subprocess
import uuid

import h5py
import numpy as np
import pytest


def test_astro_core_fixed_and_installed():
    calc_py = '/app/vendored/astro_core/astro_core/calc.py'
    assert os.path.isfile(calc_py), f"File missing: {calc_py}"

    with open(calc_py, 'r') as f:
        content = f.read()

    assert 'imprt numpy' not in content, "The deliberate typo 'imprt numpy' is still in calc.py"
    assert 'import numpy' in content, "The import statement for numpy is missing or incorrect in calc.py"

    # Try to import the package to verify it's installed correctly
    try:
        from astro_core.calc import compute_derivative
    except ImportError as e:
        pytest.fail(f"Failed to import astro_core. Make sure it is installed. Error: {e}")

    # Also exercise the installed function rather than trusting source text alone.
    x = np.array([-1.7, -0.4, 0.2, 1.6, 3.1], dtype=float)
    y = 2.3 * x**2 - 0.7 * x + 4.0
    actual = np.asarray(compute_derivative(x, y))
    expected = np.gradient(y, x)
    assert actual.shape == expected.shape
    assert np.allclose(actual, expected), "Installed compute_derivative does not behave as required"


def test_classifier_script_exists():
    script_path = '/home/user/classify.py'
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"


def test_adversarial_corpus():
    script_path = '/home/user/classify.py'
    clean_dir = '/home/user/data/clean'
    evil_dir = '/home/user/data/evil'

    assert os.path.isdir(clean_dir), f"Clean directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.h5')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.h5')]

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    failed_clean = []
    for f in clean_files:
        result = subprocess.run(['python3', script_path, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        result = subprocess.run(['python3', script_path, f], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(f))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def _array_hash(value):
    arr = np.ascontiguousarray(np.asarray(value))
    return hashlib.sha256(arr.tobytes()).hexdigest()


def _write_instrumentation(directory):
    code = r'''
import hashlib
import json
import os
import numpy as np

_TRACE = os.environ.get("CLASSIFIER_TRACE")

def _emit(event):
    if not _TRACE:
        return
    with open(_TRACE, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\\n")

def _digest(value):
    arr = np.ascontiguousarray(np.asarray(value))
    return hashlib.sha256(arr.tobytes()).hexdigest()

try:
    import astro_core
    import astro_core.calc as _astro_calc
    _real_derivative = _astro_calc.compute_derivative

    def _traced_derivative(x, y, *args, **kwargs):
        _emit({"event": "derivative", "x": _digest(x), "y": _digest(y)})
        return _real_derivative(x, y, *args, **kwargs)

    _astro_calc.compute_derivative = _traced_derivative
    astro_core.compute_derivative = _traced_derivative
except Exception as exc:
    _emit({"event": "instrumentation_error", "component": "astro_core", "error": repr(exc)})

try:
    import emcee
    import emcee.ensemble as _emcee_ensemble
    _RealSampler = emcee.EnsembleSampler

    class _TracedSampler(_RealSampler):
        def __init__(self, *args, **kwargs):
            walkers = args[0] if len(args) > 0 else kwargs.get("nwalkers")
            ndim = args[1] if len(args) > 1 else kwargs.get("ndim")
            _emit({"event": "sampler_init", "walkers": walkers, "ndim": ndim})
            super().__init__(*args, **kwargs)

        def run_mcmc(self, *args, **kwargs):
            steps = args[1] if len(args) > 1 else kwargs.get("nsteps")
            _emit({"event": "run_mcmc", "steps": steps})
            return super().run_mcmc(*args, **kwargs)

        def get_chain(self, *args, **kwargs):
            _emit({"event": "get_chain", "discard": kwargs.get("discard", 0),
                   "flat": kwargs.get("flat", False)})
            return super().get_chain(*args, **kwargs)

    emcee.EnsembleSampler = _TracedSampler
    _emcee_ensemble.EnsembleSampler = _TracedSampler
except Exception as exc:
    _emit({"event": "instrumentation_error", "component": "emcee", "error": repr(exc)})
'''
    with open(os.path.join(directory, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(code)


def test_randomized_unlabelled_inputs_and_required_libraries(tmp_path):
    script_path = '/home/user/classify.py'
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
    case_dir = tmp_path / ('inputs_' + uuid.uuid4().hex)
    hook_dir = tmp_path / ('hooks_' + uuid.uuid4().hex)
    case_dir.mkdir()
    hook_dir.mkdir()
    _write_instrumentation(str(hook_dir))

    cases = []

    # Positive-curvature, low-derivative signal: both conditions hold.
    x = np.linspace(-2.0, 2.0, 101)
    a = rng.uniform(1.8, 3.8)
    b = rng.uniform(-2.0, 2.0)
    c = rng.uniform(-5.0, 5.0)
    y = a*x*x + b*x + c + rng.normal(0.0, 0.02, x.size)
    cases.append((x, y))

    # Negative-curvature, low-derivative signal: only condition B fails.
    x = np.linspace(-2.0, 2.0, 103)
    a = -rng.uniform(1.8, 3.8)
    b = rng.uniform(-2.0, 2.0)
    c = rng.uniform(-5.0, 5.0)
    y = a*x*x + b*x + c + rng.normal(0.0, 0.02, x.size)
    cases.append((x, y))

    # Positive curvature with a randomly placed spike: condition A fails.
    x = np.linspace(-2.0, 2.0, 99)
    y = 1.5*x*x + 0.4*x + 2.0
    y[rng.integers(20, 79)] += rng.uniform(40.0, 70.0)
    cases.append((x, y))

    # Smooth positive curvature whose derivative exceeds the threshold.
    x = np.linspace(0.0, 5.0, 105)
    a = rng.uniform(6.5, 8.0)
    y = a*x*x + rng.uniform(-1.0, 1.0)*x + rng.uniform(-3.0, 3.0)
    cases.append((x, y))

    for x, y in cases:
        path = case_dir / (uuid.uuid4().hex + '.h5')
        with h5py.File(path, 'w') as f:
            f.create_dataset('time', data=x)
            f.create_dataset('flux', data=y)

        # Independently derive the two expected conditions from the generated data.
        max_derivative = float(np.max(np.abs(np.gradient(y, x))))
        fitted_a = float(np.polyfit(x, y, 2)[0])
        assert abs(fitted_a) > 1.0, "Generated posterior-sign test was not well separated"
        expected = 0 if max_derivative < 50.0 and fitted_a > 0.0 else 1

        trace = tmp_path / (uuid.uuid4().hex + '.jsonl')
        env = os.environ.copy()
        env['PYTHONPATH'] = str(hook_dir) + os.pathsep + env.get('PYTHONPATH', '')
        env['CLASSIFIER_TRACE'] = str(trace)
        result = subprocess.run(
            ['python3', script_path, str(path)],
            cwd=str(case_dir), env=env, capture_output=True, timeout=120
        )
        assert result.returncode == expected, (
            f"Wrong classification for an unlabelled generated HDF5 input: "
            f"expected {expected}, got {result.returncode}; stderr={result.stderr.decode(errors='replace')}"
        )

        assert trace.is_file(), "Classifier did not execute under verification instrumentation"
        events = [json.loads(line) for line in trace.read_text().splitlines() if line.strip()]
        assert not [e for e in events if e.get('event') == 'instrumentation_error'], events

        derivative_calls = [e for e in events if e.get('event') == 'derivative']
        assert any(e.get('x') == _array_hash(x) and e.get('y') == _array_hash(y)
                   for e in derivative_calls), (
            "Classifier did not call astro_core.compute_derivative with the HDF5 time and flux data"
        )

        # MCMC may be skipped after an already-failing derivative check, but it is
        # required whenever Condition A passes and Condition B must be evaluated.
        if max_derivative < 50.0:
            sampler_inits = [e for e in events if e.get('event') == 'sampler_init']
            sampler_runs = [e for e in events if e.get('event') == 'run_mcmc']
            assert any(e.get('walkers') == 32 and e.get('ndim') == 3 for e in sampler_inits), (
                "Classifier did not construct an emcee sampler with 32 walkers and 3 parameters"
            )
            assert any(e.get('steps') == 500 for e in sampler_runs), (
                "Classifier did not run the emcee sampler for 500 steps"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
