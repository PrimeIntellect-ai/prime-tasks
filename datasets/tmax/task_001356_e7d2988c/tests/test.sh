#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import socket
import subprocess
import time

import pytest
import redis

COLLECTOR = "/app/collector/collector.py"


def start_collector():
    proc = subprocess.Popen(
        ["python3", COLLECTOR],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1)
    assert proc.poll() is None, "collector.py exited before accepting telemetry"
    return proc


def stop_collector(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
    time.sleep(0.5)


def test_redis_dbsize_metric():
    """Execute collector.py, validate decoding, then run the fixed simulation."""
    assert os.path.isfile(COLLECTOR), f"Missing collector artifact: {COLLECTOR}"
    with open(COLLECTOR, "r", encoding="utf-8") as fh:
        ast.parse(fh.read(), filename=COLLECTOR)

    subprocess.run(["pkill", "-f", "collector.py"], capture_output=True)
    subprocess.run(["redis-cli", "shutdown", "nosave"], capture_output=True)
    subprocess.run(["pkill", "-f", "redis-server"], capture_output=True)
    time.sleep(1)

    subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
    client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            if client.ping():
                break
        except redis.RedisError:
            pass
        time.sleep(0.1)
    else:
        pytest.fail("Redis did not become ready")

    # Randomized behavioral probe: arbitrary pre-populated keys cannot satisfy this.
    probe_proc = start_collector()
    try:
        client.flushall()
        nonce = secrets.token_hex(16)
        expected_probe = {f"probe_{nonce}_{i}" for i in range(200)}
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for i, decoded in enumerate(sorted(expected_probe)):
            depth = 1 + (i % 8)
            packet = ("layer:" * depth + decoded).encode("utf-8")
            sock.sendto(packet, ("127.0.0.1", 5555))
            if i % 10 == 0:
                sock.sendto(f"layer:malformed:{nonce}_{i}".encode(), ("127.0.0.1", 5555))
            time.sleep(0.0005)
        # This specifically exercises recursion termination on an empty nested payload.
        sock.sendto(b"layer:", ("127.0.0.1", 5555))
        sock.close()

        deadline = time.time() + 6
        seen = set()
        while time.time() < deadline:
            seen = {k.decode("utf-8") for k in client.scan_iter()}
            if len(seen & expected_probe) == len(expected_probe) and "" in seen:
                break
            time.sleep(0.1)

        allowed_probe = expected_probe | {""}
        assert seen <= allowed_probe, f"Collector stored non-decoded/arbitrary probe keys: {seen - allowed_probe}"
        assert len(seen & expected_probe) >= 190, (
            f"Collector decoded only {len(seen & expected_probe)} of 200 randomized UDP probes"
        )
        assert "" in seen, "Collector did not terminate decoding of the empty nested payload"
        assert all(client.get(key) == b"1" for key in seen), "Decoded probe values were not stored as expected"
    finally:
        stop_collector(probe_proc)

    # Run the original 10,000-packet simulation with a fresh collector and database.
    sim_proc = start_collector()
    try:
        client.flushall()
        result = subprocess.run(["/app/run_malware.sh"], capture_output=True)
        assert result.returncode == 0, "Malware simulator failed to run"
        time.sleep(3)

        dbsize_result = subprocess.run(["redis-cli", "DBSIZE"], capture_output=True, text=True)
        try:
            dbsize = int(dbsize_result.stdout.strip())
        except ValueError:
            pytest.fail(f"Could not parse redis-cli DBSIZE output. Raw output: {dbsize_result.stdout}")

        # Preserve the original throughput assertion.
        assert dbsize >= 9500, (
            f"Metric threshold failed: Expected DBSIZE >= 9500, but got {dbsize}. "
            "The recursion and concurrency bugs in collector.py likely still limit throughput."
        )

        # Every stored key must be a decoded result derivable from malware_sim's packets.
        expected_sim = {""}
        expected_sim.update(
            f"payload_{i}"
            for i in range(10000)
            if i % 1000 not in (500, 999)
        )
        stored = {k.decode("utf-8") for k in client.scan_iter()}
        unexpected = stored - expected_sim
        assert not unexpected, f"Redis contains keys that are not decoded simulator payloads: {list(unexpected)[:10]}"
        assert len(stored) >= 9500, "Fewer than 9500 valid decoded simulator payload keys were stored"
        assert all(client.get(key) == b"1" for key in stored), "Simulator payload values were not stored as expected"
    finally:
        stop_collector(sim_proc)


def test_debugging_summary_exists():
    path = "/home/user/debugging_summary.txt"
    assert os.path.isfile(path), f"Debugging summary log file is missing at {path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
