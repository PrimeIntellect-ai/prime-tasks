#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import importlib
import math
import os
import secrets
import subprocess
import sys

import pytest

PROJECT = "/home/user/sim_project"


def test_bad_file():
    path = "/home/user/sim_project/bad_file.txt"
    assert os.path.exists(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert "input_037.txt" in content, "bad_file.txt does not contain the correct filename (input_037.txt)."


def test_utils_stability():
    sys.path.insert(0, PROJECT)
    try:
        try:
            utils = importlib.import_module("utils")
            utils = importlib.reload(utils)
        except ImportError:
            pytest.fail("Could not import utils.py from /home/user/sim_project")

        try:
            # Preserve the original fixed assertion.
            res = utils.compute_weights([1000.0, 1000.0])
            assert len(res) == 2, "compute_weights should return a list of the same length as the input."
            assert abs(res[0] - 0.5) < 1e-6, "compute_weights returned incorrect probabilities."
            assert abs(res[1] - 0.5) < 1e-6, "compute_weights returned incorrect probabilities."
        except OverflowError:
            pytest.fail("compute_weights still raises OverflowError for large inputs. The numerical instability is not fixed.")

        # Exercise varied inputs selected at verification time and compare with an
        # independently computed max-shift softmax.
        rng = secrets.SystemRandom()
        cases = [
            [1000.0, 1001.0, 999.0],
            [-1000.0, -1001.0, -999.0],
            [1.25, -7.5, 3000.0, 2999.5],
        ]
        for _ in range(12):
            n = rng.randrange(2, 9)
            offset = rng.uniform(-10000.0, 10000.0)
            values = [offset + rng.uniform(-40.0, 40.0) for _ in range(n)]
            cases.append(values)

        for values in cases:
            maximum = max(values)
            shifted = [math.exp(v - maximum) for v in values]
            denominator = sum(shifted)
            expected = [v / denominator for v in shifted]
            actual = utils.compute_weights(values)
            assert isinstance(actual, (list, tuple))
            assert len(actual) == len(values)
            assert all(math.isfinite(x) and x >= 0.0 for x in actual)
            assert math.isclose(sum(actual), 1.0, rel_tol=1e-11, abs_tol=1e-11)
            for got, want in zip(actual, expected):
                assert math.isclose(got, want, rel_tol=1e-10, abs_tol=1e-12), (values, actual, expected)
    finally:
        sys.path.pop(0)


def test_main_fd_leak_fixed():
    path = "/home/user/sim_project/main.py"
    assert os.path.exists(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    has_close = ".close(" in content
    has_with_open = "with open(" in content
    assert has_close or has_with_open, "main.py does not appear to fix the file descriptor leak. No .close() or 'with open' found."


def test_error_state_handles_are_really_closed(monkeypatch, tmp_path):
    sys.path.insert(0, PROJECT)
    try:
        main_module = importlib.import_module("main")
        main_module = importlib.reload(main_module)

        input_path = tmp_path / "input.txt"
        input_path.write_text("1.0\n2.0\n")
        handles = []
        real_open = builtins.open

        class TrackedHandle:
            def __init__(self):
                self.closed = False

            def write(self, data):
                assert not self.closed
                return len(data)

            def close(self):
                self.closed = True

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                self.close()
                return False

        def tracking_open(file, *args, **kwargs):
            if isinstance(file, (str, bytes, os.PathLike)) and "/states/error_state_" in os.fspath(file):
                handle = TrackedHandle()
                handles.append(handle)
                return handle
            return real_open(file, *args, **kwargs)

        def force_overflow(_values):
            raise OverflowError("forced verifier overflow")

        monkeypatch.setattr(builtins, "open", tracking_open)
        monkeypatch.setattr(main_module, "compute_weights", force_overflow)

        with pytest.raises(OverflowError):
            main_module.process_file(str(input_path))

        assert len(handles) == 10, "The overflow state-dump path was not exercised as expected."
        assert all(h.closed for h in handles), "One or more error-state dump files are left open."
    finally:
        sys.path.pop(0)


def test_regression_test_exists():
    path = "/home/user/sim_project/test_regression.py"
    assert os.path.exists(path), f"Missing regression test file: {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "test_stability" in content, "test_regression.py is missing the 'test_stability' function."
    assert "compute_weights" in content, "test_regression.py does not import or use 'compute_weights'."

    tree = ast.parse(content, filename=path)
    functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "test_stability"]
    assert functions, "test_regression.py must define test_stability()."
    function = functions[0]
    calls_compute_weights = any(
        isinstance(n, ast.Call)
        and ((isinstance(n.func, ast.Name) and n.func.id == "compute_weights")
             or (isinstance(n.func, ast.Attribute) and n.func.attr == "compute_weights"))
        for n in ast.walk(function)
    )
    has_large_value = any(
        isinstance(n, ast.Constant)
        and isinstance(n.value, (int, float))
        and abs(n.value) >= 1000
        for n in ast.walk(function)
    )
    assert calls_compute_weights, "test_stability() must call compute_weights."
    assert has_large_value, "test_stability() must exercise extremely large values."
    assert any(isinstance(n, ast.Assert) for n in ast.walk(function)), "test_stability() must assert the result."

    result = subprocess.run(
        [sys.executable, "-m", "pytest", path, "-q"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"The submitted regression test does not pass:\n{result.stdout}"


def test_main_recomputes_aggregate_from_inputs():
    token = secrets.token_hex(8)
    extra_path = os.path.join(PROJECT, "data", f"input_verify_{token}.txt")
    aggregate = os.path.join(PROJECT, "aggregate_result.txt")

    try:
        with open(extra_path, "w") as f:
            f.write("12000.0\n12001.0\n11999.0\n")
        if os.path.exists(aggregate):
            os.remove(aggregate)

        result = subprocess.run(
            [sys.executable, "main.py"],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert result.returncode == 0, f"main.py failed:\n{result.stdout}"
        assert os.path.exists(aggregate), "main.py did not generate aggregate_result.txt"
        with open(aggregate, "r") as f:
            content = f.read().strip()
        assert content == "Total: 51.00", f"main.py did not aggregate the verifier-added input; got {content!r}"
    finally:
        if os.path.exists(extra_path):
            os.remove(extra_path)

    # Re-run against the original 50 inputs so the required final artifact is left
    # in its specified state.
    if os.path.exists(aggregate):
        os.remove(aggregate)
    result = subprocess.run(
        [sys.executable, "main.py"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"main.py failed on the original inputs:\n{result.stdout}"


def test_aggregate_result():
    path = "/home/user/sim_project/aggregate_result.txt"
    assert os.path.exists(path), f"Missing final output file: {path}. Did main.py run successfully to completion?"
    with open(path, "r") as f:
        content = f.read().strip()

    # Preserve the original aggregate assertion.
    assert "Total: 50.00" in content, f"aggregate_result.txt has incorrect content. Expected 'Total: 50.00', got: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
