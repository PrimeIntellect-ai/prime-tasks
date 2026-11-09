#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_instrument

cat <<'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import hashlib
import json
import os
import numpy as np

LOG = os.environ.get('BENCHMARK_AUDIT_LOG', '/tmp/benchmark_audit.jsonl')

def clean(value):
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {str(k): clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return repr(value)

def record(event, **fields):
    entry = {'event': event}
    entry.update({k: clean(v) for k, v in fields.items()})
    with open(LOG, 'a', encoding='utf-8') as f:
        f.write(json.dumps(entry, allow_nan=True) + '\n')

def signature(value):
    arr = np.ascontiguousarray(np.asarray(value))
    return {
        'shape': list(arr.shape),
        'sha256': hashlib.sha256(arr.tobytes()).hexdigest(),
    }

# Wrap the two required estimators while delegating all real computation to sklearn.
import sklearn.linear_model as _linear_model
import sklearn.tree as _tree
_RealRidge = _linear_model.Ridge
_RealTree = _tree.DecisionTreeRegressor

class _EstimatorProxy:
    def __init__(self, kind, real_class, args, kwargs):
        object.__setattr__(self, '_kind', kind)
        object.__setattr__(self, '_estimator', real_class(*args, **kwargs))
        record('construct', model=kind, params=self._estimator.get_params(deep=False))

    def fit(self, X, y, *args, **kwargs):
        record('fit', model=self._kind, X=signature(X), y=signature(y))
        self._estimator.fit(X, y, *args, **kwargs)
        return self

    def predict(self, X, *args, **kwargs):
        record('predict', model=self._kind, X=signature(X))
        return self._estimator.predict(X, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._estimator, name)

    def __setattr__(self, name, value):
        if name in {'_kind', '_estimator'}:
            object.__setattr__(self, name, value)
        else:
            setattr(self._estimator, name, value)

def Ridge(*args, **kwargs):
    return _EstimatorProxy('ridge', _RealRidge, args, kwargs)

def DecisionTreeRegressor(*args, **kwargs):
    return _EstimatorProxy('tree', _RealTree, args, kwargs)

_linear_model.Ridge = Ridge
_tree.DecisionTreeRegressor = DecisionTreeRegressor

# Capture the actual samples supplied to scipy's independent t-test.
import scipy.stats as _stats
_real_ttest_ind = _stats.ttest_ind

def ttest_ind(a, b, *args, **kwargs):
    result = _real_ttest_ind(a, b, *args, **kwargs)
    record('ttest_ind', a=np.asarray(a, dtype=float).ravel().tolist(),
           b=np.asarray(b, dtype=float).ravel().tolist(),
           statistic=result.statistic, pvalue=result.pvalue)
    return result

_stats.ttest_ind = ttest_ind

# Capture the datasets passed to a real matplotlib boxplot.
try:
    from matplotlib.axes import Axes
    _real_boxplot = Axes.boxplot

    def _box_datasets(x):
        if isinstance(x, (list, tuple)) and len(x) and any(np.ndim(v) > 0 for v in x):
            return [np.asarray(v, dtype=float).ravel().tolist() for v in x]
        arr = np.asarray(x, dtype=float)
        if arr.ndim == 1:
            return [arr.ravel().tolist()]
        if arr.ndim == 2:
            return [arr[:, i].ravel().tolist() for i in range(arr.shape[1])]
        return []

    def boxplot(self, x, *args, **kwargs):
        record('boxplot', datasets=_box_datasets(x))
        return _real_boxplot(self, x, *args, **kwargs)

    Axes.boxplot = boxplot
except Exception as exc:
    record('instrumentation_error', detail=repr(exc))
PY_EOF

rm -f /home/user/results.json /home/user/benchmark_plot.png /tmp/benchmark_audit.jsonl
set +e
BENCHMARK_AUDIT_LOG=/tmp/benchmark_audit.jsonl \
PYTHONPATH="/tmp/verifier_instrument${PYTHONPATH:+:$PYTHONPATH}" \
timeout 240s python3 /home/user/benchmark.py > /tmp/benchmark_run.log 2>&1
run_status=$?
set -e
echo "$run_status" > /tmp/benchmark_run.status

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.tree import DecisionTreeRegressor

RESULTS = '/home/user/results.json'
PLOT = '/home/user/benchmark_plot.png'
LOG = '/tmp/benchmark_audit.jsonl'

def signature(value):
    arr = np.ascontiguousarray(np.asarray(value))
    return {'shape': list(arr.shape), 'sha256': hashlib.sha256(arr.tobytes()).hexdigest()}

def events():
    assert os.path.isfile(LOG), 'The executed script produced no benchmark audit log.'
    with open(LOG, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]

def load_results():
    with open(RESULTS, encoding='utf-8') as f:
        return json.load(f)

def close(actual, expected):
    return math.isclose(float(actual), float(expected), rel_tol=1e-9, abs_tol=1e-12)

def test_executed_successfully():
    with open('/tmp/benchmark_run.status', encoding='utf-8') as f:
        status = int(f.read().strip())
    if status != 0:
        output = open('/tmp/benchmark_run.log', encoding='utf-8', errors='replace').read()
        pytest.fail(f'benchmark.py did not run successfully (status {status}):\n{output[-4000:]}')

def test_results_json():
    results_path = '/home/user/results.json'
    assert os.path.isfile(results_path), f"{results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not a valid JSON file.")

    expected_keys = ['mean_time_ridge', 'mean_time_tree', 't_statistic', 'p_value']
    for k in expected_keys:
        assert k in res, f"Key '{k}' is missing from {results_path}."
        assert isinstance(res[k], (float, int)), f"Value for '{k}' is not a numeric type."
    assert set(res) == set(expected_keys), 'results.json must contain exactly the four required keys.'
    assert all(type(res[k]) in (float, int) and math.isfinite(res[k]) for k in expected_keys)

