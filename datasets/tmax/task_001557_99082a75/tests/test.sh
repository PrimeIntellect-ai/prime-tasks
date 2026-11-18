#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import socket
import subprocess
import sys
import time
import urllib.request

import pytest
import redis

CONFIG_PATH = "/app/worker/config.json"
OUTPUT_PATH = "/app/worker/output/totals.csv"
AGGREGATOR_PATH = "/app/worker/aggregator.py"
EVAL_PATH = "/app/tests/evaluate_mse.py"


def read_total(path=OUTPUT_PATH):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["total"], "totals.csv must have a single 'total' column"
    assert len(rows) == 2 and len(rows[1]) == 1, "totals.csv must contain exactly one total value"
    value = float(rows[1][0])
    assert math.isfinite(value), "The reported total must be finite"
    return value


def test_01_config_recovered():
    assert os.path.exists(CONFIG_PATH), f"config.json was not recovered to {CONFIG_PATH}."
    assert os.path.isfile(CONFIG_PATH), f"{CONFIG_PATH} is not a regular file."
    try:
        with open(CONFIG_PATH) as f:
            config = json.load(f)
    except (json.JSONDecodeError, OSError) as exc:
        pytest.fail(f"{CONFIG_PATH} is not valid JSON: {exc}")

    assert "batch_size" in config, "Recovered config.json is missing 'batch_size' key."
    assert "redis_host" in config, "Recovered config.json is missing 'redis_host' key."
    assert "redis_port" in config, "Recovered config.json is missing 'redis_port' key."
    assert config == {
        "batch_size": 100,
        "redis_host": "localhost",
        "redis_port": 6379,
    }, "Recovered config.json does not contain the configuration from the ext4 image."


def test_02_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} was not generated. The pipeline may have crashed or not run."
    )
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a regular file."
    assert os.path.getsize(OUTPUT_PATH) > 0, f"Output file {OUTPUT_PATH} is empty."
    read_total()


def test_03_startup_script_runs_real_pipeline():
    subprocess.run(["bash", "/app/stop.sh"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    try:
        os.remove(OUTPUT_PATH)
    except FileNotFoundError:
        pass

    try:
        result = subprocess.run(
            ["bash", "/app/start.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
        assert result.returncode == 0, "/app/start.sh failed"

        deadline = time.time() + 15
        redis_ready = False
        simulator_ready = False
        output_ready = False
        while time.time() < deadline:
            try:
                redis_ready = bool(redis.Redis(host="localhost", port=6379, db=0,
                                               socket_connect_timeout=0.5).ping())
            except Exception:
                redis_ready = False
            try:
                with urllib.request.urlopen("http://127.0.0.1:8000/openapi.json", timeout=0.5) as response:
                    simulator_ready = response.status == 200
            except Exception:
                simulator_ready = False
            try:
                output_ready = os.path.getsize(OUTPUT_PATH) > 0
                if output_ready:
                    read_total()
            except Exception:
                output_ready = False
            if redis_ready and simulator_ready and output_ready:
                break
            time.sleep(0.2)

        assert redis_ready, "The Redis service did not start on port 6379."
        assert simulator_ready, "The FastAPI simulator did not start on port 8000."
        assert output_ready, "The running worker did not produce a valid totals.csv."

        for pid_path, name in (("/app/simulator.pid", "simulator"),
                               ("/app/worker.pid", "worker")):
            assert os.path.exists(pid_path), f"Missing {name} PID file"
            with open(pid_path) as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
    finally:
        subprocess.run(["bash", "/app/stop.sh"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
        time.sleep(0.5)


def choose_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def precision_batches():
    rng = random.SystemRandom()
    # Derive a fresh positive, tiny-valued workload for which ordinary sequential
    # addition demonstrably differs from the correctly rounded reference.
    for _ in range(10000):
        values = sorted(
            [rng.uniform(1e-10, 1e-9) for _ in range(300)],
            reverse=True,
        )
        exact = math.fsum(values)
        if abs(sum(values) - exact) >= 8 * math.ulp(exact):
            return [values[i:i + 100] for i in range(0, 300, 100)], exact
    pytest.fail("Could not construct a precision-sensitive test workload")


def test_04_worker_boundary_and_precision_behavior():
    assert os.path.isfile(AGGREGATOR_PATH), f"Missing worker artifact {AGGREGATOR_PATH}"
    # Preserve the original assertion that the shipped evaluator exists, but do
    # not execute or trust this agent-mutable script.
    assert os.path.exists(EVAL_PATH), f"Missing evaluation script {EVAL_PATH}"

    batches, expected = precision_batches()
    port = choose_port()
    pidfile = f"/tmp/verifier-redis-{port}.pid"
    with open(CONFIG_PATH, "rb") as f:
        original_config = f.read()

    worker = None
    server_started = False
    try:
        with open(CONFIG_PATH, "w") as f:
            json.dump({"batch_size": 100, "redis_host": "127.0.0.1", "redis_port": port}, f)
        try:
            os.remove(OUTPUT_PATH)
        except FileNotFoundError:
            pass

        subprocess.run([
            "redis-server", "--bind", "127.0.0.1", "--port", str(port),
            "--save", "", "--appendonly", "no", "--daemonize", "yes",
            "--pidfile", pidfile,
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server_started = True

        client = redis.Redis(host="127.0.0.1", port=port, db=0)
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                if client.ping():
                    break
            except Exception:
                time.sleep(0.05)
        else:
            pytest.fail("Verifier Redis instance did not start")

        for batch in batches:
            client.lpush("sensor_data", json.dumps(batch))

        worker = subprocess.Popen(
            [sys.executable, AGGREGATOR_PATH],
            cwd="/app/worker",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )

        deadline = time.time() + 10
        while time.time() < deadline:
            if worker.poll() is not None:
                stderr = worker.stderr.read()
                pytest.fail(f"aggregator.py crashed while processing a valid batch:\n{stderr}")
            try:
                if client.llen("sensor_data") == 0 and os.path.getsize(OUTPUT_PATH) > 0:
                    time.sleep(0.3)
                    break
            except OSError:
                pass
            time.sleep(0.05)
        else:
            pytest.fail("aggregator.py did not process the controlled batches")

        actual = read_total()
        error = actual - expected
        mse = error * error
        threshold = 1e-10
        assert mse <= threshold, (
            f"Precision issue not fully fixed. MSE is {mse}, which is > threshold {threshold}"
        )
        assert abs(error) <= 2 * math.ulp(expected), (
            "The worker's aggregation is not high precision: "
            f"got {actual!r}, reference is {expected!r}."
        )
    finally:
        if worker is not None and worker.poll() is None:
            worker.terminate()
            try:
                worker.wait(timeout=3)
            except subprocess.TimeoutExpired:
                worker.kill()
        if server_started:
            subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", str(port), "shutdown"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        with open(CONFIG_PATH, "wb") as f:
            f.write(original_config)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
