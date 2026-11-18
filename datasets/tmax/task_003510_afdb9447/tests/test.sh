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
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import signal
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/infer"
AUTH = {"Authorization": "Bearer super-secret-ds-token"}
LIB = Path("/app/tinyml/libtinyml.a")
SERVER_CPP = Path("/home/user/server.cpp")
RUN_SCRIPT = Path("/home/user/run_server.sh")
WEIGHTS = [0.2, 0.8, -0.5, 1.0, 0.1]


def run_checked(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def listening_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    if not inodes:
        return found
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(proc.name))
        except OSError:
            pass
    return found


def stop_server():
    pids = listening_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids():
        time.sleep(0.05)
    for pid in listening_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids():
        time.sleep(0.05)
    assert not listening_pids(), "Could not free 127.0.0.1:8080"


def wait_for_server(timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            requests.post(URL, json={"features": [1, 2, 3, 4, 5]}, timeout=0.3)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Server did not begin listening on 127.0.0.1:8080: {last_error}")


def expected_result(features):
    valid = [float(x) for x in features if float(x) != -9999.0]
    assert valid, "Verifier does not generate the unspecified all-missing case"
    mean = sum(valid) / len(valid)
    variance = sum((x - mean) ** 2 for x in valid) / len(valid)
    stddev = math.sqrt(variance)
    lower = mean - 2.0 * stddev
    upper = mean + 2.0 * stddev
    imputed = [mean if float(x) == -9999.0 else float(x) for x in features]
    cleaned = [min(upper, max(lower, x)) for x in imputed]
    prediction = sum(x * w for x, w in zip(cleaned, WEIGHTS))
    return cleaned, prediction


def assert_close(actual, expected, label):
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"{label} is not numeric"
    assert math.isfinite(float(actual)), f"{label} is not finite"
    assert math.isclose(float(actual), float(expected), rel_tol=1e-5, abs_tol=1e-5), (
        f"{label}: expected {expected}, got {actual}"
    )


def authorized_case(features, marker):
    before = marker.stat().st_size if marker.exists() else 0
    try:
        response = requests.post(URL, json={"features": features}, headers=AUTH, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "cleaned" in data, "Response JSON missing 'cleaned' key"
    assert "prediction" in data, "Response JSON missing 'prediction' key"
    actual_cleaned = data["cleaned"]
    assert isinstance(actual_cleaned, list), "'cleaned' must be an array"
    assert len(actual_cleaned) == 5, f"Expected cleaned array of length 5, got {len(actual_cleaned)}"

    expected_cleaned, expected_prediction = expected_result(features)
    for i, (actual, expected) in enumerate(zip(actual_cleaned, expected_cleaned)):
        assert_close(actual, expected, f"cleaned[{i}]")
    assert_close(data["prediction"], expected_prediction, "prediction")

    assert marker.exists() and marker.stat().st_size > before, (
        "The request completed without calling tinyml::dot_product from libtinyml.a"
    )


def test_complete_service():
    # Preserve the original library assertion, then prove the Makefile can really rebuild it.
    assert LIB.is_file(), f"Expected compiled library at {LIB} does not exist. Did you fix the Makefile and compile it?"
    assert SERVER_CPP.is_file(), f"Missing {SERVER_CPP}"
    assert RUN_SCRIPT.is_file(), f"Missing {RUN_SCRIPT}"

    run_checked(["make", "clean"], cwd="/app/tinyml")
    run_checked(["make"], cwd="/app/tinyml")
    assert LIB.is_file(), "The fixed Makefile did not produce libtinyml.a"
    members = run_checked(["ar", "t", str(LIB)]).stdout.splitlines()
    assert members, "libtinyml.a is not a valid nonempty archive"

    # Link and execute a standalone probe against the rebuilt archive.
    probe_cpp = Path("/tmp/tinyml_probe.cpp")
    probe_bin = Path("/tmp/tinyml_probe")
    probe_cpp.write_text('''
#include "tinyml.h"
#include <cmath>
#include <vector>
int main() {
    std::vector<double> a{1.5, -2.0, 4.0};
    std::vector<double> b{2.0, 3.0, -0.5};
    return std::fabs(tinyml::dot_product(a, b) + 5.0) < 1e-12 ? 0 : 1;
}
''')
    run_checked(["g++", "-std=c++17", "-I/app/tinyml", str(probe_cpp), str(LIB), "-o", str(probe_bin)])
    run_checked([str(probe_bin)])

    # The submitted deployment script must itself start a listening service and return.
    stop_server()
    try:
        deployed = subprocess.run(["bash", str(RUN_SCRIPT)], text=True, capture_output=True, timeout=30)
    except subprocess.TimeoutExpired:
        pytest.fail("run_server.sh did not return after starting the server in the background")
    assert deployed.returncode == 0, (
        f"run_server.sh failed\nstdout:\n{deployed.stdout}\nstderr:\n{deployed.stderr}"
    )
    wait_for_server()
    stop_server()

    # Replace only the archive with an equivalent instrumented implementation. The service
    # is then independently compiled against that archive, proving both linkage and calls.
    marker = Path(f"/tmp/.tinyml_called_{secrets.token_hex(16)}")
    instrument_cpp = Path("/tmp/instrument_tinyml.cpp")
    instrument_obj = Path("/tmp/tinyml.o")
    instrument_cpp.write_text(f'''
#include "/app/tinyml/tinyml.h"
#include <fstream>
#include <numeric>
#include <optional>
#include <stdexcept>
namespace tinyml {{
double dot_product(const std::vector<double>& a, const std::vector<double>& b) {{
    std::ofstream({json.dumps(str(marker))}, std::ios::app).put('1');
    std::optional<size_t> size_a = a.size();
    if (size_a.value() != b.size()) throw std::invalid_argument("Size mismatch");
    return std::inner_product(a.begin(), a.end(), b.begin(), 0.0);
}}
}}
''')
    run_checked(["g++", "-std=c++17", "-O2", "-c", str(instrument_cpp), "-o", str(instrument_obj)])
    LIB.unlink()
    run_checked(["ar", "rcs", str(LIB), str(instrument_obj)])

    verified_server = Path("/tmp/verified_sensor_server")
    run_checked([
        "g++", "-std=c++17", "-O2", "-pthread",
        "-I/app/tinyml", "-I/app/httplib", "-I/app/json",
        str(SERVER_CPP), str(LIB), "-o", str(verified_server)
    ])

    process = subprocess.Popen([str(verified_server)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_server()
        if marker.exists():
            marker.unlink()

        # Preserve the original unauthorized assertion and ensure inference is not invoked.
        payload = {"features": [2.0, 4.0, -9999.0, 100.0, 6.0]}
        response = requests.post(URL, json=payload, timeout=2)
        assert response.status_code == 401, f"Expected status code 401 for unauthorized request, got {response.status_code}"
        assert not marker.exists(), "Unauthorized request reached tinyml::dot_product"

        response = requests.post(URL, json=payload, headers={"Authorization": "Bearer wrong-token"}, timeout=2)
        assert response.status_code == 401, f"Expected status code 401 for an incorrect token, got {response.status_code}"
        assert not marker.exists(), "Incorrectly authorized request reached tinyml::dot_product"

        # Preserve both original inference cases and their expected behavior.
        authorized_case([2.0, 4.0, -9999.0, 100.0, 6.0], marker)
        authorized_case([1.0, 2.0, 3.0, 4.0, 5.0], marker)

        # Exercise boundary/extreme distributions and unpredictable imputation inputs.
        authorized_case([0.0, 0.0, 0.0, 0.0, 100.0], marker)
        authorized_case([-100.0, 0.0, 0.0, 0.0, 0.0], marker)

        rng = secrets.SystemRandom()
        cases = []
        for _ in range(12):
            values = [float(rng.randint(-10000, 10000)) / rng.choice([1, 2, 4, 10]) for _ in range(5)]
            missing_count = rng.randint(0, 3)
            for index in rng.sample(range(5), missing_count):
                values[index] = -9999.0
            cases.append(values)
        for features in cases:
            authorized_case(features, marker)
    finally:
        try:
            process.terminate()
            process.wait(timeout=2)
        except Exception:
            process.kill()
        stop_server()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
