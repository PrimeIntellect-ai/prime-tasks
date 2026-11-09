#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import signal
import subprocess
import time

import pytest
import requests

SERVICE_URL = "http://127.0.0.1:8080/api/v1/anomalies"
AUTH_HEADER = {"Authorization": "Bearer l10n-metrics-secret"}


def get_listener_pids(port=8080):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            if state == "0A" and local_address.rsplit(":", 1)[1].upper() == wanted_port:
                inodes.add(fields[9])

    pids = set()
    for proc in pathlib.Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def process_launch_info(pid):
    proc = pathlib.Path(f"/proc/{pid}")
    raw_cmd = (proc / "cmdline").read_bytes().split(b"\0")
    argv = [item.decode("utf-8", "surrogateescape") for item in raw_cmd if item]
    cwd = os.readlink(proc / "cwd")
    env = {}
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return argv, cwd, env


def wait_for_authorized_response(timeout=30):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(SERVICE_URL, headers=AUTH_HEADER, timeout=2)
            if response.status_code == 200:
                return response
            last_error = RuntimeError(f"status {response.status_code}: {response.text}")
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.5)
    pytest.fail(f"Service did not become ready after restart: {last_error}")


def assert_payload(response, expected):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON.")

    assert "anomalies" in data, "Response JSON missing 'anomalies' key."
    anomalies = data["anomalies"]
    assert isinstance(anomalies, list), "'anomalies' should be a list."
    assert len(anomalies) == len(expected), (
        f"Expected {len(expected)} anomalies, got {len(anomalies)}: {anomalies}"
    )

    for i, wanted in enumerate(expected):
        actual = anomalies[i]
        assert actual.get("timestamp") == wanted["timestamp"], (
            f"Mismatch in timestamp at index {i}. Expected {wanted['timestamp']}, "
            f"got {actual.get('timestamp')}"
        )
        assert actual.get("server_name") == wanted["server_name"], (
            f"Mismatch in server_name at index {i}. Expected {wanted['server_name']}, "
            f"got {actual.get('server_name')}"
        )
        assert abs(float(actual.get("metric_value", 0)) - wanted["metric_value"]) < 1e-5, (
            f"Mismatch in metric_value at index {i}. Expected {wanted['metric_value']}, "
            f"got {actual.get('metric_value')}"
        )


def test_service_running():
    try:
        response = requests.get(SERVICE_URL, headers=AUTH_HEADER, timeout=5)
        assert response.status_code in [200, 401, 403, 404, 500], (
            "Service responded with an unexpected status code."
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 0.0.0.0:8080 or is unreachable.")


def test_unauthorized_access():
    response = requests.get(SERVICE_URL, timeout=5)
    assert response.status_code in [401, 403], (
        f"Expected 401 or 403 for unauthorized access, got {response.status_code}"
    )


def test_anomalies_endpoint_response():
    response = requests.get(SERVICE_URL, headers=AUTH_HEADER, timeout=5)
    expected_anomalies = [
        {"timestamp": 1714999860, "server_name": "server_B_metric", "metric_value": 91.5},
        {"timestamp": 1715000000, "server_name": "server_regional_1", "metric_value": 94.5},
        {"timestamp": 1715000060, "server_name": "server_regional_1", "metric_value": 98.2},
    ]
    assert_payload(response, expected_anomalies)


def test_pipeline_reprocesses_changed_csv_and_audio():
    listener_pids = get_listener_pids()
    assert listener_pids, "No process is listening on port 8080."

    candidates = []
    for pid in listener_pids:
        try:
            argv, cwd, env = process_launch_info(pid)
        except OSError:
            continue
        joined = " ".join(argv).lower()
        score = sum(word in joined for word in ("python", "uvicorn", "flask", "gunicorn", "hypercorn"))
        candidates.append((score, pid, argv, cwd, env))

    assert candidates, "Could not inspect the process serving port 8080."
    candidates.sort(reverse=True, key=lambda item: item[0])
    score, _, argv, cwd, env = candidates[0]
    assert score > 0, "The listener is not a Python-based HTTP service."
    assert argv, "The service process has no restartable command line."

    # Generate verification inputs at test time so a constant response cannot pass.
    base = 1800000000 + secrets.randbelow(50000000) * 10
    audio_value_1 = 93.0 + secrets.randbelow(10) / 10.0
    audio_value_2 = 97.0 + secrets.randbelow(10) / 10.0

    csv_text = (
        "timestamp,server_A_metric,server_B_metric,server_C_metric\n"
        f"{base},12.0,90.0,95.1\n"
        f"{base + 60},90.1,40.0,90.0\n"
        f"{base + 120},89.0,91.2,20.0\n"
    )
    pathlib.Path("/app/system_metrics.csv").write_text(csv_text)

    audio_path = pathlib.Path("/app/telemetry_alert.wav")
    try:
        audio_path.unlink()
    except FileNotFoundError:
        pass
    spoken = (
        f"Timestamp {base + 180}, value {audio_value_1:.1f}. "
        f"Timestamp {base + 240}, value {audio_value_2:.1f}."
    )
    subprocess.run(["espeak", "-w", str(audio_path), spoken], check=True, timeout=20)
    assert audio_path.is_file() and audio_path.stat().st_size > 44

    # Restart the submitted service so its ETL startup path must consume the new artifacts.
    for pid in listener_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        remaining = get_listener_pids()
        if not remaining:
            break
        for pid in remaining:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.2)
    assert not get_listener_pids(), "The original service could not be stopped for pipeline retesting."

    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    response = wait_for_authorized_response()

    expected = [
        {"timestamp": base, "server_name": "server_C_metric", "metric_value": 95.1},
        {"timestamp": base + 60, "server_name": "server_A_metric", "metric_value": 90.1},
        {"timestamp": base + 120, "server_name": "server_B_metric", "metric_value": 91.2},
        {"timestamp": base + 180, "server_name": "server_regional_1", "metric_value": audio_value_1},
        {"timestamp": base + 240, "server_name": "server_regional_1", "metric_value": audio_value_2},
    ]
    assert_payload(response, expected)

    unauthorized = requests.get(SERVICE_URL, timeout=5)
    assert unauthorized.status_code in [401, 403], (
        f"Expected 401 or 403 after restart, got {unauthorized.status_code}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
