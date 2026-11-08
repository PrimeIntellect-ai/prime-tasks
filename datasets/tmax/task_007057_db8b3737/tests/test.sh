#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import importlib.machinery
import importlib.util
import inspect
import itertools
import os
import random
import subprocess
import sys
import types

SETUP_PATH = '/home/user/fastsum_project/setup.py'
SCRIPT_PATH = '/home/user/test_fastsum.py'
RESULTS_PATH = '/home/user/test_results.txt'


def test_setup_fixed():
    assert os.path.isfile(SETUP_PATH), "setup.py is missing."
    with open(SETUP_PATH, 'r') as f:
        content = f.read()
    assert 'fastsum.c' in content, "setup.py was not fixed to use 'fastsum.c'."
    assert 'wrong_source.c' not in content, "setup.py still contains 'wrong_source.c'."

    proc = subprocess.run(
        [sys.executable, 'setup.py', 'build_ext', '--inplace'],
        cwd='/home/user/fastsum_project',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, "The repaired setup.py cannot build the extension:\n" + proc.stdout


def _oracle_exists(values, target):
    for size in range(len(values) + 1):
        for positions in itertools.combinations(range(len(values)), size):
            if sum(values[i] for i in positions) == target:
                return True
    return False


def _check_solver_case(fastsum, values, target):
    expected = _oracle_exists(values, target)
    result = fastsum.solve(values, target)
    if not expected:
        assert result is None, f"Expected no solution for {values}, target {target}, got {result!r}"
        return

    assert isinstance(result, list), f"Expected a list of indices for {values}, target {target}"
    assert all(isinstance(i, int) and not isinstance(i, bool) for i in result)
    assert len(result) == len(set(result)), f"Returned duplicate indices: {result!r}"
    assert all(0 <= i < len(values) for i in result), f"Returned out-of-range indices: {result!r}"
    assert sum(values[i] for i in result) == target, (
        f"Indices {result!r} do not sum to {target} for {values!r}"
    )


def test_fastsum_installed():
    try:
        import fastsum
    except ImportError:
        assert False, "The 'fastsum' package is not installed or importable."

    module_file = os.path.realpath(getattr(fastsum, '__file__', ''))
    assert module_file and os.path.isfile(module_file), "fastsum has no loadable module file."
    assert any(module_file.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        "fastsum is not the requested compiled C extension."
    )
    assert callable(getattr(fastsum, 'solve', None)), "fastsum.solve is missing or not callable."

    # Preserve the original fixed case.
    res = fastsum.solve([1, 2, 3], 3)
    assert res is not None, "fastsum.solve returned None unexpectedly."
    assert sum([1, 2, 3][i] for i in res) == 3, "fastsum.solve did not return correct indices."

    cases = [
        ([], 0), ([], 1), ([0], 0), ([0, 0, 5], 5),
        ([2, 4, 6], 5), ([7, 7, 7], 14), ([1, 2, 4, 8], 15),
        ([1000, 0, 3, 9], 1003), ([5, 10, 12], 1),
    ]
    rng = random.Random(928451)
    for _ in range(35):
        values = [rng.randint(0, 30) for _ in range(rng.randint(0, 11))]
        target = rng.randint(0, 120)
        cases.append((values, target))
    for values, target in cases:
        _check_solver_case(fastsum, values, target)


def _qualified_name(node, aliases):
    if isinstance(node, ast.Name):
        return aliases.get(node.id, node.id)
    if isinstance(node, ast.Attribute):
        base = _qualified_name(node.value, aliases)
        return base + '.' + node.attr if base else node.attr
    return ''


def _constant(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    return None


def _integer_bounds(call, aliases):
    if not isinstance(call, ast.Call) or not _qualified_name(call.func, aliases).endswith('.integers'):
        return None
    minimum = _constant(call.args[0]) if len(call.args) >= 1 else None
    maximum = _constant(call.args[1]) if len(call.args) >= 2 else None
    for kw in call.keywords:
        if kw.arg == 'min_value':
            minimum = _constant(kw.value)
        elif kw.arg == 'max_value':
            maximum = _constant(kw.value)
    return minimum, maximum


def _resolve(node, assignments):
    seen = set()
    while isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
        seen.add(node.id)
        node = assignments[node.id]
    return node


def test_test_script_exists_and_valid():
    assert os.path.isfile(SCRIPT_PATH), f"Test script {SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    # Preserve the original content assertions.
    assert 'test_subset_sum' in content, "The test function is not named 'test_subset_sum'."
    assert '@given' in content, "The test script does not use the @given decorator from hypothesis."
    assert 'hypothesis' in content, "The test script does not import hypothesis."
    assert 'fastsum' in content, "The test script does not import fastsum."

    tree = ast.parse(content, SCRIPT_PATH)
    aliases = {}
    assignments = {}
    for node in tree.body:
        if isinstance(node, ast.Import):
            for item in node.names:
                aliases[item.asname or item.name] = item.name
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            for item in node.names:
                aliases[item.asname or item.name] = module + '.' + item.name
        elif isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            assignments[node.targets[0].id] = node.value

    functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
                 and n.name == 'test_subset_sum']
    assert len(functions) == 1, "There must be exactly one test_subset_sum test function."
    function = functions[0]
    given_calls = [d for d in function.decorator_list
                   if isinstance(d, ast.Call) and _qualified_name(d.func, aliases).endswith('.given')]
    assert given_calls, "test_subset_sum is not actually decorated with hypothesis.given."

    strategy_nodes = []
    for call in given_calls:
        strategy_nodes.extend(_resolve(arg, assignments) for arg in call.args)
        strategy_nodes.extend(_resolve(kw.value, assignments) for kw in call.keywords)

    found_list = False
    found_target = False
    for strategy in strategy_nodes:
        if isinstance(strategy, ast.Call) and _qualified_name(strategy.func, aliases).endswith('.lists'):
            element = _resolve(strategy.args[0], assignments) if strategy.args else None
            max_size = None
            for kw in strategy.keywords:
                if kw.arg == 'max_size':
                    max_size = _constant(kw.value)
            if _integer_bounds(element, aliases) == (0, 1000) and max_size == 20:
                found_list = True
        if _integer_bounds(strategy, aliases) == (0, 10000):
            found_target = True

    assert found_list, "@given must generate lists of integers from 0 to 1000 with max_size=20."
    assert found_target, "@given must generate a target integer from 0 to 10000."


def _load_with_fake(response, expected_values, expected_target):
    fake = types.ModuleType('fastsum')
    calls = []

    def solve(values, target):
        calls.append((values, target))
        if values != expected_values or target != expected_target:
            raise AssertionError("test_subset_sum did not pass its generated array and target to fastsum.solve")
        return response

    fake.solve = solve
    old = sys.modules.get('fastsum')
    sys.modules['fastsum'] = fake
    name = '_agent_property_test_' + str(random.randrange(1 << 60))
    try:
        spec = importlib.util.spec_from_file_location(name, SCRIPT_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        if old is None:
            sys.modules.pop('fastsum', None)
        else:
            sys.modules['fastsum'] = old
    test = getattr(module, 'test_subset_sum', None)
    assert callable(test), "test_subset_sum is not callable."
    handle = getattr(test, 'hypothesis', None)
    inner = getattr(handle, 'inner_test', None)
    assert callable(inner), "test_subset_sum is not a genuine Hypothesis test."
    return inner, calls


def _run_inner(response, values, target, orientation):
    inner, calls = _load_with_fake(response, values, target)
    args = (values, target) if orientation == 0 else (target, values)
    error = None
    try:
        inner(*args)
    except Exception as exc:
        error = exc
    return error, calls


def test_property_assertions_are_effective():
    # Determine the function's parameter order while requiring a valid answer to pass.
    orientation = None
    for candidate in (0, 1):
        error, calls = _run_inner([0, 1], [2, 3], 5, candidate)
        if error is None and calls:
            orientation = candidate
            break
    assert orientation is not None, "test_subset_sum rejects a valid solver result or never calls fastsum.solve."

    error, calls = _run_inner(None, [2, 3], 5, orientation)
    assert error is None and calls, "test_subset_sum must allow the solver to return None."

    error, calls = _run_inner([0], [2], 1, orientation)
    assert calls and error is not None, "test_subset_sum does not reject indices whose values have the wrong sum."

    error, calls = _run_inner([0, 0], [2], 4, orientation)
    assert calls and error is not None, "test_subset_sum does not reject duplicate indices."

    error, calls = _run_inner([1], [2], 2, orientation)
    assert calls and error is not None, "test_subset_sum does not reject out-of-bounds indices."


def test_test_results_exist_and_passed():
    assert os.path.isfile(RESULTS_PATH), f"Test results file {RESULTS_PATH} is missing."
    with open(RESULTS_PATH, 'r') as f:
        content = f.read().lower()

    # Preserve the original result-file assertions.
    assert "passed" in content, "Pytest output does not indicate successful execution ('passed' not found)."
    assert "failed" not in content, "Pytest output indicates test failures."
    assert "error" not in content, "Pytest output indicates errors."

    # Do not trust the saved text: execute the requested test itself.
    proc = subprocess.run(
        [sys.executable, '-m', 'pytest', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert proc.returncode == 0, "The submitted property-based test does not pass when executed:\n" + proc.stdout
    assert 'test_subset_sum' in proc.stdout, "Pytest did not collect test_subset_sum."
    assert 'passed' in proc.stdout.lower(), "Fresh pytest output does not report a passing test."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
