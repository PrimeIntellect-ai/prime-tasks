#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "h5py:h5py"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import h5py
import numpy as np
import pytest
from scipy.io import wavfile
from scipy.optimize import least_squares

H5_PATH = '/home/user/model_results.h5'
CLEAN_SIGNAL_PATH = '/tests/s_clean.npy'
WAV_PATH = '/app/signal.wav'
REQUIRED = ['/f1', '/f2', '/A1', '/A2', '/alpha1', '/alpha2',
            '/f1_std', '/f2_std', '/F_stat']


def read_results():
    values = {}
    with h5py.File(H5_PATH, 'r') as h5:
        for key in REQUIRED:
            assert key in h5, f'Dataset {key} is missing from the HDF5 file.'
            ds = h5[key]
            assert np.issubdtype(ds.dtype, np.floating), f'{key} must have a floating-point datatype.'
            arr = np.asarray(ds)
            assert arr.size == 1, f'{key} must be a scalar dataset.'
            values[key] = float(arr.reshape(-1)[0])
            assert np.isfinite(values[key]), f'{key} must be finite.'
    return values


def model2(p, t):
    A1, A2, a1, a2, f1, f2 = p
    return (A1 * np.exp(-a1*t) * np.sin(2*np.pi*f1*t) +
            A2 * np.exp(-a2*t) * np.sin(2*np.pi*f2*t))


def jac2(p, t):
    A1, A2, a1, a2, f1, f2 = p
    e1, e2 = np.exp(-a1*t), np.exp(-a2*t)
    s1, s2 = np.sin(2*np.pi*f1*t), np.sin(2*np.pi*f2*t)
    c1, c2 = np.cos(2*np.pi*f1*t), np.cos(2*np.pi*f2*t)
    return np.column_stack((e1*s1, e2*s2, -A1*t*e1*s1, -A2*t*e2*s2,
                            A1*e1*c1*(2*np.pi*t), A2*e2*c2*(2*np.pi*t)))


def canonical_results(v):
    components = [
        (v['/f1'], v['/A1'], v['/alpha1'], v['/f1_std']),
        (v['/f2'], v['/A2'], v['/alpha2'], v['/f2_std'])
    ]
    components.sort(key=lambda x: x[0])
    (f1, A1, a1, s1), (f2, A2, a2, s2) = components
    return np.array([A1, A2, a1, a2, f1, f2], dtype=float), np.array([s1, s2])


def load_observed():
    fs, raw = wavfile.read(WAV_PATH)
    assert fs == 8000 and raw.ndim == 1 and len(raw) == 8000
    # The WAV generator encoded one model unit as half of the signed-16-bit range.
    y = raw.astype(np.float64) / (32767.0 / 2.0)
    return fs, y


def best_one_component_rss(t, y):
    def fun(p):
        A, alpha, freq = p
        return A*np.exp(-alpha*t)*np.sin(2*np.pi*freq*t) - y

    def jac(p):
        A, alpha, freq = p
        e = np.exp(-alpha*t)
        s = np.sin(2*np.pi*freq*t)
        c = np.cos(2*np.pi*freq*t)
        return np.column_stack((e*s, -A*t*e*s, A*e*c*(2*np.pi*t)))

    best = np.inf
    for freq in np.linspace(432.0, 452.0, 11):
        for alpha in (0.5, 2.0, 5.0):
            r = least_squares(fun, [0.8, alpha, freq], jac=jac,
                              bounds=([-3.0, 0.0, 400.0], [3.0, 20.0, 480.0]),
                              max_nfev=150, xtol=1e-11, ftol=1e-11, gtol=1e-11)
            best = min(best, float(np.dot(r.fun, r.fun)))
    return best


def reference_bootstrap_stds(p, t, y):
    fitted = model2(p, t)
    residual = y - fitted
    residual = residual - residual.mean()
    midpoint = (p[4] + p[5]) / 2.0
    separation = p[5] - p[4]
    assert separation > 0.2, 'The fitted frequencies are not distinguishable.'

    lower = np.array([-3.0, -3.0, 0.0, 0.0,
                      max(350.0, p[4] - 3.0), midpoint])
    upper = np.array([3.0, 3.0, 20.0, 20.0,
                      midpoint, min(550.0, p[5] + 3.0)])
    assert np.all(p > lower) and np.all(p < upper), 'Parameters are unsuitable for residual bootstrap.'

    rng = np.random.default_rng(20250308)
    frequencies = []
    for _ in range(100):
        synthetic = fitted + rng.choice(residual, size=residual.size, replace=True)
        result = least_squares(lambda q: model2(q, t) - synthetic, p,
                               jac=lambda q: jac2(q, t), bounds=(lower, upper),
                               max_nfev=60, xtol=2e-9, ftol=2e-9, gtol=2e-9)
        frequencies.append(result.x[4:6])
    return np.std(np.asarray(frequencies), axis=0, ddof=1)


def test_complete_results_and_reconstruction():
    assert os.path.isfile(H5_PATH), f'The output file {H5_PATH} does not exist.'
    assert os.path.isfile(CLEAN_SIGNAL_PATH), 'Verification oracle is missing.'
    values = read_results()
    p, _ = canonical_results(values)

    clean = np.load(CLEAN_SIGNAL_PATH)
    t = np.arange(clean.size, dtype=float) / 8000.0
    reconstruction = model2(p, t)
    mse = float(np.mean((clean - reconstruction)**2))
    assert mse < 0.05, f'MSE of reconstructed signal is {mse:.5f}, which is not < 0.05'


def test_f_statistic_and_bootstrap_statistics():
    values = read_results()
    p, submitted_stds = canonical_results(values)
    assert np.all(submitted_stds > 0.0), 'Bootstrap standard deviations must be positive.'

    fs, y = load_observed()
    t = np.arange(y.size, dtype=float) / fs
    residual2 = y - model2(p, t)
    rss2 = float(np.dot(residual2, residual2))
    rss1 = best_one_component_rss(t, y)
    n = y.size
    expected_f = ((rss1 - rss2) / (6 - 3)) / (rss2 / (n - 6))
    assert expected_f > 0.0, 'The submitted two-component fit does not improve on the baseline.'

    submitted_f = values['/F_stat']
    relative_f_error = abs(submitted_f - expected_f) / expected_f
    assert submitted_f > 0.0 and relative_f_error <= 0.25, \
        f'F_stat={submitted_f} is inconsistent with the fitted one- and two-component residual sums of squares (expected about {expected_f}).'

    reference_stds = reference_bootstrap_stds(p, t, y)
    assert np.all(reference_stds > 0.0) and np.all(np.isfinite(reference_stds))
    ratios = submitted_stds / reference_stds
    assert np.all((ratios >= 0.2) & (ratios <= 5.0)), \
        f'Frequency standard deviations {submitted_stds.tolist()} are inconsistent with a 100-run residual bootstrap (reference {reference_stds.tolist()}).'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
