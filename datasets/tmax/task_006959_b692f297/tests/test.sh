#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from scipy.optimize import curve_fit
from scipy.stats import kstest, ttest_1samp

HOME = Path('/home/user')
CSV_PATH = HOME / 'reactor_data.csv'
JSON_PATH = HOME / 'analysis_results.json'
PLOT_PATH = HOME / 'fit_plot.png'
EXPECTED_KEYS = {'valid_trials_count', 'mean_k', 'ks_statistic', 'ttest_pvalue'}


def generate_original_data():
    np.random.seed(42)
    data = []
    times = np.linspace(0, 5, 50)
    for i in range(1, 81):
        k = np.random.normal(0.55, 0.05)
        A = np.random.normal(2.0, 0.1)
        conc = A * np.exp(-k * times) + np.random.normal(0, 0.05, len(times))
        for t, c in zip(times, conc):
            data.append({'trial_id': int(i), 'time': float(t), 'concentration': float(c)})
    for i in range(81, 101):
        conc = 2.0 * np.exp(-0.5 * times) + np.random.normal(0, 0.05, len(times))
        conc[-10:] += np.linspace(0, 50, 10)
        for t, c in zip(times, conc):
            data.append({'trial_id': int(i), 'time': float(t), 'concentration': float(c)})
    return pd.DataFrame(data)


def fit_expected(df):
    bad_ids = set(df.loc[df['concentration'] > 15.0, 'trial_id'])
    valid = df.loc[~df['trial_id'].isin(bad_ids)].copy()
    amplitudes = []
    rates = []

    def model(t, A, k):
        return A * np.exp(-k * t)

    for _, group in valid.groupby('trial_id'):
        x = group['time'].to_numpy(dtype=float)
        y = group['concentration'].to_numpy(dtype=float)
        params, _ = curve_fit(model, x, y, p0=[max(float(np.max(y)), 0.1), 0.5], maxfev=20000)
        amplitudes.append(float(params[0]))
        rates.append(float(params[1]))

    rates = np.asarray(rates)
    ks = kstest(rates, 'norm', args=(0.55, 0.05)).statistic
    pvalue = ttest_1samp(rates, 0.50).pvalue
    expected = {
        'valid_trials_count': int(valid['trial_id'].nunique()),
        'mean_k': round(float(np.mean(rates)), 4),
        'ks_statistic': round(float(ks), 4),
        'ttest_pvalue': round(float(pvalue), 4),
    }
    return expected, valid, float(np.mean(amplitudes)), float(np.mean(rates))


def install_plot_hook():
    hook_dir = Path('/tmp/reactor_plot_hook')
    hook_dir.mkdir(exist_ok=True)
    (hook_dir / 'sitecustomize.py').write_text(r'''
import atexit
import json
import os
_records = {'scatter': [], 'lines': []}
try:
    import numpy as np
    from matplotlib.axes import Axes
    _old_scatter = Axes.scatter
    _old_plot = Axes.plot

    def _flat(v):
        return np.asarray(v, dtype=float).reshape(-1).tolist()

    def scatter(self, x, y, *args, **kwargs):
        result = _old_scatter(self, x, y, *args, **kwargs)
        try:
            _records['scatter'].append({'x': _flat(x), 'y': _flat(y)})
        except Exception:
            pass
        return result

    def plot(self, *args, **kwargs):
        result = _old_plot(self, *args, **kwargs)
        try:
            for line in result:
                _records['lines'].append({
                    'x': _flat(line.get_xdata()),
                    'y': _flat(line.get_ydata()),
                    'linestyle': str(line.get_linestyle()),
                })
        except Exception:
            pass
        return result

    Axes.scatter = scatter
    Axes.plot = plot
except Exception:
    pass

@atexit.register
def _save_records():
    path = os.environ.get('REACTOR_PLOT_LOG')
    if path:
        try:
            with open(path, 'w') as f:
                json.dump(_records, f)
        except Exception:
            pass
''')
    return hook_dir


def run_script(script, dataframe, hook_dir, tag):
    dataframe.to_csv(CSV_PATH, index=False)
    for artifact in (JSON_PATH, PLOT_PATH):
        if artifact.exists():
            artifact.unlink()
    log_path = Path('/tmp') / ('reactor_plot_' + tag + '.json')
    if log_path.exists():
        log_path.unlink()
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    env['REACTOR_PLOT_LOG'] = str(log_path)
    old_pythonpath = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = str(hook_dir) + (os.pathsep + old_pythonpath if old_pythonpath else '')
    completed = subprocess.run(
        [sys.executable, str(script)], cwd=str(HOME), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180
    )
    assert completed.returncode == 0, (
        f'{script} exited with status {completed.returncode}. stderr: {completed.stderr[-2000:]}'
    )
    assert log_path.is_file(), 'The analysis script did not complete plot instrumentation.'
    with log_path.open() as f:
        plot_calls = json.load(f)
    return plot_calls


