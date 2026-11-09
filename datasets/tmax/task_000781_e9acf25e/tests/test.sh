#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import ctypes
import importlib.util
import inspect
import json
import math
import os
import random
import subprocess
import sys
import time

import pytest

APP_DIR = '/app/tinyexpr-py'
TINYEXPR_DIR = '/app/tinyexpr'
RESULTS_PATH = os.path.join(APP_DIR, 'results.json')
TEST_FILE_PATH = os.path.join(APP_DIR, 'test_te.py')
BENCHMARK_PATH = os.path.join(APP_DIR, 'benchmark.py')
LIB_PATH = os.path.join(TINYEXPR_DIR, 'libtinyexpr.so')

# Preserve trusted references before importing any submission-controlled Python.
REAL_EVAL = builtins.eval
REAL_PERF_COUNTER = time.perf_counter
REAL_SIN = math.sin
REAL_COS = math.cos

EXPECTED_BENCHMARK = '''import time
import json
from te_wrapper import evaluate

expressions = [f"sin({i} * 3.14159 / 180) + cos({i} * 3.14159 / 180)**2" for i in range(10000)]

# Benchmark Pure Python
start = time.time()
py_results = []
for expr in expressions:
    import math
    # Hack to make eval work with sin/cos
    py_results.append(eval(expr, {"sin": math.sin, "cos": math.cos}))
py_time = time.time() - start

# Benchmark TinyExpr
start = time.time()
te_results = []
for expr in expressions:
    te_results.append(evaluate(expr))
te_time = time.time() - start

# Compute MSE
mse = sum((p - t)**2 for p, t in zip(py_results, te_results)) / len(expressions)
speedup = py_time / te_time

results = {
    "mse": mse,
    "speedup": speedup,
    "py_time": py_time,
    "te_time": te_time
}

with open("results.json", "w") as f:
    json.dump(results, f, indent=2)

print(f"MSE: {mse}")
print(f"Speedup: {speedup:.2f}x")
'''


