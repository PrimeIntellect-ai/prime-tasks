#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys

import pytest

PROJECT = Path("/home/user/sparse_poly_pr")
SOURCE = PROJECT / "sparse_poly.py"
TEST_FILE = PROJECT / "test_sparse_poly.py"
SCRIPT = PROJECT / "run_tests.sh"
REPORT = PROJECT / "test_report.json"
REQUIRED_TESTS = {
    "test_sparse_poly.py::test_mult_basic",
    "test_sparse_poly.py::test_mult_zero_cancellation",
    "test_sparse_poly.py::test_mult_large_sparse",
}


def load_sparse_poly():
    name = f"sparse_poly_verified_{secrets.token_hex(8)}"
    spec = importlib.util.spec_from_file_location(name, SOURCE)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def expected_product(left, right):
    result = {}
    for degree1, coefficient1 in left.items():
        for degree2, coefficient2 in right.items():
            degree = degree1 + degree2
            result[degree] = result.get(degree, 0) + coefficient1 * coefficient2
    return {degree: coefficient for degree, coefficient in result.items() if coefficient != 0}


def test_sparse_poly_fixed():
    """Verify that sparse_poly.py correctly implements polynomial multiplication."""
    file_path = "/home/user/sparse_poly_pr/sparse_poly.py"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    sparse_poly = load_sparse_poly()
    SparsePolynomial = sparse_poly.SparsePolynomial

    # Test (2x^2 + 3) * (x + 4) = 2x^3 + 8x^2 + 3x + 12
    p1 = SparsePolynomial({2: 2, 0: 3})
    p2 = SparsePolynomial({1: 1, 0: 4})
    p3 = p1 * p2
    assert p3.coeffs == {3: 2, 2: 8, 1: 3, 0: 12}, "Multiplication logic is incorrect for basic polynomials."

    # Test (x + 1) * (x - 1) = x^2 - 1
    p4 = SparsePolynomial({1: 1, 0: 1})
    p5 = SparsePolynomial({1: 1, 0: -1})
    p6 = p4 * p5
    assert p6.coeffs == {2: 1, 0: -1}, "Multiplication logic failed to cancel out zero coefficients."

    # Required large sparse case.
    p7 = SparsePolynomial({100: 5})
    p8 = SparsePolynomial({50: 2, 0: 3})
    assert (p7 * p8).coeffs == {150: 10, 100: 15}


def test_test_suite_exists_and_contains_functions():
    """Verify that test_sparse_poly.py contains the required test functions."""
    file_path = "/home/user/sparse_poly_pr/test_sparse_poly.py"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    assert "def test_mult_basic" in content, "Missing test_mult_basic function."
    assert "def test_mult_zero_cancellation" in content, "Missing test_mult_zero_cancellation function."
    assert "def test_mult_large_sparse" in content, "Missing test_mult_large_sparse function."

    tree = ast.parse(content, filename=file_path)
    top_level_tests = {
        node.name for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_")
    }
    assert top_level_tests == {
        "test_mult_basic",
        "test_mult_zero_cancellation",
        "test_mult_large_sparse",
    }, "The submitted file must define exactly the three requested test functions."


