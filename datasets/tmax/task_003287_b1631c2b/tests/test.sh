#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import socket
import subprocess
import threading
import time

AGENT_PATH = "/home/user/app/log_aggregator_fixed"
REDIS_PORT = "6379"


def check_executable(path):
    assert os.path.isfile(path), f"Executable not found: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_aggregator_fixed must be a compiled executable"


def redis(*args):
    return subprocess.check_output(
        ["redis-cli", "--raw", "-p", REDIS_PORT, *args],
        stderr=subprocess.STDOUT,
        timeout=3,
    ).decode().strip()


def ensure_redis():
    try:
        assert redis("PING") == "PONG"
    except Exception:
        subprocess.check_call([
            "redis-server", "--port", REDIS_PORT, "--bind", "127.0.0.1",
            "--daemonize", "yes", "--save", "", "--appendonly", "no"
        ])
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                if redis("PING") == "PONG":
                    return
            except Exception:
                time.sleep(0.05)
        raise AssertionError("Redis did not start")


def clear_redis():
    assert redis("FLUSHALL") == "OK"


def get_redis_number(key):
    value = redis("GET", key)
    if value == "":
        return None
    try:
        result = float(value)
    except ValueError:
        raise AssertionError(f"Redis key {key} is not numeric: {value!r}")
    assert math.isfinite(result), f"Redis key {key} is not finite"
    return result


def make_case(rng, count=1000):
    lines = [
        "[1700000000] EVT_EDGE 1e-10",
        "[1700000001]   EVT_EDGE   2.5E-10",
        "[1700000002] EVT_EDGE -3.75e-10",
        "[1700000003] EVT_EDGE -1.25E+6",
        "[1700000004] EVT_EDGE 9.5E+20",
        "MALFORMED LINE 7.0",
        "1700000005 EVT_BAD 4.0",
        "[1700000006] EVT_BAD not-a-number",
        "[1700000007] EVT_BAD 2.0 trailing",
        "[1700000008]",
    ]
    values = [1e-10, 2.5e-10, -3.75e-10, -1.25e6, 9.5e20]

    while len(values) < count:
        timestamp = rng.randint(1000000000, 1999999999)
        event_id = f"EVT_{rng.randint(1, 1000000)}"
        choice = rng.randrange(5)
        if choice == 0:
            text = f"{rng.uniform(-1000.0, 1000.0):.8f}"
        elif choice == 1:
            text = f"{rng.uniform(1.0, 9.9):.12g}e-{rng.randint(1, 20)}"
        elif choice == 2:
            text = f"{rng.uniform(1.0, 9.9):.12g}E+{rng.randint(1, 20)}"
        elif choice == 3:
            text = f"-{rng.uniform(1.0, 9.9):.12g}E-{rng.randint(1, 20)}"
        else:
            text = str(rng.randint(-1000000, 1000000))
        spaces = " " * rng.randint(1, 3)
        lines.append(f"[{timestamp}]{spaces}{event_id}{spaces}{text}")
        values.append(float(text))

        if rng.random() < 0.05:
            lines.append(rng.choice([
                "MALFORMED LINE",
                f"[{timestamp}] {event_id}",
                f"[{timestamp}] {event_id} xyz",
                f"[{timestamp}] {event_id} 1.0 extra",
            ]))

    rng.shuffle(lines)

    # Recompute in transmitted order, matching sequential double addition.
    valid = {}
    # Each generated valid line has a unique timestamp/event pair; edge lines are explicit.
    expected_values = []
    for line in lines:
        parts = line.split()
        if len(parts) != 3 or not parts[0].startswith("[") or not parts[0].endswith("]"):
            continue
        try:
            value = float(parts[2])
        except ValueError:
            continue
        if math.isfinite(value):
            expected_values.append(value)

    expected_sum = 0.0
    for value in expected_values:
        expected_sum += value
    return lines, len(expected_values), expected_sum


def serve_and_run(lines, expected_count):
    clear_redis()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    port = server.getsockname()[1]
    server.listen(1)
    accepted = threading.Event()
    server_error = []

    def sender():
        try:
            server.settimeout(5)
            conn, _ = server.accept()
            accepted.set()
            with conn:
                conn.sendall(("\n".join(lines) + "\n").encode())
                try:
                    conn.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
        except Exception as exc:
            server_error.append(exc)
        finally:
            server.close()

    thread = threading.Thread(target=sender, daemon=True)
    thread.start()
    proc = subprocess.Popen(
        [AGENT_PATH, str(port), REDIS_PORT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    thread.join(timeout=6)
    assert accepted.is_set(), "Executable did not connect to the input TCP port"
    assert not server_error, f"Input server failed: {server_error[0]}"

    deadline = time.time() + 4
    while time.time() < deadline:
        if proc.poll() is not None and proc.returncode != 0:
            raise AssertionError(f"Executable crashed or exited with status {proc.returncode}")
        current = get_redis_number("count_events")
        if current == expected_count:
            time.sleep(0.1)
            break
        time.sleep(0.03)

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    else:
        assert proc.returncode == 0, f"Executable exited with status {proc.returncode}"

    return get_redis_number("sum_values"), get_redis_number("count_events")


def test_fuzzed_behavior():
    check_executable(AGENT_PATH)
    ensure_redis()
    rng = random.Random(secrets.randbits(128))

    for run in range(20):
        lines, expected_count, expected_sum = make_case(rng)
        actual_sum, actual_count = serve_and_run(lines, expected_count)

        assert actual_count is not None, "Agent failed to write count_events to Redis"
        assert actual_sum is not None, "Agent failed to write sum_values to Redis"
        assert actual_count == expected_count, (
            f"Run {run}: count_events mismatch; expected {expected_count}, got {actual_count}"
        )
        assert abs(actual_sum - expected_sum) < 1e-4, (
            f"Run {run}: sum_values mismatch; expected {expected_sum}, got {actual_sum}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
