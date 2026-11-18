#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import h5py
import numpy as np

DATA_PATH = Path('/home/user/data/lightcurves.h5')
RESULT_PATH = Path('/home/user/results/params.json')


def write_dataset(path, time, flux):
    path.parent.mkdir(parents=True, exist_ok=True)
    with h5py.File(path, 'w') as f:
        f.create_dataset('time', data=time)
        f.create_dataset('flux', data=flux)


def make_original_dataset(path):
    np.random.seed(123)
    time = np.linspace(0, 10, 1000)
    flux = np.ones((100, 1000)) + np.random.normal(0, 0.005, (100, 1000))
    flux[41] = 1.0 - 0.05 * np.exp(-0.5 * ((time - 4.5) / 0.3) ** 2) + np.random.normal(0, 0.005, 1000)
    write_dataset(path, time, flux)


def make_challenge_dataset(path):
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
    time = np.linspace(0, 10, 1000)
    flux = np.ones((100, 1000)) + rng.normal(0, 0.005, (100, 1000))
    truth = {
        'A': float(rng.uniform(0.075, 0.115)),
        't0': float(rng.uniform(4.42, 4.58)),
        'sigma': float(rng.uniform(0.27, 0.38)),
    }
    flux[41] = 1.0 - truth['A'] * np.exp(-0.5 * ((time - truth['t0']) / truth['sigma']) ** 2) + rng.normal(0, 0.005, 1000)
    write_dataset(path, time, flux)
    return truth


def find_scripts():
    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        try:
            if not path.is_file() or path.is_symlink() or path.stat().st_size > 1_000_000:
                continue
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        if 'params.json' in text or ('/home/user/results' in text and 'json' in text):
            candidates.append(path)
    return sorted(candidates)


def install_instrumentation(directory):
    code = r'''
import json
import os
import numpy as np

try:
    import emcee

    _trace = os.environ.get('MCMC_TRACE_FILE')
    _orig_init = emcee.EnsembleSampler.__init__
    _orig_run = emcee.EnsembleSampler.run_mcmc
    _orig_get_chain = emcee.EnsembleSampler.get_chain

    def _write(event):
        if _trace:
            with open(_trace, 'a') as f:
                f.write(json.dumps(event) + '\n')

    def _init(self, nwalkers, ndim, *args, **kwargs):
        result = _orig_init(self, nwalkers, ndim, *args, **kwargs)
        self._verifier_nwalkers = int(nwalkers)
        self._verifier_ndim = int(ndim)
        _write({'event': 'init', 'nwalkers': int(nwalkers), 'ndim': int(ndim)})
        return result

    def _run(self, initial_state, nsteps, *args, **kwargs):
        try:
            initial = np.asarray(initial_state, dtype=float).tolist()
        except Exception:
            initial = None
        result = _orig_run(self, initial_state, nsteps, *args, **kwargs)
        event = {
            'event': 'run',
            'nwalkers': getattr(self, '_verifier_nwalkers', None),
            'ndim': getattr(self, '_verifier_ndim', None),
            'nsteps': int(nsteps),
            'initial': initial,
        }
        try:
            required = _orig_get_chain(self, discard=200, flat=True)
            event['required_mean'] = np.mean(required, axis=0).astype(float).tolist()
        except Exception as exc:
            event['summary_error'] = repr(exc)
        _write(event)
        return result

    emcee.EnsembleSampler.__init__ = _init
    emcee.EnsembleSampler.run_mcmc = _run
except Exception:
    pass
'''
    Path(directory, 'sitecustomize.py').write_text(code)


def read_result():
    assert RESULT_PATH.exists(), f'Expected results file {RESULT_PATH} does not exist.'
    assert RESULT_PATH.is_file(), f'{RESULT_PATH} is not a valid file.'
    try:
        with RESULT_PATH.open() as f:
            data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f'File {RESULT_PATH} does not contain valid JSON.')
    for key in ['A', 't0', 'sigma']:
        assert key in data, f"Key '{key}' is missing from the results JSON."
        assert isinstance(data[key], (int, float)), f"Value for '{key}' must be a number."
        assert np.isfinite(data[key]), f"Value for '{key}' must be finite."
    return data


