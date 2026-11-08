#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import struct
import subprocess
import tempfile
import time
import urllib.request
import json

ORACLE_PATH = "/opt/oracle/worker_oracle"
AGENT_PATH = "/home/user/workspace/worker_fixed"
SOURCE_PATH = "/home/user/workspace/worker.cpp"
GATEWAY_PATH = "/home/user/workspace/gateway.py"


def generate_fuzz_input(num_records):
    """Generate a binary payload of 9-byte records."""
    data = bytearray()
    mean_val = random.choice([1e6, 5e6, 1e7])
    for _ in range(num_records):
        sensor_id = random.randint(1, 5)
        timestamp = random.randint(1600000000, 1700000000)
        value = mean_val + random.uniform(-0.5, 0.5)
        data.extend(struct.pack('<BIf', sensor_id, timestamp, value))
    return bytes(data)


def compare_with_oracle(program, input_data, label):
    with tempfile.NamedTemporaryFile(delete=False) as f_in, \
         tempfile.NamedTemporaryFile(delete=False) as f_out_oracle, \
         tempfile.NamedTemporaryFile(delete=False) as f_out_agent:
        f_in.write(input_data)
        f_in.flush()
        in_name = f_in.name
        out_oracle_name = f_out_oracle.name
        out_agent_name = f_out_agent.name

    try:
        subprocess.run(
            [ORACLE_PATH, "--file-mode", in_name, out_oracle_name],
            check=True,
            capture_output=True,
            timeout=10,
        )
        result = subprocess.run(
            [program, "--file-mode", in_name, out_agent_name],
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{label} failed in file mode: {result.stderr.decode(errors='replace')}"
        )
        with open(out_oracle_name, "rb") as f:
            oracle_out = f.read()
        with open(out_agent_name, "rb") as f:
            agent_out = f.read()
        assert oracle_out == agent_out, (
            f"{label} does not match the oracle.\n"
            f"Oracle output: {oracle_out.hex()}\n"
            f"Agent output: {agent_out.hex()}"
        )
    finally:
        for path in (in_name, out_oracle_name, out_agent_name):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_worker_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "worker_fixed must be a compiled executable"
    with open(AGENT_PATH, "rb") as a, open(ORACLE_PATH, "rb") as o:
        assert a.read() != o.read(), "worker_fixed must not be a byte-identical copy of the oracle"

    random.seed(42)
    for i in range(100):
        num_records = random.randint(10, 100)
        compare_with_oracle(
            AGENT_PATH,
            generate_fuzz_input(num_records),
            f"Agent program on fuzz iteration {i} (num_records={num_records})",
        )


def test_corrected_source_builds_and_matches_oracle():
    assert os.path.isfile(SOURCE_PATH), f"Corrected source not found at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", errors="replace") as f:
        source = f.read()
    assert "/opt/oracle" not in source and "worker_oracle" not in source, (
        "worker.cpp must implement the worker rather than invoke the reference binary"
    )

    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_worker_")
    os.close(fd)
    os.remove(rebuilt)
    try:
        build = subprocess.run(
            ["g++", "-O3", "-std=c++17", SOURCE_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"worker.cpp does not compile:\n{build.stderr}"
        random.seed(314159)
        for i in range(25):
            compare_with_oracle(
                rebuilt,
                generate_fuzz_input(random.randint(10, 100)),
                f"Worker rebuilt from worker.cpp on iteration {i}",
            )
    finally:
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass


def redis(*args, check=True):
    return subprocess.run(
        ["redis-cli", "--raw", *args],
        check=check,
        capture_output=True,
        text=True,
    )


def wait_for_gateway(proc):
    deadline = time.time() + 10
    while time.time() < deadline:
        assert proc.poll() is None, "Gateway exited before accepting requests"
        try:
            urllib.request.urlopen("http://127.0.0.1:5000/", timeout=0.5)
        except urllib.error.HTTPError:
            return
        except Exception:
            time.sleep(0.1)
        else:
            return
    raise AssertionError("Gateway did not start listening on port 5000")


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def expected_sample_variance(values):
    count = 0
    mean = 0.0
    m2 = 0.0
    for value in values:
        count += 1
        delta = value - mean
        mean += delta / count
        delta2 = value - mean
        m2 += delta * delta2
    return m2 / (count - 1)


def test_end_to_end_pipeline():
    if subprocess.run(["redis-cli", "PING"], capture_output=True).returncode != 0:
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
        time.sleep(0.5)

    # Build the daemon we exercise directly from the corrected source, so an
    # unrelated wrapper at worker_fixed cannot satisfy the end-to-end check.
    fd, rebuilt = tempfile.mkstemp(prefix="daemon_worker_")
    os.close(fd)
    os.remove(rebuilt)
    build = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_PATH, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"worker.cpp does not compile:\n{build.stderr}"

    redis("DEL", "processed_variances", "raw_telemetry", "telemetry_queue")
    gateway_proc = subprocess.Popen(
        ["python3", GATEWAY_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    worker_proc = None
    try:
        wait_for_gateway(gateway_proc)
        worker_proc = subprocess.Popen(
            [rebuilt, "--daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        time.sleep(0.25)
        assert worker_proc.poll() is None, "Worker exited instead of running in daemon mode"

        rng = secrets.SystemRandom()
        sensor_id = rng.randint(20, 240)
        base_val = float(rng.randint(900000, 4000000))
        submitted = [base_val + rng.uniform(-12.0, 12.0) for _ in range(9)]
        decoded = [struct.unpack('<f', struct.pack('<f', value))[0] for value in submitted]
        expected = expected_sample_variance(decoded)

        for i, value in enumerate(submitted):
            req_data = json.dumps({
                "sensor_id": sensor_id,
                "timestamp": 1620000000 + i,
                "value": value,
            }).encode("utf-8")
            req = urllib.request.Request(
                "http://127.0.0.1:5000/ingest",
                data=req_data,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=3) as response:
                assert response.status == 200

        deadline = time.time() + 10
        outputs = []
        while time.time() < deadline:
            outputs = redis("LRANGE", "processed_variances", "0", "-1").stdout.splitlines()
            if redis("LLEN", "raw_telemetry").stdout.strip() == "0" and outputs:
                numeric = []
                for output in outputs:
                    for token in re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", output):
                        try:
                            numeric.append(float(token))
                        except ValueError:
                            pass
                if any(
                    math.isfinite(value)
                    and math.isclose(value, expected, rel_tol=1e-5, abs_tol=1e-4)
                    for value in numeric
                ):
                    break
            time.sleep(0.1)

        # Preserve the original communication assertion and additionally check
        # that the gateway records were consumed and the variance is correct.
        assert outputs, "No output found in Redis list 'processed_variances'. Pipeline communication may still be broken."
        assert redis("LLEN", "raw_telemetry").stdout.strip() == "0", (
            "The worker did not consume the records placed on the gateway's Redis list"
        )

        numeric = []
        for output in outputs:
            for token in re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", output):
                try:
                    numeric.append(float(token))
                except ValueError:
                    pass
        assert any(
            math.isfinite(value)
            and math.isclose(value, expected, rel_tol=1e-5, abs_tol=1e-4)
            for value in numeric
        ), f"No processed output contained the correct sample variance {expected!r}; outputs were {outputs!r}"
    finally:
        stop_process(gateway_proc)
        if worker_proc is not None:
            stop_process(worker_proc)
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
