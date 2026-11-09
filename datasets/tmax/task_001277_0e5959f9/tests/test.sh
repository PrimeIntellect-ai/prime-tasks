#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import ast
import io
import os
import re
import sys
import subprocess
import unittest
import importlib
import importlib.util
import uuid
import pytest

APP_DIR = "/home/user/app"


def load_processor():
    if APP_DIR not in sys.path:
        sys.path.insert(0, APP_DIR)
    try:
        import processor
    except ImportError:
        pytest.fail("Could not import processor.py. Is it missing or broken?")
    return importlib.reload(processor)


def test_processor_fixed():
    """Check if processor.py has been fixed to raise ValueError on circular references."""
    if APP_DIR not in sys.path:
        sys.path.insert(0, APP_DIR)

    try:
        import processor
    except ImportError:
        pytest.fail("Could not import processor.py. Is it missing or broken?")

    # Reload to ensure we get the latest version if previously imported
    import importlib
    importlib.reload(processor)

    try:
        processor.flatten_data({"alias_of": "group_omega"})
        pytest.fail("flatten_data did not raise a ValueError on a circular reference.")
    except ValueError as e:
        assert "Circular reference detected" in str(e) or "circular" in str(e).lower(), \
            f"ValueError raised, but message was unexpected: {e}"
    except Exception as e:
        pytest.fail(f"flatten_data raised an unexpected exception: {e}")


def test_general_alias_cycle_detection_and_normal_behavior():
    """Exercise generated cycles and acyclic aliases instead of one fixed alias."""
    processor = load_processor()
    original_resolver = processor.resolve_alias
    prefix = "verifier_" + uuid.uuid4().hex
    a, b, c = prefix + "_a", prefix + "_b", prefix + "_c"
    terminal = prefix + "_terminal"

    cycle_map = {
        a: {"alias_of": b},
        b: {"alias_of": c},
        c: {"alias_of": a},
    }

    try:
        processor.resolve_alias = lambda name: cycle_map.get(name, {"value": name})
        for entry in (a, b, c):
            with pytest.raises(ValueError) as excinfo:
                processor.flatten_data({"alias_of": entry})
            assert str(excinfo.value) == "Circular reference detected"

        processor.resolve_alias = lambda name: (
            {"alias_of": terminal} if name == a
            else {"value": "finished"} if name == terminal
            else {"value": name}
        )
        expected = [{"value": "finished"}, 17]
        assert processor.flatten_data([{"alias_of": a}, 17]) == expected
        # Visited state must belong to one invocation, not leak into later calls.
        assert processor.flatten_data([{"alias_of": a}, 17]) == expected
    finally:
        processor.resolve_alias = original_resolver


def test_regression_file_contents():
    """Check if test_regression.py exists and contains the required elements."""
    test_file = os.path.join(APP_DIR, "test_regression.py")
    assert os.path.isfile(test_file), "test_regression.py is missing."

    with open(test_file, "r") as f:
        content = f.read()

    assert "unittest" in content, "test_regression.py does not use the unittest framework."
    assert "group_omega" in content, "test_regression.py does not contain the extracted alias 'group_omega'."
    assert "ValueError" in content, "test_regression.py does not assert that a ValueError is raised."
    assert "flatten_data" in content, "test_regression.py does not reference flatten_data."