@pytest.fixture(scope='session', autouse=True)
def rebuild_and_run_benchmark():
    assert os.path.isfile(BENCHMARK_PATH), f'{BENCHMARK_PATH} is missing.'
    with open(BENCHMARK_PATH, 'r') as f:
        assert f.read() == EXPECTED_BENCHMARK, 'benchmark.py was modified.'

    clean = subprocess.run(['make', 'clean'], cwd=TINYEXPR_DIR,
                           capture_output=True, text=True)
    assert clean.returncode == 0, f'make clean failed:\n{clean.stdout}\n{clean.stderr}'

    build = subprocess.run(['make'], cwd=TINYEXPR_DIR,
                           capture_output=True, text=True, timeout=120)
    assert build.returncode == 0, f'make failed:\n{build.stdout}\n{build.stderr}'
    assert os.path.isfile(LIB_PATH), 'Makefile did not build libtinyexpr.so.'
    with open(LIB_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'libtinyexpr.so is not an ELF shared library.'

    # Recheck after make in case a build rule altered the benchmark.
    with open(BENCHMARK_PATH, 'r') as f:
        assert f.read() == EXPECTED_BENCHMARK, 'The build modified benchmark.py.'

    if os.path.exists(RESULTS_PATH):
        os.unlink(RESULTS_PATH)
    run = subprocess.run([sys.executable, BENCHMARK_PATH], cwd=APP_DIR,
                         capture_output=True, text=True, timeout=180)
    assert run.returncode == 0, f'benchmark.py failed:\n{run.stdout}\n{run.stderr}'


def load_wrapper():
    if APP_DIR not in sys.path:
        sys.path.insert(0, APP_DIR)
    import te_wrapper
    return te_wrapper


def test_results_json_exists():
    assert os.path.isfile(RESULTS_PATH), f'{RESULTS_PATH} was not generated. Did you run benchmark.py?'


def test_metrics_thresholds():
    with open(RESULTS_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'Could not parse {RESULTS_PATH} as valid JSON.')

    assert 'mse' in data, f"{RESULTS_PATH} is missing the 'mse' key."
    assert 'speedup' in data, f"{RESULTS_PATH} is missing the 'speedup' key."

    mse = data['mse']
    speedup = data['speedup']
    expected_mse_threshold = 1e-7
    expected_speedup_threshold = 10.0

    assert isinstance(mse, (int, float)) and math.isfinite(mse)
    assert isinstance(speedup, (int, float)) and math.isfinite(speedup)
    assert mse < expected_mse_threshold, f'MSE too high: {mse} (expected < {expected_mse_threshold})'
    assert speedup >= expected_speedup_threshold, f'Speedup too low: {speedup}x (expected >= {expected_speedup_threshold}x)'


def test_wrapper_abi_and_hidden_correctness():
    wrapper = load_wrapper()
    assert wrapper.lib.te_interp.argtypes == [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    assert wrapper.lib.te_interp.restype is ctypes.c_double

    rng = random.SystemRandom()
    squared_errors = []
    for _ in range(250):
        x = rng.uniform(-500.0, 500.0)
        y = rng.uniform(-500.0, 500.0)
        expression = f'sin({x:.15g}) + cos({y:.15g})**2 + ({x:.15g})/37.25'
        expected = REAL_SIN(x) + REAL_COS(y) ** 2 + x / 37.25
        actual = wrapper.evaluate(expression)
        assert isinstance(actual, (int, float)) and math.isfinite(actual)
        squared_errors.append((expected - actual) ** 2)

    mse = sum(squared_errors) / len(squared_errors)
    assert mse < 1e-7, f'Independent randomized MSE too high: {mse}'
    with pytest.raises(ValueError):
        wrapper.evaluate('2 + definitely_not_a_valid_token')


def test_independent_benchmark_metrics():
    evaluate = load_wrapper().evaluate
    expressions = [f'sin({i} * 3.14159 / 180) + cos({i} * 3.14159 / 180)**2' for i in range(10000)]

    start = REAL_PERF_COUNTER()
    py_results = [REAL_EVAL(expr, {'sin': REAL_SIN, 'cos': REAL_COS}) for expr in expressions]
    py_time = REAL_PERF_COUNTER() - start

    start = REAL_PERF_COUNTER()
    te_results = [evaluate(expr) for expr in expressions]
    te_time = REAL_PERF_COUNTER() - start

    mse = sum((p - t) ** 2 for p, t in zip(py_results, te_results)) / len(expressions)
    speedup = py_time / te_time
    assert mse < 1e-7, f'Independent benchmark MSE too high: {mse}'
    assert speedup >= 10.0, f'Independent benchmark speedup too low: {speedup}x'


def test_test_te_passes():
    assert os.path.isfile(TEST_FILE_PATH), f'{TEST_FILE_PATH} is missing.'
    result = subprocess.run(['pytest', TEST_FILE_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f'pytest {TEST_FILE_PATH} failed to pass. Output:\n{result.stdout}\n{result.stderr}'


def test_mock_env_fixture_provides_state():
    spec = importlib.util.spec_from_file_location('submitted_test_te', TEST_FILE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    fixture = getattr(module, 'mock_env', None)
    assert fixture is not None, 'mock_env fixture is missing.'
    raw = getattr(fixture, '_fixture_function', None)
    if raw is None:
        wrapped = getattr(fixture, '__pytest_wrapped__', None)
        raw = getattr(wrapped, 'obj', None)
    assert raw is not None, 'mock_env is not a pytest fixture.'
    generated = raw()
    assert inspect.isgenerator(generated), 'mock_env must yield its setup state.'
    state = next(generated)
    assert isinstance(state, dict) and state.get('var') == 42.0, 'mock_env did not provide the injected variable state.'
    generated.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
