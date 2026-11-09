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
import os
import re
import json
import csv
import time
import signal
import secrets
import subprocess
from collections import defaultdict

import pytest
import requests


def get_expected_data():
    data = defaultdict(list)
    raw_dir = "/home/user/raw_data"
    for root, _, files in os.walk(raw_dir):
        for f in files:
            path = os.path.join(root, f)
            if f.endswith('.csv'):
                with open(path, 'r') as csvfile:
                    reader = csv.DictReader(csvfile)
                    for row in reader:
                        ts = f"{row['date'].strip()}T{row['time'].strip()}"
                        data[row['sensor'].strip()].append({"timestamp": ts, "value": float(row['reading'])})
            elif f.endswith('.json'):
                with open(path, 'r') as jsonfile:
                    try:
                        content = json.load(jsonfile)
                        for item in content:
                            data[item['sensor_id']].append({"timestamp": item['ts'], "value": float(item['val'])})
                    except Exception:
                        pass
            elif f.endswith('.log'):
                with open(path, 'r') as logfile:
                    records = logfile.read().strip().split('---RECORD---')
                    for record in records:
                        if not record.strip():
                            continue
                        ts = None
                        sid = None
                        val = None
                        for line in record.split('\n'):
                            line = line.strip()
                            if line.startswith('TS:'):
                                ts = line.split(':', 1)[1].strip()
                            elif line.startswith('ID:'):
                                sid = line.split(':', 1)[1].strip()
                            elif line.startswith('VAL:'):
                                val = float(line.split(':', 1)[1].strip())
                        if ts and sid and val is not None:
                            data[sid].append({"timestamp": ts, "value": val})
            elif f.endswith('.dat'):
                try:
                    out = subprocess.check_output(['/app/sensor_decoder', path], text=True)
                    content = json.loads(out)
                    for item in content:
                        data[item['sensor']].append({"timestamp": item['timestamp'], "value": float(item['reading'])})
                except Exception:
                    pass

    for sid in data:
        data[sid].sort(key=lambda x: x['timestamp'])
    return data


@pytest.fixture(scope="module")
def expected_data():
    return get_expected_data()


def test_auth_missing():
    response = requests.get("http://127.0.0.1:8080/query?sensor=test", timeout=5)
    assert response.status_code == 401, "Expected 401 Unauthorized when auth header is missing"


def test_auth_invalid():
    headers = {"Authorization": "Bearer WRONG-TOKEN"}
    response = requests.get("http://127.0.0.1:8080/query?sensor=test", headers=headers, timeout=5)
    assert response.status_code == 401, "Expected 401 Unauthorized when auth header is incorrect"


def test_sensor_not_found():
    headers = {"Authorization": "Bearer RES-992"}
    response = requests.get("http://127.0.0.1:8080/query?sensor=NON_EXISTENT_SENSOR_999", headers=headers, timeout=5)
    assert response.status_code == 200, "Expected 200 OK for non-existent sensor"
    assert response.json() == [], "Expected empty JSON array for non-existent sensor"


def assert_service_data(expected):
    assert expected, "No expected data found to test against. Check raw data parsing."
    headers = {"Authorization": "Bearer RES-992"}
    for sensor_id, expected_records in expected.items():
        response = requests.get(
            "http://127.0.0.1:8080/query",
            params={"sensor": sensor_id},
            headers=headers,
            timeout=5,
        )
        assert response.status_code == 200, f"Expected 200 OK for sensor {sensor_id}"
        actual_records = response.json()
        assert isinstance(actual_records, list), "Response must be a JSON array"
        assert len(actual_records) == len(expected_records), f"Mismatch in number of records for sensor {sensor_id}"
        for actual, expected_record in zip(actual_records, expected_records):
            assert "timestamp" in actual, "Missing 'timestamp' in response object"
            assert "value" in actual, "Missing 'value' in response object"
            assert actual["timestamp"] == expected_record["timestamp"], f"Timestamp mismatch for sensor {sensor_id}"
            assert abs(float(actual["value"]) - expected_record["value"]) < 1e-5, f"Value mismatch for sensor {sensor_id}"


def test_sensor_data(expected_data):
    assert_service_data(expected_data)


