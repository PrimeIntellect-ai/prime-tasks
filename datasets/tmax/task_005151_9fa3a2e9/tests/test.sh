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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import math
import os
import signal
import subprocess
import sys
import time

import pandas as pd
import pytest
import requests
from pandas.testing import assert_frame_equal

TRANSACTIONS = "/home/user/data/transactions.csv"
USERS = "/home/user/data/users.csv"
CLEANED = "/home/user/data/cleaned_dataset.csv"
LOG = "/home/user/experiment_log.json"
SCRIPT = "/home/user/serve_data.py"
PACKAGE_ROOT = "/app/miniserve-0.1.0/miniserve"
BASE_URL = "http://127.0.0.1:8888"
AUTH = {"Authorization": "Bearer ds-secret"}


def expected_results():
    transactions = pd.read_csv(TRANSACTIONS)
    users = pd.read_csv(USERS)
    joined = transactions.merge(users, on="user_id", how="inner")
    joined = joined.dropna(subset=["age"]).copy()
    mean_amount = float(joined["amount"].mean())
    joined["amount"] = joined["amount"].fillna(mean_amount)
    correlation = float(joined["age"].corr(joined["amount"], method="pearson"))
    return joined, mean_amount, correlation


def assert_scalar_equal(actual, expected):
    if pd.isna(expected):
        assert actual is None or pd.isna(actual)
    elif isinstance(expected, (int, float)) and not isinstance(expected, bool):
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isclose(float(actual), float(expected), rel_tol=1e-9, abs_tol=1e-9)
    else:
        assert str(actual) == str(expected)


def assert_api(base_url, cleaned, metrics):
    session = requests.Session()
    session.trust_env = False

    for endpoint in ("/api/stats", "/api/data"):
        response = session.get(base_url + endpoint, timeout=2)
        assert response.status_code == 401, (
            f"Expected 401 without authorization for {endpoint}, got {response.status_code}"
        )
        response = session.get(
            base_url + endpoint,
            headers={"Authorization": "Bearer incorrect"},
            timeout=2,
        )
        assert response.status_code == 401, (
            f"Expected 401 with incorrect authorization for {endpoint}, got {response.status_code}"
        )

    response = session.get(base_url + "/api/stats", headers=AUTH, timeout=2)
    assert response.status_code == 200, f"Expected 200 from /api/stats, got {response.status_code}"
    try:
        stats = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON from /api/stats, got: {response.text}")
    assert isinstance(stats, dict)
    assert set(stats) == {"mean_amount", "correlation_age_amount"}
    assert_scalar_equal(stats["mean_amount"], metrics["mean_amount"])
    assert_scalar_equal(stats["correlation_age_amount"], metrics["correlation_age_amount"])

    response = session.get(base_url + "/api/data", headers=AUTH, timeout=2)
    assert response.status_code == 200, f"Expected 200 from /api/data, got {response.status_code}"
    try:
        rows = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON from /api/data, got: {response.text}")

    assert isinstance(rows, list), "Expected API to return a list of dictionaries"
    assert len(rows) > 0, "API returned an empty list"
    assert len(rows) == min(10, len(cleaned)), "API must return exactly the first 10 rows (or all if fewer)"
    assert isinstance(rows[0], dict), "Expected list of dictionaries"
    assert "user_id" in rows[0]
    assert "amount" in rows[0]

    expected_rows = cleaned.head(10).to_dict(orient="records")
    for actual_row, expected_row in zip(rows, expected_rows):
        assert isinstance(actual_row, dict)
        assert set(actual_row) == set(expected_row), "API row has missing or extra columns"
        for key, expected_value in expected_row.items():
            assert_scalar_equal(actual_row[key], expected_value)


def listener_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_for_inodes(inodes):
    found = set()
    if not inodes:
        return found
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
                    found.add(int(name))
                    break
        except OSError:
            continue
    return found


