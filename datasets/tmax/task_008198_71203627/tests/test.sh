#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import random
import re
from datetime import datetime, timedelta

REMOTE_ROOT = "/home/user/remote_servers"
RAW_ROOT = "/home/user/analysis/raw_logs"
RESULTS_FILE = "/home/user/analysis/results.json"

PROFILES = {
    "server_1": [5 if h in [8, 14, 20] else 1 for h in range(24)],
    "server_2": [15 if h in [2, 10, 18] else 2 for h in range(24)],
    "server_3": [6 if h in [8, 14, 20] else 1 for h in range(24)],
}

LOG_RE = re.compile(
    r'^\S+ \S+ \S+ \[(?P<date>\d{2}/[A-Za-z]{3}/\d{4}):'
    r'(?P<hour>\d{2}):\d{2}:\d{2} [^\]]+\] "[^"]*" '
    r'(?P<status>\d{3}) \S+(?: .*)?$'
)


def generate_pristine_logs():
    """Reconstruct the deterministic inputs created by setup.sh."""
    random.seed(42)
    base_time = datetime(2023, 10, 10, 0, 0, 0)
    generated = {}

    for server in ("server_1", "server_2", "server_3"):
        lines = []
        for hour in range(24):
            num_normal = random.randint(50, 100)
            for _ in range(num_normal):
                minute = random.randint(0, 59)
                sec = random.randint(0, 59)
                t = base_time + timedelta(hours=hour, minutes=minute, seconds=sec)
                lines.append(
                    f'192.168.1.1 - - [{t.strftime("%d/%b/%Y:%H:%M:%S +0000")}] '
                    '"GET /api HTTP/1.1" 200 512\n'
                )

            for _ in range(PROFILES[server][hour]):
                minute = random.randint(0, 59)
                sec = random.randint(0, 59)
                t = base_time + timedelta(hours=hour, minutes=minute, seconds=sec)
                lines.append(
                    f'192.168.1.2 - - [{t.strftime("%d/%b/%Y:%H:%M:%S +0000")}] '
                    '"GET /api HTTP/1.1" 502 512\n'
                )

        generated[server] = "".join(lines).encode("ascii")

    return generated


PRISTINE_LOGS = generate_pristine_logs()


def error_vector(path):
    vector = [0] * 24
    with open(path, "r", encoding="ascii") as log_file:
        for line_number, line in enumerate(log_file, 1):
            match = LOG_RE.fullmatch(line.rstrip("\n"))
            assert match is not None, f"Malformed combined-log line in {path}:{line_number}"
            status = int(match.group("status"))
            if 500 <= status <= 599:
                hour = int(match.group("hour"))
                assert 0 <= hour <= 23, f"Invalid hour in {path}:{line_number}"
                vector[hour] += 1
    return vector


def test_raw_logs_transferred():
    for i in range(1, 4):
        server = f"server_{i}"
        log_file = os.path.join(RAW_ROOT, f"{server}.log")
        remote_file = os.path.join(REMOTE_ROOT, server, "access.log")

        assert os.path.isfile(log_file), f"Expected copied log file is missing: {log_file}"
        assert os.path.getsize(log_file) > 0, f"Copied log file is empty: {log_file}"
        assert os.path.isfile(remote_file), f"Provided source log is missing: {remote_file}"

        with open(remote_file, "rb") as source:
            source_bytes = source.read()
        with open(log_file, "rb") as copied:
            copied_bytes = copied.read()

        assert source_bytes == PRISTINE_LOGS[server], f"Provided source log was altered: {remote_file}"
        assert copied_bytes == source_bytes, f"{log_file} is not an exact copy of {remote_file}"


def test_results_json():
    assert os.path.isfile(RESULTS_FILE), f"Results file is missing: {RESULTS_FILE}"

    with open(RESULTS_FILE, "r", encoding="utf-8") as f:
        raw_results = f.read()
        try:
            data = json.loads(raw_results)
        except json.JSONDecodeError:
            assert False, f"Results file is not valid JSON: {RESULTS_FILE}"

    assert "closest_pair" in data, "Key 'closest_pair' missing from results.json"
    assert "distance" in data, "Key 'distance' missing from results.json"

    closest_pair = data["closest_pair"]
    assert isinstance(closest_pair, list), "'closest_pair' should be a list"
    assert len(closest_pair) == 2, "'closest_pair' should contain exactly two elements"
    assert closest_pair == sorted(closest_pair), "'closest_pair' must be sorted alphabetically"

    distance = data["distance"]
    assert isinstance(distance, (int, float)) and not isinstance(distance, bool), "'distance' should be a number"

    vectors = {
        server: error_vector(os.path.join(RAW_ROOT, f"{server}.log"))
        for server in ("server_1", "server_2", "server_3")
    }
    distances = {}
    for first, second in itertools.combinations(sorted(vectors), 2):
        distances[(first, second)] = math.sqrt(
            sum((a - b) ** 2 for a, b in zip(vectors[first], vectors[second]))
        )

    expected_pair = min(distances, key=lambda pair: (distances[pair], pair))
    expected_distance = round(distances[expected_pair], 2)

    assert closest_pair == list(expected_pair), (
        f"Expected closest pair {list(expected_pair)}, got {closest_pair}"
    )
    assert distance == expected_distance, f"Expected distance {expected_distance}, got {distance}"

    # Retain the original known-result assertions as an additional sanity check.
    assert closest_pair == ["server_1", "server_3"], (
        f"Expected closest pair ['server_1', 'server_3'], got {closest_pair}"
    )
    original_expected_distance = round(math.sqrt(3), 2)
    assert distance == original_expected_distance, (
        f"Expected distance {original_expected_distance}, got {distance}"
    )

    assert re.search(r'"distance"\s*:\s*-?\d+\.\d{2}(?=\s*[,}])', raw_results), (
        "'distance' must be written with exactly two decimal places"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
