#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import signal
import subprocess
import time
from pathlib import Path

import requests

BASE_URL = "http://127.0.0.1:8080"
HEADERS = {"Authorization": "Bearer secret_ts_2024"}
SCRIPT = Path("/home/user/run_server.sh")
BASELINE = Path("/app/baseline.csv")
EXPECTED_DATA = [
    {"time": 0, "value": 20.0},
    {"time": 10, "value": 22.0},
    {"time": 20, "value": 24.0},
    {"time": 30, "value": 26.0},
    {"time": 40, "value": 28.0},
    {"time": 50, "value": 30.0},
]


def wait_for_server(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(BASE_URL, timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.25)
    return False


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    result = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            pass
    return result


def stop_server():
    for _ in range(20):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.15)
    assert not listener_pids(), "Could not stop the existing server on port 8080"


def assert_auth_and_payload(expected_mae):
    for endpoint in ("/api/telemetry", "/api/mae"):
        response = requests.get(BASE_URL + endpoint, timeout=3)
        assert response.status_code == 401, \
            f"Expected 401 for {endpoint} without auth, got {response.status_code}"
        response = requests.get(
            BASE_URL + endpoint,
            headers={"Authorization": "Bearer wrong_token"},
            timeout=3,
        )
        assert response.status_code == 401, \
            f"Expected 401 for {endpoint} with bad auth, got {response.status_code}"

    response = requests.get(BASE_URL + "/api/telemetry", headers=HEADERS, timeout=3)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    payload = response.json()
    assert "operator" in payload, "Response missing 'operator' field"
    assert payload["operator"] == "MASKED", \
        f"Expected operator to be 'MASKED', got {payload['operator']}"
    assert "data" in payload, "Response missing 'data' field"
    actual = payload["data"]
    assert len(actual) == len(EXPECTED_DATA), \
        f"Expected {len(EXPECTED_DATA)} data points, got {len(actual)}"
    for expected, item in zip(EXPECTED_DATA, actual):
        assert item["time"] == expected["time"], \
            f"Expected time {expected['time']}, got {item['time']}"
        assert math.isclose(item["value"], expected["value"], rel_tol=1e-3), \
            f"Expected value {expected['value']} at time {expected['time']}, got {item['value']}"

    response = requests.get(BASE_URL + "/api/mae", headers=HEADERS, timeout=3)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    payload = response.json()
    assert "mae" in payload, "Response missing 'mae' field"
    assert isinstance(payload["mae"], (int, float)), "MAE must be numeric"
    assert math.isclose(payload["mae"], expected_mae, rel_tol=1e-3, abs_tol=1e-6), \
        f"Expected MAE ~{expected_mae}, got {payload['mae']}"


def test_complete_workflow():
    assert SCRIPT.is_file(), "/home/user/run_server.sh is missing"
    script_text = SCRIPT.read_text(errors="replace")
    assert re.search(r"(^|[^A-Za-z0-9_])(g\+\+|c\+\+|clang\+\+|cmake|make|ninja)([^A-Za-z0-9_]|$)", script_text), \
        "run_server.sh does not compile/build a C++ server"

    cpp_sources = []
    for root in (Path("/home/user"), Path("/app")):
        for suffix in ("*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hxx"):
            cpp_sources.extend(root.rglob(suffix))
    assert cpp_sources or re.search(r"-x\s*c\+\+", script_text), \
        "No C++ implementation source was found"

    # Preserve all original fixed-input assertions against the server left running by the agent.
    assert wait_for_server(10), "Server is not listening on port 8080"
    assert_auth_and_payload(4.0 / 6.0)

    original_baseline = BASELINE.read_bytes()
    launcher = None
    try:
        stop_server()

        # Use unpredictable baseline values so a fixed MAE response cannot pass.
        baseline_values = [round(random.SystemRandom().uniform(3.0, 87.0), 4) for _ in EXPECTED_DATA]
        rows = ["time,value"] + [
            f"{point['time']},{value:.4f}"
            for point, value in zip(EXPECTED_DATA, baseline_values)
        ]
        BASELINE.write_text("\n".join(rows) + "\n")
        expected_mae = sum(
            abs(point["value"] - baseline)
            for point, baseline in zip(EXPECTED_DATA, baseline_values)
        ) / len(EXPECTED_DATA)

        launcher = subprocess.Popen(
            ["runuser", "-u", "user", "--", "bash", str(SCRIPT)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        assert wait_for_server(30), "run_server.sh did not start a server on port 8080"

        pids = listener_pids()
        assert pids, "No process owns the listening socket on port 8080"
        for pid in pids:
            status = Path(f"/proc/{pid}/status").read_text(errors="replace")
            uid_match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
            assert uid_match and int(uid_match.group(1)) != 0, "Server is running as root"

            exe = Path(f"/proc/{pid}/exe").resolve()
            with exe.open("rb") as handle:
                assert handle.read(4) == b"\x7fELF", "Listening server is not a compiled native executable"
            assert exe.name.lower() not in {
                "python", "python3", "node", "ruby", "perl", "php", "java",
                "bash", "sh", "dash", "socat", "nc", "netcat",
            }, "Listening process is an interpreter or generic server, not the C++ application"

        assert_auth_and_payload(expected_mae)
    finally:
        BASELINE.write_bytes(original_baseline)
        stop_server()
        if launcher is not None and launcher.poll() is None:
            try:
                os.killpg(launcher.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
