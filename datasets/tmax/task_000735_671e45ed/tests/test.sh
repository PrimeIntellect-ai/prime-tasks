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
import importlib
import importlib.metadata
import importlib.util
import os
import signal
import subprocess
import sys
import time

import h5py
import numpy as np
import pytest
import requests

SCRIPT = "/home/user/run_pipeline.sh"
RESULTS = "/home/user/results.txt"
BASE_URL = "http://127.0.0.1:9090"
AUTH = {"Authorization": "Bearer secret-bio-token"}


def get_expected_trace(seq_id):
    spectra_file = "/app/data/spectra.h5"
    if not os.path.exists(spectra_file):
        pytest.fail(f"Data file {spectra_file} is missing.")

    with h5py.File(spectra_file, "r") as f:
        if seq_id not in f:
            pytest.fail(f"Dataset {seq_id} missing in HDF5 file.")
        M = f[seq_id][:]

    L = np.linalg.cholesky(M + np.eye(M.shape[0]) * 1e-5)
    return np.trace(L)


def wait_for_server(url, timeout=10):
    start = time.time()
    while time.time() - start < timeout:
        try:
            requests.get(url, timeout=1)
            return
        except requests.RequestException:
            time.sleep(0.2)
    pytest.fail(f"Server not reachable at {url} within {timeout} seconds.")


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
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
        except OSError:
            pass
    return pids


def stop_existing_server():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(9090)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.5)
    assert not listener_pids(9090), "Could not stop the pre-existing service on port 9090"


