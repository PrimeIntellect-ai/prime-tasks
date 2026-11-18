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
import os
import re
import secrets
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"


def get_expected_t_init():
    cmd = [
        "ffmpeg", "-i", "/app/thermal_experiment.mp4",
        "-vf", "select=eq(n\\,20),format=gray",
        "-vframes", "1",
        "-f", "rawvideo", "-"
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    data = res.stdout
    if not data:
        return None, None
    avg_floor = int(sum(data) / len(data))
    avg_round = round(sum(data) / len(data))
    return avg_floor, avg_round


def read_report():
    report_path = "/home/user/profiling_report.txt"
    assert os.path.exists(report_path), f"Profiling report not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in profiling report, got {len(lines)}"
    t_init_line, bottleneck_line = lines
    assert t_init_line.startswith("T_INIT="), f"First line must start with T_INIT=, got: {t_init_line}"
    assert bottleneck_line.startswith("BOTTLENECK="), f"Second line must start with BOTTLENECK=, got: {bottleneck_line}"

    try:
        t_init_val = int(t_init_line.split("=", 1)[1])
    except ValueError:
        pytest.fail(f"T_INIT value is not a valid integer: {t_init_line}")

    bottleneck_val = bottleneck_line.split("=", 1)[1]
    assert len(bottleneck_val) > 0, "BOTTLENECK value must not be empty"
    return t_init_val, bottleneck_val


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) > 9 and fields[1].upper().endswith(":1F40") and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def find_native_server():
    denied = re.compile(r"^(python|pypy|bash|dash|sh|node|perl|ruby|php|java)([0-9.]*)$")
    for pid in listener_pids():
        exe_link = f"/proc/{pid}/exe"
        try:
            exe_name = os.path.basename(os.readlink(exe_link)).replace(" (deleted)", "")
            with open(exe_link, "rb") as f:
                magic = f.read(4)
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            continue
        if magic == b"\x7fELF" and not denied.match(exe_name.lower()):
            return pid, exe_link, cmdline
    pytest.fail("The process listening on port 8000 is not a native compiled server executable")


def solve_reference(t_init, steps):
    n = 100
    r = 0.5 * 0.01 / (0.1 * 0.1)
    u = [0.0] * n
    for i in range(40, 60):
        u[i] = float(t_init)

    interior = n - 2
    lower = -r
    diagonal = 1.0 + 2.0 * r
    upper = -r

    for _ in range(steps):
        cprime = [0.0] * interior
        dprime = [0.0] * interior
        cprime[0] = upper / diagonal
        dprime[0] = u[1] / diagonal
        for j in range(1, interior):
            denom = diagonal - lower * cprime[j - 1]
            cprime[j] = upper / denom if j < interior - 1 else 0.0
            dprime[j] = (u[j + 1] - lower * dprime[j - 1]) / denom

        new_u = [0.0] * n
        new_u[n - 2] = dprime[interior - 1]
        for j in range(interior - 2, -1, -1):
            new_u[j + 1] = dprime[j] - cprime[j] * new_u[j + 2]
        u = new_u

    return [float(f"{value:.2f}") for value in u]


def request_simulation(steps, timeout=5):
    try:
        resp = requests.get(f"{BASE_URL}/simulate", params={"steps": steps}, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to /simulate?steps={steps}: {exc}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert isinstance(data, list), f"Expected JSON array, got {type(data)}"
    assert len(data) == 100, f"Expected exactly 100 points, got {len(data)}"
    for i, val in enumerate(data):
        assert isinstance(val, (int, float)) and not isinstance(val, bool), \
            f"Value at index {i} is not a number: {val}"

    number = r"-?\d+\.\d{2}"
    assert re.fullmatch(rf"\[\s*{number}(?:\s*,\s*{number}){{99}}\s*\]", resp.text.strip()), \
        "Simulation response must contain exactly 100 values formatted to two decimal places"
    return data


def assert_correct_simulation(steps, t_init):
    actual = request_simulation(steps)
    expected = solve_reference(t_init, steps)
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == pytest.approx(want, abs=0.0001), \
            f"Incorrect temperature at index {i} after {steps} steps: expected {want:.2f}, got {got}"


def test_profiling_report():
    t_init_val, bottleneck_val = read_report()
    avg_floor, avg_round = get_expected_t_init()
    if avg_floor is not None:
        assert t_init_val in (avg_floor, avg_round), \
            f"Expected T_INIT to be {avg_floor} or {avg_round}, got {t_init_val}"

    _, exe_link, _ = find_native_server()
    result = subprocess.run(
        ["nm", "-a", "--defined-only", exe_link],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, "Unable to inspect symbols in the native server executable"
    function_symbols = set()
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[-2] in ("T", "t", "W", "w"):
            function_symbols.add(parts[-1])
    assert bottleneck_val in function_symbols, \
        f"Reported bottleneck '{bottleneck_val}' is not a function defined by the server executable"


def test_health_endpoint():
    try:
        resp = requests.get(f"{BASE_URL}/health", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /health endpoint: {e}")
    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    assert resp.text.strip() == "OK", f"Expected body 'OK', got '{resp.text}'"


def test_simulate_endpoint():
    t_init, _ = read_report()
    assert_correct_simulation(10, t_init)

    # Unpredictable step counts prevent a fixed, shape-only response from passing.
    tested = set()
    while len(tested) < 3:
        tested.add(1 + secrets.randbelow(79))
    for steps in tested:
        assert_correct_simulation(steps, t_init)


def test_heavy_simulation_is_supported():
    # The required C implementation should handle the profiling-scale workload.
    data = request_simulation(10000, timeout=5)
    assert len(data) == 100


def test_server_is_native_executable():
    find_native_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