def listening_pid(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(':', 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    return int(entry)
        except OSError:
            continue
    return None


def process_launch_info(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors='surrogateescape') for part in f.read().split(b'\0') if part]
    assert argv, "Could not determine the service command"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for item in f.read().split(b'\0'):
                if b'=' in item:
                    key, value = item.split(b'=', 1)
                    env[key.decode(errors='surrogateescape')] = value.decode(errors='surrogateescape')
    except OSError:
        pass
    return argv, cwd, env


def stop_listener():
    pid = listening_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if listening_pid() != pid:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def find_bash_pipeline():
    candidates = []
    excluded = {"/tmp/test_final_state.py"}
    for base in ("/home/user", "/app", "/tmp"):
        for root, dirs, files in os.walk(base):
            if root.startswith('/home/user/raw_data'):
                dirs[:] = []
                continue
            for name in files:
                path = os.path.join(root, name)
                if path in excluded:
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, 'r', errors='ignore') as f:
                        text = f.read()
                except OSError:
                    continue
                is_shell = name.endswith('.sh') or text.startswith('#!/bin/bash') or text.startswith('#!/usr/bin/env bash')
                if not is_shell:
                    continue
                lower = text.lower()
                required = ["raw_data", "sensor_decoder", ".csv", ".json", ".log", ".dat"]
                if not all(token in lower for token in required):
                    continue
                if not re.search(r'(^|[^a-z0-9_])find([^a-z0-9_]|$)', lower):
                    continue
                if not (re.search(r'(^|[^a-z0-9_])jq([^a-z0-9_]|$)', lower) or
                        re.search(r'(^|[^a-z0-9_])awk([^a-z0-9_]|$)', lower)):
                    continue
                score = sum(lower.count(x) for x in ("find", "jq", "awk", "while", "case"))
                candidates.append((score, path))
    assert candidates, "No substantive Bash-based recursive data-processing pipeline was found"
    candidates.sort(reverse=True)
    return candidates[0][1]


def run_pipeline(path):
    proc = subprocess.Popen(
        ["bash", path],
        cwd=os.path.dirname(path) or '/',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()


def wait_for_service(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get("http://127.0.0.1:8080/query?sensor=probe", timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.2)
    pytest.fail("Service did not restart on 127.0.0.1:8080")


def test_pipeline_processes_unseen_nested_inputs_and_invokes_decoder():
    pipeline = find_bash_pipeline()
    pid = listening_pid()
    assert pid is not None, "No service is listening on port 8080"
    argv, cwd, env = process_launch_info(pid)

    token = secrets.token_hex(8)
    sensor = f"DYNAMIC-{token}"
    nested = os.path.join('/home/user/raw_data', f'audit_{token}', 'one', 'two', 'three')
    os.makedirs(nested, exist_ok=True)

    with open(os.path.join(nested, f'readings_{token}.csv'), 'w') as f:
        f.write(f"date,time,sensor,reading\n2037-04-03,03:04:05,{sensor},31.125\n")
    with open(os.path.join(nested, f'readings_{token}.json'), 'w') as f:
        json.dump([{"ts": "2037-04-01T01:02:03", "sensor_id": sensor, "val": 17.75}], f)
    with open(os.path.join(nested, f'readings_{token}.log'), 'w') as f:
        f.write(f"---RECORD---\nTS: 2037-04-02T02:03:04\nID: {sensor}\nVAL: 23.5\n---END---\n")
    dat_path = os.path.join(nested, f'readings_{token}.dat')
    with open(dat_path, 'wb') as f:
        f.write(secrets.token_bytes(19))

    decoder = '/app/sensor_decoder'
    real_decoder = '/app/sensor_decoder.verifier-real'
    decoder_log = f'/tmp/decoder_calls_{token}.log'
    assert os.path.isfile(decoder) and os.access(decoder, os.X_OK), "Legacy decoder is missing or not executable"
    os.rename(decoder, real_decoder)
    try:
        with open(decoder, 'w') as f:
            f.write('#!/bin/bash\nprintf "%s\\n" "$1" >> ' + json.dumps(decoder_log) + '\nexec ' + json.dumps(real_decoder) + ' "$@"\n')
        os.chmod(decoder, 0o755)
        run_pipeline(pipeline)
    finally:
        try:
            os.unlink(decoder)
        except FileNotFoundError:
            pass
        os.rename(real_decoder, decoder)

    assert os.path.exists(decoder_log), "The Bash pipeline did not invoke /app/sensor_decoder"
    with open(decoder_log) as f:
        decoder_calls = [line.strip() for line in f if line.strip()]
    assert dat_path in decoder_calls, "The Bash pipeline did not recursively process the newly added .dat file"

    stop_listener()
    with open('/tmp/restarted_service.log', 'ab') as output:
        subprocess.Popen(argv, cwd=cwd, env=env, stdout=output, stderr=output, start_new_session=True)
    wait_for_service()

    expected = get_expected_data()
    assert sensor in expected, "Dynamic fixture was not included in independently computed expected data"
    assert expected[sensor] == [
        {"timestamp": "2037-04-01T01:02:03", "value": 17.75},
        {"timestamp": "2037-04-02T02:03:04", "value": 23.5},
        {"timestamp": "2037-04-03T03:04:05", "value": 31.125},
    ]
    assert_service_data(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
