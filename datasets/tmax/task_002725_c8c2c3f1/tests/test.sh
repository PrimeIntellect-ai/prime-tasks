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
# test_final_state.py
import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"

def test_target_neighborhood():
    url = f"{BASE_URL}/api/target_neighborhood"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the API at {url}. Is the server running?")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected = ["N_01", "N_02", "N_42", "N_99"]
    assert isinstance(data, list), "Expected a JSON array"
    assert sorted(data) == expected, f"Expected {expected}, got {sorted(data)}"
    assert data == expected, f"Expected alphabetically sorted output {expected}, got {data}"

def test_aggregate_like():
    url = f"{BASE_URL}/api/aggregate?interaction_type=like"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the API at {url}. Is the server running?")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert isinstance(data, dict), "Expected a JSON object"
    assert "average_age" in data, "Expected key 'average_age' in response"

    # 25 + 40 = 65 / 2 = 32.5
    assert float(data["average_age"]) == 32.5, f"Expected average_age to be 32.5, got {data['average_age']}"

def test_aggregate_comment():
    url = f"{BASE_URL}/api/aggregate?interaction_type=comment"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to the API at {url}. Is the server running?")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert isinstance(data, dict), "Expected a JSON object"
    assert "average_age" in data, "Expected key 'average_age' in response"

    # Source for comment is N_02, age is 30
    assert float(data["average_age"]) == 30.0, f"Expected average_age to be 30.0, got {data['average_age']}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_state.py
import glob
import os
import signal
import subprocess
import time

import requests

BASE_URL = "http://127.0.0.1:8080"
PORT_HEX = "1F90"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].upper().endswith(":" + PORT_HEX) and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return int(proc.rsplit("/", 1)[-1])
    return None


def read_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        args = [x.decode() for x in f.read().split(b"\0") if x]
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = [x for x in f.read().split(b"\0") if x]
    env = {}
    for entry in entries:
        key, sep, value = entry.partition(b"=")
        if sep:
            env[key.decode()] = value.decode()
    cwd = os.readlink(f"/proc/{pid}/cwd")
    assert args, "Could not determine the server command"
    return args, env, cwd


def stop_current_server():
    first = listener_pid()
    assert first is not None, "No process is listening on 127.0.0.1:8080"
    launch = read_process(first)

    deadline = time.time() + 8
    while time.time() < deadline:
        pid = listener_pid()
        if pid is None:
            return launch
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        time.sleep(0.2)

    pid = listener_pid()
    if pid is not None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pid() is not None:
        time.sleep(0.1)
    assert listener_pid() is None, "Could not stop the original API server"
    return launch


def wait_for_server(proc):
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Restarted server exited with status {proc.returncode}")
        try:
            response = requests.get(BASE_URL + "/api/target_neighborhood", timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f"Restarted server did not become ready: {last_error}")


def get_json(path):
    response = requests.get(BASE_URL + path, timeout=5)
    assert response.status_code == 200, f"Expected status 200 for {path}, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        raise AssertionError(f"Response for {path} is not valid JSON: {response.text}")


args, env, cwd = stop_current_server()

with open("/home/user/data/nodes.csv", "w") as f:
    f.write('node_id,profile_data\n')
    f.write('N_10,"{""age"": 20, ""country"": ""AA""}"\n')
    f.write('N_20,"{""age"": 44, ""country"": ""BB""}"\n')
    f.write('N_77,"{""age"": 31, ""country"": ""CC""}"\n')
    f.write('N_80,"{""age"": 58, ""country"": ""DD""}"\n')
    f.write('N_90,"{""age"": 73, ""country"": ""EE""}"\n')

with open("/home/user/data/edges.csv", "w") as f:
    f.write('source,target,interaction_type\n')
    f.write('N_10,N_20,spark\n')
    f.write('N_77,N_20,spark\n')
    f.write('N_80,N_77,wave\n')
    f.write('N_90,N_80,spark\n')
    f.write('N_10,N_80,spark\n')

subprocess.run([
    "convert", "-background", "white", "-fill", "black", "-pointsize", "36",
    "label:Target Node: N_77\\nDepth: 2", "/app/query_params.png"
], check=True)

proc = subprocess.Popen(
    args,
    cwd=cwd,
    env=env,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)
wait_for_server(proc)

neighborhood = get_json("/api/target_neighborhood")
expected_neighborhood = ["N_10", "N_20", "N_77", "N_80", "N_90"]
assert isinstance(neighborhood, list), "Expected target_neighborhood to return a JSON array"
assert neighborhood == expected_neighborhood, (
    f"Expected alphabetically sorted data-derived neighborhood {expected_neighborhood}, got {neighborhood}"
)

spark = get_json("/api/aggregate?interaction_type=spark")
assert isinstance(spark, dict), "Expected spark aggregation to return a JSON object"
assert "average_age" in spark, "Expected key 'average_age' in spark response"
assert float(spark["average_age"]) == 41.33, f"Expected rounded spark average 41.33, got {spark['average_age']}"

wave = get_json("/api/aggregate?interaction_type=wave")
assert isinstance(wave, dict), "Expected wave aggregation to return a JSON object"
assert "average_age" in wave, "Expected key 'average_age' in wave response"
assert float(wave["average_age"]) == 58.0, f"Expected wave average 58.0, got {wave['average_age']}"
DYNAMIC_EOF

ok=0
if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    if python3 /tmp/test_dynamic_state.py 2>&1; then
        ok=1
    fi
fi

echo "$ok" > /logs/verifier/reward.txt
exit 0