def test_models_are_default_and_use_entire_dataset():
    ev = events()
    assert not [e for e in ev if e['event'] == 'instrumentation_error']

    df = pd.read_csv('/home/user/data.csv')
    expected_X = signature(df[['f1', 'f2', 'f3', 'f4', 'f5']])
    expected_y = signature(df['target'])
    defaults = {
        'ridge': Ridge().get_params(deep=False),
        'tree': DecisionTreeRegressor().get_params(deep=False),
    }

    for model in ('ridge', 'tree'):
        constructs = [e for e in ev if e['event'] == 'construct' and e['model'] == model]
        assert constructs, f'{model} was not instantiated.'
        assert all(e['params'] == defaults[model] for e in constructs), \
            f'{model} must use default hyperparameters.'

        fits = [e for e in ev if e['event'] == 'fit' and e['model'] == model]
        assert fits, f'{model} was not trained.'
        assert any(e['X'] == expected_X and e['y'] == expected_y for e in fits), \
            f'{model} was not trained on the entire required dataset.'

        predictions = [e for e in ev if e['event'] == 'predict' and e['model'] == model]
        assert len(predictions) == 100, f'{model} must perform exactly 100 predict calls.'
        assert all(e['X'] == expected_X for e in predictions), \
            f'Every {model} prediction must use the entire feature dataset.'

def test_statistics_match_measured_samples():
    tests = [e for e in events() if e['event'] == 'ttest_ind']
    assert len(tests) == 1, 'scipy.stats.ttest_ind must be called once.'
    test = tests[0]
    ridge_times = np.asarray(test['a'], dtype=float)
    tree_times = np.asarray(test['b'], dtype=float)
    assert ridge_times.shape == (100,) and tree_times.shape == (100,)
    assert np.all(np.isfinite(ridge_times)) and np.all(np.isfinite(tree_times))
    assert np.all(ridge_times >= 0) and np.all(tree_times >= 0)
    assert np.any(ridge_times > 0) and np.any(tree_times > 0)

    res = load_results()
    assert close(res['mean_time_ridge'], np.mean(ridge_times))
    assert close(res['mean_time_tree'], np.mean(tree_times))
    assert close(res['t_statistic'], test['statistic'])
    assert close(res['p_value'], test['pvalue'])
    assert 0.0 <= res['p_value'] <= 1.0

def test_benchmark_plot():
    plot_path = '/home/user/benchmark_plot.png'
    assert os.path.isfile(plot_path), f"{plot_path} does not exist."

    size = os.path.getsize(plot_path)
    assert size > 1000, f"{plot_path} is too small ({size} bytes), likely empty or invalid."
    with open(plot_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'benchmark_plot.png is not a PNG image.'

    import matplotlib.image as mpimg
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10

    test = [e for e in events() if e['event'] == 'ttest_ind'][0]
    plots = [e for e in events() if e['event'] == 'boxplot']
    assert any(len(e['datasets']) == 2 and
               np.array_equal(np.asarray(e['datasets'][0]), np.asarray(test['a'])) and
               np.array_equal(np.asarray(e['datasets'][1]), np.asarray(test['b']))
               for e in plots), 'The plot must be a two-box plot of the benchmark timing samples.'

def test_benchmark_script_exists():
    script_path = '/home/user/benchmark.py'
    assert os.path.isfile(script_path), f"{script_path} does not exist."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
