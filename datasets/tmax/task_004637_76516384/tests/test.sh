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
import ast
import math
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid

import pytest
import requests

APP = "/home/user/app"
RESHAPE = APP + "/scripts/reshape_data.sh"
RUN_MPI = APP + "/scripts/run_mpi_sim.sh"
SIMULATOR = APP + "/simulator.py"
VENV_PYTHON = "/home/user/venv/bin/python"
EXPECTED_RESULT = 10.0 * (1.0 - 0.01) ** 100


def aggregator_request(message):
    with socket.create_connection(("127.0.0.1", 9090), timeout=5) as sock:
        sock.sendall(message.encode() + b"\n")
        if message == "GET_RESULTS":
            return sock.recv(1024).decode("utf-8").strip()


def test_simulation_pipeline():
    # Make stale or hardcoded aggregator values distinguishable from this run.
    aggregator_request("RESULT 1234567.25")

    payload = {
        "data": "0.0,10.0,0.1\n0.1,9.8,0.2\n0.2,9.5,0.8\n0.3,9.1,0.1"
    }
    try:
        response = requests.post(
            "http://127.0.0.1:8080/simulate", json=payload, timeout=15
        )
        assert response.status_code == 200, (
            f"Expected status code 200, got {response.status_code}. "
            f"Response: {response.text}"
        )
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API Gateway at 127.0.0.1:8080: {exc}")

    deadline = time.time() + 10
    data = ""
    while time.time() < deadline:
        try:
            data = aggregator_request("GET_RESULTS")
            if data and float(data) != 1234567.25:
                break
        except (OSError, ValueError):
            pass
        time.sleep(0.2)

    assert data, "Received empty response from Aggregator"
    try:
        result_val = float(data)
    except ValueError:
        pytest.fail(f"Expected a floating point number from Aggregator, got: {data}")

    assert not math.isnan(result_val), "Simulation diverged: received NaN"
    assert not math.isinf(result_val), "Simulation diverged: received Infinity"
    assert result_val != 1234567.25, "Aggregator was not updated by this request"
    assert math.isclose(result_val, EXPECTED_RESULT, rel_tol=1e-9, abs_tol=1e-9), (
        f"Expected Euler integration result {EXPECTED_RESULT}, got {result_val}"
    )


