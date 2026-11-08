#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone

SOURCE = "/home/user/analyze.cpp"
BINARY = "/home/user/analyze"
LOG = "/home/user/server.log"
ALERTS = "/home/user/alerts.txt"
PATTERN = re.compile(r'^\[.*?\]\s+\S+\s+(\S+)\s+(\d+)$')


def expected_alerts(log_text):
    windows = defaultdict(lambda: deque(maxlen=3))
    expected = []
    for line in log_text.splitlines():
        line = line.strip()
        if not line:
            continue
        match = PATTERN.match(line)
        if match:
            endpoint = match.group(1)
            latency = int(match.group(2))
            windows[endpoint].append(latency)
            if len(windows[endpoint]) == 3:
                avg = sum(windows[endpoint]) // 3
                if avg >= 500:
                    expected.append(
                        f"ALERT: {endpoint} is experiencing degradation. Current 3-request rolling average is {avg}ms."
                    )
    return expected


def read_alerts():
    assert os.path.isfile(ALERTS), f"{ALERTS} is missing. Did you run the program?"
    with open(ALERTS, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check(log_text):
    with open(LOG, "w") as f:
        f.write(log_text)
    if os.path.exists(ALERTS):
        os.remove(ALERTS)

    result = subprocess.run(
        [BINARY], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{BINARY} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_alerts()
    expected = expected_alerts(log_text)
    assert actual == expected, (
        f"Contents of {ALERTS} do not match the expected alerts.\n"
        f"Expected:\n" + "\n".join(expected) + "\n\n"
        f"Actual:\n" + "\n".join(actual)
    )


def make_hidden_log():
    rng = secrets.SystemRandom()
    nonce = secrets.token_hex(8)
    streams = {}
    for i in range(6):
        endpoint = f"/hidden/{nonce}/service-{i}?variant={rng.randrange(10000)}"
        if i % 2 == 0:
            values = [
                100 + rng.randrange(100), 200 + rng.randrange(100), 300 + rng.randrange(100),
                1100 + rng.randrange(300), 1200 + rng.randrange(300), 1300 + rng.randrange(300),
                rng.randrange(100), rng.randrange(100), rng.randrange(100),
            ]
        else:
            values = [
                800 + rng.randrange(300), 900 + rng.randrange(300), 1000 + rng.randrange(300),
                100 + rng.randrange(100), 100 + rng.randrange(100), 100 + rng.randrange(100),
                1400 + rng.randrange(300), 1500 + rng.randrange(300), 1600 + rng.randrange(300),
            ]
        streams[endpoint] = deque(values)

    events = []
    active = list(streams)
    while active:
        endpoint = rng.choice(active)
        events.append((endpoint, streams[endpoint].popleft(), rng.choice(["GET", "POST", "PUT", "DELETE"])))
        if not streams[endpoint]:
            active.remove(endpoint)

    start = datetime(2025, 1, 2, 3, 4, 5, tzinfo=timezone.utc)
    lines = []
    for i, (endpoint, latency, method) in enumerate(events):
        timestamp = (start + timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
        lines.append(f"[{timestamp}] {method} {endpoint} {latency}")
    return "\n".join(lines) + "\n"


def test_complete_solution():
    # Preserve the original verifier's file and fixed-log assertions.
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(BINARY), f"{BINARY} executable is missing. Did you compile it?"
    assert os.path.isfile(ALERTS), f"{ALERTS} is missing. Did you run the program?"
    assert os.path.isfile(LOG), f"The file {LOG} is missing."

    with open(LOG, "rb") as f:
        original_log_bytes = f.read()
    with open(ALERTS, "rb") as f:
        original_alert_bytes = f.read()
    original_log = original_log_bytes.decode()

    actual_original = read_alerts()
    expected_original = expected_alerts(original_log)
    assert actual_original == expected_original, (
        f"Contents of {ALERTS} do not match the expected alerts.\n"
        f"Expected:\n" + "\n".join(expected_original) + "\n\n"
        f"Actual:\n" + "\n".join(actual_original)
    )

    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled executable."

    with open(SOURCE, "r") as f:
        source_text = f.read()
    assert re.search(r'#\s*include\s*<regex>', source_text), "The source does not include <regex>."
    assert re.search(r'\b(?:std::)?regex_(?:match|search)\s*\(', source_text), (
        "The source does not use regex_match or regex_search to parse input."
    )

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", BINARY],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            f"Failed to compile {SOURCE}.\nstdout:\n{compile_result.stdout}\n"
            f"stderr:\n{compile_result.stderr}"
        )
        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

        # Execute the submitted program on the original input and on fresh,
        # unpredictable valid inputs whose answers are independently derived.
        run_and_check(original_log)
        run_and_check(
            "[2025-02-03T04:05:06Z] GET /short/a 999\n"
            "[2025-02-03T04:05:07Z] POST /short/a 999\n"
            "[2025-02-03T04:05:08Z] GET /short/b 2000\n"
        )
        hidden_log = make_hidden_log()
        assert expected_alerts(hidden_log), "Internal test generation produced no alerts."
        run_and_check(hidden_log)
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log_bytes)
        with open(ALERTS, "wb") as f:
            f.write(original_alert_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
