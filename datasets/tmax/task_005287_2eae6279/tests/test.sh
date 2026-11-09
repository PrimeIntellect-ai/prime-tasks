#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import stat
import subprocess
import threading
import time

import pytest
import redis

AGENT_PROCESSOR = "/home/user/processor"
AGENT_SOURCE = "/home/user/processor.cpp"


def ensure_redis():
    client = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    try:
        client.ping()
    except Exception:
        subprocess.run(
            ["redis-server", "--port", "6379", "--daemonize", "yes"],
            check=True,
            capture_output=True,
            text=True,
        )
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                if client.ping():
                    break
            except Exception:
                time.sleep(0.1)
        else:
            pytest.fail("Redis did not start on 127.0.0.1:6379")
    return client


def impute(values):
    result = [None if value is None else float(value) for value in values]
    valid = [i for i, value in enumerate(result) if value is not None]
    assert valid

    first = valid[0]
    for i in range(first):
        result[i] = result[first]

    for left, right in zip(valid, valid[1:]):
        start = result[left]
        end = result[right]
        span = right - left
        for i in range(left + 1, right):
            result[i] = start + (end - start) * ((i - left) / span)

    last = valid[-1]
    for i in range(last + 1, len(result)):
        result[i] = result[last]
    return result


def expected_distance(readings, target):
    filled = impute(readings)
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(filled, target)))


def assert_output_line(line, sensor_id, expected):
    try:
        parsed = json.loads(line)
    except Exception as exc:
        pytest.fail(f"Invalid JSON output for {sensor_id}: {line!r}: {exc}")

    assert isinstance(parsed, dict), f"Output is not a JSON object: {line!r}"
    assert set(parsed) == {"sensor_id", "distance"}, f"Unexpected output fields: {line!r}"
    assert parsed["sensor_id"] == sensor_id, f"Wrong sensor_id in output: {line!r}"

    match = re.search(r'"distance"\s*:\s*(-?\d+\.\d{4})(?=\s*[,}])', line)
    assert match, f"Distance is not formatted with exactly four decimal places: {line!r}"
    expected_text = f"{expected:.4f}"
    assert match.group(1) == expected_text, (
        f"Wrong distance for {sensor_id}: expected {expected_text}, got {match.group(1)}"
    )


def test_agent_processor_exists_and_is_compiled():
    assert os.path.isfile(AGENT_SOURCE), f"Agent source not found at {AGENT_SOURCE}"
    assert os.path.getsize(AGENT_SOURCE) > 0, f"Agent source at {AGENT_SOURCE} is empty"
    assert os.path.isfile(AGENT_PROCESSOR), f"Agent processor not found at {AGENT_PROCESSOR}"
    assert os.access(AGENT_PROCESSOR, os.X_OK), f"Agent processor is not executable"
    with open(AGENT_PROCESSOR, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "Processor is not a compiled ELF executable"


def test_processor_fuzzed_against_derived_answers():
    client = ensure_redis()

    # Preserve the original verifier's initialization step, then install isolated
    # metadata whose answers are derived by this test.
    if os.path.isfile("/app/init_redis.py"):
        subprocess.run(["python3", "/app/init_redis.py"], capture_output=True, text=True)
    client.flushdb()

    rng = random.SystemRandom()
    cases = [
        ([None, 2.0], [2.0, 2.0]),
        ([1.0, None, 3.0, None, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0]),
        ([1.0, None, None, 7.0], [1.0, 3.0, 5.0, 7.0]),
        ([4.5, None, None], [4.5, 4.5, 4.5]),
    ]

    for _ in range(1000):
        length = rng.randint(2, 24)
        readings = []
        for _ in range(length):
            readings.append(None if rng.random() < 0.35 else round(rng.uniform(-200, 200), 3))
        if all(value is None for value in readings):
            readings[rng.randrange(length)] = round(rng.uniform(-200, 200), 3)
        target = [round(rng.uniform(-200, 200), 3) for _ in range(length)]
        cases.append((readings, target))

    input_lines = []
    expected = []
    pipe = client.pipeline(transaction=False)
    nonce = os.urandom(8).hex()
    for index, (readings, target) in enumerate(cases):
        sensor_id = f"VERIFY_{nonce}_{index}"
        pipe.set(f"sensor:{sensor_id}", json.dumps(target, separators=(",", ":")))
        input_lines.append(json.dumps({"sensor_id": sensor_id, "readings": readings}, separators=(",", ":")))
        expected.append((sensor_id, expected_distance(readings, target)))
    pipe.execute()

    result = subprocess.run(
        [AGENT_PROCESSOR],
        input="\n".join(input_lines) + "\n",
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Processor failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    output_lines = result.stdout.splitlines()
    assert len(output_lines) == len(expected), (
        f"Expected {len(expected)} output lines, got {len(output_lines)}"
    )
    for line, (sensor_id, distance) in zip(output_lines, expected):
        assert_output_line(line, sensor_id, distance)


def test_named_pipe_end_to_end_flow():
    client = ensure_redis()
    for path in ("/tmp/input.pipe", "/tmp/output.pipe"):
        assert os.path.exists(path), f"Required named pipe is missing: {path}"
        assert stat.S_ISFIFO(os.stat(path).st_mode), f"Path is not a named pipe: {path}"

    # Remove any stale processor instances so they cannot consume this test input.
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == AGENT_PROCESSOR:
                os.kill(int(entry), 15)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.2)

    for path in ("/tmp/input.pipe", "/tmp/output.pipe"):
        os.unlink(path)
        os.mkfifo(path, 0o666)

    sensor_id = f"PIPE_{os.urandom(8).hex()}"
    readings = [None, 2.0, None, 8.0, None]
    target = [2.0, 2.0, 5.0, 8.0, 8.0]
    client.set(f"sensor:{sensor_id}", json.dumps(target))
    expected = expected_distance(readings, target)

    processor = subprocess.Popen(
        ["bash", "-c", "exec /home/user/processor < /tmp/input.pipe > /tmp/output.pipe"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    received = []
    errors = []

    def read_sink():
        try:
            with open("/tmp/output.pipe", "r") as sink:
                received.append(sink.readline().rstrip("\n"))
        except Exception as exc:
            errors.append(exc)

    sink_thread = threading.Thread(target=read_sink, daemon=True)
    sink_thread.start()
    try:
        with open("/tmp/input.pipe", "w") as source:
            source.write(json.dumps({"sensor_id": sensor_id, "readings": readings}) + "\n")
            source.flush()
        sink_thread.join(10)
        assert not sink_thread.is_alive(), "Timed out reading processor output from /tmp/output.pipe"
        assert not errors, f"Sink failed: {errors}"
        assert len(received) == 1 and received[0], "No pipeline output was produced"
        assert_output_line(received[0], sensor_id, expected)
        returncode = processor.wait(timeout=10)
        stderr = processor.stderr.read()
        assert returncode == 0, f"FIFO-connected processor failed: {stderr}"
    finally:
        if processor.poll() is None:
            processor.kill()
            processor.wait()


def test_e2e_sh_success():
    if os.path.isfile("/app/test_e2e.sh"):
        result = subprocess.run(["bash", "/app/test_e2e.sh"], capture_output=True, text=True)
        assert result.returncode == 0, (
            f"End-to-end test script failed:\n{result.stdout}\n{result.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
