#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import traceback

HOME = pathlib.Path('/home/user')
OBS = HOME / 'observed_signal.csv'
REF = HOME / 'reference.csv'
RESULTS = HOME / 'results.json'
EVENTS = pathlib.Path('/tmp/emcee_audit_events.jsonl')


def load_results():
    assert RESULTS.exists(), f'File missing: {RESULTS}'
    assert RESULTS.is_file(), f'Not a file: {RESULTS}'
    try:
        with RESULTS.open() as f:
            res = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULTS} is not valid JSON') from exc

    expected_keys = {
        'dominant_frequency_fft',
        'closest_reference_name',
        'mcmc_mean_A',
        'mcmc_mean_f',
        'mcmc_mean_phi',
        'mcmc_mean_sigma',
    }
    missing = expected_keys - set(res)
    assert not missing, f'Missing keys in results.json: {missing}'
    return res


def check_original_assertions():
    res = load_results()
    assert res['closest_reference_name'] == 'Gamma_Burst', (
        f"Incorrect reference matching: {res['closest_reference_name']} != Gamma_Burst"
    )
    assert abs(res['dominant_frequency_fft'] - 3.14) < 0.05, (
        f"FFT freq {res['dominant_frequency_fft']} out of bounds"
    )
    assert abs(res['mcmc_mean_A'] - 2.5) < 0.1, (
        f"MCMC A {res['mcmc_mean_A']} out of bounds"
    )
    assert abs(res['mcmc_mean_f'] - 3.1415) < 0.05, (
        f"MCMC f {res['mcmc_mean_f']} out of bounds"
    )
    phi = res['mcmc_mean_phi']
    assert abs(phi - 1.0) < 0.2 or abs(phi - (1.0 + 2 * 3.1415926535)) < 0.2, (
        f'MCMC phi {phi} out of bounds'
    )
    assert abs(res['mcmc_mean_sigma'] - 0.5) < 0.1, (
        f"MCMC sigma {res['mcmc_mean_sigma']} out of bounds"
    )


def find_script():
    candidates = []
    preferred = HOME / 'analyze.py'
    if preferred.is_file():
        candidates.append(preferred)
    for path in sorted(HOME.glob('*.py')):
        if path not in candidates and path.is_file():
            candidates.append(path)

    matches = []
    for path in candidates:
        try:
            source = path.read_text()
            compile(source, str(path), 'exec')
        except (OSError, UnicodeError, SyntaxError):
            continue
        if 'observed_signal.csv' in source and 'results.json' in source and 'emcee' in source:
            matches.append((path, source))

    assert matches, 'No executable Python analysis script using the CSV input, emcee, and results.json was found'
    path, source = matches[0]
    assert '500' in source, 'Analysis script does not contain the required 500-step burn-in'
    return path


def write_instrumentation(directory):
    code = r'''
import json
import os
try:
    import emcee
    _RealSampler = emcee.EnsembleSampler
    _event_path = os.environ.get('EMCEE_AUDIT_LOG')

    def _log(event):
        if not _event_path:
            return
        try:
            with open(_event_path, 'a') as f:
                f.write(json.dumps(event) + '\n')
        except Exception:
            pass

    class AuditedEnsembleSampler(_RealSampler):
        def __init__(self, nwalkers, ndim, *args, **kwargs):
            _log({'event': 'init', 'nwalkers': int(nwalkers), 'ndim': int(ndim)})
            super().__init__(nwalkers, ndim, *args, **kwargs)

        def run_mcmc(self, initial_state, nsteps, **kwargs):
            _log({'event': 'run_mcmc', 'nsteps': int(nsteps)})
            return super().run_mcmc(initial_state, nsteps, **kwargs)

        def sample(self, *args, **kwargs):
            iterations = kwargs.get('iterations')
            if iterations is not None:
                _log({'event': 'sample', 'iterations': int(iterations)})
            return super().sample(*args, **kwargs)

        def get_chain(self, *args, **kwargs):
            _log({'event': 'get_chain', 'discard': int(kwargs.get('discard', 0)),
                  'flat': bool(kwargs.get('flat', False))})
            return super().get_chain(*args, **kwargs)

    emcee.EnsembleSampler = AuditedEnsembleSampler
except Exception:
    pass
'''
    (pathlib.Path(directory) / 'sitecustomize.py').write_text(code)


