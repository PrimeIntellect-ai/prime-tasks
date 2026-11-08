#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
from collections import Counter, defaultdict

import pytest

EVENTS_FILE = "/home/user/events.csv"
OUTPUT_FILE = "/home/user/anomalies_sampled.json"
ETL_BIN = "/tmp/etl_submission"

ORIGINAL_ROWS = [
    (100, "en", "Hello!"),
    (100, "es", "¡Hola!"),
    (101, "en", "Short"),
    (102, "en", "A"),
    (102, "en", "B"),
    (102, "en", "C"),
    (102, "fr", "Bonjour"),
    (102, "fr", "Oui"),
    (102, "ja", "こんにちは"),
    (102, "ja", "はい"),
    (103, "en", "Normal"),
    (104, "zh", "你好"),
    (104, "zh", "世界"),
    (104, "zh", "测试"),
    (104, "zh", "数据"),
    (104, "zh", "管道"),
    (104, "zh", "工程师"),
    (104, "en", "Wow that is a lot"),
]


def write_events(rows):
    with open(EVENTS_FILE, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp_sec", "language", "content"])
        writer.writerows(rows)


def execute_etl(rows):
    write_events(rows)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        [ETL_BIN], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"Compiled ETL program exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"Path {OUTPUT_FILE} is not a file."
    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"File {OUTPUT_FILE} is not valid JSON: {e}")


def expected_for(rows):
    counts = Counter(timestamp for timestamp, _, _ in rows)
    anomaly_seconds = {
        timestamp for timestamp, count in counts.items()
        if count > 5 and count >= 2 * counts.get(timestamp - 1, 0)
    }

    by_language = defaultdict(list)
    for timestamp, language, content in rows:
        if timestamp in anomaly_seconds:
            by_language[language].append({
                "timestamp_sec": timestamp,
                "language": language,
                "content": content,
            })

    sampled = []
    for language in sorted(by_language):
        candidates = sorted(
            by_language[language],
            key=lambda item: (-len(item["content"]), item["content"]),
        )
        sampled.extend(candidates[:2])

    return sorted(
        sampled,
        key=lambda item: (
            item["language"], -len(item["content"]), item["content"]
        ),
    )


def generated_rows(case_number):
    base = secrets.randbelow(500000) + 1000 + case_number * 1000000
    token = secrets.token_hex(6)
    rows = []
    languages = ["en", "fr", "ja", "zh"]
    fragments = ["a", "éclair", "猫", "🙂🙂", "comma,value", "αλφα"]

    def add(second, count, offset):
        for i in range(count):
            language = languages[(i + offset) % len(languages)]
            fragment = fragments[(i * 3 + offset) % len(fragments)]
            content = f"{fragment}-{token}-{case_number}-{offset}-{i}"
            rows.append((second, language, content))

    add(base, 3, 0)       # Not anomalous: count is not greater than five.
    add(base + 1, 6, 1)   # Anomalous: exactly double the preceding count.
    add(base + 2, 11, 2)  # Not anomalous: less than double six.
    add(base + 4, 6, 3)   # Anomalous: the immediately preceding second is absent.
    add(base + 5, 12, 4)  # Anomalous: exactly double the preceding count.
    add(base + 6, 5, 5)   # Not anomalous: threshold is strict.

    random.SystemRandom().shuffle(rows)
    return rows


def test_compiled_etl_and_outputs():
    assert os.path.exists("/home/user/etl.go"), "Required Go source /home/user/etl.go does not exist."
    assert os.path.isfile("/home/user/etl.go"), "/home/user/etl.go is not a file."

    actual_data = execute_etl(ORIGINAL_ROWS)
    expected_data = [
        {"timestamp_sec": 104, "language": "en", "content": "Wow that is a lot"},
        {"timestamp_sec": 102, "language": "en", "content": "A"},
        {"timestamp_sec": 102, "language": "fr", "content": "Bonjour"},
        {"timestamp_sec": 102, "language": "fr", "content": "Oui"},
        {"timestamp_sec": 102, "language": "ja", "content": "こんにちは"},
        {"timestamp_sec": 102, "language": "ja", "content": "はい"},
        {"timestamp_sec": 104, "language": "zh", "content": "工程师"},
        {"timestamp_sec": 104, "language": "zh", "content": "世界"},
    ]

    assert isinstance(actual_data, list), f"Expected JSON array, got {type(actual_data).__name__}."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(actual_data)}."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}. Expected {expected}, got {actual}."

    try:
        for case_number in range(4):
            rows = generated_rows(case_number)
            actual = execute_etl(rows)
            expected = expected_for(rows)
            assert isinstance(actual, list), f"Expected JSON array, got {type(actual).__name__}."
            assert actual == expected, (
                f"ETL output was incorrect for generated case {case_number}. "
                f"Expected {expected}, got {actual}."
            )
    finally:
        # Leave the required output corresponding to the supplied dataset.
        final_actual = execute_etl(ORIGINAL_ROWS)
        assert final_actual == expected_data
TEST_EOF

if [ -f /home/user/etl.go ] \
   && timeout 30s go build -o /tmp/etl_submission /home/user/etl.go \
   && ETL_BIN=/tmp/etl_submission python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
