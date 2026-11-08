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
import glob
import math
import os
import re
import signal
import subprocess
import time
import wave

import pytest
import requests

SIM_DIR = "/home/user/sim_server"
WAV_PATH = "/app/source.wav"
URL = "http://127.0.0.1:9090/solve"


def assert_response(expected_amplitude, expected_solution):
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "max_amplitude" in data, "Response JSON missing 'max_amplitude' field."
    assert "solution" in data, "Response JSON missing 'solution' field."
    assert math.isclose(float(data["max_amplitude"]), expected_amplitude, rel_tol=1e-9, abs_tol=1e-9), \
        f"Expected max_amplitude {expected_amplitude}, got {data['max_amplitude']}"

    actual = data["solution"]
    assert isinstance(actual, list), "'solution' must be a list."
    assert len(actual) == 3, f"Expected 'solution' to have 3 elements, got {len(actual)}"
    for i, (got, want) in enumerate(zip(actual, expected_solution)):
        assert isinstance(got, (int, float)) and not isinstance(got, bool), \
            f"Solution element {i} is not numeric"
        assert math.isclose(float(got), want, rel_tol=1e-9, abs_tol=0.01), \
            f"Solution element {i} incorrect. Expected approx {want}, got {got}"


def independently_solve(amplitude):
    a = [[4.0, -1.0, 0.0], [-1.0, 4.0, -1.0], [0.0, -1.0, 4.0]]
    b = [amplitude, amplitude / 2.0, amplitude / 4.0]
    n = len(b)
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(a[row][col]))
        assert a[pivot][col] != 0.0
        if pivot != col:
            a[col], a[pivot] = a[pivot], a[col]
            b[col], b[pivot] = b[pivot], b[col]
        for row in range(col + 1, n):
            factor = a[row][col] / a[col][col]
            for k in range(col, n):
                a[row][k] -= factor * a[col][k]
            b[row] -= factor * b[col]
    x = [0.0] * n
    for row in range(n - 1, -1, -1):
        x[row] = (b[row] - sum(a[row][k] * x[k] for k in range(row + 1, n))) / a[row][row]
    return x


def kill_port_9090():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].upper().endswith(":2382") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = int(proc_dir.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc_dir + "/fd"):
                try:
                    target = os.readlink(proc_dir + "/fd/" + fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    victims.add(pid)
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        if all(not os.path.exists(f"/proc/{pid}") for pid in victims):
            break
        time.sleep(0.05)
    for pid in victims:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.15)


def write_wav(samples):
    import struct
    with wave.open(WAV_PATH, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(11025)
        output.writeframes(b"".join(struct.pack("<h", value) for value in samples))


def launch_and_wait():
    proc = subprocess.Popen(
        ["go", "run", "."],
        cwd=SIM_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    deadline = time.time() + 20
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            stdout, stderr = proc.communicate(timeout=2)
            pytest.fail(f"Submitted server exited during startup:\n{stdout}\n{stderr}")
        try:
            requests.get(URL, timeout=0.3)
            return proc
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.15)
    stop_process(proc)
    pytest.fail(f"Submitted server did not listen on port 9090: {last_error}")


def stop_process(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)
    kill_port_9090()


def test_go_test_passes_and_regression_test_exists():
    assert os.path.isdir(SIM_DIR), f"Expected directory {SIM_DIR} does not exist."
    test_path = os.path.join(SIM_DIR, "math_test.go")
    assert os.path.isfile(test_path), "Required math_test.go is missing."

    sources = {}
    for path in glob.glob(os.path.join(SIM_DIR, "*.go")):
        with open(path, encoding="utf-8") as handle:
            sources[path] = handle.read()
    implementation = "\n".join(text for path, text in sources.items() if not path.endswith("_test.go"))
    regression = sources[test_path]

    assert '"encoding/binary"' in implementation, "WAV implementation must use encoding/binary."
    assert re.search(r'"os"', implementation), "WAV implementation must use os."
    assert "gonum" not in implementation.lower(), "External Gonum numerical code is forbidden."
    assert re.search(r"\bfunc\s+Test\w*\s*\(\s*\w+\s+\*testing\.T\s*\)", regression), \
        "math_test.go must contain a standard Go Test function."

    implementation_functions = set(re.findall(r"\bfunc\s+(\w+)\s*\(", implementation))
    implementation_functions.discard("main")
    called_functions = {name for name in implementation_functions if re.search(r"\b" + re.escape(name) + r"\s*\(", regression)}
    assert called_functions, "The regression test must call numerical implementation code, not merely contain constants."

    try:
        result = subprocess.run(
            ["go", "test", "-v"], cwd=SIM_DIR, capture_output=True, text=True, timeout=20
        )
    except FileNotFoundError:
        pytest.fail("Go toolchain not found. Is Go installed?")
    except subprocess.TimeoutExpired:
        pytest.fail("go test command timed out.")

    assert result.returncode == 0, f"'go test' failed with output:\n{result.stdout}\n{result.stderr}"
    assert re.search(r"^=== RUN\s+Test", result.stdout, re.MULTILINE), \
        f"go test succeeded without running a regression test:\n{result.stdout}"


def test_original_http_server_response():
    expected_amplitude = 15000.0
    expected_solution = [4620.535714285715, 3482.1428571428573, 1808.0357142857142]
    assert_response(expected_amplitude, expected_solution)


def test_server_recomputes_from_independent_wav_inputs():
    with open(WAV_PATH, "rb") as handle:
        original_wav = handle.read()

    cases = [
        [0, 17, -61, 2048, -23456, 91, 7000],
        [-3, 12, 3211, -3200, 44, 100, -8],
    ]
    proc = None
    try:
        kill_port_9090()
        for samples in cases:
            write_wav(samples)
            amplitude = float(max(abs(value) for value in samples))
            proc = launch_and_wait()
            assert_response(amplitude, independently_solve(amplitude))
            stop_process(proc)
            proc = None
    finally:
        stop_process(proc)
        with open(WAV_PATH, "wb") as handle:
            handle.write(original_wav)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
