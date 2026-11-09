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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
import socket
from pathlib import Path

import numpy as np
import pytest
import requests
from scipy.optimize import minimize

BASE_SIGNAL = [1.0, 0.5, -0.2, -0.8, 0.1, 0.9, -0.4, 0.0]


def reference_denoise(signal):
    values = np.asarray(signal, dtype=np.float64)
    return values * np.exp(-0.01 * np.abs(values))


def compute_expected_pipeline(signal):
    # Derive expectations independently of the agent-installed package.
    denoised = reference_denoise(signal)
    fft_vals = np.fft.fft(denoised)
    n = len(fft_vals)
    pos_freq_magnitudes = np.abs(fft_vals[:n // 2 + (1 if n % 2 != 0 else 0)])

    def objective(alpha):
        target = 100 * np.exp(-alpha[0] * np.arange(len(pos_freq_magnitudes)))
        return np.mean((pos_freq_magnitudes - target) ** 2)

    result = minimize(objective, [1.0], method="Nelder-Mead")
    alpha = result.x[0]
    smoothed = 100 * np.exp(-alpha * np.arange(len(pos_freq_magnitudes)))
    return alpha, smoothed.tolist()


def generated_signals():
    rng = np.random.default_rng(731942)
    return [
        BASE_SIGNAL,
        [0.0, 3.25, -2.5, 0.125, 8.0],
        rng.normal(0.0, 1.7, 11).tolist(),
        rng.uniform(-6.0, 6.0, 16).tolist(),
        (rng.normal(size=23) * np.linspace(0.2, 4.0, 23)).tolist(),
    ]


def assert_pipeline_result(data, signal):
    expected_alpha, expected_smoothed = compute_expected_pipeline(signal)
    assert "alpha" in data, "Response JSON missing 'alpha' key."
    assert "smoothed_spectrum" in data, "Response JSON missing 'smoothed_spectrum' key."
    assert np.isclose(data["alpha"], expected_alpha, rtol=1e-3), (
        f"Expected alpha ~{expected_alpha}, got {data['alpha']}"
    )
    assert np.allclose(data["smoothed_spectrum"], expected_smoothed, rtol=1e-3), (
        "Smoothed spectrum does not match expected values."
    )


def test_pipeline_module_exists():
    path = Path("/home/user/pipeline_server.py")
    assert path.is_file(), "/home/user/pipeline_server.py is missing."
    assert path.stat().st_size > 0, "/home/user/pipeline_server.py is empty."


def test_makefile_fixed():
    makefile_path = "/app/freq_optimizer-1.0/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lm" in content, (
        "Makefile does not contain '-lm'. The C-extension will fail to link the math library."
    )
    active_lines = [
        line for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    assert any("-lm" in line for line in active_lines), (
        "The '-lm' flag appears only in a comment, not in an active Makefile line."
    )


def test_package_installed_and_working():
    try:
        import freq_optimizer
        import freq_optimizer._core as core
    except ImportError as exc:
        pytest.fail(f"Failed to import freq_optimizer: {exc}")

    assert any(core.__file__.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        "freq_optimizer._core is not an installed native extension module."
    )

    # Preserve the original numerical-stability check.
    signal = np.array([0.0, 1e10, -1e10])
    try:
        out = np.asarray(freq_optimizer.denoise(signal), dtype=np.float64)
        assert not np.any(np.isnan(out)), "Output contains NaN values."
    except Exception as exc:
        pytest.fail(f"freq_optimizer.denoise raised an exception: {exc}")

    # Verify denoise against the proprietary transform rather than trusting the
    # installed Python wrapper as the expectation oracle.
    probes = [
        np.array([0.0, 1.0, -1.0, 17.5, -240.0, 1e10, -1e10]),
        np.linspace(-50.0, 50.0, 37),
    ]
    for probe in probes:
        actual = np.asarray(freq_optimizer.denoise(probe), dtype=np.float64)
        expected = reference_denoise(probe)
        assert actual.shape == expected.shape
        assert np.all(np.isfinite(actual)), "denoise returned a non-finite value."
        assert np.allclose(actual, expected, rtol=1e-12, atol=1e-12), (
            "freq_optimizer.denoise does not implement the required native transform."
        )


@pytest.mark.parametrize("signal", generated_signals())
def test_http_api(signal):
    headers = {"Authorization": "Bearer ML_SECRET_2024"}
    payload = {"signal": signal}
    try:
        response = requests.post(
            "http://127.0.0.1:8000/process",
            json=payload,
            headers=headers,
            timeout=5,
        )
    except requests.RequestException as exc:
        pytest.fail(f"HTTP request to port 8000 failed: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"
    )
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert_pipeline_result(data, signal)


def request_tcp(signal):
    try:
        with socket.create_connection(("127.0.0.1", 9000), timeout=5) as sock:
            sock.settimeout(5)
            sock.sendall(b"AUTH:ML_SECRET_2024\n")
            payload = ",".join(map(str, signal)) + "\n"
            sock.sendall(payload.encode("utf-8"))
            response = b""
            while b"\n" not in response:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
    except Exception as exc:
        pytest.fail(f"TCP connection or communication failed: {exc}")

    response_str = response.decode("utf-8").strip()
    assert response_str, "Received empty response from TCP server."
    try:
        return [float(value) for value in response_str.split(",")]
    except ValueError:
        pytest.fail(
            f"TCP response could not be parsed as comma-separated floats: {response_str}"
        )


@pytest.mark.parametrize("signal", generated_signals())
def test_tcp_api(signal):
    _, expected_smoothed = compute_expected_pipeline(signal)
    actual_smoothed = request_tcp(signal)
    assert np.allclose(actual_smoothed, expected_smoothed, rtol=1e-3), (
        "TCP response smoothed spectrum does not match expected values."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
