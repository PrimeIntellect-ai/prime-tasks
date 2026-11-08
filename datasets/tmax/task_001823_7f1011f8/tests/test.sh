#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import statistics
import subprocess
import time

import pytest
import requests

APP_DIR = "/home/user/app"
BASE_URL = "http://localhost:5000"


def matching_pids(fragment):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as fh:
                cmdline = fh.read().replace(b"\0", b" ").decode(errors="ignore")
            if fragment in cmdline:
                found.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def stop_matching(fragment):
    pids = matching_pids(fragment)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_for_http(timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(f"{BASE_URL}/metrics", timeout=0.5)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Aggregator did not become available on port 5000: {last_error}")


def redis_command(port, *args):
    return subprocess.run(
        ["redis-cli", "-p", str(port), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    )


def live_redis_ports():
    ports = []
    for port in (6379, 6380):
        result = redis_command(port, "PING")
        if result.returncode == 0 and result.stdout.strip() == "PONG":
            ports.append(port)
    return ports


@pytest.fixture(scope="module")
def running_services():
    stop_matching("/home/user/app/sensor.py")
    stop_matching("/home/user/app/aggregator.py")

    start_proc = subprocess.Popen(
        ["bash", "start.sh"],
        cwd=APP_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    replacement_aggregator = None

    try:
        wait_for_http()

        # The sensor proves start.sh can launch the composition, but its random
        # traffic must not contaminate the verifier's independently derived data.
        stop_matching("/home/user/app/sensor.py")

        ports = live_redis_ports()
        assert ports, "start.sh did not make Redis available"
        for port in ports:
            result = redis_command(port, "FLUSHALL")
            assert result.returncode == 0 and result.stdout.strip() == "OK"

        yield {
            "start_proc": start_proc,
            "redis_ports": ports,
            "set_replacement": lambda proc: globals().update(_replacement_proc=proc),
        }
    finally:
        stop_matching("/home/user/app/sensor.py")
        stop_matching("/home/user/app/aggregator.py")
        if start_proc.poll() is None:
            start_proc.terminate()
            try:
                start_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                start_proc.kill()
                start_proc.wait()


def get_variance(session):
    try:
        response = session.get(f"{BASE_URL}/metrics", timeout=2)
        assert response.status_code == 200, "Failed to get metrics from Aggregator"
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to Aggregator to fetch metrics.")

    data = response.json()
    assert "variance" in data, "Response JSON is missing the 'variance' key."
    return float(data["variance"])


def assert_variance(session, values):
    reference_variance = float(statistics.variance(values))
    agent_variance = get_variance(session)
    mse = (agent_variance - reference_variance) ** 2
    threshold = 1e-10
    assert mse <= threshold, (
        "Variance calculation is not numerically stable.\n"
        f"MSE {mse} exceeds threshold {threshold}.\n"
        f"Agent variance: {agent_variance}\n"
        f"Reference variance: {reference_variance}"
    )


def test_aggregator_variance_and_parsing(running_services):
    """Exercise parsing, Redis-backed persistence, and stable variance on 100,000 held-out values."""
    total = 100000
    rng = random.SystemRandom()
    base_value = rng.randrange(900_000_000, 1_100_000_000)
    values = [base_value + rng.randrange(-500, 501) for _ in range(total)]

    session = requests.Session()
    headers = {"Content-Type": "application/json"}
    checkpoints = {137, 1009, 10000, 50000, total}
    restart_at = 1009

    for i, value in enumerate(values):
        # Inject the edge-case formats captured in the pcap and checked by the
        # original verifier, but with unpredictable values.
        if i % 3 == 0:
            payload = f'{{"value": {value},}}'
        elif i % 3 == 1:
            payload = f'{{"value": "{value}e0"}}'
        else:
            payload = f'{{"value": {value}}}'

        try:
            response = session.post(
                f"{BASE_URL}/record", data=payload, headers=headers, timeout=2
            )
            assert response.status_code == 200, (
                f"Aggregator rejected payload: {payload}. Status: {response.status_code}"
            )
        except requests.exceptions.ConnectionError:
            pytest.fail(
                "Failed to connect to Aggregator on port 5000. Is it running and connected to Redis?"
            )

        count = i + 1
        if count in checkpoints:
            assert_variance(session, values[:count])

        if count == restart_at:
            before_restart = get_variance(session)

            populated = False
            for port in running_services["redis_ports"]:
                result = redis_command(port, "DBSIZE")
                if result.returncode == 0 and int(result.stdout.strip() or "0") > 0:
                    populated = True
            assert populated, "Aggregator did not store its running state in Redis"

            # Restart only the aggregator. Its variance must survive because the
            # running calculation is required to be stored in Redis.
            stop_matching("/home/user/app/aggregator.py")
            replacement = subprocess.Popen(
                ["python3", "/home/user/app/aggregator.py"],
                cwd=APP_DIR,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            wait_for_http()
            after_restart = get_variance(session)
            assert abs(after_restart - before_restart) <= 1e-12, (
                "Aggregator lost its running variance state after restart"
            )

    # Retain the original final high-precision MSE assertion, now over the full
    # unpredictable held-out dataset of 100,000 requests.
    assert_variance(session, values)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