def test_run_tests_script():
    """Verify, and actually execute, the end-to-end orchestration script."""
    file_path = "/home/user/sparse_poly_pr/run_tests.sh"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."

    with open(file_path, "r") as f:
        content = f.read()

    assert "pytest" in content, "Script does not invoke pytest."
    assert "pytest-json-report" in content or "pytest_json_report" in content or "--json-report" in content, "Script does not use json-report."
    assert "pip" in content, "Script does not install the required packages with pip."

    if REPORT.exists():
        REPORT.unlink()
    completed = subprocess.run(
        [str(SCRIPT)],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert completed.returncode == 0, f"run_tests.sh failed:\n{completed.stdout}"
    assert REPORT.is_file(), "run_tests.sh did not generate test_report.json."


def test_submitted_suite_is_real_and_checks_each_required_case(tmp_path):
    """Run the submitted suite and ensure each named test detects its corresponding defect."""
    suite_report = tmp_path / "submitted_report.json"
    completed = subprocess.run(
        [
            sys.executable, "-m", "pytest", str(TEST_FILE), "-q",
            "--json-report", f"--json-report-file={suite_report}",
        ],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, f"Submitted pytest suite fails:\n{completed.stdout}"
    data = json.loads(suite_report.read_text())
    assert data.get("summary", {}).get("passed") == 3, "Exactly three submitted tests must pass."
    nodeids = {entry.get("nodeid") for entry in data.get("tests", [])}
    assert nodeids == REQUIRED_TESTS, f"Unexpected collected tests: {nodeids}"

    original_source = SOURCE.read_bytes()
    mutant_template = '''
MODE = {mode!r}

class SparsePolynomial:
    def __init__(self, coeffs=None):
        self.coeffs = coeffs if coeffs is not None else {{}}
        self._cleanup()

    def _cleanup(self):
        self.coeffs = {{k: v for k, v in self.coeffs.items() if v != 0}}

    def __add__(self, other):
        res = self.coeffs.copy()
        for k, v in other.coeffs.items():
            res[k] = res.get(k, 0) + v
        return SparsePolynomial(res)

    def __mul__(self, other):
        res = {{}}
        for k1, v1 in self.coeffs.items():
            for k2, v2 in other.coeffs.items():
                res[k1 + k2] = res.get(k1 + k2, 0) + v1 * v2
        clean = {{k: v for k, v in res.items() if v != 0}}
        if MODE == "basic" and clean == {{3: 2, 2: 8, 1: 3, 0: 12}}:
            clean[0] = 13
        result = SparsePolynomial(clean)
        if MODE == "cancellation" and clean == {{2: 1, 0: -1}}:
            result.coeffs[1] = 0
        if MODE == "large" and clean == {{150: 10, 100: 15}}:
            result.coeffs[150] = 11
        return result

    def __eq__(self, other):
        return self.coeffs == other.coeffs
'''
    cases = [
        ("basic", "test_mult_basic"),
        ("cancellation", "test_mult_zero_cancellation"),
        ("large", "test_mult_large_sparse"),
    ]
    try:
        for mode, test_name in cases:
            SOURCE.write_text(mutant_template.format(mode=mode))
            shutil.rmtree(PROJECT / "__pycache__", ignore_errors=True)
            result = subprocess.run(
                [sys.executable, "-m", "pytest", f"{TEST_FILE}::{test_name}", "-q"],
                cwd=str(PROJECT),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=60,
            )
            assert result.returncode != 0, (
                f"{test_name} passed an implementation deliberately broken for its required case."
            )
    finally:
        SOURCE.write_bytes(original_source)
        shutil.rmtree(PROJECT / "__pycache__", ignore_errors=True)


def test_test_report_json():
    """Verify that test_report.json is valid and records the three real submitted tests."""
    file_path = "/home/user/sparse_poly_pr/test_report.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Did the orchestration script run?"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "summary" in data, "JSON report missing 'summary' key."
    assert data["summary"].get("passed", 0) >= 3, "Expected at least 3 passed tests in the JSON report."
    assert data["summary"].get("passed") == 3, "The report must contain exactly the three required passing tests."
    reported = {entry.get("nodeid") for entry in data.get("tests", []) if entry.get("outcome") == "passed"}
    assert reported == REQUIRED_TESTS, f"JSON report does not contain the required test results: {reported}"


def test_general_polynomial_multiplication_after_orchestration():
    """Exercise general, collision-heavy multiplication on verifier-derived inputs."""
    SparsePolynomial = load_sparse_poly().SparsePolynomial
    rng = secrets.SystemRandom()

    cases = [
        ({}, {4: 7}),
        ({0: 0, 9: 3}, {2: 0, 1: -4}),
        ({0: 1, 1: 1, 2: 1}, {0: 1, 1: -1}),
        ({137: -6, 3: 4}, {211: 5, 97: -2, 0: 9}),
    ]
    for _ in range(24):
        left_degrees = rng.sample(range(0, 260), rng.randint(1, 8))
        right_degrees = rng.sample(range(0, 260), rng.randint(1, 8))
        left = {degree: rng.choice([i for i in range(-9, 10) if i]) for degree in left_degrees}
        right = {degree: rng.choice([i for i in range(-9, 10) if i]) for degree in right_degrees}
        cases.append((left, right))

    for left, right in cases:
        expected = expected_product(left, right)
        actual = SparsePolynomial(dict(left)) * SparsePolynomial(dict(right))
        assert actual.coeffs == expected, f"Incorrect product for {left} * {right}"
        assert all(value != 0 for value in actual.coeffs.values()), "Zero coefficients were not cleaned up."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
mkdir -p /logs/verifier
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
