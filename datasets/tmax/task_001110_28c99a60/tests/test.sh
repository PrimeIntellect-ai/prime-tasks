#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import uuid

import pytest
import requests

DAEMON = "/home/user/sensor_daemon"
WWW = "/home/user/www"


def get_csv_data(legacy_data_dir):
    data = []
    for root, _, files in os.walk(legacy_data_dir):
        for file in files:
            if file.endswith(".csv"):
                with open(os.path.join(root, file), "r") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        parts = line.split(",")
                        if len(parts) == 3:
                            try:
                                data.append({
                                    "timestamp": int(parts[0]),
                                    "sensor_id": int(parts[1]),
                                    "value": float(parts[2]),
                                })
                            except ValueError:
                                pass
    return data


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.4):
                return
        except OSError:
            time.sleep(0.15)
    pytest.fail(f"Port {port} did not become available")


def redis_hget(sensor_id):
    result = subprocess.run(
        ["redis-cli", "HGET", "sensor_averages", str(sensor_id)],
        capture_output=True,
        text=True,
        check=True,
    )
    value = result.stdout.strip()
    return None if value == "" else value


def averages_to_dict(value):
    result = {}
    if isinstance(value, list):
        for item in value:
            if not isinstance(item, dict):
                continue
            sid = str(item.get("sensor_id", ""))
            if sid:
                result[sid] = float(item.get("average", item.get("value", 0)))
    elif isinstance(value, dict):
        for key, item in value.items():
            result[str(key)] = float(item)
    return result


def fetch_live_dict():
    response = requests.get("http://127.0.0.1:8080/live_averages.json", timeout=5)
    response.raise_for_status()
    return averages_to_dict(response.json())


