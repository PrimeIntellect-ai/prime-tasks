#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib
import os
import random
import re
import subprocess
import sys

import pytest

API_DIR = "/home/user/api"


def load_main():
    os.chdir(API_DIR)
    sys.path.insert(0, API_DIR)
    sys.modules.pop("main", None)
    try:
        return importlib.import_module("main")
    except Exception as exc:
        pytest.fail(f"Failed to import main.py. Is the library loading fixed? Error: {exc}")


def make_client(app):
    try:
        from fastapi.testclient import TestClient
    except ImportError:
        pytest.fail("fastapi.testclient could not be imported. Are dependencies installed?")
    return TestClient(app)


def test_main_py_fixed_and_handles_unpredictable_expressions():
    main = load_main()
    assert hasattr(main, "app"), "main.py does not define the FastAPI app"

    libraries = [value for value in vars(main).values() if isinstance(value, ctypes.CDLL)]
    assert libraries, "main.py does not load the C shared library with ctypes.CDLL"
    assert os.path.isfile(os.path.join(API_DIR, "libmatheval.so")), "libmatheval.so is missing"
    with open(os.path.join(API_DIR, "libmatheval.so"), "rb") as library_file:
        assert library_file.read(4) == b"\x7fELF", "libmatheval.so is not an ELF shared library"

    client = make_client(main.app)

    # Verify that the endpoint really calls the bound C function and supplies the
    # UTF-8 expression as ASCII hex bytes, rather than answering in Python.
    expression = f"{random.SystemRandom().randint(100001, 999999)}+17+23"
    expected_argument = expression.encode("utf-8").hex().encode("ascii")
    sentinel = 987654321.125
    calls = []

    class Recorder:
        def __call__(self, argument):
            calls.append(argument)
            return sentinel

    recorder = Recorder()
    restorations = []
    cfunc_type = getattr(ctypes, "_CFuncPtr", ())

    for name, value in list(vars(main).items()):
        if cfunc_type and isinstance(value, cfunc_type) and getattr(value, "__name__", "") == "evaluate_hex_expr":
            restorations.append(("global", name, value))
            setattr(main, name, recorder)

    for library in libraries:
        try:
            original = getattr(library, "evaluate_hex_expr")
        except AttributeError:
            continue
        restorations.append(("library", library, original))
        setattr(library, "evaluate_hex_expr", recorder)

    try:
        response = client.post("/evaluate", json={"expression": expression})
        assert response.status_code == 200
        assert response.json().get("result") == sentinel, "The endpoint did not use the bound C function's return value"
        assert calls, "The endpoint did not call evaluate_hex_expr"
        assert calls[-1] == expected_argument, f"Expected C argument {expected_argument!r}, got {calls[-1]!r}"
    finally:
        for kind, target, original in reversed(restorations):
            if kind == "global":
                setattr(main, target, original)
            else:
                setattr(target, "evaluate_hex_expr", original)

    # Preserve the original fixed examples.
    response = client.post("/evaluate", json={"expression": "10+20"})
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert data["result"] == 30.0, f"Expected result 30.0, got {data['result']}"

    response2 = client.post("/evaluate", json={"expression": "15+2+99"})
    assert response2.status_code == 200
    assert response2.json()["result"] == 116.0

    # Exercise expressions selected only at verification time, preventing a
    # fixed response table from satisfying the endpoint checks.
    rng = random.SystemRandom()
    for _ in range(30):
        terms = [rng.randint(0, 1_000_000) for _ in range(rng.randint(1, 9))]
        generated_expression = "+".join(map(str, terms))
        generated_response = client.post("/evaluate", json={"expression": generated_expression})
        assert generated_response.status_code == 200
        generated_data = generated_response.json()
        assert "result" in generated_data
        assert generated_data["result"] == float(sum(terms)), (
            f"Wrong result for {generated_expression!r}: {generated_data['result']}"
        )


def test_test_api_py_exists_uses_hypothesis_and_is_a_real_property_test():
    test_file = os.path.join(API_DIR, "test_api.py")
    assert os.path.isfile(test_file), f"{test_file} does not exist."
    with open(test_file, "r", encoding="utf-8") as file_handle:
        content = file_handle.read()

    # Preserve the original assertions.
    assert "hypothesis" in content, f"{test_file} does not use hypothesis."
    assert "TestClient" in content, f"{test_file} does not use TestClient."

    tree = ast.parse(content, filename=test_file)
    property_tests = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        has_given = False
        for decorator in node.decorator_list:
            for part in ast.walk(decorator):
                if isinstance(part, ast.Name) and part.id == "given":
                    has_given = True
                if isinstance(part, ast.Attribute) and part.attr == "given":
                    has_given = True
        if has_given:
            property_tests.append(node)

    assert property_tests, "test_api.py has no test decorated with Hypothesis @given"
    assert "+" in content, "The property test does not construct addition expressions"

    has_evaluate_post = False
    has_status_assertion = False
    for test_node in property_tests:
        for node in ast.walk(test_node):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "post":
                if any(isinstance(part, ast.Constant) and part.value == "/evaluate" for part in ast.walk(node)):
                    has_evaluate_post = True
            if isinstance(node, ast.Assert):
                parts = list(ast.walk(node.test))
                checks_status = any(isinstance(part, ast.Attribute) and part.attr == "status_code" for part in parts)
                checks_200 = any(isinstance(part, ast.Constant) and part.value == 200 for part in parts)
                checks_ok = any(isinstance(part, ast.Attribute) and part.attr == "OK" for part in parts)
                if checks_status and (checks_200 or checks_ok):
                    has_status_assertion = True

    assert has_evaluate_post, "The Hypothesis test does not POST generated data to /evaluate"
    assert has_status_assertion, "The Hypothesis test does not assert that the response status is 200"

    completed = subprocess.run(
        [sys.executable, "-m", "pytest", test_file, "-q", "--hypothesis-show-statistics", "--tb=short"],
        cwd=API_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, f"test_api.py failed when executed:\n{completed.stdout}"
    assert re.search(r"\b\d+\s+passed\b", completed.stdout), f"pytest did not execute a passing test:\n{completed.stdout}"
    assert re.search(r"\b[1-9]\d*\s+passing examples\b", completed.stdout), (
        "No successfully generated Hypothesis examples were reported; "
        f"the property test may not actually be using Hypothesis.\n{completed.stdout}"
    )


def test_test_results_log_exists_and_passed():
    log_file = os.path.join(API_DIR, "test_results.log")
    test_file = os.path.join(API_DIR, "test_api.py")
    assert os.path.isfile(log_file), f"{log_file} does not exist."
    with open(log_file, "r", encoding="utf-8", errors="replace") as file_handle:
        content = file_handle.read().lower()

    # Preserve the original assertion and additionally require a real pytest
    # pass summary rather than an arbitrary occurrence of the word "passed".
    assert "passed" in content or "100%" in content, "Test results log does not indicate successful test execution."
    assert re.search(r"\b[1-9]\d*\s+passed\b", content), "test_results.log does not contain a successful pytest summary"
    assert os.path.getmtime(log_file) >= os.path.getmtime(test_file), "test_results.log predates test_api.py; rerun the test and save its output"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
