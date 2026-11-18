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
import math
import os
import re
import shutil
import subprocess
import time

import numpy as np
import pytest
import requests

EXECUTABLE = "/home/user/integrator"
ANALYZER = "/home/user/analyze.sh"
URL = "http://127.0.0.1:8080/simulate"
TOKEN_HEADERS = {"Authorization": "Bearer perf-eng-token-2024"}


def _run_integrator(freq, damping, duration=8.0):
    env = os.environ.copy()
    env.update({
        "DAMPING_COEF": str(damping),
        "NATURAL_FREQ": str(freq),
        "H_MAX": "0.01",
    })
    proc = subprocess.run(
        [EXECUTABLE, str(duration)], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert proc.returncode == 0, f"integrator failed: {proc.stderr}"

    rows = []
    for line in proc.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        try:
            rows.append((float(fields[0]), float(fields[1])))
        except ValueError:
            continue
    assert len(rows) >= 100, "integrator did not emit a usable time series"
    data = np.asarray(rows, dtype=float)
    assert np.all(np.isfinite(data)), "integrator emitted non-finite values"
    assert np.all(np.diff(data[:, 0]) > 0), "integrator timestamps are not increasing"
    return data


def _dominant_frequency(data):
    t = data[:, 0]
    y = data[:, 1]
    dt = float(np.median(np.diff(t)))
    uniform_t = np.arange(t[0], t[-1] + dt / 2, dt)
    uniform_y = np.interp(uniform_t, t, y)
    uniform_y = uniform_y - np.mean(uniform_y)
    spectrum = np.abs(np.fft.rfft(uniform_y))
    frequencies = np.fft.rfftfreq(len(uniform_y), dt)
    spectrum[0] = 0
    return float(frequencies[int(np.argmax(spectrum))])


def _numbers(text):
    return [float(x) for x in re.findall(r"(?<![A-Za-z_])[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", text)]


def _run_analyzer_on(path, contents):
    attempts = [
        ([path], contents),
        ([path, "/tmp/verifier_signal.txt"], None),
    ]
    outputs = []
    with open("/tmp/verifier_signal.txt", "w") as f:
        f.write(contents)
    for command, stdin_text in attempts:
        try:
            proc = subprocess.run(
                command, input=stdin_text, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
            )
            if proc.returncode == 0:
                outputs.append(proc.stdout + "\n" + proc.stderr)
        except subprocess.TimeoutExpired:
            pass
    return outputs


def test_compiled_executable_exists():
    """Verify that the compiled integrator executable exists."""
    assert os.path.exists(EXECUTABLE), f"Compiled executable missing: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "integrator must be a compiled native executable"


def test_analyze_script_exists():
    """Verify that the analyze.sh script exists."""
    assert os.path.exists(ANALYZER), f"Analyze script missing: {ANALYZER}"
    assert os.access(ANALYZER, os.X_OK), f"Script is not executable: {ANALYZER}"


def test_integrator_executes_and_uses_extracted_environment():
    first = _run_integrator(2.5, 0.15)
    second = _run_integrator(1.25, 0.15)
    assert math.isclose(_dominant_frequency(first), 2.5, abs_tol=0.2)
    assert math.isclose(_dominant_frequency(second), 1.25, abs_tol=0.2)

    weak = _run_integrator(2.5, 0.05, duration=2.0)
    strong = _run_integrator(2.5, 0.30, duration=2.0)
    weak_tail = float(np.sqrt(np.mean(weak[-50:, 1] ** 2)))
    strong_tail = float(np.sqrt(np.mean(strong[-50:, 1] ** 2)))
    assert strong_tail < weak_tail * 0.8, "DAMPING_COEF does not affect oscillator decay"


def test_analyze_script_performs_input_dependent_spectral_analysis():
    for frequency in (1.25, 3.0):
        t = np.arange(0.0, 8.0, 0.01)
        y = np.sin(2 * np.pi * frequency * t)
        contents = "".join(f"{ti:.6f} {yi:.9f}\n" for ti, yi in zip(t, y))
        outputs = _run_analyzer_on(ANALYZER, contents)
        assert outputs, "analyze.sh could not analyze a time series from stdin or a file argument"
        assert any(
            any(math.isclose(value, frequency, abs_tol=0.15) for value in _numbers(output))
            for output in outputs
        ), f"analyze.sh did not report the synthetic signal's {frequency} Hz dominant frequency"


def test_simulate_endpoint_unauthorized():
    """Verify that the /simulate endpoint rejects unauthorized requests with 401."""
    payload = {"duration": 50.0}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_simulate_endpoint_authorized_and_correct():
    """Verify that the /simulate endpoint works correctly with valid auth and payload."""
    payload = {"duration": 50.0}
    try:
        response = requests.post(URL, json=payload, headers=TOKEN_HEADERS, timeout=15)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "h_max" in data, "Response JSON missing 'h_max' field"
    assert "dominant_frequency" in data, "Response JSON missing 'dominant_frequency' field"
    h_max = data["h_max"]
    dominant_frequency = data["dominant_frequency"]
    assert isinstance(h_max, (int, float)), "h_max must be a number"
    assert isinstance(dominant_frequency, (int, float)), "dominant_frequency must be a number"
    assert h_max <= 0.05, f"h_max should be <= 0.05 to demonstrate stable integration, got {h_max}"
    assert math.isclose(dominant_frequency, 2.5, abs_tol=0.2), f"dominant_frequency should be close to 2.5, got {dominant_frequency}"


def test_service_runs_integrator_analyzer_and_optimization():
    integrator_real = EXECUTABLE + ".verifier-real"
    analyzer_real = ANALYZER + ".verifier-real"
    int_log = "/tmp/verifier-integrator-calls"
    ana_log = "/tmp/verifier-analyzer-calls"

    for path in (integrator_real, analyzer_real):
        if os.path.exists(path):
            os.unlink(path)
    open(int_log, "w").close()
    open(ana_log, "w").close()
    os.chmod(int_log, 0o666)
    os.chmod(ana_log, 0o666)

    os.rename(EXECUTABLE, integrator_real)
    os.rename(ANALYZER, analyzer_real)
    try:
        with open(EXECUTABLE, "w") as f:
            f.write("#!/bin/bash\nprintf '%s\\t%s\\t%s\\t%s\\n' \"${DAMPING_COEF-}\" \"${NATURAL_FREQ-}\" \"${H_MAX-}\" \"$*\" >> /tmp/verifier-integrator-calls\nexec /home/user/integrator.verifier-real \"$@\"\n")
        with open(ANALYZER, "w") as f:
            f.write("#!/bin/bash\nprintf '%s\\n' \"$*\" >> /tmp/verifier-analyzer-calls\nexec /home/user/analyze.sh.verifier-real \"$@\"\n")
        os.chmod(EXECUTABLE, 0o755)
        os.chmod(ANALYZER, 0o755)

        response = requests.post(
            URL, json={"duration": 13.25}, headers=TOKEN_HEADERS, timeout=30
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert math.isclose(float(data["dominant_frequency"]), 2.5, abs_tol=0.2)
        assert 0 < float(data["h_max"]) <= 0.05
    finally:
        if os.path.exists(EXECUTABLE):
            os.unlink(EXECUTABLE)
        if os.path.exists(ANALYZER):
            os.unlink(ANALYZER)
        if os.path.exists(integrator_real):
            os.rename(integrator_real, EXECUTABLE)
        if os.path.exists(analyzer_real):
            os.rename(analyzer_real, ANALYZER)

    with open(int_log) as f:
        calls = [line.rstrip("\n").split("\t", 3) for line in f if line.strip()]
    assert calls, "the service did not execute /home/user/integrator"
    assert all(len(call) == 4 for call in calls)
    assert all(math.isclose(float(call[0]), 0.15, abs_tol=1e-9) for call in calls), "service did not pass DAMPING_COEF=0.15"
    assert all(math.isclose(float(call[1]), 2.5, abs_tol=1e-9) for call in calls), "service did not pass NATURAL_FREQ=2.5"
    assert any(any(math.isclose(float(arg), 13.25, abs_tol=1e-9) for arg in call[3].split() if re.fullmatch(r"[-+0-9.eE]+", arg)) for call in calls), "request duration was not passed to the integrator"

    tested_steps = set()
    for call in calls:
        try:
            step = float(call[2])
            if math.isfinite(step) and step > 0:
                tested_steps.add(round(step, 12))
        except ValueError:
            pass
    assert len(tested_steps) >= 2, "optimization did not evaluate multiple H_MAX candidates"

    with open(ana_log) as f:
        analyzer_calls = [line for line in f if line.strip()]
    assert analyzer_calls, "the service did not execute /home/user/analyze.sh"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