@pytest.fixture(scope="session", autouse=True)
def validate_and_restart_submission():
    assert os.path.isfile(DAEMON), f"Missing required executable {DAEMON}"
    assert os.access(DAEMON, os.X_OK), f"{DAEMON} is not executable"
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sensor_daemon must be a compiled native executable"

    symbols = subprocess.run(
        ["readelf", "-Ws", DAEMON], capture_output=True, text=True, check=True
    ).stdout
    assert "mmap" in symbols, "sensor_daemon does not reference mmap"

    current = listener_pids(9000)
    assert current, "No daemon was left listening on TCP port 9000"
    matching = False
    for pid in current:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            if os.path.samefile(exe, DAEMON):
                matching = True
        except OSError:
            pass
    assert matching, "The process listening on port 9000 is not /home/user/sensor_daemon"

    for pid in current:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(9000):
        time.sleep(0.1)
    for pid in listener_pids(9000):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    rng = random.SystemRandom()
    fixture_path = f"/home/user/legacy_data/dir1/dir2/verifier_{uuid.uuid4().hex}.csv"
    rows = [
        (1800000000 + i, 7000 + rng.randrange(1000), rng.randrange(-5000, 5000) / 37.0)
        for i in range(5)
    ]
    with open(fixture_path, "w") as f:
        f.write("timestamp,sensor_id,value\n")
        for timestamp, sensor_id, value in rows:
            f.write(f"{timestamp},{sensor_id},{value:.9f}\n")

    for path in (f"{WWW}/historical.json", f"{WWW}/historical.tar.gz", f"{WWW}/live_averages.json"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    subprocess.run(["redis-cli", "DEL", "sensor_averages"], check=True, capture_output=True)

    proc = subprocess.Popen(
        [DAEMON], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_port(9000)

    deadline = time.time() + 8
    while time.time() < deadline:
        if os.path.isfile(f"{WWW}/historical.json") and os.path.isfile(f"{WWW}/historical.tar.gz"):
            break
        time.sleep(0.15)
    assert os.path.isfile(f"{WWW}/historical.json"), "Restarted daemon did not create historical.json"
    assert os.path.isfile(f"{WWW}/historical.tar.gz"), "Restarted daemon did not create historical.tar.gz"

    yield

    # Leave the successfully restarted daemon running, as required by the task.
    if proc.poll() is not None:
        pytest.fail("sensor_daemon exited during verification")


def test_nginx_and_historical_data():
    """Test Nginx is serving historical.tar.gz and it contains all parsed CSV data."""
    try:
        response = requests.get("http://127.0.0.1:8080/historical.tar.gz", timeout=5)
        response.raise_for_status()
    except requests.RequestException as e:
        pytest.fail(f"Failed to fetch historical.tar.gz from Nginx on port 8080: {e}")

    with tempfile.TemporaryDirectory() as tmpdir:
        tar_path = os.path.join(tmpdir, "historical.tar.gz")
        with open(tar_path, "wb") as f:
            f.write(response.content)

        try:
            with tarfile.open(tar_path, "r:gz") as tar:
                tar.extractall(path=tmpdir)
        except tarfile.TarError as e:
            pytest.fail(f"Failed to extract historical.tar.gz: {e}")

        json_path = os.path.join(tmpdir, "historical.json")
        if not os.path.exists(json_path):
            found = False
            for root, _, files in os.walk(tmpdir):
                if "historical.json" in files:
                    json_path = os.path.join(root, "historical.json")
                    found = True
                    break
            if not found:
                pytest.fail("historical.json not found inside the extracted tarball.")

        with open(json_path) as f:
            try:
                historical_data = json.load(f)
            except json.JSONDecodeError as e:
                pytest.fail(f"historical.json is not valid JSON: {e}")

    expected_data = get_csv_data("/home/user/legacy_data")
    assert len(historical_data) == len(expected_data), (
        f"Expected {len(expected_data)} records in historical.json, got {len(historical_data)}"
    )

    def sort_key(x):
        return (x.get("timestamp", 0), x.get("sensor_id", 0), x.get("value", 0))

    expected_data.sort(key=sort_key)
    historical_data.sort(key=sort_key)
    for exp, act in zip(expected_data, historical_data):
        assert exp["timestamp"] == act.get("timestamp"), "Timestamp mismatch in historical data"
        assert exp["sensor_id"] == act.get("sensor_id"), "Sensor ID mismatch in historical data"
        assert abs(exp["value"] - act.get("value", 0)) < 1e-5, "Value mismatch in historical data"


def test_invalid_auth_and_varied_live_processing():
    rng = random.SystemRandom()
    bad_sid = 40000 + rng.randrange(10000)
    subprocess.run(["redis-cli", "HDEL", "sensor_averages", str(bad_sid)], check=True, capture_output=True)

    with socket.create_connection(("127.0.0.1", 9000), timeout=5) as sock:
        sock.sendall(
            (f"AUTH wrong_token\n{{\"timestamp\":1900000000,\"sensor_id\":{bad_sid},\"value\":9876.5}}\n").encode()
        )
    time.sleep(1)
    assert redis_hget(bad_sid) is None, "Payload sent after invalid authentication was processed"
    try:
        assert str(bad_sid) not in fetch_live_dict(), "Invalidly authenticated sensor appeared in live output"
    except requests.HTTPError as e:
        if e.response is None or e.response.status_code != 404:
            raise

    sensor_ids = [50000 + rng.randrange(4000), 55000 + rng.randrange(4000)]
    while sensor_ids[1] == sensor_ids[0]:
        sensor_ids[1] = 55000 + rng.randrange(4000)
    values = {
        sensor_ids[0]: [rng.randrange(-3000, 3000) / 10.0 for _ in range(4)],
        sensor_ids[1]: [rng.randrange(-3000, 3000) / 10.0 for _ in range(3)],
    }
    expected = {sid: sum(items) / len(items) for sid, items in values.items()}

    with socket.create_connection(("127.0.0.1", 9000), timeout=5) as sock:
        sock.sendall(b"AUTH sensor_token_99X\n")
        timestamp = 1900000100
        for index in range(4):
            for sid in sensor_ids:
                if index < len(values[sid]):
                    payload = {
                        "timestamp": timestamp,
                        "sensor_id": sid,
                        "value": values[sid][index],
                    }
                    sock.sendall((json.dumps(payload) + "\n").encode())
                    timestamp += 1

    deadline = time.time() + 7
    last_live = {}
    while time.time() < deadline:
        try:
            last_live = fetch_live_dict()
            redis_ok = all(
                redis_hget(sid) is not None and abs(float(redis_hget(sid)) - expected[sid]) < 1e-5
                for sid in sensor_ids
            )
            file_ok = all(
                str(sid) in last_live and abs(last_live[str(sid)] - expected[sid]) < 1e-5
                for sid in sensor_ids
            )
            if redis_ok and file_ok:
                break
        except (requests.RequestException, ValueError, json.JSONDecodeError):
            pass
        time.sleep(0.2)
    else:
        pytest.fail(f"Varied running averages were not correctly published; last output: {last_live}")


def test_daemon_live_processing_and_redis():
    """Retain the original fixed live-data, Nginx, and Redis assertions."""
    try:
        s = socket.create_connection(("127.0.0.1", 9000), timeout=5)
    except OSError as e:
        pytest.fail(f"Could not connect to daemon on 127.0.0.1:9000: {e}")

    with s:
        s.settimeout(5.0)
        s.sendall(b"AUTH sensor_token_99X\n")
        time.sleep(0.5)
        payloads = [
            '{"timestamp": 1700000001, "sensor_id": 1, "value": 10.0}\n',
            '{"timestamp": 1700000002, "sensor_id": 1, "value": 20.0}\n',
            '{"timestamp": 1700000003, "sensor_id": 2, "value": 15.0}\n',
        ]
        for payload in payloads:
            s.sendall(payload.encode("utf-8"))
            time.sleep(0.2)

    time.sleep(2)
    try:
        response = requests.get("http://127.0.0.1:8080/live_averages.json", timeout=5)
        response.raise_for_status()
        live_averages = response.json()
    except requests.RequestException as e:
        pytest.fail(f"Failed to fetch live_averages.json from Nginx: {e}")
    except json.JSONDecodeError as e:
        pytest.fail(f"live_averages.json is not valid JSON: {e}")

    avg_dict = averages_to_dict(live_averages)
    assert "1" in avg_dict, "Sensor 1 not found in live_averages.json"
    assert "2" in avg_dict, "Sensor 2 not found in live_averages.json"
    assert abs(avg_dict["1"] - 15.0) < 1e-5, f"Expected average for sensor 1 to be 15.0, got {avg_dict['1']}"
    assert abs(avg_dict["2"] - 15.0) < 1e-5, f"Expected average for sensor 2 to be 15.0, got {avg_dict['2']}"

    for sid in (1, 2):
        try:
            redis_val = redis_hget(sid)
            assert redis_val is not None, f"Redis HGET sensor_averages {sid} returned empty"
            assert abs(float(redis_val) - 15.0) < 1e-5, (
                f"Expected Redis sensor_averages {sid} to be 15.0, got {redis_val}"
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to query Redis: {e.stderr}")
        except ValueError:
            pytest.fail(f"Redis returned non-float value for sensor {sid}: {redis_val}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
