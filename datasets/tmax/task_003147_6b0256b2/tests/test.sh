#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import random
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request

import pytest

METRICS_DIR = "/home/user/metrics"
LIB_PATH = f"{METRICS_DIR}/libmetric.so"
SCRIPT_PATH = f"{METRICS_DIR}/test_integration.sh"
BASE_URL = "http://127.0.0.1:8181/stdev"


def fetch_case(values):
    encoded_values = ",".join(format(value, ".12g") for value in values)
    url = BASE_URL + "?" + urllib.parse.urlencode({"build_times": encoded_values})
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to the web service at {url}: {exc}")

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {body}")

    assert "stdev" in data, "Response JSON does not contain 'stdev' key"
    assert isinstance(data["stdev"], (int, float)) and not isinstance(data["stdev"], bool), \
        f"stdev must be a JSON number, got {data['stdev']!r}"

    match = re.search(r'"stdev"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{2})(?=\s*[,}])', body)
    assert match, f"stdev was not formatted with exactly two decimal places: {body}"

    mean = math.fsum(values) / len(values)
    expected = math.sqrt(math.fsum((x - mean) ** 2 for x in values) / len(values))
    expected_text = f"{expected:.2f}"
    assert match.group(1) == expected_text, \
        f"Expected population stdev {expected_text} for {values}, got {match.group(1)}"
    assert data["stdev"] == float(expected_text)


def test_libmetric_so_exists_and_loads():
    assert os.path.isfile(LIB_PATH), f"Shared library not found at {LIB_PATH}"
    with open(LIB_PATH, "rb") as library:
        assert library.read(4) == b"\x7fELF", f"{LIB_PATH} is not an ELF shared library"
    try:
        ctypes.CDLL(LIB_PATH)
    except OSError as exc:
        pytest.fail(f"Shared library cannot be loaded: {exc}")


def test_integration_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Integration test script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Integration test script at {SCRIPT_PATH} is not executable"


def test_web_service_stdev():
    # sqrt(192 / 8) = sqrt(24), which rounds to 4.90.
    fetch_case([10, 12, 23, 23, 16, 23, 21, 16])


def test_web_service_on_derived_inputs():
    fixed_cases = [
        [2, 4, 4, 4, 5, 5, 7, 9],
        [1, 2, 3],
        [-3.5, 0, 4.25, 10],
        [7.125, 7.125, 7.125, 7.125],
    ]
    for values in fixed_cases:
        fetch_case(values)

    rng = random.SystemRandom()
    for _ in range(5):
        values = [rng.randint(-10000, 10000) / 10.0 for _ in range(rng.randint(5, 14))]
        fetch_case(values)


def test_server_process_loaded_libmetric():
    port_hex = f"{8181:04X}"
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == port_hex and fields[3] == "0A":
                        socket_inodes.add(fields[9])
        except OSError:
            pass
    assert socket_inodes, "No process is listening on port 8181"

    listener_pids = set()
    for pid in filter(str.isdigit, os.listdir("/proc")):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    listener_pids.add(pid)
                    break
        except OSError:
            continue

    assert listener_pids, "Could not identify the process listening on port 8181"
    for pid in listener_pids:
        try:
            with open(f"/proc/{pid}/maps") as maps:
                if LIB_PATH in maps.read():
                    return
        except OSError:
            continue
    pytest.fail(f"The web-service process listening on port 8181 has not loaded {LIB_PATH}")


def test_run_user_integration_script():
    try:
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("Integration script timed out after 10 seconds")
    assert result.returncode == 0, \
        f"Integration script failed with exit code {result.returncode}. Output:\n{result.stdout}\n{result.stderr}"


def test_integration_script_really_checks_curl_response():
    with tempfile.TemporaryDirectory() as temp_dir:
        curl_path = os.path.join(temp_dir, "curl")
        log_path = os.path.join(temp_dir, "curl.log")
        with open(curl_path, "w") as fake_curl:
            fake_curl.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$CURL_LOG\"\nprintf '%s\\n' \"$CURL_RESPONSE\"\n")
        os.chmod(curl_path, 0o755)

        base_env = os.environ.copy()
        base_env["PATH"] = temp_dir + os.pathsep + base_env.get("PATH", "")
        base_env["CURL_LOG"] = log_path

        good_env = base_env.copy()
        good_env["CURL_RESPONSE"] = '{"stdev": 2.00}'
        good = subprocess.run([SCRIPT_PATH], env=good_env, capture_output=True, text=True, timeout=10)
        assert good.returncode == 0, \
            f"Integration script rejected the required 2.00 response: {good.stdout}\n{good.stderr}"

        assert os.path.isfile(log_path), "Integration script did not invoke curl"
        with open(log_path) as log:
            curl_calls = log.read()
        required_url = "http://127.0.0.1:8181/stdev?build_times=2,4,4,4,5,5,7,9"
        assert required_url in curl_calls, f"Integration script did not request {required_url}"

        bad_env = base_env.copy()
        bad_env["CURL_RESPONSE"] = '{"stdev": 2.01}'
        bad = subprocess.run([SCRIPT_PATH], env=bad_env, capture_output=True, text=True, timeout=10)
        assert bad.returncode == 1, \
            "Integration script must exit 1 when curl returns an incorrect stdev value"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
