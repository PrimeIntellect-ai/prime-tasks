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

# Stop any server the agent may have launched separately. The verifier must test
# the server started by the submitted `make serve` target.
python3 - <<'PY'
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
if pids:
    time.sleep(0.5)
PY

setsid sh -c 'cd /app/statsserver && exec make serve' >/tmp/statsserver-verifier.log 2>&1 &
SERVER_PID=$!
cleanup() {
    kill -TERM -- "-$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import glob
import time
import pytest
import requests
from scipy import stats

RESULTS_PATH = "/home/user/data/processed/results.json"
URL = "http://127.0.0.1:8080/api/stats"
HEADERS = {"Authorization": "Bearer token-stats-2024"}


def get_quantile(data, p):
    data = sorted(data)
    n = len(data)
    if n == 0:
        return None
    pos = (n - 1) * p
    i = int(math.floor(pos))
    f = pos - i
    if i + 1 < n:
        return data[i] + f * (data[i + 1] - data[i])
    return data[i]


def filter_outliers(group_data):
    if not group_data:
        return []
    q1 = get_quantile(group_data, 0.25)
    q3 = get_quantile(group_data, 0.75)
    iqr = q3 - q1
    lower = q1 - 1.5 * iqr
    upper = q3 + 1.5 * iqr
    return [x for x in group_data if lower <= x <= upper]


def compute_stats(data):
    n = len(data)
    mean = sum(data) / n
    var = sum((x - mean) ** 2 for x in data) / (n - 1)
    return n, mean, var


def expected_results():
    data_a = []
    data_b = []

    for file in glob.glob('/home/user/data/raw/*.csv'):
        with open(file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                val_str = row.get('value', '').strip()
                if not val_str or val_str.lower() == 'nan':
                    continue
                try:
                    val = float(val_str)
                    if row['group'] == 'A':
                        data_a.append(val)
                    elif row['group'] == 'B':
                        data_b.append(val)
                except ValueError:
                    pass

    clean_a = filter_outliers(data_a)
    clean_b = filter_outliers(data_b)
    n_a, mean_a, var_a = compute_stats(clean_a)
    n_b, mean_b, var_b = compute_stats(clean_b)

    se_a = math.sqrt(var_a / n_a)
    se_b = math.sqrt(var_b / n_b)
    se_diff_sq = var_a / n_a + var_b / n_b
    t_stat = (mean_a - mean_b) / math.sqrt(se_diff_sq)
    welch_df = se_diff_sq ** 2 / (
        (var_a / n_a) ** 2 / (n_a - 1) +
        (var_b / n_b) ** 2 / (n_b - 1)
    )
    p_value = 2.0 * stats.t.sf(abs(t_stat), welch_df)

    tcrit_a = stats.t.ppf(0.975, n_a - 1)
    tcrit_b = stats.t.ppf(0.975, n_b - 1)
    zcrit = stats.norm.ppf(0.975)

    return {
        "group_a_mean": mean_a,
        "group_b_mean": mean_b,
        "t_statistic": t_stat,
        "p_value": p_value,
        "a_t_ci": (mean_a - tcrit_a * se_a, mean_a + tcrit_a * se_a),
        "b_t_ci": (mean_b - tcrit_b * se_b, mean_b + tcrit_b * se_b),
        "a_z_ci": (mean_a - zcrit * se_a, mean_a + zcrit * se_a),
        "b_z_ci": (mean_b - zcrit * se_b, mean_b + zcrit * se_b),
    }


EXPECTED_KEYS = {
    "group_a_mean", "group_a_ci_lower", "group_a_ci_upper",
    "group_b_mean", "group_b_ci_lower", "group_b_ci_upper",
    "t_statistic", "p_value"
}


def close(actual, expected):
    return math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-4)


def validate_results(data):
    assert isinstance(data, dict), "Results must be a JSON object"
    missing_keys = EXPECTED_KEYS - set(data.keys())
    assert not missing_keys, f"JSON response is missing keys: {missing_keys}"
    assert set(data.keys()) == EXPECTED_KEYS, f"JSON must contain exactly the required keys; got {set(data.keys())}"

    for key in EXPECTED_KEYS:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"{key} must be a number"
        assert math.isfinite(data[key]), f"{key} must be finite"

    expected = expected_results()
    assert close(data["group_a_mean"], expected["group_a_mean"]), \
        f"group_a_mean mismatch: expected {expected['group_a_mean']}, got {data['group_a_mean']}"
    assert close(data["group_b_mean"], expected["group_b_mean"]), \
        f"group_b_mean mismatch: expected {expected['group_b_mean']}, got {data['group_b_mean']}"
    assert close(abs(data["t_statistic"]), abs(expected["t_statistic"])), \
        f"t_statistic mismatch: expected {expected['t_statistic']}, got {data['t_statistic']}"
    assert close(data["p_value"], expected["p_value"]), \
        f"p_value mismatch: expected {expected['p_value']}, got {data['p_value']}"

    a_ci = (data["group_a_ci_lower"], data["group_a_ci_upper"])
    b_ci = (data["group_b_ci_lower"], data["group_b_ci_upper"])
    uses_t = all(close(x, y) for x, y in zip(a_ci, expected["a_t_ci"])) and \
             all(close(x, y) for x, y in zip(b_ci, expected["b_t_ci"]))
    uses_z = all(close(x, y) for x, y in zip(a_ci, expected["a_z_ci"])) and \
             all(close(x, y) for x, y in zip(b_ci, expected["b_z_ci"]))
    assert uses_t or uses_z, \
        f"Confidence intervals do not match a t or z 95% interval: A={a_ci}, B={b_ci}"


def wait_for_server():
    last_error = None
    for _ in range(50):
        try:
            response = requests.get(URL, headers=HEADERS, timeout=1)
            if response.status_code == 200:
                return response
            last_error = f"HTTP {response.status_code}: {response.text}"
        except requests.exceptions.RequestException as exc:
            last_error = str(exc)
        time.sleep(0.2)
    pytest.fail(f"Failed to start server using make serve: {last_error}")


def test_server_response_and_results_file():
    assert os.path.isfile(RESULTS_PATH), "Processed results.json is missing"
    with open(RESULTS_PATH, 'r') as f:
        file_data = json.load(f)
    validate_results(file_data)

    response = wait_for_server()
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Server did not return valid JSON. Response: {response.text}")
    validate_results(data)
    assert data == file_data, "Server response does not match the processed results.json file"

    unauthorized = requests.get(URL, timeout=5)
    assert unauthorized.status_code == 401, \
        f"Request without the exact token should return 401, got {unauthorized.status_code}"

    # Prove that make serve configured the required path rather than serving a
    # separately fabricated fixed response.
    with open(RESULTS_PATH, 'rb') as f:
        original = f.read()
    probe = {"verifier_path_probe": "results-json-path-8080"}
    try:
        with open(RESULTS_PATH, 'w') as f:
            json.dump(probe, f)
        probe_response = requests.get(URL, headers=HEADERS, timeout=5)
        assert probe_response.status_code == 200
        assert probe_response.json() == probe, \
            "Server is not reading /home/user/data/processed/results.json"
    finally:
        with open(RESULTS_PATH, 'wb') as f:
            f.write(original)


def test_makefile_fixed_and_bound_correctly():
    makefile_path = "/app/statsserver/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "STATS_DATA_PATH=/home/user/data/processed/results.json" in content, \
        "Makefile does not correctly export STATS_DATA_PATH to the processed results.json."
    assert "port=8080" in content, "Makefile does not run the flask app on port 8080."

    listening_on_loopback = False
    with open('/proc/net/tcp') as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 4 and fields[1].upper() == '0100007F:1F90' and fields[3] == '0A':
                listening_on_loopback = True
                break
    assert listening_on_loopback, "make serve did not bind the server to 127.0.0.1:8080"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
