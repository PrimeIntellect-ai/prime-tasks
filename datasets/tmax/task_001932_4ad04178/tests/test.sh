#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import random
import socket
import subprocess
import time

import pytest

APP_DIR = "/home/user/app"


def test_deploy_script_exists_and_executable():
    deploy_script = os.path.join(APP_DIR, "deploy.sh")
    assert os.path.isfile(deploy_script), f"Deployment script {deploy_script} is missing."
    assert os.access(deploy_script, os.X_OK), f"Deployment script {deploy_script} is not executable."


def test_processor_binary_compiled():
    deploy_script = os.path.join(APP_DIR, "deploy.sh")
    try:
        subprocess.run([deploy_script], check=True, capture_output=True, text=True, timeout=30)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"deploy.sh failed to run. stdout: {e.stdout}, stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.sh did not finish within 30 seconds")

    processor_bin = os.path.join(APP_DIR, "processor_bin")
    assert os.path.isfile(processor_bin), f"Compiled binary {processor_bin} is missing."
    assert os.access(processor_bin, os.X_OK), f"Compiled binary {processor_bin} is not executable."


def test_supervisord_conf_updated():
    conf_path = os.path.join(APP_DIR, "supervisord.conf")
    assert os.path.isfile(conf_path), f"Configuration file {conf_path} is missing."

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertion, then check the relevant program section.
    assert "autorestart=true" in content.lower(), "supervisord.conf does not contain autorestart=true for the processor."

    config = configparser.ConfigParser(interpolation=None)
    config.read(conf_path)
    assert config.has_section("program:aggregator"), "Missing [program:aggregator] section"
    assert config.has_section("program:processor"), "Missing [program:processor] section"
    assert config.getboolean("program:processor", "autorestart", fallback=False), \
        "autorestart=true is not set for the processor"

    aggregator_priority = config.getint("program:aggregator", "priority", fallback=999)
    processor_priority = config.getint("program:processor", "priority", fallback=999)
    assert aggregator_priority < processor_priority, \
        "Aggregator must have a lower numeric priority than processor so it starts first"


def test_throughput_metric():
    # Preserve the original end-to-end service assertion.
    time.sleep(8)

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect(("127.0.0.1", 9002))
        s.sendall(b"STATS\n")
        data = s.recv(4096).decode("utf-8").strip()
        s.close()
    except Exception as e:
        pytest.fail(f"Failed to connect to aggregator on port 9002 or retrieve stats: {e}")

    try:
        stats = json.loads(data)
    except json.JSONDecodeError:
        pytest.fail(f"Aggregator returned invalid JSON: {data}")

    assert "total_processed" in stats, "Aggregator stats missing 'total_processed'"
    assert "uptime_seconds" in stats, "Aggregator stats missing 'uptime_seconds'"

    total_processed = stats["total_processed"]
    uptime_seconds = stats["uptime_seconds"]
    assert uptime_seconds > 0, "Aggregator uptime is 0, cannot calculate throughput."

    throughput = total_processed / uptime_seconds
    threshold = 50000
    assert throughput >= threshold, \
        f"Throughput is {throughput:.2f} logs/sec, which is below the required threshold of {threshold} logs/sec."


def _stop_supervised_services():
    conf = os.path.join(APP_DIR, "supervisord.conf")
    subprocess.run(["supervisorctl", "-c", conf, "stop", "all"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=10, check=False)
    subprocess.run(["supervisorctl", "-c", conf, "shutdown"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=10, check=False)
    subprocess.run(["pkill", "-f", r"/home/user/app/(generator.py|aggregator.py|processor_bin)"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(1)


def test_processor_retry_parsing_and_independent_throughput():
    """Exercise the submitted binary against verifier-controlled inputs and metrics."""
    _stop_supervised_services()

    processor_bin = os.path.join(APP_DIR, "processor_bin")
    assert os.path.isfile(processor_bin) and os.access(processor_bin, os.X_OK)

    # The count varies per verification run and is always a full reporting batch.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    valid_count = rng.randrange(18, 25) * 10000
    invalid_count = rng.randrange(2, 5) * 10000

    records = []
    for i in range(valid_count):
        byte_count = rng.randrange(1, 65536)
        records.append(f"[{1700000000 + (i % 1000)}] 192.168.{i % 255}.1 10.0.{(i // 255) % 255}.2 TCP {byte_count}\n")
    for i in range(invalid_count):
        # Structurally valid non-TCP records must not be reported as processed TCP logs.
        records.append(f"[{1800000000 + (i % 1000)}] 172.16.{i % 255}.3 10.1.{(i // 255) % 255}.4 UDP {rng.randrange(1, 65536)}\n")
    rng.shuffle(records)
    payload = "".join(records).encode("ascii")

    generator = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    generator.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    generator.bind(("127.0.0.1", 9001))
    generator.listen(1)
    generator.settimeout(10)

    proc = subprocess.Popen([processor_bin], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    agg_listener = None
    agg_conn = None
    gen_conn = None
    try:
        # Keep port 9002 unavailable long enough to require at least five spaced
        # connection attempts (initial attempt and retries near 1, 2, 3, and 4 sec).
        time.sleep(3.25)
        assert proc.poll() is None, "processor exited instead of retrying the aggregator connection"

        agg_listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        agg_listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        agg_listener.bind(("127.0.0.1", 9002))
        agg_listener.listen(1)
        agg_listener.settimeout(8)
        aggregator_ready = time.monotonic()

        agg_conn, _ = agg_listener.accept()
        accepted_at = time.monotonic()
        # A tight retry loop would connect immediately; a one-second backoff connects
        # on the next approximately one-second retry boundary.
        assert accepted_at - aggregator_ready >= 0.30, \
            "processor retries aggregator connections too rapidly; a 1-second delay is required"
        agg_conn.settimeout(15)

        gen_conn, _ = generator.accept()
        benchmark_start = time.perf_counter()
        gen_conn.sendall(payload)
        gen_conn.shutdown(socket.SHUT_WR)
        gen_conn.close()
        gen_conn = None

        received = b""
        reached_expected_at = None
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                chunk = agg_conn.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            received += chunk
            tokens = received.split()
            if tokens and all(token.isdigit() for token in tokens):
                reported_so_far = sum(int(token) for token in tokens)
                if reported_so_far >= valid_count and reached_expected_at is None:
                    reached_expected_at = time.perf_counter()

        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail("processor did not terminate after the controlled generator closed")

        tokens = received.split()
        assert tokens, "processor sent no metrics to the controlled aggregator"
        assert all(token.isdigit() for token in tokens), \
            f"processor emitted a non-numeric metric: {received[:200]!r}"
        reported_total = sum(int(token) for token in tokens)
        assert reported_total == valid_count, \
            f"processor reported {reported_total} logs for a challenge containing exactly {valid_count} TCP logs"
        assert reached_expected_at is not None, "processor did not report all valid TCP logs"

        measured_throughput = valid_count / (reached_expected_at - benchmark_start)
        assert measured_throughput >= 50000, \
            f"Controlled throughput is {measured_throughput:.2f} logs/sec, below 50000 logs/sec"
    finally:
        for sock in (gen_conn, agg_conn, agg_listener, generator):
            if sock is not None:
                try:
                    sock.close()
                except OSError:
                    pass
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
