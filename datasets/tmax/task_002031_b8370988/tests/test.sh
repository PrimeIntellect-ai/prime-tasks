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
import csv
import json
import math
import os
import random
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest
import redis
import requests
from scipy.stats import ttest_1samp

SCRIPT_PATH = "/home/user/filter.py"
BASELINE_PATH = "/app/reference_baselines.csv"
UPLOAD_URL = "http://127.0.0.1:8080/upload"


def read_baselines():
    with open(BASELINE_PATH, newline="") as f:
        return {row["sensor_id"]: float(row["baseline_mean"]) for row in csv.DictReader(f)}


def run_filter(records):
    fd, path = tempfile.mkstemp(prefix=f"sensor-{secrets.token_hex(8)}-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(records, f)
        return subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True, text=True, timeout=15)
    finally:
        if os.path.exists(path):
            os.remove(path)


def assert_filter(records, anomalous):
    result = run_filter(records)
    expected_text = "EVIL" if anomalous else "CLEAN"
    expected_code = 1 if anomalous else 0
    assert result.returncode == expected_code, (
        f"Expected exit {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout in (expected_text, expected_text + "\n"), (
        f"Expected exactly {expected_text!r}, got {result.stdout!r}"
    )


def records_for(groups):
    records = []
    timestamp = random.randint(1_700_000_000, 1_900_000_000)
    for sensor_id, values in groups.items():
        for value in values:
            records.append({"sensor_id": sensor_id, "timestamp": timestamp, "value": value})
            timestamp += random.randint(1, 7)
    random.shuffle(records)
    return records


def expected_anomalous(groups, baselines):
    for sensor_id, values in groups.items():
        if sensor_id not in baselines:
            return True
        if len(values) < 2:
            continue
        pvalue = float(ttest_1samp(values, baselines[sensor_id]).pvalue)
        if not math.isnan(pvalue) and pvalue < 0.01:
            return True
    return False


def running_process(predicate):
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            command = (entry / "comm").read_text().strip()
            cmdline = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            cwd = os.readlink(entry / "cwd")
        except (OSError, UnicodeError):
            continue
        if predicate(command, cmdline, cwd):
            return True
    return False


def test_filter_script_corpus():
    script_path = "/home/user/filter.py"
    assert os.path.isfile(script_path), f"Missing filter script: {script_path}"

    clean_dir = Path("/app/tests/corpus/clean")
    evil_dir = Path("/app/tests/corpus/evil")

    clean_files = list(clean_dir.glob("*.json"))
    evil_files = list(evil_dir.glob("*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        res = subprocess.run(["python3", script_path, str(cf)], capture_output=True, text=True)
        if res.returncode != 0 or "CLEAN" not in res.stdout:
            clean_failed.append(cf.name)

    evil_failed = []
    for ef in evil_files:
        res = subprocess.run(["python3", script_path, str(ef)], capture_output=True, text=True)
        if res.returncode != 1 or "EVIL" not in res.stdout:
            evil_failed.append(ef.name)

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_filter_randomized_and_grouped_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Missing filter script: {SCRIPT_PATH}"
    baselines = read_baselines()
    assert baselines

    # Every configured sensor is represented in one shuffled, valid file.
    clean_groups = {
        sensor_id: [mean - 0.75, mean, mean + 0.75]
        for sensor_id, mean in baselines.items()
    }
    assert_filter(records_for(clean_groups), False)

    # Fewer than two values is valid for each known sensor, even for huge values.
    singleton_groups = {
        sensor_id: [mean + random.uniform(5000, 10000)]
        for sensor_id, mean in baselines.items()
    }
    assert_filter(records_for(singleton_groups), False)

    # One anomalous group must reject a file even when all other groups are clean.
    evil_sensor = random.choice(list(baselines))
    mixed_groups = dict(clean_groups)
    mean = baselines[evil_sensor]
    mixed_groups[evil_sensor] = [mean + 70.0, mean + 70.2, mean + 69.8, mean + 70.1]
    assert_filter(records_for(mixed_groups), True)

    # An unknown sensor immediately rejects, including when it has only one value.
    unknown = "UNKNOWN_" + secrets.token_hex(10)
    missing_groups = {random.choice(list(baselines)): [0.0], unknown: [random.uniform(-100, 100)]}
    assert_filter(records_for(missing_groups), True)

    # Exercise fresh values and derive each answer using scipy.stats.ttest_1samp.
    sensor_ids = list(baselines)
    checked = 0
    while checked < 16:
        selected = random.sample(sensor_ids, random.randint(1, len(sensor_ids)))
        groups = {}
        safely_away_from_boundary = True
        for sensor_id in selected:
            count = random.randint(2, 8)
            mean = baselines[sensor_id]
            offset = random.uniform(-12, 12)
            spread = random.uniform(0.2, 5.0)
            values = [mean + offset + random.gauss(0, spread) for _ in range(count)]
            pvalue = float(ttest_1samp(values, mean).pvalue)
            if not math.isnan(pvalue) and abs(pvalue - 0.01) < 0.002:
                safely_away_from_boundary = False
                break
            groups[sensor_id] = values
        if not safely_away_from_boundary:
            continue
        expected = expected_anomalous(groups, baselines)
        assert_filter(records_for(groups), expected)
        checked += 1


def test_filter_reloads_reference_baselines():
    # Adding a random baseline creates a case that must be CLEAN, while the same
    # unknown ID must be EVIL after restoration. This verifies the CSV is loaded.
    original = Path(BASELINE_PATH).read_bytes()
    sensor_id = "DYNAMIC_" + secrets.token_hex(10)
    mean = random.uniform(-250, 250)
    payload = records_for({sensor_id: [mean - 1.25, mean, mean + 1.25]})
    try:
        with open(BASELINE_PATH, "ab") as f:
            if original and not original.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"{sensor_id},{mean:.17g}\n".encode())
        assert_filter(payload, False)
    finally:
        Path(BASELINE_PATH).write_bytes(original)
    assert_filter(payload, True)


def test_env_configured():
    env_path = "/app/data_app/.env"
    assert os.path.isfile(env_path), "Missing .env file"
    with open(env_path, "r") as f:
        content = f.read()

    assert "REDIS_HOST=127.0.0.1" in content, "REDIS_HOST not set correctly in .env"
    assert "REDIS_PORT=6379" in content, "REDIS_PORT not set correctly in .env"
    assert "FILTER_SCRIPT=/home/user/filter.py" in content, "FILTER_SCRIPT not set correctly in .env"


def test_services_running_and_proxying():
    # Preserve the original fixed end-to-end assertions.
    clean_payload = [{"sensor_id": "S1", "timestamp": 1620000000, "value": 10.5}, {"sensor_id": "S1", "timestamp": 1620000001, "value": 10.6}]
    evil_payload = [{"sensor_id": "S1", "timestamp": 1620000000, "value": 100.5}, {"sensor_id": "S1", "timestamp": 1620000001, "value": 100.6}]

    try:
        res_clean = requests.post(UPLOAD_URL, json=clean_payload, timeout=5)
        assert res_clean.status_code == 200, f"Expected HTTP 200 for clean payload, got {res_clean.status_code}"

        res_evil = requests.post(UPLOAD_URL, json=evil_payload, timeout=5)
        assert res_evil.status_code == 400, f"Expected HTTP 400 for evil payload, got {res_evil.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx proxy on port 8080: {e}")


