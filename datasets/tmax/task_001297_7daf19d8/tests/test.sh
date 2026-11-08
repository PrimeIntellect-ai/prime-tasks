#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove any services left running by the agent; the verifier supplies its own
# independent Redis instance and sensor stream.
pkill -9 -x ingest 2>/dev/null || true
pkill -9 -x redis-server 2>/dev/null || true
pkill -9 -f '[s]ensor_simulator.py' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import signal
import socket
import struct
import subprocess
import threading
import time

import pytest
import redis

APP_DIR = "/home/user/app"
INGEST_BIN = os.path.join(APP_DIR, "ingest")
BENCHMARK_SCRIPT = os.path.join(APP_DIR, "benchmark.py")
PASSWORD = "s3cr3t_w3ath3r_p4ss"
RECORD_COUNT = 7000
TARGET_THROUGHPUT = 2000.0


def test_ingest_binary_exists():
    """Ensure that the ingestion artifact is a compiled executable."""
    assert os.path.isfile(INGEST_BIN), (
        f"Compiled binary not found at {INGEST_BIN}. "
        "Make sure you fixed the compiler/linker errors and successfully built the project."
    )
    assert os.access(INGEST_BIN, os.X_OK), f"File at {INGEST_BIN} is not executable."
    with open(INGEST_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "ingest must be a compiled ELF binary, not a script."


def test_benchmark_script_exists():
    # Preserve the original project-state assertion, but do not trust this mutable
    # script to report the score.
    assert os.path.isfile(BENCHMARK_SCRIPT), f"Benchmark script missing at {BENCHMARK_SCRIPT}"


def test_throughput_metric():
    redis_proc = None
    ingest_proc = None
    stop_server = threading.Event()
    server_ready = threading.Event()
    connection_closed = threading.Event()
    server_errors = []

    now = int(time.time())
    rng = random.SystemRandom()
    expected = []
    wire_parts = []
    for i in range(RECORD_COUNT):
        timestamp = now + rng.randint(-3, 3)
        sensor_id = rng.randint(1, 100)
        # Generate an arbitrary float32 in the documented simulator range.
        requested_temp = rng.uniform(10.0, 30.0)
        packet = struct.pack(">IIf", timestamp, sensor_id, requested_temp)
        decoded_temp = struct.unpack(">IIf", packet)[2]
        expected.append((timestamp, sensor_id, decoded_temp))
        wire_parts.append(packet)
    wire = b"".join(wire_parts)

    def sensor_server():
        listener = None
        conn = None
        try:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 8081))
            listener.listen(1)
            listener.settimeout(8)
            server_ready.set()
            conn, _ = listener.accept()

            # Deliberately split packet boundaries and then coalesce thousands of
            # packets, as a TCP stream is allowed to do.
            conn.sendall(wire[:1])
            time.sleep(0.03)
            offset = 1
            for size in (2, 5, 3, 11, 7, 1, 17, 4, 9, 23):
                conn.sendall(wire[offset:offset + size])
                offset += size
            conn.sendall(wire[offset:])

            # Keep the stream open so ingest must continue running, and observe
            # whether SIGINT actually closes its connection.
            conn.settimeout(0.1)
            while not stop_server.is_set():
                try:
                    data = conn.recv(1, socket.MSG_PEEK)
                    if data == b"":
                        connection_closed.set()
                        break
                except socket.timeout:
                    continue
                except (ConnectionResetError, OSError):
                    connection_closed.set()
                    break
        except Exception as exc:
            server_errors.append(repr(exc))
            server_ready.set()
        finally:
            if conn is not None:
                try:
                    conn.close()
                except OSError:
                    pass
            if listener is not None:
                try:
                    listener.close()
                except OSError:
                    pass

    thread = threading.Thread(target=sensor_server, daemon=True)

    try:
        redis_proc = subprocess.Popen(
            [
                "redis-server", "--port", "6379", "--bind", "127.0.0.1",
                "--requirepass", PASSWORD, "--save", "", "--appendonly", "no",
                "--daemonize", "no"
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        client = redis.Redis(host="127.0.0.1", port=6379, password=PASSWORD)
        deadline = time.monotonic() + 5
        while True:
            try:
                assert client.ping()
                break
            except redis.RedisError:
                if redis_proc.poll() is not None or time.monotonic() >= deadline:
                    pytest.fail("Verifier could not start its isolated Redis server.")
                time.sleep(0.05)
        client.delete("sensor_data")

        thread.start()
        assert server_ready.wait(2), "Verifier sensor server did not start."
        assert not server_errors, f"Verifier sensor server failed: {server_errors}"

        env = os.environ.copy()
        # A correct Unix timestamp implementation is independent of local TZ.
        env["TZ"] = "Pacific/Honolulu"
        started = time.monotonic()
        ingest_proc = subprocess.Popen(
            [INGEST_BIN], cwd=APP_DIR, env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

        throughput_deadline = started + (RECORD_COUNT / TARGET_THROUGHPUT)
        reached = False
        count = 0
        while time.monotonic() <= throughput_deadline:
            count = client.llen("sensor_data")
            if count >= RECORD_COUNT:
                reached = True
                break
            if ingest_proc.poll() is not None:
                break
            time.sleep(0.01)

        elapsed = time.monotonic() - started
        assert reached, (
            f"Only {count} of {RECORD_COUNT} packets were stored within "
            f"{RECORD_COUNT / TARGET_THROUGHPUT:.2f} seconds."
        )
        throughput = RECORD_COUNT / elapsed
        assert throughput >= TARGET_THROUGHPUT, (
            f"Throughput is too low. Measured: {throughput:.2f} records/sec. "
            f"Target: >= {TARGET_THROUGHPUT:.2f} records/sec."
        )

        # No packets are sent after the fixed corpus, so extra records indicate
        # fabricated or duplicated output.
        time.sleep(0.15)
        assert client.llen("sensor_data") == RECORD_COUNT, (
            "The number of stored records does not match the packets streamed."
        )

        raw_records = client.lrange("sensor_data", 0, -1)
        assert len(raw_records) == RECORD_COUNT
        for index, (raw, wanted) in enumerate(zip(raw_records, expected)):
            try:
                item = json.loads(raw)
            except Exception as exc:
                pytest.fail(f"Record {index} is not valid JSON: {exc}; value={raw!r}")
            assert isinstance(item, dict), f"Record {index} is not a JSON object."
            assert item.get("timestamp") == wanted[0], (
                f"Record {index} has the wrong timestamp."
            )
            assert item.get("sensor_id") == wanted[1], (
                f"Record {index} has the wrong sensor_id."
            )
            temp = item.get("temp")
            assert isinstance(temp, (int, float)) and math.isfinite(float(temp)), (
                f"Record {index} has an invalid temperature."
            )
            assert abs(float(temp) - wanted[2]) <= 1e-4, (
                f"Record {index} has the wrong temperature."
            )

        # The service must not exit merely because it has processed the available
        # corpus; it must remain alive until interrupted.
        assert ingest_proc.poll() is None, "ingest exited before receiving SIGINT."
        ingest_proc.send_signal(signal.SIGINT)
        try:
            ingest_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail("ingest did not terminate promptly after SIGINT.")
        assert connection_closed.wait(1), (
            "ingest left its sensor connection open after SIGINT."
        )
        assert not server_errors, f"Sensor server error: {server_errors}"
    finally:
        stop_server.set()
        if ingest_proc is not None and ingest_proc.poll() is None:
            ingest_proc.kill()
            try:
                ingest_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        thread.join(timeout=1)
        if redis_proc is not None and redis_proc.poll() is None:
            redis_proc.terminate()
            try:
                redis_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                redis_proc.kill()
                redis_proc.wait(timeout=2)
TEST_EOF

if timeout 30s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