@pytest.fixture(scope="session", autouse=True)
def execute_master_pipeline():
    assert os.path.isfile(SCRIPT), f"Master pipeline script {SCRIPT} is missing."

    stop_existing_server()
    try:
        os.remove(RESULTS)
    except FileNotFoundError:
        pass

    # Remove any prior installation so running the master script must install it.
    subprocess.run(
        [sys.executable, "-m", "pip", "uninstall", "-y", "biomatrix"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
        check=False,
    )

    log_path = "/tmp/run_pipeline.log"
    with open(log_path, "w") as log:
        proc = subprocess.Popen(
            ["/bin/bash", SCRIPT],
            cwd="/home/user",
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            rc = proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            pytest.fail("run_pipeline.sh did not finish after starting its background server")

    if rc != 0:
        with open(log_path, errors="replace") as log:
            pytest.fail(f"run_pipeline.sh exited with status {rc}:\n{log.read()}")

    wait_for_server(BASE_URL, timeout=15)


def assert_correct_factorizer(fn):
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    matrices = []
    a = rng.normal(size=(9, 5))
    matrices.append(a @ a.T)
    b = rng.normal(size=(6, 6))
    matrices.append(b @ b.T + np.eye(6) * 0.2)

    for matrix in matrices:
        expected = np.linalg.cholesky(matrix + np.eye(matrix.shape[0]) * 1e-5)
        actual = np.asarray(fn(matrix.copy()))
        assert actual.shape == expected.shape
        np.testing.assert_allclose(actual, expected, rtol=1e-9, atol=1e-11)


def test_vendored_solver_was_fixed():
    solver_path = "/app/vendor/biomatrix-0.1.0/biomatrix/solver.py"
    assert os.path.isfile(solver_path), f"Vendored solver {solver_path} is missing."
    spec = importlib.util.spec_from_file_location("vendored_solver_under_test", solver_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert_correct_factorizer(module.factorize_signal)


def test_fixed_package_is_installed():
    assert importlib.metadata.version("biomatrix") == "0.1.0"
    for name in list(sys.modules):
        if name == "biomatrix" or name.startswith("biomatrix."):
            del sys.modules[name]
    importlib.invalidate_caches()
    solver = importlib.import_module("biomatrix.solver")
    assert_correct_factorizer(solver.factorize_signal)


def test_results_file_exists_and_format():
    results_file = "/home/user/results.txt"
    assert os.path.isfile(results_file), f"Results file {results_file} is missing."

    with open(results_file, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 50, f"Expected 50 lines in {results_file}, found {len(lines)}."

    # Keep the original seq_10 formatting and correctness assertions.
    seq_10_line = next((line for line in lines if line.startswith("seq_10:")), None)
    assert seq_10_line is not None, "seq_10 not found in results.txt"

    parts = seq_10_line.split(":")
    assert len(parts) == 2, f"Malformed line for seq_10 in results.txt: {seq_10_line}"

    val_str = parts[1].strip()
    try:
        val = float(val_str)
    except ValueError:
        pytest.fail(f"Value for seq_10 is not a valid float: {val_str}")

    expected_val = get_expected_trace("seq_10")
    assert np.isclose(val, expected_val, rtol=1e-4), f"Incorrect trace for seq_10 in results.txt. Expected {expected_val}, got {val}"

    parsed = {}
    for line in lines:
        parts = line.split(":")
        assert len(parts) == 2, f"Malformed results line: {line}"
        seq_id, value_text = parts[0].strip(), parts[1].strip()
        assert seq_id not in parsed, f"Duplicate sequence in results.txt: {seq_id}"
        try:
            parsed[seq_id] = float(value_text)
        except ValueError:
            pytest.fail(f"Value for {seq_id} is not a valid float: {value_text}")

    expected_ids = {f"seq_{i}" for i in range(50)}
    assert set(parsed) == expected_ids, "results.txt must contain each seq_0 through seq_49 exactly once"
    for seq_id in sorted(expected_ids):
        expected = get_expected_trace(seq_id)
        assert np.isclose(parsed[seq_id], expected, rtol=1e-4), \
            f"Incorrect trace for {seq_id}. Expected {expected}, got {parsed[seq_id]}"


def test_server_unauthorized():
    url = "http://127.0.0.1:9090/trace/seq_10"
    wait_for_server("http://127.0.0.1:9090")

    response = requests.get(url, timeout=3)
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"


def test_server_invalid_token():
    url = "http://127.0.0.1:9090/trace/seq_10"
    headers = {"Authorization": "Bearer wrong-token"}
    response = requests.get(url, headers=headers, timeout=3)
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {response.status_code}"


def test_server_valid_request():
    url = "http://127.0.0.1:9090/trace/seq_10"
    headers = {"Authorization": "Bearer secret-bio-token"}
    response = requests.get(url, headers=headers, timeout=3)

    assert response.status_code == 200, f"Expected 200 OK for valid request, got {response.status_code}. Response: {response.text}"

    try:
        returned_trace = float(response.text.strip())
    except ValueError:
        pytest.fail(f"Server returned non-float response: {response.text}")

    expected_val = get_expected_trace("seq_10")
    assert np.isclose(returned_trace, expected_val, rtol=1e-4), f"Server returned incorrect trace for seq_10. Expected {expected_val}, got {returned_trace}"


def test_server_another_sequence():
    url = "http://127.0.0.1:9090/trace/seq_42"
    headers = {"Authorization": "Bearer secret-bio-token"}
    response = requests.get(url, headers=headers, timeout=3)

    assert response.status_code == 200, f"Expected 200 OK for valid request, got {response.status_code}"

    try:
        returned_trace = float(response.text.strip())
    except ValueError:
        pytest.fail(f"Server returned non-float response: {response.text}")

    expected_val = get_expected_trace("seq_42")
    assert np.isclose(returned_trace, expected_val, rtol=1e-4), f"Server returned incorrect trace for seq_42. Expected {expected_val}, got {returned_trace}"


def test_server_all_sequences():
    for i in range(50):
        seq_id = f"seq_{i}"
        response = requests.get(f"{BASE_URL}/trace/{seq_id}", headers=AUTH, timeout=3)
        assert response.status_code == 200, f"Expected 200 for {seq_id}, got {response.status_code}"
        try:
            returned = float(response.text.strip())
        except ValueError:
            pytest.fail(f"Server returned a non-float response for {seq_id}: {response.text}")
        expected = get_expected_trace(seq_id)
        assert np.isclose(returned, expected, rtol=1e-4), \
            f"Server returned incorrect trace for {seq_id}. Expected {expected}, got {returned}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