def test_actual_services_random_end_to_end_and_redis():
    nginx_conf = Path("/app/nginx/nginx.conf").read_text()
    assert re.search(r"\blisten\s+8080\s*;", nginx_conf), "Nginx is not configured to listen on 8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", nginx_conf), (
        "Nginx is not configured to proxy to 127.0.0.1:5000"
    )
    config_test = subprocess.run(["nginx", "-t", "-c", "/app/nginx/nginx.conf"], capture_output=True, text=True)
    assert config_test.returncode == 0, config_test.stderr

    assert running_process(lambda comm, cmd, cwd: comm == "nginx"), "Nginx process is not running"
    assert running_process(lambda comm, cmd, cwd: comm.startswith("redis-server")), "Redis server is not running"
    assert running_process(lambda comm, cmd, cwd: "app.py" in cmd and cwd == "/app/data_app"), (
        "Flask data application is not running from /app/data_app"
    )

    cache = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=5)
    assert cache.ping() is True, "Redis did not answer PING"
    cache.delete("last_upload")

    baselines = read_baselines()
    sensor_id = random.choice(list(baselines))
    mean = baselines[sensor_id]
    base_ts = random.randint(2_000_000_000, 2_100_000_000)
    clean_payload = [
        {"sensor_id": sensor_id, "timestamp": base_ts, "value": mean - 1.0},
        {"sensor_id": sensor_id, "timestamp": base_ts + 3, "value": mean},
        {"sensor_id": sensor_id, "timestamp": base_ts + 9, "value": mean + 1.0},
    ]

    response = requests.post(UPLOAD_URL, json=clean_payload, timeout=10)
    assert response.status_code == 200
    assert response.json() == {"status": "CLEAN"}
    stored = cache.get("last_upload")
    assert stored is not None, "Clean upload was not stored in Redis"
    assert json.loads(stored) == clean_payload, "Redis last_upload does not contain the submitted payload"

    evil_payload = [
        {"sensor_id": sensor_id, "timestamp": base_ts + 20 + i, "value": mean + 80 + i / 10}
        for i in range(5)
    ]
    response = requests.post(UPLOAD_URL, json=evil_payload, timeout=10)
    assert response.status_code == 400
    assert response.json() == {"status": "EVIL"}
    assert json.loads(cache.get("last_upload")) == clean_payload, "An evil upload overwrote Redis"

    # Confirm the Flask application itself is listening on the required upstream port.
    direct_payload = [{"sensor_id": sensor_id, "timestamp": base_ts + 100, "value": mean + 9999}]
    direct = requests.post("http://127.0.0.1:5000/upload", json=direct_payload, timeout=10)
    assert direct.status_code == 200
    assert direct.json() == {"status": "CLEAN"}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