def test_configuration_ports():
    settings = {}
    with open(APP + "/config/settings.env", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                settings[key.strip()] = value.strip()
    assert settings.get("GATEWAY_PORT") == "8080"
    assert settings.get("WORKER_PORT") == "5000"
    assert settings.get("AGGREGATOR_PORT") == "9090"


def test_reshape_data_behavior():
    assert os.path.isfile(RESHAPE), f"Missing {RESHAPE}"
    with open(RESHAPE, encoding="utf-8") as handle:
        content = handle.read()
    assert "0.5" in content, "reshape_data.sh does not seem to filter error > 0.5"

    token = uuid.uuid4().int % 100000
    rows = [
        (token + 0.125, 17.25, 0.5),
        (token + 1.375, -3.75, 0.5001),
        (token + 2.625, 91.125, 0.0),
        (token + 3.875, 44.5, 0.91),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        source = os.path.join(tmp, "raw.csv")
        output = os.path.join(tmp, "reshaped.dat")
        with open(source, "w", encoding="utf-8") as handle:
            for row in rows:
                handle.write(f"{row[0]},{row[1]},{row[2]}\n")
        with open(output, "w", encoding="utf-8") as handle:
            handle.write("stale output must be replaced\n")

        subprocess.run([RESHAPE, source, output], check=True, timeout=10)
        with open(output, encoding="utf-8") as handle:
            lines = [line.strip() for line in handle if line.strip()]

    assert all("," not in line for line in lines), "Output must be space-separated"
    parsed = []
    for line in lines:
        fields = line.split()
        assert len(fields) == 2, f"Expected exactly 'time value', got {line!r}"
        parsed.append(tuple(map(float, fields)))
    expected = [(rows[0][0], rows[0][1]), (rows[2][0], rows[2][1])]
    assert parsed == expected, f"Expected filtered rows {expected}, got {parsed}"


def test_run_mpi_wrapper_really_launches_four_venv_ranks():
    assert os.path.isfile(RUN_MPI), f"Missing {RUN_MPI}"
    with open(RUN_MPI, encoding="utf-8") as handle:
        content = handle.read()
    assert "mpirun" in content and "-n 4" in content, (
        "run_mpi_sim.sh does not invoke mpirun with 4 processes"
    )
    assert "venv" in content, "run_mpi_sim.sh does not load the virtual environment"

    with tempfile.TemporaryDirectory() as tmp:
        original = open(SIMULATOR, "rb").read()
        original_mode = os.stat(SIMULATOR).st_mode
        probe = f'''import os, sys\nfrom mpi4py import MPI\ncomm = MPI.COMM_WORLD\nrank = comm.Get_rank()\nwith open({tmp!r} + "/rank_" + str(rank), "w") as f:\n    f.write(str(comm.Get_size()) + "\\n")\n    f.write(sys.prefix + "\\n")\n    f.write(os.environ.get("VIRTUAL_ENV", "") + "\\n")\n    f.write(" ".join(sys.argv[1:]) + "\\n")\ncomm.Barrier()\n'''
        input_path = os.path.join(tmp, "input.dat")
        with open(input_path, "w", encoding="utf-8") as handle:
            handle.write("0 10\n")
        try:
            with open(SIMULATOR, "w", encoding="utf-8") as handle:
                handle.write(probe)
            os.chmod(SIMULATOR, original_mode)
            env = os.environ.copy()
            env["OMPI_ALLOW_RUN_AS_ROOT"] = "1"
            env["OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"] = "1"
            subprocess.run([RUN_MPI, input_path], check=True, timeout=30, env=env)
        finally:
            with open(SIMULATOR, "wb") as handle:
                handle.write(original)
            os.chmod(SIMULATOR, original_mode)

        files = sorted(name for name in os.listdir(tmp) if name.startswith("rank_"))
        assert files == ["rank_0", "rank_1", "rank_2", "rank_3"], (
            f"Expected four MPI ranks, got {files}"
        )
        for name in files:
            lines = open(os.path.join(tmp, name), encoding="utf-8").read().splitlines()
            assert lines[0] == "4", f"{name} reports MPI world size {lines[0]}"
            assert lines[1] == "/home/user/venv", f"{name} used Python prefix {lines[1]}"
            assert lines[2] == "/home/user/venv", f"{name} did not inherit the venv"
            assert lines[3] == input_path, f"{name} did not receive the input path"


def test_simulator_dt_and_numerical_behavior():
    assert os.path.isfile(SIMULATOR), f"Missing {SIMULATOR}"
    source = open(SIMULATOR, encoding="utf-8").read()
    assert "0.01" in source, "simulator.py does not seem to use dt = 0.01"

    tree = ast.parse(source)
    dt_values = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(target, ast.Name) and target.id == "dt" for target in targets):
                try:
                    dt_values.append(float(ast.literal_eval(node.value)))
                except (ValueError, TypeError):
                    pass
    assert 0.01 in dt_values, "dt is not assigned the numeric value 0.01"

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]
    received = []

    def receive_result():
        listener.settimeout(15)
        try:
            conn, _ = listener.accept()
            with conn:
                received.append(conn.recv(1024).decode().strip())
        finally:
            listener.close()

    thread = threading.Thread(target=receive_result, daemon=True)
    thread.start()
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as handle:
        handle.write("0 10\n")
        input_path = handle.name
    env = os.environ.copy()
    env["AGGREGATOR_PORT"] = str(port)
    try:
        subprocess.run(
            [VENV_PYTHON, SIMULATOR, input_path], check=True, timeout=20, env=env
        )
    finally:
        os.unlink(input_path)
    thread.join(timeout=16)

    assert received and received[0].startswith("RESULT "), (
        f"Simulator did not send a result; received {received}"
    )
    value = float(received[0].split()[1])
    assert math.isclose(value, EXPECTED_RESULT, rel_tol=1e-9, abs_tol=1e-9), (
        f"Simulator produced {value}, expected {EXPECTED_RESULT}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