def make_challenge():
    import numpy as np
    import pandas as pd

    seed = int.from_bytes(os.urandom(8), 'little')
    rng = np.random.default_rng(seed)
    t = np.linspace(0.0, 10.0, 1000, endpoint=False)
    true_A = rng.uniform(1.8, 3.8)
    true_f = rng.uniform(1.8, 4.1)
    true_phi = rng.uniform(0.6, 2.4)
    true_sigma = rng.uniform(0.30, 0.65)
    y = true_A * np.sin(2 * np.pi * true_f * t + true_phi)
    y += rng.normal(0.0, true_sigma, size=t.size)

    dt = float(np.median(np.diff(t)))
    freqs = np.fft.rfftfreq(t.size, d=dt)
    spectrum = np.abs(np.fft.rfft(y))
    spectrum[0] = 0.0
    f_peak = float(freqs[int(np.argmax(spectrum))])

    token = os.urandom(5).hex()
    target_name = f'Target_{token}'
    references = pd.DataFrame({
        'name': [f'Low_{token}', target_name, f'High_{token}', f'Far_{token}'],
        'frequency': [f_peak - 0.73, f_peak + 0.007, f_peak + 0.68, f_peak + 1.31],
    })
    closest_name = str(references.iloc[(references['frequency'] - f_peak).abs().argmin()]['name'])

    pd.DataFrame({'t': t, 'y': y}).to_csv(OBS, index=False)
    references.to_csv(REF, index=False)

    # Independently derive sinusoid estimates from the generated samples. For each
    # trial frequency, solve the linear sine/cosine coefficients by least squares.
    best = None
    for f in np.linspace(f_peak - 0.20, f_peak + 0.20, 3201):
        s = np.sin(2 * np.pi * f * t)
        c = np.cos(2 * np.pi * f * t)
        design = np.column_stack((s, c))
        coef, _, _, _ = np.linalg.lstsq(design, y, rcond=None)
        residual = y - design @ coef
        rss = float(residual @ residual)
        if best is None or rss < best[0]:
            best = (rss, float(f), float(coef[0]), float(coef[1]))

    rss, fit_f, sin_coef, cos_coef = best
    fit_A = math.hypot(sin_coef, cos_coef)
    fit_phi = math.atan2(cos_coef, sin_coef) % (2 * math.pi)
    fit_sigma = math.sqrt(rss / t.size)
    return {
        'f_peak': f_peak,
        'closest_name': closest_name,
        'A': fit_A,
        'f': fit_f,
        'phi': fit_phi,
        'sigma': fit_sigma,
    }


def circular_distance(a, b):
    return abs((a - b + math.pi) % (2 * math.pi) - math.pi)


def check_challenge(expected):
    res = load_results()
    for key in ('dominant_frequency_fft', 'mcmc_mean_A', 'mcm_mean_f',
                'mcmc_mean_f', 'mcmc_mean_phi', 'mcmc_mean_sigma'):
        if key in res and key != 'mcm_mean_f':
            assert isinstance(res[key], (int, float)) and not isinstance(res[key], bool), f'{key} is not numeric'
            assert math.isfinite(float(res[key])), f'{key} is not finite'

    assert abs(float(res['dominant_frequency_fft']) - expected['f_peak']) < 0.051, (
        'Dominant FFT frequency was not recomputed for the verification signal'
    )
    assert res['closest_reference_name'] == expected['closest_name'], (
        'Closest reference name was not recomputed from reference.csv'
    )
    assert abs(float(res['mcmc_mean_A']) - expected['A']) < 0.40, 'MCMC amplitude is inconsistent with the verification signal'
    assert abs(float(res['mcmc_mean_f']) - expected['f']) < 0.08, 'MCMC frequency is inconsistent with the verification signal'
    assert circular_distance(float(res['mcmc_mean_phi']), expected['phi']) < 0.45, 'MCMC phase is inconsistent with the verification signal'
    assert abs(float(res['mcmc_mean_sigma']) - expected['sigma']) < 0.20, 'MCMC noise is inconsistent with the verification signal'


def check_emcee_events():
    assert EVENTS.is_file(), 'The executed analysis did not use the instrumented emcee sampler'
    events = []
    for line in EVENTS.read_text().splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    assert any(e.get('event') == 'init' and e.get('nwalkers') == 16 and e.get('ndim') == 4 for e in events), (
        'emcee.EnsembleSampler was not run with 16 walkers and 4 parameters'
    )
    assert any((e.get('event') == 'run_mcmc' and e.get('nsteps') == 2000) or
               (e.get('event') == 'sample' and e.get('iterations') == 2000) for e in events), (
        'The emcee sampler was not run for 2000 steps'
    )


def main():
    original_obs = OBS.read_bytes()
    original_ref = REF.read_bytes()
    original_results = RESULTS.read_bytes() if RESULTS.exists() and RESULTS.is_file() else None
    try:
        # Preserve every assertion made by the original verifier.
        check_original_assertions()
        script = find_script()
        expected = make_challenge()
        if RESULTS.exists():
            RESULTS.unlink()
        if EVENTS.exists():
            EVENTS.unlink()

        with tempfile.TemporaryDirectory(prefix='emcee-audit-') as audit_dir:
            write_instrumentation(audit_dir)
            env = os.environ.copy()
            env['EMCEE_AUDIT_LOG'] = str(EVENTS)
            old_pythonpath = env.get('PYTHONPATH', '')
            env['PYTHONPATH'] = audit_dir + (os.pathsep + old_pythonpath if old_pythonpath else '')
            completed = subprocess.run(
                [sys.executable, str(script)], cwd=str(HOME), env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                timeout=420,
            )
        assert completed.returncode == 0, 'Analysis script failed when executed:\n' + completed.stdout[-4000:]
        check_emcee_events()
        check_challenge(expected)
    finally:
        OBS.write_bytes(original_obs)
        REF.write_bytes(original_ref)
        if original_results is None:
            if RESULTS.exists():
                RESULTS.unlink()
        else:
            RESULTS.write_bytes(original_results)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