def stop_port(port):
    pids = pids_for_inodes(listener_inodes(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    for pid in pids_for_inodes(listener_inodes(port)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    assert not listener_inodes(port), "Could not free port 8888 to execute serve_data.py"


def wait_for_server(process, timeout=8):
    session = requests.Session()
    session.trust_env = False
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            output = ""
            try:
                output = open("/tmp/serve_data_verifier.log").read()
            except OSError:
                pass
            pytest.fail(f"serve_data.py exited early with {process.returncode}: {output}")
        try:
            session.get(BASE_URL + "/api/stats", timeout=0.4)
            return
        except requests.RequestException:
            time.sleep(0.1)
    pytest.fail("Timed out waiting for serve_data.py on port 8888")


def test_complete_task():
    expected, expected_mean, expected_corr = expected_results()

    assert os.path.exists(CLEANED), f"Cleaned dataset not found at {CLEANED}"
    with open(CLEANED) as handle:
        lines = [line.strip() for line in handle if line.strip()]
    assert len(lines) >= 5, "Cleaned dataset should have header and 4 data rows"
    assert "user_id" in lines[0]
    assert "age" in lines[0]
    assert "amount" in lines[0]
    for line in lines[1:]:
        assert not line.startswith("3,"), "User 3 should have been dropped due to missing age"

    actual = pd.read_csv(CLEANED)
    assert set(actual.columns) == set(expected.columns), "Cleaned CSV has missing or extra columns"
    assert len(actual) == len(expected), "Cleaned CSV has the wrong number of joined rows"
    actual_cmp = actual[list(expected.columns)].sort_values(list(expected.columns), na_position="first").reset_index(drop=True)
    expected_cmp = expected.sort_values(list(expected.columns), na_position="first").reset_index(drop=True)
    assert_frame_equal(actual_cmp, expected_cmp, check_dtype=False, rtol=1e-9, atol=1e-9)
    assert not actual["age"].isna().any()
    assert not actual["amount"].isna().any()

    assert os.path.exists(LOG), f"Experiment log not found at {LOG}"
    with open(LOG) as handle:
        metrics = json.load(handle)
    assert isinstance(metrics, dict)
    assert set(metrics) == {"mean_amount", "correlation_age_amount"}, "Log must have exactly two keys"
    assert type(metrics["mean_amount"]) is float, "mean_amount must be a JSON float"
    assert type(metrics["correlation_age_amount"]) is float, "correlation_age_amount must be a JSON float"
    assert math.isfinite(metrics["mean_amount"])
    assert math.isfinite(metrics["correlation_age_amount"])
    assert math.isclose(metrics["mean_amount"], 75.375, rel_tol=1e-3)
    assert -0.95 <= metrics["correlation_age_amount"] <= -0.75
    assert math.isclose(metrics["mean_amount"], expected_mean, rel_tol=1e-9, abs_tol=1e-9)
    assert math.isclose(metrics["correlation_age_amount"], expected_corr, rel_tol=1e-9, abs_tol=1e-9)

    assert os.path.isfile(SCRIPT), f"Serving script not found at {SCRIPT}"

    import miniserve
    package_file = os.path.realpath(miniserve.__file__)
    assert package_file.startswith(os.path.realpath(PACKAGE_ROOT) + os.sep), (
        f"Installed miniserve does not resolve to the vendored package: {package_file}"
    )
    assert importlib.metadata.version("miniserve") == "0.1.0"
    encoded = miniserve.JsonResponse({"text": "quoted \"value\"", "items": [1, 2]})
    assert isinstance(encoded, str)
    assert json.loads(encoded) == {"text": "quoted \"value\"", "items": [1, 2]}

    # Preserve validation of the server the agent was instructed to leave running.
    assert_api(BASE_URL, actual, metrics)

    # Execute the submitted artifact ourselves and instrument the installed framework
    # so a hand-written replacement HTTP server cannot satisfy the miniserve requirement.
    stop_port(8888)
    probe_dir = "/tmp/miniserve_verifier_probe"
    marker = "/tmp/miniserve_run_marker.json"
    os.makedirs(probe_dir, exist_ok=True)
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    with open(os.path.join(probe_dir, "sitecustomize.py"), "w") as handle:
        handle.write(r'''
import json
import os
import miniserve
import miniserve.server

_expected = os.path.realpath("/app/miniserve-0.1.0/miniserve") + os.sep
_origin = os.path.realpath(miniserve.__file__)
_original_run = miniserve.server.Miniserve.run

def _verified_run(self, host="0.0.0.0", port=8888):
    with open("/tmp/miniserve_run_marker.json", "w") as marker:
        json.dump({"origin": _origin, "valid_origin": _origin.startswith(_expected),
                   "host": host, "port": port}, marker)
    return _original_run(self, host=host, port=port)

miniserve.server.Miniserve.run = _verified_run
''')

    env = os.environ.copy()
    env["PYTHONPATH"] = probe_dir + os.pathsep + env.get("PYTHONPATH", "")
    output = open("/tmp/serve_data_verifier.log", "w")
    process = subprocess.Popen(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=output,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_for_server(process)

    assert os.path.exists(marker), "serve_data.py did not call miniserve.Miniserve.run"
    with open(marker) as handle:
        invocation = json.load(handle)
    assert invocation["valid_origin"] is True, "serve_data.py did not use the installed vendored miniserve"
    assert invocation["host"] == "0.0.0.0", "Server must listen on 0.0.0.0"
    assert int(invocation["port"]) == 8888, "Server must listen on port 8888"

    # The IPv4 listener itself must be bound to all interfaces, not only loopback.
    wildcard = False
    with open("/proc/net/tcp") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if port_hex.upper() == "22B8" and fields[3] == "0A" and address == "00000000":
                wildcard = True
                break
    assert wildcard, "Port 8888 is not bound to 0.0.0.0"

    assert_api(BASE_URL, actual, metrics)
    assert process.poll() is None, "serve_data.py did not remain running"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