def validate_trace(trace_path, result):
    events = []
    if trace_path.exists():
        for line in trace_path.read_text().splitlines():
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    expected_initial = np.array([0.1, 5.0, 0.5]) + 1e-4 * np.random.RandomState(42).randn(32, 3)
    valid_runs = []
    for event in events:
        if event.get('event') != 'run':
            continue
        if event.get('nwalkers') != 32 or event.get('ndim') != 3 or event.get('nsteps') != 1000:
            continue
        try:
            initial = np.asarray(event['initial'], dtype=float)
            required_mean = np.asarray(event['required_mean'], dtype=float)
        except Exception:
            continue
        if initial.shape != (32, 3) or required_mean.shape != (3,):
            continue
        if not np.allclose(initial, expected_initial, rtol=0, atol=1e-12):
            continue
        submitted = np.array([result['A'], result['t0'], result['sigma']], dtype=float)
        if np.allclose(submitted, required_mean, rtol=0, atol=1e-4):
            valid_runs.append(event)

    assert valid_runs, (
        'No compliant emcee run was observed. The script must use 32 walkers, the specified '
        'seeded initialization, 1000 steps, and save the mean of the chain after discarding 200 steps.'
    )


def run_script(script, instrument_dir, trace_path):
    RESULT_PATH.unlink(missing_ok=True)
    trace_path.write_text('')
    trace_path.chmod(0o666)
    env = os.environ.copy()
    env['PYTHONPATH'] = str(instrument_dir) + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['MCMC_TRACE_FILE'] = str(trace_path)
    proc = subprocess.run(
        ['runuser', '-u', 'user', '--', 'python3', str(script)],
        cwd='/home/user', env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=180,
    )
    assert proc.returncode == 0, f'Script {script} failed:\n{proc.stdout}\n{proc.stderr}'
    result = read_result()
    validate_trace(trace_path, result)
    return result


def test_pipeline_executes_and_uses_lightcurve():
    scripts = find_scripts()
    assert scripts, 'No Python pipeline script that writes params.json was found under /home/user.'

    backup_dir = Path(tempfile.mkdtemp(prefix='verifier_backup_'))
    backup_data = backup_dir / 'lightcurves.h5'
    if DATA_PATH.exists():
        shutil.copy2(DATA_PATH, backup_data)

    instrument_dir = Path(tempfile.mkdtemp(prefix='mcmc_instrument_'))
    install_instrumentation(instrument_dir)
    trace_path = instrument_dir / 'trace.jsonl'
    original_result_bytes = None

    try:
        make_original_dataset(DATA_PATH)
        selected = None
        original = None
        errors = []
        for script in scripts:
            try:
                original = run_script(script, instrument_dir, trace_path)
                selected = script
                break
            except Exception as exc:
                errors.append(f'{script}: {exc}')
        assert selected is not None, 'No discovered Python script produced a valid MCMC result.\n' + '\n'.join(errors)

        # Preserve every assertion made by the original verifier.
        assert 0.045 < original['A'] < 0.055, f"Value for A ({original['A']}) is outside the expected range (0.045 - 0.055)."
        assert 4.45 < original['t0'] < 4.55, f"Value for t0 ({original['t0']}) is outside the expected range (4.45 - 4.55)."
        assert 0.25 < original['sigma'] < 0.35, f"Value for sigma ({original['sigma']}) is outside the expected range (0.25 - 0.35)."
        original_result_bytes = RESULT_PATH.read_bytes()

        truth = make_challenge_dataset(DATA_PATH)
        challenged = run_script(selected, instrument_dir, trace_path)
        assert abs(challenged['A'] - truth['A']) < 0.008, 'A does not track the challenged index-41 lightcurve.'
        assert abs(challenged['t0'] - truth['t0']) < 0.02, 't0 does not track the challenged index-41 lightcurve.'
        assert abs(challenged['sigma'] - truth['sigma']) < 0.02, 'sigma does not track the challenged index-41 lightcurve.'
    finally:
        if backup_data.exists():
            shutil.copy2(backup_data, DATA_PATH)
        if original_result_bytes is not None:
            RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
            RESULT_PATH.write_bytes(original_result_bytes)
        shutil.rmtree(backup_dir, ignore_errors=True)
        shutil.rmtree(instrument_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
