#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import secrets
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests


def compute_signature(timestamp: str, sensor_id: int, temperature: float) -> str:
    # Match the C binary logic: SHA256 of `<timestamp_iso8601>|<sensor_id>|<temperature>`
    payload = f"{timestamp}|{sensor_id}|{temperature}"
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()


def test_api_sensor_101():
    url = "http://127.0.0.1:8080/api/data?sensor_id=101"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    data = response.json()
    assert isinstance(data, list), "Expected API response to be a JSON array"
    assert len(data) == 5, f"Expected 5 records for sensor 101, got {len(data)}"

    expected_times = [
        "2023-10-01T10:00:00Z",
        "2023-10-01T10:05:00Z",
        "2023-10-01T10:10:00Z",
        "2023-10-01T10:15:00Z",
        "2023-10-01T10:20:00Z"
    ]
    expected_temps = [22.5, 22.6, 22.6, 22.6, 23.0]
    expected_humids = [45.0, 45.2, 45.2, 45.2, 46.0]

    for i, record in enumerate(data):
        assert record.get("timestamp") == expected_times[i], f"Mismatch in timestamp at index {i}"
        assert str(record.get("sensor_id")) == "101", f"Mismatch in sensor_id at index {i}"
        assert record.get("location") == "Warehouse_A", f"Mismatch in location at index {i}"
        assert float(record.get("temperature")) == expected_temps[i], f"Mismatch in temperature at index {i}"
        assert float(record.get("humidity")) == expected_humids[i], f"Mismatch in humidity at index {i}"

        expected_sig = compute_signature(expected_times[i], 101, expected_temps[i])
        assert record.get("signature") == expected_sig, f"Mismatch in signature at index {i}"


def test_api_sensor_102():
    url = "http://127.0.0.1:8080/api/data?sensor_id=102"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    data = response.json()
    assert isinstance(data, list), "Expected API response to be a JSON array"
    assert len(data) == 3, f"Expected 3 records for sensor 102, got {len(data)}"

    expected_times = [
        "2023-10-01T10:00:00Z",
        "2023-10-01T10:05:00Z",
        "2023-10-01T10:10:00Z"
    ]
    expected_temps = [19.0, 19.0, 19.5]
    expected_humids = [50.0, 50.0, 51.0]

    for i, record in enumerate(data):
        assert record.get("timestamp") == expected_times[i], f"Mismatch in timestamp at index {i}"
        assert str(record.get("sensor_id")) == "102", f"Mismatch in sensor_id at index {i}"
        assert record.get("location") == "Basement", f"Mismatch in location at index {i}"
        assert float(record.get("temperature")) == expected_temps[i], f"Mismatch in temperature at index {i}"
        assert float(record.get("humidity")) == expected_humids[i], f"Mismatch in humidity at index {i}"

        expected_sig = compute_signature(expected_times[i], 102, expected_temps[i])
        assert record.get("signature") == expected_sig, f"Mismatch in signature at index {i}"


