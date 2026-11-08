#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import socket
import sys

import numpy as np
import pytest
import requests
import scipy.integrate
from scipy.linalg import expm

BASE = "/home/user/molecule_sim"


def get_redis_value(key: str):
    s = None
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(("127.0.0.1", 6379))
        s.sendall(f"GET {key}\r\n".encode())
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
            if b"\r\n" not in response:
                continue
            first = response.split(b"\r\n", 1)[0]
            if first.startswith(b"$"):
                length = int(first[1:])
                if length == -1:
                    return None
                start = len(first) + 2
                if len(response) >= start + length + 2:
                    return response[start:start + length].decode()
            elif first.startswith(b"-"):
                raise RuntimeError(first.decode())
            else:
                return first.decode()
    except Exception as exc:
        pytest.fail(f"Failed to connect to Redis or read key '{key}': {exc}")
    finally:
        if s is not None:
            s.close()
    return None


def load_calc():
    path = f"{BASE}/calc.py"
    spec = importlib.util.spec_from_file_location("submitted_calc", path)
    assert spec is not None and spec.loader is not None, f"Cannot load {path}"
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def unpack_bounds(result):
    if isinstance(result, dict):
        assert "lower_ci" in result and "upper_ci" in result
        lower, upper = result["lower_ci"], result["upper_ci"]
    elif isinstance(result, (tuple, list)) and len(result) == 2:
        lower, upper = result
    else:
        pytest.fail("compute_diffusion must return lower and upper confidence bounds")
    lower = np.asarray(lower, dtype=float)
    upper = np.asarray(upper, dtype=float)
    assert lower.shape == (4,) and upper.shape == (4,)
    assert np.all(np.isfinite(lower)) and np.all(np.isfinite(upper))
    assert np.all(lower <= upper + 1e-10)
    return lower, upper


def test_regularized_inverse_and_bootstrap_pipeline(monkeypatch):
    calc = load_calc()
    assert callable(getattr(calc, "solve_steady_state", None))
    assert callable(getattr(calc, "compute_diffusion", None))

    # This singular graph Laplacian has a well-defined Tikhonov-regularized inverse.
    lap = np.array([
        [1.0, -1.0, 0.0, 0.0],
        [-1.0, 2.0, -1.0, 0.0],
        [0.0, -1.0, 2.0, -1.0],
        [0.0, 0.0, -1.0, 1.0],
    ])
    got = np.asarray(calc.solve_steady_state(lap.copy()), dtype=float)
    expected = np.linalg.inv(lap + 1e-6 * np.eye(4))
    assert got.shape == (4, 4)
    np.testing.assert_allclose(got, expected, rtol=2e-6, atol=2e-5)

    real_odeint = scipy.integrate.odeint
    real_solve_ivp = scipy.integrate.solve_ivp
    calls = []

    def record(y0, final, matrix, start, end):
        y0 = np.asarray(y0, dtype=float).reshape(-1)
        final = np.asarray(final, dtype=float).reshape(-1)
        matrix = np.asarray(matrix, dtype=float)
        calls.append({"y0": y0, "final": final, "A": matrix,
                      "start": float(start), "end": float(end)})

    def odeint_wrapper(func, y0, t, args=(), **kwargs):
        t_arr = np.asarray(t, dtype=float)
        result = real_odeint(func, y0, t, args=args, **kwargs)
        values = result[0] if isinstance(result, tuple) else result
        n = np.asarray(y0).size
        tfirst = bool(kwargs.get("tfirst", False))

        def derivative(y):
            if tfirst:
                return np.asarray(func(float(t_arr[0]), y, *args), dtype=float)
            return np.asarray(func(y, float(t_arr[0]), *args), dtype=float)

        zero = derivative(np.zeros(n))
        assert np.allclose(zero, 0.0, atol=1e-10), "Diffusion ODE is not homogeneous"
        A = np.column_stack([derivative(np.eye(n)[i]) for i in range(n)])
        probe = np.arange(1, n + 1, dtype=float) / 7.0
        np.testing.assert_allclose(derivative(probe), A @ probe, rtol=1e-8, atol=1e-9)
        record(y0, np.asarray(values)[-1], A, t_arr[0], t_arr[-1])
        return result

    def solve_ivp_wrapper(fun, t_span, y0, *args, **kwargs):
        result = real_solve_ivp(fun, t_span, y0, *args, **kwargs)
        n = np.asarray(y0).size
        extra = kwargs.get("args", ())

        def derivative(y):
            return np.asarray(fun(float(t_span[0]), y, *extra), dtype=float)

        zero = derivative(np.zeros(n))
        assert np.allclose(zero, 0.0, atol=1e-10), "Diffusion ODE is not homogeneous"
        A = np.column_stack([derivative(np.eye(n)[i]) for i in range(n)])
        probe = np.arange(1, n + 1, dtype=float) / 7.0
        np.testing.assert_allclose(derivative(probe), A @ probe, rtol=1e-8, atol=1e-9)
        record(y0, result.y[:, -1], A, t_span[0], t_span[1])
        return result

    monkeypatch.setattr(scipy.integrate, "odeint", odeint_wrapper)
    monkeypatch.setattr(scipy.integrate, "solve_ivp", solve_ivp_wrapper)
    if hasattr(calc, "odeint"):
        monkeypatch.setattr(calc, "odeint", odeint_wrapper)
    if hasattr(calc, "solve_ivp"):
        monkeypatch.setattr(calc, "solve_ivp", solve_ivp_wrapper)

    initial = np.array([0.61, 0.23, 0.11, 0.05])
    lower, upper = unpack_bounds(calc.compute_diffusion(initial.copy()))

    # The implementation must integrate each of the 500 bootstrap vectors; an
    # additional nominal-state integration is permitted.
    assert len(calls) in (500, 501), f"Expected 500 bootstrap integrations, observed {len(calls)}"
    for call in calls:
        assert call["y0"].shape == (4,)
        assert call["start"] == pytest.approx(0.0, abs=1e-12)
        assert call["end"] == pytest.approx(5.0, abs=1e-12)
        assert all(np.any(np.isclose(v, initial, atol=0, rtol=0)) for v in call["y0"]), \
            "Bootstrap vectors must sample initial-state entries with replacement"
        assert call["A"].shape == (4, 4)
        # A = -(L + 1e-6 I), so a graph Laplacian's zero row sums become -1e-6.
        np.testing.assert_allclose(call["A"].sum(axis=1), -1e-6, rtol=2e-4, atol=2e-9)
        exact_final = expm(call["A"] * 5.0) @ call["y0"]
        np.testing.assert_allclose(call["final"], exact_final, rtol=2e-5, atol=2e-7)

    first_A = calls[0]["A"]
    for call in calls[1:]:
        np.testing.assert_allclose(call["A"], first_A, rtol=1e-10, atol=1e-12)

    # Match the returned percentiles to 500 independently recomputed endpoints.
    candidate_sets = []
    if len(calls) == 500:
        candidate_sets.append(calls)
    else:
        # A 501st call should be the nominal integration; allow it at any position.
        nominal_indices = [i for i, c in enumerate(calls)
                           if np.array_equal(c["y0"], initial)]
        for index in nominal_indices:
            candidate_sets.append(calls[:index] + calls[index + 1:])
    assert candidate_sets, "No nominal integration was identifiable among 501 calls"

    matched = False
    for selected in candidate_sets:
        finals = np.array([expm(c["A"] * 5.0) @ c["y0"] for c in selected])
        expected_lower = np.percentile(finals, 2.5, axis=0)
        expected_upper = np.percentile(finals, 97.5, axis=0)
        if (np.allclose(lower, expected_lower, rtol=2e-5, atol=2e-7) and
                np.allclose(upper, expected_upper, rtol=2e-5, atol=2e-7)):
            matched = True
            break
    assert matched, "Returned bounds are not the 2.5th/97.5th percentiles of 500 integrations"


