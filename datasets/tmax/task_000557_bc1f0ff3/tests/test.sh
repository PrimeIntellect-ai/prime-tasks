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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

API_URL = "http://127.0.0.1:8080/api/v1/prepare"
AUTH_HEADER = {"Authorization": "Bearer train-token-99"}
APP_DIR = Path("/home/user/ml-api")
LIB_DIR = Path("/app/vendored/statslib")
BINARY = Path("/tmp/ml-api-verified")
INSTRUMENTED_BINARY = Path("/tmp/ml-api-instrumented")


def listening_socket_inodes(port):
    found = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                found.add(fields[9])
    return found


def kill_port(port):
    inodes = listening_socket_inodes(port)
    if not inodes:
        return
    victims = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)


def wait_for_server(proc, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert proc.poll() is None, "The compiled Go server exited before accepting connections"
        try:
            requests.options(API_URL, timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.15)
    pytest.fail("The compiled Go server is not listening on 127.0.0.1:8080")


def launch(binary):
    kill_port(8080)
    proc = subprocess.Popen(
        [str(binary)],
        cwd=str(APP_DIR),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    wait_for_server(proc)
    return proc


def stop(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


@pytest.fixture(scope="session", autouse=True)
def compiled_go_server():
    assert (LIB_DIR / "tables.go").is_file(), "tables.go was not generated in /app/vendored/statslib"
    assert (APP_DIR / "go.mod").is_file(), "/home/user/ml-api/go.mod does not exist"
    assert (APP_DIR / "main.go").is_file(), "/home/user/ml-api/main.go does not exist"

    subprocess.run(
        ["go", "test", "./..."], cwd=str(LIB_DIR), check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60,
    )
    subprocess.run(
        ["go", "build", "-o", str(BINARY), "."], cwd=str(APP_DIR), check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60,
    )

    state = {"proc": launch(BINARY)}
    yield state
    stop(state.get("proc"))
    kill_port(8080)


def assert_invalid_schema(payload):
    response = requests.post(API_URL, headers=AUTH_HEADER, json=payload, timeout=3)
    assert response.status_code == 400, f"Expected 400 for invalid schema, got {response.status_code}: {response.text}"
    assert response.json().get("error") == "invalid schema", "Expected error message 'invalid schema'"


def assert_valid_result(payload, expected_lower, expected_upper):
    response = requests.post(API_URL, headers=AUTH_HEADER, json=payload, timeout=3)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert set(data) == {"schema_valid", "ci_lower", "ci_upper", "regression_ready"}
    assert data.get("schema_valid") is True
    assert isinstance(data.get("ci_lower"), (int, float)) and not isinstance(data.get("ci_lower"), bool)
    assert isinstance(data.get("ci_upper"), (int, float)) and not isinstance(data.get("ci_upper"), bool)
    assert math.isclose(data["ci_lower"], expected_lower, rel_tol=0, abs_tol=1e-7)
    assert math.isclose(data["ci_upper"], expected_upper, rel_tol=0, abs_tol=1e-7)
    expected_ready = expected_lower > 0.0 and expected_upper < 100.0
    assert data.get("regression_ready") is expected_ready


def test_tables_go_generated():
    assert os.path.isfile("/app/vendored/statslib/tables.go"), "tables.go was not generated in /app/vendored/statslib"


def test_go_mod_exists_and_replaces():
    go_mod_path = "/home/user/ml-api/go.mod"
    assert os.path.isfile(go_mod_path), f"{go_mod_path} does not exist"
    with open(go_mod_path) as f:
        content = f.read()
    assert "replace github.com/local/statslib => /app/vendored/statslib" in content or \
           "replace github.com/local/statslib => /app/vendored/statslib" in content.replace("\t", " "), \
           "go.mod does not contain the correct replace directive for github.com/local/statslib"


def test_main_go_exists():
    assert os.path.isfile("/home/user/ml-api/main.go"), "/home/user/ml-api/main.go does not exist"


def test_api_invalid_auth():
    response = requests.post(API_URL, json={"data": []}, timeout=3)
    assert response.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {response.status_code}"
    response = requests.post(
        API_URL,
        headers={"Authorization": "Bearer wrong-token"},
        json={"data": []},
        timeout=3,
    )
    assert response.status_code in (401, 403), f"Expected 401 or 403 for invalid auth, got {response.status_code}"


def test_api_invalid_schema():
    assert_invalid_schema({"data": [{"feature_2": 2.0, "target": 10.5}]})
    assert_invalid_schema({"data": [{"feature_1": 1.0, "feature_2": 2.0, "target": 10.5, "extra": 1.0}]})
    assert_invalid_schema({"data": [{"feature_1": "string", "feature_2": 2.0, "target": 10.5}]})


def test_api_valid_schema_regression_ready():
    payload = {"data": [
        {"feature_1": 10.0, "feature_2": 5.0, "target": 2.0},
        {"feature_1": 12.0, "feature_2": 5.0, "target": 2.0},
    ]}
    assert_valid_result(payload, 9.04, 12.96)


def test_api_valid_schema_not_regression_ready():
    payload = {"data": [
        {"feature_1": -5.0, "feature_2": 5.0, "target": 2.0},
        {"feature_1": -3.0, "feature_2": 5.0, "target": 2.0},
    ]}
    assert_valid_result(payload, -5.96, -2.04)


def test_only_required_route_and_method():
    response = requests.get(API_URL, headers=AUTH_HEADER, timeout=3)
    assert response.status_code != 200
    response = requests.post(
        "http://127.0.0.1:8080/api/v1/not-prepare",
        headers=AUTH_HEADER,
        json={"data": [{"feature_1": 1.0, "feature_2": 2.0, "target": 3.0}]},
        timeout=3,
    )
    assert response.status_code != 200


def test_randomized_valid_payloads():
    rng = random.SystemRandom()
    for _ in range(14):
        count = rng.randint(1, 9)
        center = rng.choice([
            rng.uniform(-25.0, -3.0),
            rng.uniform(3.0, 90.0),
            rng.uniform(101.0, 180.0),
            1.96 + rng.uniform(-0.02, 0.02),
            98.04 + rng.uniform(-0.02, 0.02),
        ])
        feature_1 = [center + rng.uniform(-7.0, 7.0) for _ in range(count)]
        rows = [
            {
                "feature_1": value,
                "feature_2": rng.uniform(-1000.0, 1000.0),
                "target": rng.uniform(-1000.0, 1000.0),
            }
            for value in feature_1
        ]
        mean = sum(feature_1) / len(feature_1)
        assert_valid_result({"data": rows}, mean - 1.96, mean + 1.96)


def test_randomized_schema_rejections():
    rng = random.SystemRandom()
    keys = ["feature_1", "feature_2", "target"]
    bad_values = [None, True, False, "3.5", [1.0], {"x": 1.0}]
    for _ in range(12):
        good = {"feature_1": rng.uniform(-10, 10), "feature_2": rng.uniform(-10, 10), "target": rng.uniform(-10, 10)}
        mode = rng.choice(["missing", "extra", "type", "mixed"])
        if mode == "missing":
            del good[rng.choice(keys)]
            rows = [good]
        elif mode == "extra":
            good["unexpected_" + str(rng.randrange(1000000))] = rng.random()
            rows = [good]
        elif mode == "type":
            good[rng.choice(keys)] = rng.choice(bad_values)
            rows = [good]
        else:
            bad = dict(good)
            bad[rng.choice(keys)] = rng.choice(bad_values)
            rows = [{"feature_1": 2.0, "feature_2": 3.0, "target": 4.0}, bad]
        assert_invalid_schema({"data": rows})


def test_server_uses_statslib_calculate_ci(compiled_go_server):
    tables = LIB_DIR / "tables.go"
    original = tables.read_bytes()
    marker = Path("/tmp/statslib-calculate-ci-called")
    marker.unlink(missing_ok=True)
    instrumented = '''package statslib

import "os"

func CalculateCI(data []float64) (float64, float64) {
    _ = os.WriteFile("/tmp/statslib-calculate-ci-called", []byte("called"), 0600)
    weighted := 0.0
    for i, v := range data {
        weighted += float64(i+1) * v
    }
    lower := -30.125 + weighted*0.173 + float64(len(data))*0.019
    return lower, lower + 7.375
}
'''
    try:
        tables.write_text(instrumented)
        subprocess.run(
            ["go", "build", "-o", str(INSTRUMENTED_BINARY), "."],
            cwd=str(APP_DIR), check=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=60,
        )
    finally:
        tables.write_bytes(original)

    stop(compiled_go_server["proc"])
    compiled_go_server["proc"] = launch(INSTRUMENTED_BINARY)

    rng = random.SystemRandom()
    values = [rng.uniform(2.25, 8.75) for _ in range(rng.randint(3, 7))]
    rows = [
        {"feature_1": value, "feature_2": rng.uniform(200, 400), "target": rng.uniform(-400, -200)}
        for value in values
    ]
    weighted = sum((i + 1) * value for i, value in enumerate(values))
    lower = -30.125 + weighted * 0.173 + len(values) * 0.019
    upper = lower + 7.375
    assert_valid_result({"data": rows}, lower, upper)
    assert marker.read_text() == "called", "The running server did not invoke statslib.CalculateCI"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
