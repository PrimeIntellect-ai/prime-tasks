#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess

import pytest

SOURCE = "/home/user/process.go"
RAW = "/home/user/raw_data.jsonl"
OUTPUT = "/home/user/processed_data.jsonl"
BINARY = "/tmp/process_submission"

CANONICAL_RECORDS = [
    {"id": 1, "text_a": "hallo", "text_b": "hello", "series": [0.0, None, 10.0]},
    {"id": 2, "text_a": "こんにちは世界", "text_b": "こんちは世界", "series": [5.0, None, None, 20.0]},
    {"id": 3, "text_a": "Привет 🌍", "text_b": "Привет 🌎", "series": [-1.0, None, -5.0]},
    {"id": 4, "text_a": "résumé", "text_b": "resume", "series": [100.0, None, None, None, 200.0]},
]


def write_jsonl(path, records):
    with open(path, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")


def run_submission(records):
    write_jsonl(RAW, records)
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        [BINARY], cwd="/home/user", text=True, capture_output=True, timeout=20
    )
    assert completed.returncode == 0, (
        f"process.go executable failed with exit code {completed.returncode}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )


def test_process_go_exists_builds_and_runs():
    assert os.path.exists(SOURCE), f"Required Go source {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."

    env = os.environ.copy()
    env["GO111MODULE"] = "off"
    env["GOPROXY"] = "off"

    listed = subprocess.run(
        ["go", "list", "-deps", "-f", "{{if not .Standard}}{{.ImportPath}}{{end}}", SOURCE],
        cwd="/home/user", env=env, text=True, capture_output=True, timeout=30
    )
    assert listed.returncode == 0, f"process.go is not valid Go: {listed.stderr}"
    nonstandard = [
        line.strip() for line in listed.stdout.splitlines()
        if line.strip() and line.strip() != "command-line-arguments"
    ]
    assert not nonstandard, f"process.go uses non-standard packages: {nonstandard}"

    built = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd="/home/user", env=env, text=True, capture_output=True, timeout=60
    )
    assert built.returncode == 0, f"process.go did not compile: {built.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    run_submission(CANONICAL_RECORDS)


def test_processed_data_exists():
    file_path = "/home/user/processed_data.jsonl"
    assert os.path.exists(file_path), f"Output file {file_path} does not exist. Did you run your Go program?"
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."


def test_processed_data_content():
    file_path = "/home/user/processed_data.jsonl"
    if not os.path.exists(file_path):
        pytest.fail(f"File {file_path} is missing.")

    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in {file_path}, got {len(lines)}."

    expected_results = {
        1: {
            "text_a": "hallo",
            "text_b": "hello",
            "series": [0.0, 5.0, 10.0],
            "text_distance": 1
        },
        2: {
            "text_a": "こんにちは世界",
            "text_b": "こんちは世界",
            "series": [5.0, 10.0, 15.0, 20.0],
            "text_distance": 1
        },
        3: {
            "text_a": "Привет 🌍",
            "text_b": "Привет 🌎",
            "series": [-1.0, -3.0, -5.0],
            "text_distance": 1
        },
        4: {
            "text_a": "résumé",
            "text_b": "resume",
            "series": [100.0, 125.0, 150.0, 175.0, 200.0],
            "text_distance": 2
        }
    }

    actual_ids = []
    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON line in {file_path}: {line}")

        assert "id" in data, f"Missing 'id' in record: {data}"
        record_id = data["id"]
        actual_ids.append(record_id)

        assert record_id in expected_results, f"Unexpected id {record_id} found in output."
        expected = expected_results[record_id]

        assert data.get("text_a") == expected["text_a"], f"Incorrect text_a for id {record_id}."
        assert data.get("text_b") == expected["text_b"], f"Incorrect text_b for id {record_id}."

        actual_series = data.get("series")
        assert actual_series is not None, f"Missing 'series' for id {record_id}."
        assert len(actual_series) == len(expected["series"]), f"Incorrect series length for id {record_id}."
        for act, exp in zip(actual_series, expected["series"]):
            assert act is not None, f"Found null in series for id {record_id}."
            assert abs(act - exp) < 1e-6, f"Incorrect series value for id {record_id}: expected {exp}, got {act}."

        actual_distance = data.get("text_distance")
        assert actual_distance is not None, f"Missing 'text_distance' for id {record_id}."
        assert actual_distance == expected["text_distance"], f"Incorrect text_distance for id {record_id}: expected {expected['text_distance']}, got {actual_distance}."

    assert sorted(actual_ids) == [1, 2, 3, 4], "Missing some expected ids in the output."


def levenshtein(a, b):
    a = list(a)
    b = list(b)
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def interpolate(series):
    result = [None if value is None else float(value) for value in series]
    left = 0
    while left < len(result) - 1:
        right = left + 1
        while result[right] is None:
            right += 1
        if right > left + 1:
            start = result[left]
            end = result[right]
            gap = right - left
            for index in range(left + 1, right):
                result[index] = start + (end - start) * (index - left) / gap
        left = right
    return result


def test_program_handles_additional_unicode_and_interpolation_inputs():
    rng = random.SystemRandom()
    alphabet = list("abZéßЖ你界🙂🌍🌎λ")
    records = []

    explicit_pairs = [
        ("🌍", "🌎"),
        ("你🙂Ж", "你🌎Ж"),
        ("mañana", "manana"),
        ("東京abc", "東x京ac"),
        ("🙂🙂界", "🙂界界🙂"),
    ]

    for index in range(18):
        if index < len(explicit_pairs):
            text_a, text_b = explicit_pairs[index]
        else:
            text_a = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 11)))
            text_b = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 11)))

        length = rng.randrange(2, 13)
        series = [None] * length
        series[0] = rng.uniform(-500.0, 500.0)
        series[-1] = rng.uniform(-500.0, 500.0)
        for position in range(1, length - 1):
            if rng.random() < 0.32:
                series[position] = rng.uniform(-500.0, 500.0)

        records.append({
            "id": 1000 + index,
            "text_a": text_a,
            "text_b": text_b,
            "series": series,
        })

    run_submission(records)
    assert os.path.isfile(OUTPUT), "Program did not create processed_data.jsonl."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(records), f"Expected {len(records)} output records, got {len(lines)}."

    expected_by_id = {record["id"]: record for record in records}
    seen = []
    for line in lines:
        try:
            actual = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Invalid output JSON: {exc}: {line}")

        record_id = actual.get("id")
        assert record_id in expected_by_id, f"Unexpected output id {record_id}."
        assert record_id not in seen, f"Duplicate output id {record_id}."
        seen.append(record_id)
        source = expected_by_id[record_id]

        assert actual.get("text_a") == source["text_a"]
        assert actual.get("text_b") == source["text_b"]
        assert actual.get("text_distance") == levenshtein(source["text_a"], source["text_b"]), (
            f"Incorrect rune-based Levenshtein distance for id {record_id}."
        )

        expected_series = interpolate(source["series"])
        actual_series = actual.get("series")
        assert isinstance(actual_series, list), f"Missing series for id {record_id}."
        assert len(actual_series) == len(expected_series)
        for actual_value, expected_value in zip(actual_series, expected_series):
            assert actual_value is not None, f"Found null in series for id {record_id}."
            assert isinstance(actual_value, (int, float)) and not isinstance(actual_value, bool)
            assert math.isfinite(actual_value)
            assert abs(actual_value - expected_value) < 1e-7, (
                f"Incorrect interpolated value for id {record_id}: "
                f"expected {expected_value}, got {actual_value}."
            )

    assert sorted(seen) == sorted(expected_by_id)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
