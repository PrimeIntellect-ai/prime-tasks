#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import ctypes
import importlib.util
import io
import math
import os
import re
import subprocess
import sys

import pytest

BASE_DIR = "/home/user/math_service"


def test_libfastmath_so_exists_and_valid():
    lib_path = os.path.join(BASE_DIR, "libfastmath.so")
    assert os.path.isfile(lib_path), f"Shared library {lib_path} does not exist."

    try:
        lib = ctypes.CDLL(lib_path)
    except Exception as e:
        pytest.fail(f"Failed to load {lib_path} as a shared library: {e}")

    assert hasattr(lib, "fast_inv_sqrt"), "Library is missing the fast_inv_sqrt function."

    fn = lib.fast_inv_sqrt
    fn.argtypes = [ctypes.c_float]
    fn.restype = ctypes.c_float
    for value in (0.1, 0.5, 1.0, 4.0, 25.0, 1000.0):
        result = float(fn(value))
        assert math.isfinite(result) and result > 0
        reconstructed = 1.0 / (result * result)
        assert math.isclose(reconstructed, value, rel_tol=0.10), (
            f"fast_inv_sqrt({value}) returned {result}"
        )


def test_math_ops_fixed():
    py_file = os.path.join(BASE_DIR, "math_ops.py")
    assert os.path.isfile(py_file), f"File {py_file} does not exist."
    with open(py_file, "r") as f:
        content = f.read()

    assert "c_double" not in content, "math_ops.py still contains c_double."
    assert "c_float" in content, "math_ops.py does not use ctypes.c_float."

    sys.path.insert(0, BASE_DIR)
    try:
        sys.modules.pop("math_ops", None)
        import math_ops

        assert math_ops.lib is not None
        fn = math_ops.lib.fast_inv_sqrt
        assert list(fn.argtypes or []) == [ctypes.c_float], "Argument type must be ctypes.c_float."
        assert fn.restype is ctypes.c_float, "Return type must be ctypes.c_float."

        for value in (0.1, 0.25, 1.0, 2.0, 4.0, 100.0, 1000.0):
            result = math_ops.get_inv_sqrt(value)
            assert isinstance(result, float)
            assert math.isfinite(result) and result > 0
            assert math.isclose(1.0 / (result * result), value, rel_tol=0.10)

        with pytest.raises(ValueError):
            math_ops.get_inv_sqrt(0.0)
        with pytest.raises(ValueError):
            math_ops.get_inv_sqrt(-1.0)
    finally:
        sys.path.remove(BASE_DIR)


def test_api_fixed():
    api_file = os.path.join(BASE_DIR, "api.py")
    assert os.path.isfile(api_file), f"File {api_file} does not exist."
    with open(api_file, "r") as f:
        content = f.read()

    has_float_route = "<float:value>" in content
    has_float_cast = "float(value)" in content or "float(" in content
    assert has_float_route or has_float_cast, "api.py does not cast the parameter to float or use <float:value> in the route."

    sys.path.insert(0, BASE_DIR)
    try:
        sys.modules.pop("api", None)
        import api

        client = api.app.test_client()
        for value in (0.1, 4.0, 16.5, 1000.0):
            response = client.get(f"/invsqrt/{value}")
            assert response.status_code == 200, response.get_data(as_text=True)
            payload = response.get_json()
            assert isinstance(payload, dict) and set(payload) == {"result"}
            result = payload["result"]
            assert isinstance(result, float)
            assert math.isclose(1.0 / (result * result), value, rel_tol=0.10)
    finally:
        sys.path.remove(BASE_DIR)


def _load_submitted_tests():
    sys.path.insert(0, BASE_DIR)
    path = os.path.join(BASE_DIR, "test_api.py")
    spec = importlib.util.spec_from_file_location("submitted_test_api", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_test_api_fixed():
    test_file = os.path.join(BASE_DIR, "test_api.py")
    assert os.path.isfile(test_file), f"File {test_file} does not exist."
    with open(test_file, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "test_api.py does not import hypothesis."
    assert "test_inv_sqrt_property" in content, "test_api.py is missing the test_inv_sqrt_property function."
    assert "0.1" in content and "1000.0" in content, "test_api.py does not seem to use the 0.1 to 1000.0 range for the property test."

    try:
        module = _load_submitted_tests()
        fn = getattr(module, "test_inv_sqrt_property", None)
        assert callable(fn), "test_inv_sqrt_property is not callable."
        assert getattr(fn, "is_hypothesis_test", False), "test_inv_sqrt_property is not a Hypothesis test."
        inner = getattr(getattr(fn, "hypothesis", None), "inner_test", None)
        assert callable(inner), "Hypothesis did not wrap test_inv_sqrt_property correctly."

        import math_ops
        seen = []

        def exact_inv_sqrt(value):
            value = float(value)
            seen.append(value)
            return 1.0 / math.sqrt(value)

        original_module_fn = getattr(module, "get_inv_sqrt", None)
        original_math_fn = math_ops.get_inv_sqrt
        inner_globals = inner.__globals__
        had_inner_fn = "get_inv_sqrt" in inner_globals
        original_inner_fn = inner_globals.get("get_inv_sqrt")

        try:
            module.get_inv_sqrt = exact_inv_sqrt
            math_ops.get_inv_sqrt = exact_inv_sqrt
            if had_inner_fn:
                inner_globals["get_inv_sqrt"] = exact_inv_sqrt
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                fn()

            assert len(seen) >= 2 and len(set(seen)) >= 2, "Property test did not exercise multiple generated values."
            assert all(math.isfinite(v) and 0.1 <= v <= 1000.0 for v in seen), (
                "Property test generated values outside 0.1 through 1000.0."
            )

            def bad_inv_sqrt(value):
                return 2.0 / math.sqrt(float(value))

            module.get_inv_sqrt = bad_inv_sqrt
            math_ops.get_inv_sqrt = bad_inv_sqrt
            if had_inner_fn:
                inner_globals["get_inv_sqrt"] = bad_inv_sqrt
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                with pytest.raises(AssertionError):
                    fn()
        finally:
            if original_module_fn is not None:
                module.get_inv_sqrt = original_module_fn
            math_ops.get_inv_sqrt = original_math_fn
            if had_inner_fn:
                inner_globals["get_inv_sqrt"] = original_inner_fn
    finally:
        if BASE_DIR in sys.path:
            sys.path.remove(BASE_DIR)


def test_submitted_pytest_suite_really_passes():
    proc = subprocess.run(
        [sys.executable, "-m", "pytest", "-q"],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, "Submitted pytest suite failed:\n" + proc.stdout


def test_test_results_log():
    log_file = os.path.join(BASE_DIR, "test_results.log")
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."
    with open(log_file, "r") as f:
        content = f.read()

    assert "passed" in content.lower() or "ok" in content.lower(), "test_results.log does not indicate that the tests passed."
    assert "failed" not in content.lower() or "0 failed" in content.lower(), "test_results.log indicates that tests failed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
