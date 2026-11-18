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
import json
import math
import os
import signal
import stat
import subprocess
import time

import numpy as np
import pytest
import requests

BINARY = "/app/spectral-ode-sim-1.0/ode_sim"
SOURCE_DIR = "/app/spectral-ode-sim-1.0"
SIM_CSV = "/home/user/sim_results.csv"
REF_CSV = "/home/user/reference.csv"
SCRIPT = "/home/user/analyze_and_serve.sh"
URL = "http://127.0.0.1:8333/status"


def dominant_frequency(path):
    data = np.loadtxt(path, delimiter=",")
    assert data.ndim == 2 and data.shape[1] == 2
    assert data.shape[0] >= 3
    times = data[:, 0]
    values = data[:, 1]
    assert np.all(np.isfinite(data))
    spacing = np.diff(times)
    assert np.all(spacing > 0)
    dt = float(np.median(spacing))
    spectrum = np.abs(np.fft.rfft(values))
    frequencies = np.fft.rfftfreq(len(values), d=dt)
    assert len(spectrum) > 1
    return float(frequencies[1 + np.argmax(spectrum[1:])])


def get_status(timeout=5):
    response = requests.get(URL, timeout=timeout)
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type: application/json, got {content_type}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")
    return response, data


def listener_pids(port=8333):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_server():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)
    assert not listener_pids(), "Could not stop the existing server on port 8333"


def start_script_and_wait():
    proc = subprocess.Popen(
        ["bash", SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    last_error = None
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            return proc, get_status(timeout=0.5)
        except (requests.RequestException, AssertionError) as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"analyze_and_serve.sh did not start a valid server: {last_error}")


def write_signal(path, frequency, n=1000, dt=0.01):
    with open(path, "w") as f:
        for i in range(n):
            t = i * dt
            value = math.sin(2 * math.pi * frequency * t)
            f.write(f"{t:.8f},{value:.12f}\n")


def assert_payload(data, expected_peak, expected_match):
    assert set(data) == {"peak_freq", "reference_match"}, "JSON body must contain exactly the required keys."
    assert isinstance(data["peak_freq"], (int, float)) and not isinstance(data["peak_freq"], bool), "'peak_freq' must be a number."
    assert isinstance(data["reference_match"], bool), "'reference_match' must be a boolean."
    assert math.isfinite(float(data["peak_freq"]))
    assert float(data["peak_freq"]) == pytest.approx(round(expected_peak, 2), abs=1e-9)
    assert data["reference_match"] is expected_match


def test_ode_sim_compiled():
    """Verify that the Makefile really builds a functional ode_sim binary."""
    if os.path.exists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        ["make"], cwd=SOURCE_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"The repaired Makefile failed to compile ode_sim:\n{result.stdout}"
    assert os.path.isfile(BINARY), f"Binary {BINARY} does not exist. Did you fix the Makefile and compile?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "ode_sim is not a compiled ELF binary."

    run = subprocess.run([BINARY, "1000"], cwd=SOURCE_DIR, capture_output=True, text=True, timeout=30)
    assert run.returncode == 0, f"ode_sim failed when run: {run.stderr}"
    rows = [line.split(",") for line in run.stdout.splitlines()]
    assert len(rows) == 1000, f"ode_sim 1000 produced {len(rows)} rows instead of 1000."
    for i, row in enumerate(rows):
        assert len(row) == 2
        t, value = map(float, row)
        expected_t = i * 0.01
        expected_value = math.sin(2 * math.pi * 2.15 * expected_t) + 0.1 * math.cos(2 * math.pi * 5.0 * expected_t)
        assert t == pytest.approx(expected_t, abs=1e-6)
        assert value == pytest.approx(expected_value, abs=2e-6)


def test_sim_results_generated():
    """Verify that sim_results.csv is the actual 1000-step simulator output."""
    assert os.path.isfile(SIM_CSV), f"File {SIM_CSV} does not exist. Did you run the simulator?"
    assert os.path.getsize(SIM_CSV) > 0, f"File {SIM_CSV} is empty."
    fresh = subprocess.run([BINARY, "1000"], cwd=SOURCE_DIR, capture_output=True, timeout=30)
    assert fresh.returncode == 0
    with open(SIM_CSV, "rb") as f:
        submitted = f.read()
    assert submitted == fresh.stdout, "sim_results.csv is not the output of ./ode_sim 1000."
    data = np.loadtxt(SIM_CSV, delimiter=",")
    assert data.shape == (1000, 2)


def test_analyze_and_serve_script_exists():
    """Verify that the analyze_and_serve.sh script exists."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."


def test_analysis_script_computes_fft_and_comparison():
    """Exercise the script on independently generated inputs, including both match outcomes."""
    with open(SIM_CSV, "rb") as f:
        original_sim = f.read()
    with open(REF_CSV, "rb") as f:
        original_ref = f.read()

    try:
        stop_server()

        write_signal(SIM_CSV, 3.2)
        write_signal(REF_CSV, 3.2)
        _, (_, data) = start_script_and_wait()
        sim_peak = dominant_frequency(SIM_CSV)
        ref_peak = dominant_frequency(REF_CSV)
        assert_payload(data, sim_peak, abs(sim_peak - ref_peak) <= 0.05)
        assert data["reference_match"] is True

        stop_server()
        write_signal(SIM_CSV, 4.1)
        write_signal(REF_CSV, 2.7)
        _, (_, data) = start_script_and_wait()
        sim_peak = dominant_frequency(SIM_CSV)
        ref_peak = dominant_frequency(REF_CSV)
        assert_payload(data, sim_peak, abs(sim_peak - ref_peak) <= 0.05)
        assert data["reference_match"] is False
    finally:
        stop_server()
        with open(SIM_CSV, "wb") as f:
            f.write(original_sim)
        with open(REF_CSV, "wb") as f:
            f.write(original_ref)
        start_script_and_wait()


def test_http_api_status():
    """Verify that the persistent API reports the FFT result for the required datasets."""
    try:
        response, data = get_status()
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {URL}. Is it running? Error: {e}")

    assert "peak_freq" in data, "JSON response missing 'peak_freq' key."
    assert "reference_match" in data, "JSON response missing 'reference_match' key."
    assert isinstance(data["peak_freq"], (int, float)), "'peak_freq' must be a number."
    assert isinstance(data["reference_match"], bool), "'reference_match' must be a boolean."

    expected_sim = dominant_frequency(SIM_CSV)
    expected_ref = dominant_frequency(REF_CSV)
    assert_payload(data, expected_sim, abs(expected_sim - expected_ref) <= 0.05)

    # Keep the original expected assertion for the supplied datasets.
    assert data["reference_match"] is True, "Expected reference_match to be true."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