def listener_pid(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port:
                    inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return None


def read_process(pid):
    proc = Path(f"/proc/{pid}")
    argv = [part.decode("utf-8", "surrogateescape") for part in (proc / "cmdline").read_bytes().split(b"\0") if part]
    cwd = os.readlink(proc / "cwd")
    env = os.environ.copy()
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    assert argv, "Could not determine the API server command"
    return argv, cwd, env


def stop_listener(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 4
    while time.time() < deadline:
        if listener_pid() is None:
            return
        time.sleep(0.1)
    current = listener_pid()
    if current is not None:
        os.kill(current, signal.SIGKILL)
    deadline = time.time() + 2
    while time.time() < deadline and listener_pid() is not None:
        time.sleep(0.05)


def wait_for_api(sensor_id):
    url = f"http://127.0.0.1:8080/api/data?sensor_id={sensor_id}"
    deadline = time.time() + 12
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                return response
            last_error = AssertionError(f"HTTP {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"Restarted API did not become ready: {last_error}")


def is_null(value):
    return value is None or (isinstance(value, float) and math.isnan(value))


def test_pipeline_on_randomized_source_files_and_signer_invocation():
    pid = listener_pid()
    assert pid is not None, "No process is listening on 127.0.0.1:8080"
    argv, cwd, env = read_process(pid)
    stop_listener(pid)
    assert listener_pid() is None, "Could not stop the original API server"

    # Instrument the required signer without changing its input/output behavior.
    signer = Path("/app/data_signer")
    real_signer = Path("/app/data_signer.verifier_real")
    call_log = Path("/tmp/verifier_signer_calls.log")
    shutil.copy2(signer, real_signer)
    call_log.write_text("")
    signer.write_text("""#!/usr/bin/python3
import subprocess
import sys
payload = sys.stdin.readline()
with open('/tmp/verifier_signer_calls.log', 'a', encoding='utf-8') as log:
    log.write(payload.rstrip('\\r\\n') + '\\n')
result = subprocess.run(['/app/data_signer.verifier_real'], input=payload, text=True, capture_output=True, check=True)
sys.stdout.write(result.stdout)
""")
    signer.chmod(0o755)

    # Random IDs, values, and metadata prevent a fixed response table from passing.
    sid1 = secrets.randbelow(700000) + 200000
    sid2 = sid1 + secrets.randbelow(999) + 1
    token = secrets.token_hex(5)
    loc1 = f"Dock_{token}"
    loc2 = f"Cellar_{token}"
    t1 = float(secrets.randbelow(70) + 10) + 0.1
    t2 = t1 + 0.6
    t3 = t2 + 1.3
    h1 = float(secrets.randbelow(30) + 40) + 0.2
    h2 = h1 + 0.7
    h3 = h2 + 1.1
    u1 = float(secrets.randbelow(50) + 5) + 0.3
    u2 = u1 + 0.8
    v1 = float(secrets.randbelow(25) + 50) + 0.4
    v2 = v1 + 0.9

    raw = Path("/home/user/raw_data")
    (raw / "sensor_1.csv").write_text(
        "timestamp,sensor_id,temperature,humidity,remarks\n"
        f'2024-02-03T12:00:00Z,{sid1},{t1:.1f},{h1:.1f},"Started"\n'
        f'2024-02-03T12:05:00Z,{sid1},{t2:.1f},{h2:.1f},"Embedded line one\nEmbedded line two"\n'
        f'2024-02-03T12:30:00Z,{sid1},{t3:.1f},{h3:.1f},"Resumed"\n',
        encoding="utf-8"
    )
    sensor2 = (
        "timestamp,sensor_id,temperature,humidity,remarks\n"
        f'2024-02-03T12:00:00Z,{sid2},{u1:.1f},{v1:.1f},"Chilly résumé"\n'
        f'2024-02-03T12:10:00Z,{sid2},{u2:.1f},{v2:.1f},"Warming"\n'
    )
    (raw / "sensor_2.csv").write_bytes(sensor2.encode("windows-1252"))
    (raw / "sensor_metadata.csv").write_text(
        f"sensor_id,location\n{sid1},{loc1}\n{sid2},{loc2}\n", encoding="utf-8"
    )

    server_log = open("/tmp/verifier_restarted_server.log", "ab", buffering=0)
    subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                     stdout=server_log, stderr=subprocess.STDOUT, start_new_session=True)

    response1 = wait_for_api(sid1)
    response2 = requests.get(f"http://127.0.0.1:8080/api/data?sensor_id={sid2}", timeout=5)
    assert response2.status_code == 200
    data1 = response1.json()
    data2 = response2.json()

    times1 = [f"2024-02-03T12:{minute:02d}:00Z" for minute in range(0, 31, 5)]
    temps1 = [t1, t2, t2, t2, t2, None, t3]
    humids1 = [h1, h2, h2, h2, h2, None, h3]
    assert isinstance(data1, list)
    assert len(data1) == 7, "Resampling must retain the interval left null after the 3-gap fill limit"
    for i, record in enumerate(data1):
        assert record.get("timestamp") == times1[i]
        assert str(record.get("sensor_id")) == str(sid1)
        assert record.get("location") == loc1
        if temps1[i] is None:
            assert is_null(record.get("temperature"))
            assert is_null(record.get("humidity"))
            assert is_null(record.get("signature"))
        else:
            assert float(record.get("temperature")) == temps1[i]
            assert float(record.get("humidity")) == humids1[i]
            assert record.get("signature") == compute_signature(times1[i], sid1, temps1[i])

    times2 = ["2024-02-03T12:00:00Z", "2024-02-03T12:05:00Z", "2024-02-03T12:10:00Z"]
    temps2 = [u1, u1, u2]
    humids2 = [v1, v1, v2]
    assert isinstance(data2, list)
    assert len(data2) == 3
    for i, record in enumerate(data2):
        assert record.get("timestamp") == times2[i]
        assert str(record.get("sensor_id")) == str(sid2)
        assert record.get("location") == loc2
        assert float(record.get("temperature")) == temps2[i]
        assert float(record.get("humidity")) == humids2[i]
        assert record.get("signature") == compute_signature(times2[i], sid2, temps2[i])

    expected_payloads = {
        f"{timestamp}|{sid1}|{temperature}"
        for timestamp, temperature in zip(times1, temps1) if temperature is not None
    }
    expected_payloads.update(
        f"{timestamp}|{sid2}|{temperature}"
        for timestamp, temperature in zip(times2, temps2)
    )
    logged_payloads = set(call_log.read_text(encoding="utf-8").splitlines())
    assert expected_payloads <= logged_payloads, "The application did not invoke /app/data_signer for every valid row"
    assert not any(line.startswith(f"{times1[5]}|{sid1}|") for line in logged_payloads), \
        "The application invoked the signer for a null row"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
