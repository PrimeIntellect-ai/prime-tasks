#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.machinery
import json
import os
from pathlib import Path
import runpy
import secrets
import shutil
import subprocess
import sys
import timeit

import pytest

PROJECT = Path('/home/user/math_accelerator')
PACKAGE = PROJECT / 'math_accelerator'
BENCHMARK = Path('/home/user/benchmark.py')
RESULTS = Path('/home/user/benchmark_results.json')


def expected_tribonacci(n):
    if n == 0:
        return 0
    if n in (1, 2):
        return 1
    a, b, c = 0, 1, 1
    for _ in range(3, n + 1):
        a, b, c = b, c, a + b + c
    return c


@pytest.fixture(scope='session', autouse=True)
def rebuild_extension():
    # Remove importable artifacts so success requires setup.py to build the module.
    for pattern in ('trib_c*.so', 'trib_c*.pyd', 'trib_c.py'):
        for path in PACKAGE.glob(pattern):
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    fake_package = PACKAGE / 'trib_c'
    if fake_package.exists():
        if fake_package.is_dir():
            shutil.rmtree(fake_package)
        else:
            fake_package.unlink()
    pycache = PACKAGE / '__pycache__'
    if pycache.is_dir():
        for path in pycache.glob('trib_c*.pyc'):
            path.unlink()

    subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '-e', '.', '--force-reinstall', '--no-build-isolation'],
        cwd=str(PROJECT),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sys.modules.pop('math_accelerator.trib_c', None)
    importlib.invalidate_caches()
    if str(PROJECT) not in sys.path:
        sys.path.insert(0, str(PROJECT))


def test_c_extension_built_and_correct():
    try:
        import math_accelerator.trib_c as tc
    except ImportError as e:
        pytest.fail(f'Failed to import math_accelerator.trib_c. Extension was not built properly. Error: {e}')

    assert isinstance(tc.__loader__, importlib.machinery.ExtensionFileLoader), \
        'math_accelerator.trib_c is not a compiled extension module'
    module_path = Path(tc.__file__).resolve()
    assert any(str(module_path).endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
    assert PACKAGE.resolve() in module_path.parents, 'Compiled extension was not built into the project package'

    # Preserve the original assertions.
    assert tc.tribonacci(0) == 0, 'C extension tribonacci(0) failed'
    assert tc.tribonacci(1) == 1, 'C extension tribonacci(1) failed'
    assert tc.tribonacci(2) == 1, 'C extension tribonacci(2) failed'
    assert tc.tribonacci(10) == 81, 'C extension tribonacci(10) failed'
    assert tc.tribonacci(25) == 1389537, 'C extension tribonacci(25) failed'

    rng = secrets.SystemRandom()
    for n in {rng.randrange(3, 55) for _ in range(18)}:
        assert tc.tribonacci(n) == expected_tribonacci(n)


def test_python_fallback_correct():
    try:
        import math_accelerator.trib_py as tp
    except ImportError as e:
        pytest.fail(f'Failed to import math_accelerator.trib_py. Error: {e}')

    assert hasattr(tp, 'tribonacci'), 'trib_py.py is missing tribonacci function'

    # Preserve the original assertions.
    assert tp.tribonacci(0) == 0, 'Python fallback tribonacci(0) should be 0'
    assert tp.tribonacci(1) == 1, 'Python fallback tribonacci(1) should be 1'
    assert tp.tribonacci(2) == 1, 'Python fallback tribonacci(2) should be 1'
    assert tp.tribonacci(10) == 81, 'Python fallback tribonacci(10) should be 81'
    assert tp.tribonacci(25) == 1389537, 'Python fallback tribonacci(25) should be 1389537'

    # Unpredictable and large inputs prevent a fixed lookup table from passing.
    rng = secrets.SystemRandom()
    inputs = {rng.randrange(3, 350) for _ in range(30)} | {75, 100, 200, 350}
    for n in inputs:
        assert tp.tribonacci(n) == expected_tribonacci(n), f'Python fallback failed for n={n}'


def test_benchmark_script_is_executed_and_measures_both_implementations(monkeypatch):
    assert BENCHMARK.is_file(), f'Benchmark script not found at {BENCHMARK}'

    import math_accelerator.trib_c as tc
    import math_accelerator.trib_py as tp

    original_c = tc.tribonacci
    original_py = tp.tribonacci
    counts = {'c': 0, 'py': 0, 'c25': 0, 'py25': 0}

    def counted_c(*args, **kwargs):
        counts['c'] += 1
        if args and args[0] == 25:
            counts['c25'] += 1
        return original_c(*args, **kwargs)

    def counted_py(*args, **kwargs):
        counts['py'] += 1
        if args and args[0] == 25:
            counts['py25'] += 1
        return original_py(*args, **kwargs)

    monkeypatch.setattr(tc, 'tribonacci', counted_c)
    monkeypatch.setattr(tp, 'tribonacci', counted_py)

    original_timer_timeit = timeit.Timer.timeit
    records = []

    def observed_timeit(self, number=timeit.default_number):
        before = counts.copy()
        elapsed = original_timer_timeit(self, number=number)
        after = counts.copy()
        delta = {key: after[key] - before[key] for key in counts}
        if delta['c'] or delta['py']:
            records.append({'number': number, 'elapsed': elapsed, 'delta': delta})
        return elapsed

    monkeypatch.setattr(timeit.Timer, 'timeit', observed_timeit)
    if RESULTS.exists():
        RESULTS.unlink()

    old_cwd = os.getcwd()
    try:
        os.chdir('/home/user')
        runpy.run_path(str(BENCHMARK), run_name='__main__')
    finally:
        os.chdir(old_cwd)

    assert RESULTS.exists(), f'Benchmark results file not found at {RESULTS}'
    with RESULTS.open() as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('Benchmark results file is not valid JSON')

    assert set(data) == {'value_25', 'c_faster_than_py'}, 'Benchmark JSON has incorrect keys'
    assert data['value_25'] == 1389537, f"Expected value_25 to be 1389537, got {data['value_25']}"
    assert isinstance(data['c_faster_than_py'], bool), 'c_faster_than_py must be a boolean'

    assert len(records) == 2, 'Benchmark must separately time the C and Python implementations'
    c_records = [r for r in records if r['delta']['c'] == 100 and r['delta']['py'] == 0 and r['delta']['c25'] == 100]
    py_records = [r for r in records if r['delta']['py'] == 100 and r['delta']['c'] == 0 and r['delta']['py25'] == 100]
    assert len(c_records) == 1, 'C tribonacci(25) was not timed exactly 100 times'
    assert len(py_records) == 1, 'Python tribonacci(25) was not timed exactly 100 times'
    assert c_records[0]['number'] == 100
    assert py_records[0]['number'] == 100

    # Each function must also have been called outside the timed loops for the equality check.
    assert counts['c25'] >= 101 and counts['py25'] >= 101, \
        'Benchmark did not call both implementations to verify their n=25 values'

    measured_comparison = c_records[0]['elapsed'] < py_records[0]['elapsed']
    assert data['c_faster_than_py'] is measured_comparison, \
        'c_faster_than_py does not reflect the measured execution times'
    # Preserve the original assertion.
    assert data['c_faster_than_py'] is True, 'Expected c_faster_than_py to be True'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
