#!/bin/bash
set -u
mkdir -p /logs/verifier
status=0

# The repaired requirements must retain the project's dependencies.
python3 - <<'PY' || status=1
import re
from pathlib import Path

path = Path('/home/user/project/requirements.txt')
assert path.is_file(), f'Requirements file not found: {path}'
content = path.read_text()
for package in ('numpy', 'pandas', 'pytest'):
    assert re.search(rf'(?im)^\s*{package}(?:\s|\[|[<>=!~;])', content), \
        f'{package} is missing from requirements.txt'
PY

# Actually exercise dependency resolution and installation.
python3 -m pip install -r /home/user/project/requirements.txt || status=1

# Execute the regression test the agent was required to create.
if [ -f /home/user/project/test_optimize.py ]; then
    runuser -u user -- sh -c 'cd /home/user/project && python3 -m pytest -q test_optimize.py::test_convergence' || status=1
else
    status=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import importlib.util
import math
import os
from pathlib import Path
import re
import subprocess
import sys

import pytest


def _numeric_constants(node):
    values = []
    for item in ast.walk(node):
        if isinstance(item, ast.Constant) and isinstance(item.value, (int, float)) and not isinstance(item.value, bool):
            values.append(float(item.value))
        elif (isinstance(item, ast.UnaryOp) and isinstance(item.op, ast.USub)
              and isinstance(item.operand, ast.Constant)
              and isinstance(item.operand.value, (int, float))):
            values.append(-float(item.operand.value))
    return values


def _derived_real_root():
    # Independently derive the real root of x^3 - 2x + 2 by bisection.
    lo, hi = -2.0, -1.0
    def polynomial(x):
        return x**3 - 2*x + 2
    for _ in range(100):
        mid = (lo + hi) / 2
        if polynomial(lo) * polynomial(mid) <= 0:
            hi = mid
        else:
            lo = mid
    return (lo + hi) / 2


def _load_optimize():
    opt_file = '/home/user/project/optimize.py'
    assert os.path.exists(opt_file), f'Script not found: {opt_file}'
    spec = importlib.util.spec_from_file_location('optimize', opt_file)
    module = importlib.util.module_from_spec(spec)
    sys.modules['optimize'] = module
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        pytest.fail(f'Failed to import {opt_file}: {exc}')
    return module


def test_requirements_are_installed_and_satisfied():
    req_file = Path('/home/user/project/requirements.txt')
    assert req_file.is_file(), f'Requirements file not found: {req_file}'
    content = req_file.read_text()
    for package in ('numpy', 'pandas', 'pytest'):
        assert re.search(rf'(?im)^\s*{package}(?:\s|\[|[<>=!~;])', content), \
            f'{package} is missing from requirements.txt'
        importlib.metadata.version(package)


def test_test_optimize_file_exists_and_contains_test():
    test_file = '/home/user/project/test_optimize.py'
    assert os.path.exists(test_file), f'Test file not found: {test_file}'

    with open(test_file, 'r') as f:
        content = f.read()
        assert 'test_convergence' in content, "Test function 'test_convergence' is missing in test_optimize.py"
        assert 'pytest' in content or 'import pytest' in content or 'optimize_function' in content, \
            'test_optimize.py does not look like a proper test file'

    tree = ast.parse(content, filename=test_file)
    functions = [n for n in ast.walk(tree)
                 if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
                 and n.name == 'test_convergence']
    assert functions, 'test_convergence must be a test function'
    function = functions[0]
    assert any(isinstance(n, ast.Assert) for n in ast.walk(function)), \
        'test_convergence must contain an assertion'
    assert 'optimize_function' in content, 'test_convergence must use optimize_function'
    values = _numeric_constants(function)
    assert any(abs(v - (-1.76929)) <= 1e-4 for v in values), \
        'test_convergence must check the requested root'
    assert any(0 < abs(v) <= 1e-4 for v in values), \
        'test_convergence must use a tolerance no larger than 1e-4'


def test_root_txt_contains_correct_value():
    root_file = '/home/user/root.txt'
    assert os.path.exists(root_file), f'Root output file not found: {root_file}'
    with open(root_file, 'r') as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {root_file} is not a valid float string: '{content}'")
    expected_root = -1.7692923542386314
    assert math.isclose(val, expected_root, rel_tol=1e-3, abs_tol=1e-3), \
        f'Incorrect root value in {root_file}: {val}. Expected approximately {expected_root}'


def test_optimize_script_is_fixed():
    module = _load_optimize()
    assert hasattr(module, 'optimize_function'), 'optimize_function is missing in optimize.py'
    try:
        result = module.optimize_function()
    except Exception as exc:
        pytest.fail(f'optimize_function() raised an exception: {exc}. The convergence issue might not be fixed.')
    expected_root = -1.7692923542386314
    assert math.isclose(result, expected_root, rel_tol=1e-3, abs_tol=1e-3), \
        f'optimize_function() returned {result}, expected approximately {expected_root}'

    # Check convergence from several valid starting points against an independently
    # derived answer, rather than accepting a single hard-coded return value.
    derived = _derived_real_root()
    for guess in (-4.0, -2.5, -1.5):
        result = module.optimize_function(initial_guess=guess)
        assert math.isclose(result, derived, rel_tol=0.0, abs_tol=1e-4), \
            f'optimize_function({guess}) returned {result}, expected {derived}'


def test_optimizer_uses_the_function_it_is_supposed_to_solve():
    module = _load_optimize()
    original_f, original_df = module.f, module.df
    try:
        # Linear cases have independently generated exact roots and exercise the
        # Newton implementation without relying on the disclosed project root.
        for slope, intercept, guess in ((3.25, -7.5, 11.0), (-2.0, -8.25, 3.0)):
            expected = -intercept / slope
            module.f = lambda x, a=slope, b=intercept: a * x + b
            module.df = lambda x, a=slope: a
            result = module.optimize_function(initial_guess=guess)
            assert math.isclose(result, expected, rel_tol=0.0, abs_tol=1e-5), \
                f'Optimizer returned {result} for a function whose root is {expected}'
    finally:
        module.f, module.df = original_f, original_df


def test_optimize_script_executes_successfully():
    completed = subprocess.run(
        [sys.executable, '/home/user/project/optimize.py'],
        cwd='/home/user/project', text=True, capture_output=True, timeout=20
    )
    assert completed.returncode == 0, completed.stderr
    try:
        value = float(completed.stdout.strip())
    except ValueError:
        pytest.fail(f'optimize.py did not print a plain float: {completed.stdout!r}')
    assert math.isclose(value, _derived_real_root(), rel_tol=0.0, abs_tol=1e-4)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
