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
import pytest
import requests
import csv
import math
import io

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer pipe-auth-token-xyz"}

# Immutable copy of the dataset used to build the task. Expectations must not
# depend on the agent-writable file under /home/user.
ORIGINAL_CSV = '''Timestamp,ServerID,CPU,Memory,LogLevel,Message
2023-01-01T00:00:01Z,Server-Alpha,45.5,1024,INFO,"Starting process
Process ID: 123
Success"
2023-01-01T00:00:01Z,Server-Beta,50.0,2048,WARN,"High memory
Check swap"
2023-01-01T00:00:02Z,Server-Alpha,48.0,1048,ERROR,"Crash in module
Line 42"
2023-01-01T00:00:02Z,Server-Beta,40.0,2000,INFO,"Normal operation"
2023-01-01T00:00:03Z,Server-Alpha,42.5,1030,INFO,"Restarting
ok"
2023-01-01T00:00:03Z,Server-Beta,41.0,2010,WARN,"CPU spike
temp warning"
2023-01-01T00:00:04Z,Server-Alpha,50.0,1100,ERROR,"Failed to bind
port 80"
2023-01-01T00:00:04Z,Server-Beta,42.0,2020,ERROR,"Disk full
/dev/sda1"
'''

@pytest.fixture(scope="module")
def expected_data():
    records = []
    reader = csv.DictReader(io.StringIO(ORIGINAL_CSV, newline=''))
    for row in reader:
        row['CPU'] = float(row['CPU'])
        row['Memory'] = float(row['Memory'])
        records.append(row)

    stats = {}
    for r in records:
        sid = r['ServerID']
        if sid not in stats:
            stats[sid] = {'cpu': [], 'mem': []}
        stats[sid]['cpu'].append(r['CPU'])
        stats[sid]['mem'].append(r['Memory'])

    expected_stats = {}
    for sid, vals in stats.items():
        expected_stats[sid] = {
            "avg_cpu": sum(vals['cpu']) / len(vals['cpu']),
            "max_mem": float(max(vals['mem']))
        }

    alpha_cpu = [r['CPU'] for r in sorted(records, key=lambda x: x['Timestamp']) if r['ServerID'] == 'Server-Alpha']
    beta_cpu = [r['CPU'] for r in sorted(records, key=lambda x: x['Timestamp']) if r['ServerID'] == 'Server-Beta']
    dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(alpha_cpu, beta_cpu)))

    levels = {}
    for r in sorted(records, key=lambda x: x['Timestamp']):
        lvl = r['LogLevel']
        if lvl not in levels:
            levels[lvl] = []
        if len(levels[lvl]) < 2:
            levels[lvl].append(r)

    expected_sample = []
    for lvl in sorted(levels.keys()):
        expected_sample.extend(levels[lvl])

    return expected_stats, dist, expected_sample

@pytest.mark.parametrize("endpoint", ["stats", "distance", "sample"])
@pytest.mark.parametrize("headers", [None, {"Authorization": "Bearer wrong-token"}, {"Authorization": "pipe-auth-token-xyz"}])
def test_auth_required(endpoint, headers):
    """Verify every endpoint rejects missing and incorrect credentials."""
    try:
        response = requests.get(f"{BASE_URL}/{endpoint}", headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("API server is not reachable at 127.0.0.1:8080.")
    assert response.status_code in (401, 403), \
        f"Expected 401/403 for {endpoint} with invalid auth, got {response.status_code}"

def test_stats_endpoint(expected_data):
    expected_stats, _, _ = expected_data
    response = requests.get(f"{BASE_URL}/stats", headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"/stats returned status {response.status_code}. Body: {response.text}"
    data = response.json()
    assert isinstance(data, dict), "Expected a JSON dictionary from /stats"
    assert set(data) == set(expected_stats), f"Unexpected server IDs in /stats: {set(data) ^ set(expected_stats)}"
    for server_id, expected_vals in expected_stats.items():
        assert server_id in data, f"Missing {server_id} in /stats response"
        assert math.isclose(data[server_id]["avg_cpu"], expected_vals["avg_cpu"], rel_tol=1e-5), \
            f"Incorrect avg_cpu for {server_id}. Expected {expected_vals['avg_cpu']}, got {data[server_id]['avg_cpu']}"
        assert math.isclose(data[server_id]["max_mem"], expected_vals["max_mem"], rel_tol=1e-5), \
            f"Incorrect max_mem for {server_id}. Expected {expected_vals['max_mem']}, got {data[server_id]['max_mem']}"

def test_distance_endpoint(expected_data):
    _, expected_dist, _ = expected_data
    response = requests.get(f"{BASE_URL}/distance", headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"/distance returned status {response.status_code}. Body: {response.text}"
    data = response.json()
    assert "euclidean_distance" in data, "Missing 'euclidean_distance' key in /distance response"
    actual_dist = data["euclidean_distance"]
    assert math.isclose(actual_dist, expected_dist, rel_tol=1e-5), \
        f"Incorrect euclidean_distance. Expected {expected_dist}, got {actual_dist}"

def test_sample_endpoint(expected_data):
    _, _, expected_sample = expected_data
    response = requests.get(f"{BASE_URL}/sample", headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"/sample returned status {response.status_code}. Body: {response.text}"
    data = response.json()
    assert isinstance(data, list), "Expected a JSON list from /sample"
    assert len(data) == len(expected_sample), f"Expected {len(expected_sample)} records in sample, got {len(data)}"
    for i, (actual, expected) in enumerate(zip(data, expected_sample)):
        assert actual["LogLevel"] == expected["LogLevel"], f"Record {i}: Expected LogLevel {expected['LogLevel']}, got {actual.get('LogLevel')}"
        assert actual["Timestamp"] == expected["Timestamp"], f"Record {i}: Expected Timestamp {expected['Timestamp']}, got {actual.get('Timestamp')}"
        assert actual["ServerID"] == expected["ServerID"], f"Record {i}: Expected ServerID {expected['ServerID']}, got {actual.get('ServerID')}"
        assert math.isclose(float(actual["CPU"]), expected["CPU"], rel_tol=1e-5), f"Record {i}: CPU mismatch"
        assert math.isclose(float(actual["Memory"]), expected["Memory"], rel_tol=1e-5), f"Record {i}: Memory mismatch"
        assert actual["Message"] == expected["Message"], f"Record {i}: Expected Message {repr(expected['Message'])}, got {repr(actual.get('Message'))}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