def validate_outputs(df, plot_calls, require_original_ranges=False):
    expected, valid, mean_A, mean_k_unrounded = fit_expected(df)

    # Preserve and strengthen the original artifact assertions.
    assert PLOT_PATH.is_file(), f'Visualization plot not found at {PLOT_PATH}.'
    assert PLOT_PATH.stat().st_size > 0, 'Visualization plot file is empty.'
    assert PLOT_PATH.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n', 'fit_plot.png is not a PNG file.'
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, 'Plot is not a valid image.'

    assert JSON_PATH.is_file(), f'Results JSON not found at {JSON_PATH}.'
    with JSON_PATH.open() as f:
        results = json.load(f)
    actual_keys = set(results.keys())
    assert EXPECTED_KEYS.issubset(actual_keys), f'JSON is missing keys. Expected {EXPECTED_KEYS}, found {actual_keys}.'
    assert actual_keys == EXPECTED_KEYS, f'JSON must contain exactly {EXPECTED_KEYS}, found {actual_keys}.'

    valid_trials = results.get('valid_trials_count')
    assert isinstance(valid_trials, int), f"'valid_trials_count' must be an integer, got {type(valid_trials)}."
    for key in ('mean_k', 'ks_statistic', 'ttest_pvalue'):
        assert isinstance(results.get(key), (int, float)), f"'{key}' must be numeric, got {type(results.get(key))}."

    assert results == expected, f'Incorrect statistical results. Expected {expected}, got {results}.'

    if require_original_ranges:
        assert valid_trials == 80, f'Expected 80 valid trials, got {valid_trials}.'
        assert 0.54 < results['mean_k'] < 0.57, f"'mean_k' out of expected bounds (0.54, 0.57): {results['mean_k']}"
        assert 0.05 < results['ks_statistic'] < 0.08, f"'ks_statistic' out of expected bounds (0.05, 0.08): {results['ks_statistic']}"
        assert results['ttest_pvalue'] < 0.01, f"'ttest_pvalue' out of expected bounds (< 0.01): {results['ttest_pvalue']}"

    scatter = plot_calls.get('scatter', [])
    assert scatter, 'No scatter plot call was made.'
    observed_parts = []
    for call in scatter:
        x = np.asarray(call.get('x', []), dtype=float)
        y = np.asarray(call.get('y', []), dtype=float)
        if len(x) == len(y):
            observed_parts.append(np.column_stack([x, y]))
    assert observed_parts, 'Scatter calls did not contain usable time/concentration data.'
    observed = np.concatenate(observed_parts, axis=0)
    wanted = valid[['time', 'concentration']].to_numpy(dtype=float)
    observed = observed[np.lexsort((observed[:, 1], observed[:, 0]))]
    wanted = wanted[np.lexsort((wanted[:, 1], wanted[:, 0]))]
    assert observed.shape == wanted.shape, 'Scatter plot must contain all and only valid data points.'
    assert np.allclose(observed, wanted, rtol=1e-10, atol=1e-10), 'Scatter data do not match the cleaned dataset.'

    matching_lines = 0
    for call in plot_calls.get('lines', []):
        x = np.asarray(call.get('x', []), dtype=float)
        y = np.asarray(call.get('y', []), dtype=float)
        if len(x) < 2 or len(x) != len(y):
            continue
        expected_y = mean_A * np.exp(-mean_k_unrounded * x)
        solid = call.get('linestyle') in ('-', 'solid')
        covers_domain = np.min(x) <= valid['time'].min() + 1e-8 and np.max(x) >= valid['time'].max() - 1e-8
        if solid and covers_domain and np.allclose(y, expected_y, rtol=2e-3, atol=2e-3):
            matching_lines += 1
    assert matching_lines == 1, 'Plot must contain a single solid average fitted curve using mean A and mean k.'


def test_end_to_end_analysis():
    original = generate_original_data()
    current = pd.read_csv(CSV_PATH)
    assert list(current.columns) == ['trial_id', 'time', 'concentration']
    assert current.shape == original.shape
    assert np.array_equal(current['trial_id'].to_numpy(), original['trial_id'].to_numpy())
    assert np.allclose(current[['time', 'concentration']], original[['time', 'concentration']], rtol=0, atol=1e-12), 'The supplied dataset was modified.'

    scripts = sorted(p for p in HOME.rglob('*.py') if p.is_file())
    assert scripts, 'No Python analysis script was created under /home/user.'
    hook_dir = install_plot_hook()
    failures = []
    chosen = None

    try:
        for index, script in enumerate(scripts):
            try:
                calls = run_script(script, original, hook_dir, f'candidate_{index}')
                validate_outputs(original, calls, require_original_ranges=True)
                chosen = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert chosen is not None, 'No Python script performed the required analysis. ' + ' | '.join(failures[-5:])

        # Exercise the selected script on changed data so fixed, self-reported values cannot pass.
        changed = original.copy()
        changed['concentration'] = changed['concentration'] * np.exp(-0.08 * changed['time'])
        last_trial_one = changed.index[changed['trial_id'] == 1][-1]
        changed.loc[last_trial_one, 'concentration'] = 16.0
        changed_calls = run_script(chosen, changed, hook_dir, 'changed')
        validate_outputs(changed, changed_calls, require_original_ranges=False)

        # Restore the supplied input and require the final delivered artifacts to be correct for it.
        final_calls = run_script(chosen, original, hook_dir, 'final')
        validate_outputs(original, final_calls, require_original_ranges=True)
    finally:
        original.to_csv(CSV_PATH, index=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
