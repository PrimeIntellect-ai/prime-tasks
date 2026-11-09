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
import importlib.util
import json
import math
import os
import signal
import socket
import subprocess
import sys
import time
from decimal import Decimal, localcontext

import pytest
import requests

DASHBOARD_URL = "http://127.0.0.1:8080/api/status"
AUTH_TOKEN = "SRE-M0N-8821"
REPO = "/home/user/monitor-stack"
CHECKER = os.path.join(REPO, "checker")
DASHBOARD_APP = os.path.join(REPO, "dashboard", "app.py")


def recover_state_key():
    commits = subprocess.check_output(
        ["git", "-C", REPO, "rev-list", "--all", "--", "config.env"],
        text=True,
    ).splitlines()
    for commit in commits:
        result = subprocess.run(
            ["git", "-C", REPO, "show", f"{commit}:config.env"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if line.startswith("STATE_KEY=") and line.partition("=")[2]:
                    return line.partition("=")[2]
    pytest.fail("Could not recover STATE_KEY from Git history")


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    time.sleep(0.5)


def ipv4_listener_address():
    try:
        with open("/proc/net/tcp") as f:
            next(f)
            for line in f:
                fields = line.split()
                address, port = fields[1].split(":")
                if port.upper() == "1F90" and fields[3] == "0A":
                    return address.upper()
    except OSError:
        pass
    return None


@pytest.fixture(scope="session", autouse=True)
def run_required_artifacts(request):
    assert os.path.isfile(os.path.join(CHECKER, "main.go")), "Missing Go checker source"
    assert os.path.isfile(DASHBOARD_APP), "Missing dashboard app.py"

    with open(os.path.join(CHECKER, "main.go")) as f:
        checker_source = f.read()
    assert "STATE_KEY" in checker_source, "The checker no longer consumes STATE_KEY"

    state_key = recover_state_key()
    health_path = "/tmp/health.json"
    debug_path = "/home/user/variance_debug.txt"
    for path in (health_path, debug_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    no_key_env = os.environ.copy()
    no_key_env.pop("STATE_KEY", None)
    no_key = subprocess.run(
        ["go", "run", "."],
        cwd=CHECKER,
        env=no_key_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert no_key.returncode != 0, "The checker must refuse to run without STATE_KEY"
    assert not os.path.exists(health_path), "Checker produced health data without STATE_KEY"

    keyed_env = os.environ.copy()
    keyed_env["STATE_KEY"] = state_key
    try:
        checker = subprocess.run(
            ["go", "run", "."],
            cwd=CHECKER,
            env=keyed_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Go checker did not terminate; cyclic dependencies are not handled")

    assert checker.returncode == 0, (
        f"Go checker failed with recovered STATE_KEY. stdout={checker.stdout!r}, "
        f"stderr={checker.stderr!r}"
    )
    assert os.path.isfile(health_path), "Go checker did not create /tmp/health.json"
    with open(health_path) as f:
        health = json.load(f)
    assert health == {"status": "ok"}, f"Unexpected checker health output: {health!r}"

    kill_port_8080()
    log = open("/tmp/dashboard-verifier.log", "w+")
    proc = subprocess.Popen(
        [sys.executable, DASHBOARD_APP],
        cwd=os.path.dirname(DASHBOARD_APP),
        stdout=log,
        stderr=subprocess.STDOUT,
    )

    def cleanup():
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
        log.close()

    request.addfinalizer(cleanup)

    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            requests.get(DASHBOARD_URL, timeout=0.3)
            break
        except requests.RequestException:
            time.sleep(0.1)

    if proc.poll() is not None:
        log.flush()
        log.seek(0)
        pytest.fail(f"Dashboard app.py exited during startup:\n{log.read()}")

    assert ipv4_listener_address() == "0100007F", (
        "Dashboard must listen on 127.0.0.1:8080, not a wildcard or other address"
    )
    yield


def expected_stddev(values):
    with localcontext() as ctx:
        ctx.prec = 80
        decimals = [Decimal.from_float(x) for x in values]
        mean = sum(decimals) / Decimal(len(decimals))
        variance = sum((x - mean) ** 2 for x in decimals) / Decimal(len(decimals))
        return float(variance.sqrt())


def load_dashboard_module():
    spec = importlib.util.spec_from_file_location("verified_dashboard", DASHBOARD_APP)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_variance_implementation_is_stable():
    module = load_dashboard_module()
    assert hasattr(module, "calculate_variance"), "Missing calculate_variance function"

    datasets = [
        [1000000000.0, 1000000000.000001],
        [1000000000000.0 + i * math.ulp(1000000000000.0) for i in (-8, -3, 0, 4, 9)],
    ]
    for values in datasets:
        actual = module.calculate_variance(values)
        expected = expected_stddev(values)
        assert isinstance(actual, (int, float)) and math.isfinite(actual)
        assert actual >= 0
        assert math.isclose(actual, expected, rel_tol=0.05, abs_tol=1e-15), (
            f"Numerically unstable result for {values!r}: got {actual}, expected {expected}"
        )


def test_api_status_unauthorized_no_token():
    try:
        response = requests.get(DASHBOARD_URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the dashboard at {DASHBOARD_URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"


def test_api_status_unauthorized_wrong_token():
    headers = {"Authorization": "Bearer WRONG-TOKEN"}
    try:
        response = requests.get(DASHBOARD_URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the dashboard at {DASHBOARD_URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized with wrong token, got {response.status_code}"


def test_api_status_authorized():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    try:
        response = requests.get(DASHBOARD_URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the dashboard at {DASHBOARD_URL}: {e}")

    assert response.status_code == 200, (
        f"Expected 200 OK with correct token, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but failed to parse. Response text: {response.text}")

    assert isinstance(data, dict), "Expected JSON response to be a dictionary"
    assert data.get("health") == {"status": "ok"}, f"Dashboard did not expose checker health: {data!r}"
    assert "variance" in data and isinstance(data["variance"], (int, float))
    expected = expected_stddev([1000000000.0, 1000000000.000001])
    assert math.isfinite(data["variance"])
    assert math.isclose(data["variance"], expected, rel_tol=0.05, abs_tol=1e-15), (
        f"Dashboard returned incorrect stable variance value: {data['variance']!r}"
    )


def test_variance_debug_file():
    path = "/home/user/variance_debug.txt"
    assert os.path.isfile(path), f"Missing variance debug file at {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    try:
        variance = float(content)
    except ValueError:
        pytest.fail(f"Expected a valid float in {path}, but got: {content}")
    assert variance >= 0, f"Variance cannot be negative, got: {variance}"
    expected = expected_stddev([1000000000.0, 1000000000.000001])
    assert math.isfinite(variance)
    assert math.isclose(variance, expected, rel_tol=0.05, abs_tol=1e-15), (
        f"Debug file contains {variance}, expected corrected value {expected}"
    )


def test_health_json_exists():
    path = "/tmp/health.json"
    assert os.path.isfile(path), f"Missing health data file at {path}. The Go checker might have failed or not run."
    with open(path) as f:
        data = json.load(f)
    assert data == {"status": "ok"}, f"Invalid health data: {data!r}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
