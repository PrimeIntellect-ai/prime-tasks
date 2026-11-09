#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib.machinery
import os
import subprocess
import sys

import pytest

WORKSPACE_DIR = "/home/user/rate_limiter"
TEST_PATH = os.path.join(WORKSPACE_DIR, "test_limiter.py")


def test_setup_py_fixed():
    setup_path = os.path.join(WORKSPACE_DIR, "setup.py")
    assert os.path.isfile(setup_path), f"Missing {setup_path}"

    with open(setup_path, "r") as f:
        content = f.read()

    assert "_bucket" in content, "setup.py does not define the extension name as '_bucket'"
    assert "bucket.c" in content, "setup.py does not include 'bucket.c' in sources"


def test_extension_built():
    so_files = glob.glob(os.path.join(WORKSPACE_DIR, "_bucket*.so"))
    assert len(so_files) > 0, "The C-extension module _bucket*.so was not found in the workspace. Did you build it in-place?"


def test_extension_imports_and_behaves_correctly():
    code = r'''
import importlib.machinery
import os
import sys
sys.path.insert(0, "/home/user/rate_limiter")
import _bucket
from limiter import TokenBucket

origin = os.path.realpath(_bucket.__file__)
workspace = os.path.realpath("/home/user/rate_limiter") + os.sep
assert origin.startswith(workspace), origin
assert any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), origin
assert callable(_bucket.consume)

# Derive expected results independently and exercise a range of inputs.
for capacity in (1, 7, 100, 137):
    for fill_rate in (0, 1, 10, 23):
        for current in (0, capacity // 2, capacity):
            for elapsed in (0, 1, 3, 20):
                for requested in (1, 2, capacity + 1):
                    refilled = min(capacity, current + elapsed * fill_rate)
                    expected = (1, refilled - requested) if refilled >= requested else (0, refilled)
                    actual = _bucket.consume(requested, elapsed, capacity, fill_rate, current)
                    assert actual == expected, (capacity, fill_rate, current, elapsed, requested, actual, expected)

bucket = TokenBucket(capacity=100, fill_rate=10)
expected_tokens = 100
for elapsed in [0, 0, 1, 20, 3, 0, 7, 2]:
    expected_tokens = min(100, expected_tokens + elapsed * 10)
    expected_success = expected_tokens >= 1
    if expected_success:
        expected_tokens -= 1
    assert bucket.consume(1, elapsed) is expected_success
    assert bucket.get_tokens() == expected_tokens
    assert 0 <= bucket.get_tokens() <= 100
'''
    result = subprocess.run(
        [sys.executable, "-c", code],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout


def test_test_limiter_py_content():
    assert os.path.isfile(TEST_PATH), f"Missing {TEST_PATH}"

    with open(TEST_PATH, "r") as f:
        content = f.read()

    required_strings = [
        "hypothesis",
        "given",
        "st.lists",
        "st.integers",
        "TokenBucket",
        "consume",
        "get_tokens",
        "100",
        "0"
    ]

    for req in required_strings:
        assert req in content, f"Expected to find '{req}' in test_limiter.py"


def _call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def _literal_keyword(call, name):
    for keyword in call.keywords:
        if keyword.arg == name and isinstance(keyword.value, ast.Constant):
            return keyword.value.value
    return None


def test_property_test_has_required_strategy_and_operations():
    with open(TEST_PATH, "r") as f:
        tree = ast.parse(f.read(), TEST_PATH)

    functions = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    candidates = []
    for function in functions:
        given_calls = [d for d in function.decorator_list if isinstance(d, ast.Call) and _call_name(d.func) == "given"]
        if given_calls:
            candidates.append((function, given_calls))
    assert candidates, "No test function decorated with hypothesis.given was found"

    valid = False
    for function, given_calls in candidates:
        calls = [n for n in ast.walk(function) if isinstance(n, ast.Call)]
        lists_calls = [c for dec in given_calls for c in ast.walk(dec)
                       if isinstance(c, ast.Call) and _call_name(c.func) == "lists"]
        strategy_ok = False
        for lists_call in lists_calls:
            integer_calls = [c for c in ast.walk(lists_call)
                             if isinstance(c, ast.Call) and _call_name(c.func) == "integers"]
            if (_literal_keyword(lists_call, "min_size") == 1 and
                    _literal_keyword(lists_call, "max_size") == 50 and
                    any(_literal_keyword(c, "min_value") == 0 and
                        _literal_keyword(c, "max_value") == 20 for c in integer_calls)):
                strategy_ok = True

        constructors = [c for c in calls if _call_name(c.func) == "TokenBucket"]
        constructor_ok = any(_literal_keyword(c, "capacity") == 100 and
                             _literal_keyword(c, "fill_rate") == 10 for c in constructors)
        consume_ok = any(_call_name(c.func) == "consume" and c.args and
                         isinstance(c.args[0], ast.Constant) and c.args[0].value == 1
                         for c in calls)
        get_tokens_ok = any(_call_name(c.func) == "get_tokens" for c in calls)
        loop_ok = any(isinstance(n, (ast.For, ast.comprehension)) for n in ast.walk(function))
        assert_count = sum(isinstance(n, ast.Assert) for n in ast.walk(function))

        if strategy_ok and constructor_ok and consume_ok and get_tokens_ok and loop_ok and assert_count >= 1:
            valid = True
            break

    assert valid, ("The @given test must use the exact requested list/integer bounds, instantiate "
                   "TokenBucket(capacity=100, fill_rate=10), iterate, consume one token, and assert on get_tokens()")


def _run_submitted_test(extra_plugin=None):
    env = os.environ.copy()
    env["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    env["PYTHONPATH"] = "/tmp:" + WORKSPACE_DIR
    command = [sys.executable, "-m", "pytest", "-q", "--confcutdir=/tmp"]
    if extra_plugin:
        command += ["-p", extra_plugin]
    command.append(TEST_PATH)
    return subprocess.run(
        command,
        cwd="/tmp",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )


def test_submitted_property_test_actually_passes():
    result = _run_submitted_test()
    assert result.returncode == 0, result.stdout
    assert "1 passed" in result.stdout, "Expected the submitted property test itself to run and pass:\n" + result.stdout


def test_submitted_test_rejects_both_token_bound_violations():
    for value in (101, -1):
        plugin_name = f"bounds_plugin_{'high' if value > 100 else 'low'}"
        plugin_path = os.path.join("/tmp", plugin_name + ".py")
        with open(plugin_path, "w") as f:
            f.write(
                "def pytest_configure(config):\n"
                "    import limiter\n"
                f"    limiter.TokenBucket.get_tokens = lambda self: {value}\n"
            )
        result = _run_submitted_test(plugin_name)
        assert result.returncode != 0, (
            f"The submitted property test did not reject get_tokens() == {value}; "
            "it is not enforcing both required token bounds.\n" + result.stdout
        )
        assert "AssertionError" in result.stdout, (
            f"The mutated run failed for an unexpected reason rather than a token-bound assertion:\n{result.stdout}"
        )


def test_report_log_passed():
    log_path = os.path.join(WORKSPACE_DIR, "test_report.log")
    assert os.path.isfile(log_path), f"Missing {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    assert "1 passed" in content, "test_report.log does not indicate that 1 test passed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