def test_regression_test_structure_and_effectiveness():
    """Require a real unittest that calls flatten_data with the crash alias."""
    test_file = os.path.join(APP_DIR, "test_regression.py")
    with open(test_file, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=test_file)

    flatten_names = set()
    unittest_imported = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == "unittest":
                    unittest_imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module == "unittest":
                unittest_imported = True
            if node.module == "processor":
                for item in node.names:
                    if item.name == "flatten_data":
                        flatten_names.add(item.asname or item.name)

    assert unittest_imported, "test_regression.py must import unittest."
    assert flatten_names, "test_regression.py must import flatten_data from processor."

    def is_value_error(node):
        return isinstance(node, ast.Name) and node.id == "ValueError"

    def is_required_call(node):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):
            return False
        if node.func.id not in flatten_names or not node.args:
            return False
        arg = node.args[0]
        if not isinstance(arg, ast.Dict):
            return False
        pairs = {}
        for key, value in zip(arg.keys, arg.values):
            if isinstance(key, ast.Constant) and isinstance(key.value, str) and isinstance(value, ast.Constant):
                pairs[key.value] = value.value
        return pairs.get("alias_of") == "group_omega"

    found = False
    for cls in [n for n in tree.body if isinstance(n, ast.ClassDef)]:
        is_case = any(
            isinstance(base, ast.Attribute)
            and isinstance(base.value, ast.Name)
            and base.value.id == "unittest"
            and base.attr == "TestCase"
            for base in cls.bases
        )
        if not is_case:
            continue
        for method in [n for n in cls.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test")]:
            for with_node in [n for n in ast.walk(method) if isinstance(n, (ast.With, ast.AsyncWith))]:
                raises_value_error = False
                for item in with_node.items:
                    expr = item.context_expr
                    if isinstance(expr, ast.Call) and isinstance(expr.func, ast.Attribute) and expr.func.attr == "assertRaises":
                        if expr.args and is_value_error(expr.args[0]):
                            raises_value_error = True
                if raises_value_error and any(is_required_call(n) for n in ast.walk(with_node)):
                    found = True
    assert found, (
        "A unittest.TestCase test method must call flatten_data({\"alias_of\": "
        "\"group_omega\"}) inside assertRaises(ValueError)."
    )

    processor = load_processor()
    original_flatten = processor.flatten_data

    def execute_with_behavior(should_raise):
        calls = []

        def controlled_flatten(data):
            calls.append(data)
            if should_raise:
                raise ValueError("Circular reference detected")
            return []

        processor.flatten_data = controlled_flatten
        module_name = "submitted_regression_" + uuid.uuid4().hex
        spec = importlib.util.spec_from_file_location(module_name, test_file)
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        try:
            spec.loader.exec_module(module)
            suite = unittest.defaultTestLoader.loadTestsFromModule(module)
            count = suite.countTestCases()
            stream = io.StringIO()
            result = unittest.TextTestRunner(stream=stream, verbosity=1).run(suite)
            return count, result.wasSuccessful(), calls, stream.getvalue()
        finally:
            sys.modules.pop(module_name, None)

    try:
        count, passed, calls, details = execute_with_behavior(True)
        assert count > 0, "test_regression.py contains no runnable unittest tests."
        assert passed, f"Regression test did not pass when flatten_data raised ValueError:\n{details}"
        assert {"alias_of": "group_omega"} in calls, "Regression test never called flatten_data with the required dictionary."

        count, passed, calls, details = execute_with_behavior(False)
        assert count > 0
        assert {"alias_of": "group_omega"} in calls
        assert not passed, "Regression test still passes when flatten_data does not raise ValueError."
    finally:
        processor.flatten_data = original_flatten


def test_test_output_file():
    """Check if test_output.txt exists and indicates a successful test run."""
    output_file = os.path.join(APP_DIR, "test_output.txt")
    assert os.path.isfile(output_file), "test_output.txt is missing. Did you redirect the test output?"

    with open(output_file, "r") as f:
        content = f.read()

    assert "OK" in content, "test_output.txt does not contain 'OK', indicating the test may not have passed or output was not captured correctly."
    match = re.search(r"Ran\s+([0-9]+)\s+tests?", content)
    assert match and int(match.group(1)) > 0, "test_output.txt does not show that any unittest test was run."
    assert "FAILED" not in content, "test_output.txt indicates a failed test run."


def test_regression_execution():
    """Check if the regression test actually passes when run."""
    test_file = os.path.join(APP_DIR, "test_regression.py")
    assert os.path.isfile(test_file), "test_regression.py is missing."

    result = subprocess.run(
        [sys.executable, "-m", "unittest", test_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    assert result.returncode == 0, f"Running test_regression.py failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert "OK" in result.stderr or "OK" in result.stdout, "Test execution did not output 'OK'."
    combined = result.stdout + result.stderr
    match = re.search(r"Ran\s+([0-9]+)\s+tests?", combined)
    assert match and int(match.group(1)) > 0, "Regression execution did not run any unittest tests."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