def post_simulation(payload):
    url = "http://127.0.0.1:8080/simulate"
    try:
        response = requests.post(url, json=payload, timeout=60.0)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the Flask API at {url}: {exc}")
    assert response.status_code == 200, \
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response was not valid JSON: {response.text}")
    assert data.get("status") == "success"
    assert "lower_ci" in data, "Response JSON missing 'lower_ci'"
    assert "upper_ci" in data, "Response JSON missing 'upper_ci'"
    lower, upper = data["lower_ci"], data["upper_ci"]
    assert isinstance(lower, list), "'lower_ci' must be a list"
    assert isinstance(upper, list), "'upper_ci' must be a list"
    assert len(lower) == 4, f"Expected 'lower_ci' to have length 4, got {len(lower)}"
    assert len(upper) == 4, f"Expected 'upper_ci' to have length 4, got {len(upper)}"
    for val in lower + upper:
        assert isinstance(val, (int, float)) and np.isfinite(val), \
            f"Expected finite numeric CI values, got {val!r}"
    return data


def assert_redis_matches(data):
    redis_val_str = get_redis_value("latest_bounds")
    assert redis_val_str is not None, "Key 'latest_bounds' not found in Redis."
    try:
        redis_data = json.loads(redis_val_str)
    except json.JSONDecodeError:
        pytest.fail(f"Redis value for 'latest_bounds' is not valid JSON: {redis_val_str}")
    assert isinstance(redis_data, dict), f"Unexpected JSON structure in Redis: {redis_data}"
    assert "lower_ci" in redis_data and "upper_ci" in redis_data
    np.testing.assert_allclose(redis_data["lower_ci"], data["lower_ci"], rtol=0, atol=0)
    np.testing.assert_allclose(redis_data["upper_ci"], data["upper_ci"], rtol=0, atol=0)


def test_simulation_endpoint_and_redis_cache():
    # Preserve the original endpoint exercise and shape/type assertions.
    first = post_simulation({"initial_state": [1.0, 0.0, 0.0, 0.0]})
    assert_redis_matches(first)

    # Every bootstrap resample of a uniform vector is identical. For any graph
    # Laplacian, regularization therefore gives P(5)=exp(-5e-6) P(0), allowing
    # an exact graph-independent behavioral check despite no topology being supplied.
    second = post_simulation({"initial_state": [0.25, 0.25, 0.25, 0.25]})
    expected = np.full(4, 0.25 * np.exp(-5e-6))
    np.testing.assert_allclose(second["lower_ci"], expected, rtol=1e-6, atol=2e-7)
    np.testing.assert_allclose(second["upper_ci"], expected, rtol=1e-6, atol=2e-7)
    assert_redis_matches(second)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
