#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import secrets
import subprocess
import sys
import unittest
import pytest

MODERN_PATH = "/home/user/modern/math_eval.py"
TEST_PATH = "/home/user/modern/test_math.py"
INPUT_PATH = "/home/user/inputs.txt"
OUTPUT_PATH = "/home/user/output.txt"


def test_modern_math_eval_exists():
    path = MODERN_PATH
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "rb") as modern, open("/home/user/legacy/math_eval.py", "rb") as legacy:
        assert modern.read() != legacy.read(), "The modern implementation must not be an unchanged copy of the Python 2 script."


def test_output_file_contents():
    path = OUTPUT_PATH
    assert os.path.isfile(path), f"Output file {path} was not created."

    expected_lines = [
        "Expression: + 3 4 | Result: 7 | Checksum: 284242851",
        "Expression: - 10 * 2 3 | Result: 4 | Checksum: 3514757530",
        "Expression: / 10 3 | Result: 3 | Checksum: 216744030",
        "Expression: + / 20 6 * 2 5 | Result: 13 | Checksum: 2603831737"
    ]

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The contents of output.txt do not match the expected output format or mathematical results."


def test_math_test_fixture_runs():
    path = TEST_PATH
    assert os.path.isfile(path), f"Test fixture {path} does not exist."

    result = subprocess.run(
        ["python3", "-m", "unittest", path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Unittest failed to run successfully:\n{result.stderr}\n{result.stdout}"


def test_math_eval_code_fixes():
    path = MODERN_PATH
    with open(path, "r") as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"math_eval.py has invalid Python 3 syntax: {e}")

    has_floor_div = "//" in source
    has_int_cast = "int(" in source
    assert has_floor_div or has_int_cast, "math_eval.py must use floor division (//) or int() casting to preserve legacy division behavior."

    has_encode = ".encode" in source or "bytes(" in source
    assert has_encode, "math_eval.py must encode the string to bytes before passing it to the C function."


def _checksum(expr):
    value = 5381
    for byte in expr.encode("utf-8"):
        value = ((value * 33) + byte) & 0xffffffff
    return value


def _random_expression(rng, depth):
    if depth <= 0 or rng.randrange(5) == 0:
        value = rng.randint(-40, 40)
        return str(value), value

    op = rng.choice(["+", "-", "*", "/"])
    left_expr, left_value = _random_expression(rng, depth - 1)
    if op == "/":
        for _ in range(100):
            right_expr, right_value = _random_expression(rng, depth - 1)
            if right_value != 0:
                break
        else:
            right_expr, right_value = "1", 1
        value = left_value // right_value
    else:
        right_expr, right_value = _random_expression(rng, depth - 1)
        if op == "+":
            value = left_value + right_value
        elif op == "-":
            value = left_value - right_value
        else:
            value = left_value * right_value
    return f"{op} {left_expr} {right_expr}", value


def _load_math_eval(name):
    spec = importlib.util.spec_from_file_location(name, MODERN_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_randomized_parser_math_ffi_and_file_processing():
    rng = secrets.SystemRandom()
    cases = [
        ("/ -7 3", -3),
        ("/ 7 -3", -3),
        ("+ * -4 6 / 29 5", -19),
        ("- / -31 6 * 3 -2", 0),
    ]
    for _ in range(20):
        cases.append(_random_expression(rng, rng.randint(2, 5)))

    module = _load_math_eval("agent_math_eval_randomized")
    assert callable(getattr(module, "evaluate_and_hash", None)), "math_eval.py must define evaluate_and_hash."
    for expr, expected_result in cases:
        assert module.evaluate_and_hash(expr) == (expected_result, _checksum(expr)), \
            f"evaluate_and_hash failed for generated expression {expr!r}"

    old_inputs = open(INPUT_PATH, "rb").read() if os.path.exists(INPUT_PATH) else None
    old_output = open(OUTPUT_PATH, "rb").read() if os.path.exists(OUTPUT_PATH) else None
    try:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            for expr, _ in cases:
                f.write(expr + "\n")

        result = subprocess.run(
            ["python3", MODERN_PATH],
            cwd="/home/user/modern",
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Running math_eval.py failed:\n{result.stderr}\n{result.stdout}"
        assert os.path.isfile(OUTPUT_PATH), "Running math_eval.py did not create output.txt."

        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual = [line.rstrip("\n") for line in f]
        expected = [
            f"Expression: {expr} | Result: {value} | Checksum: {_checksum(expr)}"
            for expr, value in cases
        ]
        assert actual == expected, "math_eval.py did not correctly process generated inputs.txt cases."
    finally:
        if old_inputs is None:
            if os.path.exists(INPUT_PATH):
                os.unlink(INPUT_PATH)
        else:
            with open(INPUT_PATH, "wb") as f:
                f.write(old_inputs)
        if old_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(old_output)


def test_fixture_really_calls_evaluator_under_mock_patch():
    with open(TEST_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(
        (isinstance(node.func, ast.Attribute) and node.func.attr == "patch")
        or (isinstance(node.func, ast.Name) and node.func.id == "patch")
        for node in calls
    ), "test_math.py must use mock.patch."
    assert any(
        isinstance(node.func, ast.Attribute) and node.func.attr == "assertEqual"
        for node in calls
    ), "test_math.py must use assertEqual for the required tuple assertion."

    sys.path.insert(0, "/home/user/modern")
    old_math_eval = sys.modules.pop("math_eval", None)
    try:
        module = _load_math_eval("math_eval")
        original_evaluate = module.evaluate_and_hash
        observed = []

        def unmocked_ffi(*args, **kwargs):
            raise AssertionError("The real FFI call was not replaced by mock.patch")

        patch_points = []
        if hasattr(module, "compute_checksum"):
            try:
                setattr(module, "compute_checksum", unmocked_ffi)
                patch_points.append((module, "compute_checksum"))
            except Exception:
                pass
        for value in list(vars(module).values()):
            if hasattr(value, "compute_checksum"):
                try:
                    setattr(value, "compute_checksum", unmocked_ffi)
                    point = (value, "compute_checksum")
                    if all(id(value) != id(existing[0]) for existing in patch_points):
                        patch_points.append(point)
                except Exception:
                    pass
        assert patch_points, "Could not locate the submitted compute_checksum FFI binding."

        def recording_evaluate(expr):
            patch_active = any(getattr(obj, attr, unmocked_ffi) is not unmocked_ffi for obj, attr in patch_points)
            result = original_evaluate(expr)
            observed.append((expr, result, patch_active))
            return result

        module.evaluate_and_hash = recording_evaluate
        spec = importlib.util.spec_from_file_location("submitted_test_math", TEST_PATH)
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        suite = unittest.defaultTestLoader.loadTestsFromModule(fixture)
        assert suite.countTestCases() >= 1, "test_math.py must contain at least one discoverable unittest test method."
        result = unittest.TestResult()
        suite.run(result)
        assert result.wasSuccessful(), f"Instrumented fixture failed: errors={result.errors}, failures={result.failures}"
        assert any(
            expr == "- 10 3" and value == (7, 999) and patch_active
            for expr, value, patch_active in observed
        ), "The fixture must call evaluate_and_hash('- 10 3') while compute_checksum is patched and obtain (7, 999)."
    finally:
        sys.modules.pop("math_eval", None)
        sys.modules.pop("submitted_test_math", None)
        if old_math_eval is not None:
            sys.modules["math_eval"] = old_math_eval
        if sys.path and sys.path[0] == "/home/user/modern":
            sys.path.pop(0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
